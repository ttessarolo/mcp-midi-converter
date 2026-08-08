import Foundation
import MPCMidiConverterCore

enum XPMMappingDisposition: String, CaseIterable, Identifiable {
    case primary
    case fallback
    case unavailable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .primary: "Primary"
        case .fallback: "Fallback"
        case .unavailable: "Unavailable"
        }
    }
}

struct XPMReviewRow: Identifiable {
    let gmNote: UInt8
    let gmInstrument: String
    var disposition: XPMMappingDisposition
    var targetNote: UInt8?
    let suggestedTarget: UInt8?
    let suggestedSampleName: String?
    let suggestionConfidence: XPMInferenceConfidence?

    var id: UInt8 { gmNote }
}

@MainActor
final class XPMImportDraft: ObservableObject, Identifiable {
    let id = UUID()
    let sourceURL: URL
    let analysis: XPMProgramAnalysis
    let xpmSHA256: String
    let populatedPads: [XPMProgramPad]
    let emptyPads: [XPMProgramPad]
    let warnings: [String]

    @Published var profileName: String
    @Published var profileID: String
    @Published var targetProgramName: String
    @Published var silentNote: UInt8?
    @Published var rows: [XPMReviewRow]
    @Published var confirmedReview = false
    @Published var actionError: String?

    init(
        sourceURL: URL,
        analysis: XPMProgramAnalysis,
        proposal: XPMGMProfileProposal,
        xpmSHA256: String,
        additionalWarnings: [String]
    ) {
        self.sourceURL = sourceURL
        self.analysis = analysis
        self.xpmSHA256 = xpmSHA256
        populatedPads = analysis.pads.filter { !$0.isEmpty }.sorted { $0.note < $1.note }
        emptyPads = analysis.pads.filter(\.isEmpty).sorted { $0.note < $1.note }
        let shareableProgramName = Self.isShareableLabel(analysis.programName)
            ? analysis.programName
            : "Imported MPC Drum Program"
        profileName = "Akai MPC - \(shareableProgramName)"
        profileID = Self.makeProfileID(from: shareableProgramName)
        targetProgramName = shareableProgramName
        silentNote = proposal.silentNote

        let evidenceByNote = Dictionary(uniqueKeysWithValues: proposal.evidence.map { ($0.gmNote, $0) })
        rows = GMInstrument.all.map { instrument in
            let evidence = evidenceByNote[instrument.note]
            return XPMReviewRow(
                gmNote: instrument.note,
                gmInstrument: instrument.name,
                disposition: .unavailable,
                targetNote: evidence?.targetNote,
                suggestedTarget: evidence?.targetNote,
                suggestedSampleName: evidence?.sampleName,
                suggestionConfidence: evidence?.confidence
            )
        }
        var combinedWarnings = analysis.warnings + proposal.reviewRequired + additionalWarnings
        if shareableProgramName != analysis.programName {
            combinedWarnings.append("The XPM program name resembled a path, URL, or control text, so it was not copied into shareable profile fields. Enter a public-safe Drum Program name.")
        }
        warnings = combinedWarnings
    }

    var formatLabel: String {
        let base = switch analysis.format {
        case .mpc3ACVSJSON: "MPC 3 ACVS/JSON"
        case .legacyXML: "Legacy MPC XML"
        }
        if let version = analysis.formatVersion { return "\(base) · \(version)" }
        return base
    }

