import AppKit
import CryptoKit
import Foundation
import MPCMidiConverterCore
import UniformTypeIdentifiers

@MainActor
final class ConverterViewModel: ObservableObject {
    static let shared = ConverterViewModel()

    @Published private(set) var files: [URL] = []
    @Published var selectedProfile: TranslationProfile = .bfdPop113
    @Published var unavailablePolicy: UnavailableNotePolicy = .musicalFallback
    @Published var channelSelection: MIDIChannelSelection = .generalMIDIPercussion
    @Published var remapPolyphonicKeyPressure = true
    @Published var overwriteExisting = false
    @Published private(set) var outcomes: [FileConversionOutcome] = []
    @Published private(set) var isConverting = false
    @Published private(set) var isAnalyzingXPM = false
    @Published var notice: String?
    @Published var xpmDraft: XPMImportDraft?

    @Published private(set) var profiles: [TranslationProfile]

    private init() {
        profiles = Self.loadInstalledProfiles()
        if let defaultProfile = profiles.first(where: { $0.id == selectedProfile.id }) {
            selectedProfile = defaultProfile
        }
    }

    func addFiles(_ urls: [URL]) {
        var rejected: [String] = []
        var knownPaths = Set(files.map(\.standardizedFileURL.path))
        for url in urls {
            let normalized = url.standardizedFileURL
            let extensionLowercased = normalized.pathExtension.lowercased()
            guard extensionLowercased == "mid" || extensionLowercased == "midi" else {
                rejected.append(normalized.lastPathComponent)
                continue
            }
            if knownPaths.insert(normalized.path).inserted {
                files.append(normalized)
            }
        }
        outcomes = []
        if !rejected.isEmpty {
            notice = "Ignored non-MIDI files: \(rejected.joined(separator: ", "))."
        } else {
            notice = nil
        }
    }

    func removeFile(_ url: URL) {
        files.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        outcomes.removeAll { $0.input.standardizedFileURL == url.standardizedFileURL }
    }

    func clearFiles() {
        files.removeAll()
        outcomes.removeAll()
        notice = nil
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "Choose General MIDI Files"
        panel.prompt = "Add"
        panel.allowedContentTypes = [.midi]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            addFiles(panel.urls)
        }
    }

    func importProfile() {
        let panel = NSOpenPanel()
        panel.title = "Import a Mapping Profile"
        panel.prompt = "Import"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let profile = try TranslationProfile.load(from: url)
            let storedURL = try Self.storeImportedProfile(data: Data(contentsOf: url), profile: profile)
            if let existing = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[existing] = profile
            } else {
                profiles.append(profile)
                profiles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
            selectedProfile = profile
            outcomes = []
            notice = "Installed profile: \(profile.name) (\(storedURL.lastPathComponent))."
        } catch {
            notice = "Invalid profile: \(error.localizedDescription)"
        }
    }

    func chooseXPMProgram() {
        let panel = NSOpenPanel()
        panel.title = "Choose an MPC Drum Program"
        panel.prompt = "Analyze"
        panel.allowedContentTypes = [UTType(filenameExtension: "xpm") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        analyzeXPMProgram(at: url)
    }

    func dismissXPMDraft() {
        xpmDraft = nil
    }

    func installGeneratedProfile(_ draft: XPMImportDraft) {
        do {
            let profile = try persistGeneratedProfile(draft)
            xpmDraft = nil
            notice = "Installed profile: \(profile.name)."
        } catch {
            draft.actionError = error.localizedDescription
        }
    }

    func installAndPrepareProfileIssue(_ draft: XPMImportDraft) {
        do {
            let issueURL = try draft.githubIssueURL()
            let profile = try persistGeneratedProfile(draft)
            guard NSWorkspace.shared.open(issueURL) else {
                throw XPMImportUIError.cannotOpenBrowser
            }
            xpmDraft = nil
            notice = "Installed \(profile.name) and opened an editable GitHub issue. Nothing was submitted automatically."
        } catch {
            draft.actionError = error.localizedDescription
        }
    }

    func convert() {
        guard !files.isEmpty, !isConverting else { return }
        isConverting = true
        outcomes = []
        notice = nil

        let inputs = files
        let overwrite = overwriteExisting
        let configuration = MIDITranslationConfiguration(
            profile: selectedProfile,
            unavailableNotePolicy: unavailablePolicy,
            channels: channelSelection,
            remapPolyphonicKeyPressure: remapPolyphonicKeyPressure
        )

        Task {
            let converted = await Task.detached(priority: .userInitiated) {
                inputs.map { input in
                    convertFile(input, configuration: configuration, overwrite: overwrite)
                }
            }.value
            outcomes = converted
            isConverting = false
        }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func analyzeXPMProgram(at url: URL) {
        guard !isAnalyzingXPM else { return }
        isAnalyzingXPM = true
        notice = nil

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                loadXPMAnalysis(from: url)
            }.value
            isAnalyzingXPM = false
            switch result {
            case let .success(analysis, proposal, hash, warnings):
                xpmDraft = XPMImportDraft(
                    sourceURL: url,
                    analysis: analysis,
                    proposal: proposal,
                    xpmSHA256: hash,
                    additionalWarnings: warnings
                )
            case let .failure(message):
                notice = "Could not analyze XPM: \(message)"
            }
        }
    }

    private func persistGeneratedProfile(_ draft: XPMImportDraft) throws -> TranslationProfile {
        let profile = try draft.makeProfile()
        let data = try profile.jsonData()
        _ = try Self.storeImportedProfile(data: data, profile: profile)
        if let existing = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[existing] = profile
        } else {
            profiles.append(profile)
        }
        profiles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        selectedProfile = profile
        outcomes = []
        return profile
    }

    private static func loadInstalledProfiles() -> [TranslationProfile] {
        var profilesByID = Dictionary(
            uniqueKeysWithValues: TranslationProfile.builtIns.map { ($0.id, $0) }
        )
        if let resources = Bundle.main.resourceURL {
            loadProfiles(
                from: resources.appendingPathComponent("Profiles", isDirectory: true),
                into: &profilesByID
            )
        }
        if let directory = try? profilesDirectory() {
            loadProfiles(from: directory, into: &profilesByID)
        }
        return profilesByID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func loadProfiles(
        from directory: URL,
        into profilesByID: inout [String: TranslationProfile]
    ) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files
            .filter({ $0.pathExtension.lowercased() == "json" })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if let profile = try? TranslationProfile.load(from: file) {
                profilesByID[profile.id] = profile
            }
        }
    }

    private static func storeImportedProfile(
        data: Data,
        profile: TranslationProfile
    ) throws -> URL {
        let safeID = profile.id.map { character in
            character.isLetter || character.isNumber || "-_.".contains(character)
                ? character
                : "_"
        }
        let output = try profilesDirectory()
            .appendingPathComponent("profile-\(String(safeID))")
            .appendingPathExtension("json")
        try data.write(to: output, options: .atomic)
        return output
    }

    private static func profilesDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base
            .appendingPathComponent("MPC MIDI Converter", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}