    var validationMessage: String? {
        if profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a profile name."
        }
        if !Self.isShareableIdentifier(profileID) {
            return "Use only lowercase letters, numbers, dots, underscores, and hyphens in the profile ID."
        }
        if !Self.isShareableLabel(profileName) {
            return "The profile name must be a single public-safe label, not a path or URL."
        }
        if !Self.isShareableLabel(targetProgramName) {
            return "The target Drum Program must be a single public-safe label, not a path or URL."
        }
        guard silentNote != nil else {
            return "Choose an empty pad note for unavailable GM instruments."
        }
        if let row = rows.first(where: { $0.disposition != .unavailable && $0.targetNote == nil }) {
            return "Choose a destination pad for GM note \(row.gmNote)."
        }
        if rows.allSatisfy({ $0.disposition == .unavailable }) {
            return "Review the suggestions and mark at least one GM instrument as Primary or Fallback."
        }
        if !confirmedReview {
            return "Confirm that you reviewed the proposed mappings and the silent pad."
        }
        return nil
    }

    var canInstall: Bool { validationMessage == nil }

    func pad(for note: UInt8?) -> XPMProgramPad? {
        guard let note else { return nil }
        return analysis.pads.first { $0.note == note }
    }

    func targetLabel(for pad: XPMProgramPad) -> String {
        let sample = representativeName(for: pad)
        return "\(pad.note) · \(padLabel(for: pad.index)) · \(sample) · \(populatedLayerCount(for: pad)) layer(s)"
    }

    func silentLabel(for pad: XPMProgramPad) -> String {
        "\(pad.note) · \(padLabel(for: pad.index))"
    }

    func makeProfile() throws -> TranslationProfile {
        if let validationMessage {
            throw XPMProfileDraftError.invalidDraft(validationMessage)
        }
        guard let silentNote else {
            throw XPMProfileDraftError.invalidDraft("Choose an empty pad note.")
        }
        guard emptyPads.contains(where: { $0.note == silentNote }) else {
            throw XPMProfileDraftError.invalidDraft("The silent note must belong to an empty pad in this XPM.")
        }
        let populatedNotes = Set(populatedPads.map(\.note))
        var direct: [UInt8: UInt8] = [:]
        var fallback: [UInt8: UInt8] = [:]
        for row in rows {
            guard let target = row.targetNote else { continue }
            guard populatedNotes.contains(target) else {
                throw XPMProfileDraftError.invalidDraft("GM note \(row.gmNote) must target a populated pad in this XPM.")
            }
            switch row.disposition {
            case .primary:
                direct[row.gmNote] = target
            case .fallback:
                fallback[row.gmNote] = target
            case .unavailable:
                break
            }
        }
        let profile = TranslationProfile(
            id: profileID.trimmingCharacters(in: .whitespacesAndNewlines),
            name: profileName.trimmingCharacters(in: .whitespacesAndNewlines),
            description: "Generated from an MPC XPM for \(targetProgramName), SHA-256 \(xpmSHA256), and reviewed in MPC MIDI Converter.",
            source: "General MIDI Level 1 percussion",
            target: targetProgramName.trimmingCharacters(in: .whitespacesAndNewlines),
            gmRange: 35...81,
            silentNote: silentNote,
            direct: direct,
            fallback: fallback
        )
        try profile.validate()
        return profile
    }

    func makeProfileJSON() throws -> Data {
        try makeProfile().jsonData()
    }

    func githubIssueURL() throws -> URL {
        let profile = try makeProfile()
        let json = String(decoding: try profile.jsonData(), as: UTF8.self)
        let body = """
        ## Generated profile

        This proposal was prepared in MPC MIDI Converter and still requires maintainer review.

        - MPC Drum Program: `\(sanitizedMarkdown(profile.target))`
        - XPM format: \(shareableFormatLabel)
        - XPM SHA-256: `\(xpmSHA256)`
        - Local review completed: yes

        No XPM, sample audio, sample filenames, or filesystem paths are included.

        ```profile-json
        \(json)
        ```

        ## Hardware test

        Add the MPC model, firmware version, and the result of loading a converted GM MIDI file before submitting.
        """
        var components = URLComponents(string: "https://github.com/ttessarolo/mpc-midi-converter/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "template", value: "profile-submission.md"),
            URLQueryItem(name: "title", value: "[Profile] \(profile.name)"),
            URLQueryItem(name: "body", value: body)
        ]
        guard let url = components?.url else { throw XPMProfileDraftError.cannotCreateIssueURL }
        return url
    }

    private func representativeName(for pad: XPMProgramPad) -> String {
        pad.layers.compactMap(\.sampleName).first
            ?? pad.layers.compactMap(\.sampleFile).first
            ?? "Unnamed sample"
    }

    private func populatedLayerCount(for pad: XPMProgramPad) -> Int {
        pad.layers.filter { $0.sampleFile != nil }.count
    }

    private func padLabel(for index: Int) -> String {
        let bankScalar = UnicodeScalar(65 + index / 16) ?? "?"
        return "\(Character(bankScalar))\(String(format: "%02d", index % 16 + 1))"
    }

    private static func makeProfileID(from name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let parts = folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let slug = parts.joined(separator: "-").lowercased()
        return "akai-mpc-\(slug.isEmpty ? "custom-kit" : slug)"
    }

    private static func isShareableLabel(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.count <= 160,
              value.rangeOfCharacter(from: .newlines) == nil,
              !value.contains("/"),
              !value.contains("\\"),
              !value.contains("://"),
              !value.lowercased().hasPrefix("file:"),
              !value.hasPrefix("~"),
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return false
        }
        return true
    }

    private var shareableFormatLabel: String {
        let family = switch analysis.format {
        case .mpc3ACVSJSON: "MPC 3 ACVS/JSON"
        case .legacyXML: "Legacy MPC XML"
        }
        guard let version = analysis.formatVersion,
              !version.isEmpty,
              version.count <= 40,
              version.unicodeScalars.allSatisfy({ scalar in
                  CharacterSet.decimalDigits.contains(scalar)
                      || ".-_".unicodeScalars.contains(scalar)
              }) else {
            return family
        }
        return "\(family) \(version)"
    }

    private static func isShareableIdentifier(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 120 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            CharacterSet.lowercaseLetters.contains(scalar)
                || CharacterSet.decimalDigits.contains(scalar)
                || "-_.".unicodeScalars.contains(scalar)
        }
    }

    private func sanitizedMarkdown(_ value: String) -> String {
        value.replacingOccurrences(of: "`", with: "'")
    }
}

private enum XPMProfileDraftError: LocalizedError {
    case invalidDraft(String)
    case cannotCreateIssueURL

    var errorDescription: String? {
        switch self {
        case let .invalidDraft(message): message
        case .cannotCreateIssueURL: "The GitHub issue URL could not be created."
        }
    }
}

private struct GMInstrument {
    let note: UInt8
    let name: String

    static let all: [GMInstrument] = [
        .init(note: 35, name: "Acoustic Bass Drum"), .init(note: 36, name: "Bass Drum 1"),
        .init(note: 37, name: "Side Stick"), .init(note: 38, name: "Acoustic Snare"),
        .init(note: 39, name: "Hand Clap"), .init(note: 40, name: "Electric Snare"),
        .init(note: 41, name: "Low Floor Tom"), .init(note: 42, name: "Closed Hi-Hat"),
        .init(note: 43, name: "High Floor Tom"), .init(note: 44, name: "Pedal Hi-Hat"),
        .init(note: 45, name: "Low Tom"), .init(note: 46, name: "Open Hi-Hat"),
        .init(note: 47, name: "Low-Mid Tom"), .init(note: 48, name: "Hi-Mid Tom"),
        .init(note: 49, name: "Crash Cymbal 1"), .init(note: 50, name: "High Tom"),
        .init(note: 51, name: "Ride Cymbal 1"), .init(note: 52, name: "Chinese Cymbal"),
        .init(note: 53, name: "Ride Bell"), .init(note: 54, name: "Tambourine"),
        .init(note: 55, name: "Splash Cymbal"), .init(note: 56, name: "Cowbell"),
        .init(note: 57, name: "Crash Cymbal 2"), .init(note: 58, name: "Vibra Slap"),
        .init(note: 59, name: "Ride Cymbal 2"), .init(note: 60, name: "Hi Bongo"),
        .init(note: 61, name: "Low Bongo"), .init(note: 62, name: "Mute Hi Conga"),
        .init(note: 63, name: "Open Hi Conga"), .init(note: 64, name: "Low Conga"),
        .init(note: 65, name: "High Timbale"), .init(note: 66, name: "Low Timbale"),
        .init(note: 67, name: "High Agogo"), .init(note: 68, name: "Low Agogo"),
        .init(note: 69, name: "Cabasa"), .init(note: 70, name: "Maracas"),
        .init(note: 71, name: "Short Whistle"), .init(note: 72, name: "Long Whistle"),
        .init(note: 73, name: "Short Guiro"), .init(note: 74, name: "Long Guiro"),
        .init(note: 75, name: "Claves"), .init(note: 76, name: "Hi Wood Block"),
        .init(note: 77, name: "Low Wood Block"), .init(note: 78, name: "Mute Cuica"),
        .init(note: 79, name: "Open Cuica"), .init(note: 80, name: "Mute Triangle"),
        .init(note: 81, name: "Open Triangle")
    ]
}