private enum XPMAnalysisLoadResult: Sendable {
    case success(XPMProgramAnalysis, XPMGMProfileProposal, String, [String])
    case failure(String)
}

private enum XPMImportUIError: LocalizedError {
    case cannotOpenBrowser

    var errorDescription: String? {
        "The profile was installed, but the GitHub issue could not be opened in the browser."
    }
}

private func loadXPMAnalysis(from url: URL) -> XPMAnalysisLoadResult {
    let hasSecurityScope = url.startAccessingSecurityScopedResource()
    defer {
        if hasSecurityScope { url.stopAccessingSecurityScopedResource() }
    }
    do {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 64 * 1_024 * 1_024 else {
            return .failure("The XPM file exceeds the 64 MiB input safety limit.")
        }
        let analysis = try XPMProgramAnalyzer.analyze(data)
        let proposal = XPMGMProfileProposer.propose(from: analysis)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let warnings = sampleReferenceWarnings(xpmURL: url, analysis: analysis)
        return .success(analysis, proposal, hash, warnings)
    } catch {
        return .failure(error.localizedDescription)
    }
}

private func sampleReferenceWarnings(xpmURL: URL, analysis: XPMProgramAnalysis) -> [String] {
    let references = Set(analysis.pads.flatMap(\.layers).compactMap(\.sampleFile))
    guard !references.isEmpty else {
        return ["No sample references were found in the XPM."]
    }

    let parent = xpmURL.deletingLastPathComponent().standardizedFileURL
    let candidateProgramData = URL(
        fileURLWithPath: xpmURL.deletingPathExtension().path + "_[ProgramData]",
        isDirectory: true
    ).standardizedFileURL
    var isDirectory: ObjCBool = false
    let hasProgramData = FileManager.default.fileExists(atPath: candidateProgramData.path, isDirectory: &isDirectory)
        && isDirectory.boolValue
        && !isSymbolicLink(candidateProgramData)
    let programData = candidateProgramData
    let roots = hasProgramData ? [programData, parent] : [parent]

    var unsafe = 0
    var missing = 0
    for reference in references {
        let relative = reference.replacingOccurrences(of: "\\", with: "/")
        guard !relative.hasPrefix("/"),
              !relative.contains("/"),
              relative != ".",
              relative != ".." else {
            unsafe += 1
            continue
        }
        let exists = roots.contains { root in
            let candidate = root.appendingPathComponent(relative).standardizedFileURL
            let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
            return candidate.path.hasPrefix(prefix)
                && !isSymbolicLink(candidate)
                && FileManager.default.fileExists(atPath: candidate.path)
        }
        if !exists { missing += 1 }
    }

    var warnings: [String] = []
    if !hasProgramData, analysis.format == .mpc3ACVSJSON {
        warnings.append("The sibling _[ProgramData] folder was not found; sample references were checked only beside the XPM.")
    }
    if missing > 0 {
        warnings.append("\(missing) referenced sample file(s) could not be found. Sample names are not included in this warning for privacy.")
    }
    if unsafe > 0 {
        warnings.append("\(unsafe) absolute or parent-traversing sample reference(s) were ignored for safety.")
    }
    return warnings
}

private func isSymbolicLink(_ url: URL) -> Bool {
    (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
}

struct FileConversionOutcome: Identifiable, Sendable {
    let input: URL
    let output: URL?
    let report: MIDIConversionReport?
    let errorMessage: String?

    var id: String { input.standardizedFileURL.path }
    var succeeded: Bool { output != nil && errorMessage == nil }
}

private func convertFile(
    _ input: URL,
    configuration: MIDITranslationConfiguration,
    overwrite: Bool
) -> FileConversionOutcome {
    let hasSecurityScope = input.startAccessingSecurityScopedResource()
    defer {
        if hasSecurityScope {
            input.stopAccessingSecurityScopedResource()
        }
    }

    do {
        let data = try Data(contentsOf: input, options: .mappedIfSafe)
        let result = try StandardMIDIRewriter.rewrite(data, configuration: configuration)
        let output = try OutputFile.write(result.data, for: input, overwrite: overwrite)
        return FileConversionOutcome(
            input: input,
            output: output,
            report: result.report,
            errorMessage: nil
        )
    } catch {
        return FileConversionOutcome(
            input: input,
            output: nil,
            report: nil,
            errorMessage: error.localizedDescription
        )
    }
}
