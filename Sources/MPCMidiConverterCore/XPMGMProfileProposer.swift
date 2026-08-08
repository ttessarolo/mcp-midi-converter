import Foundation

public enum XPMInferenceConfidence: String, Sendable, Equatable, Comparable {
    case low, medium, high
    public static func < (lhs: Self, rhs: Self) -> Bool { [Self.low, .medium, .high].firstIndex(of: lhs)! < [Self.low, .medium, .high].firstIndex(of: rhs)! }
}

/// Evidence retained for a proposed GM mapping so a person can review the inference.
public struct XPMMappingEvidence: Sendable, Equatable, Identifiable {
    public let gmNote: UInt8
    public let targetNote: UInt8
    public let padIndex: Int
    public let sampleName: String
    public let confidence: XPMInferenceConfidence
    public var id: String { "\(gmNote)-\(targetNote)-\(padIndex)" }
}

/// A conservative, reviewable profile proposal. No fallback substitutions are generated.
public struct XPMGMProfileProposal: Sendable, Equatable {
    public let direct: [UInt8: UInt8]
    public let fallback: [UInt8: UInt8]
    public let silentNote: UInt8?
    public let evidence: [XPMMappingEvidence]
    public let reviewRequired: [String]
}

public enum XPMGMProfileProposer {
    /// Proposes only unambiguous role-name matches; musical substitutions remain a user decision.
    public static func propose(from analysis: XPMProgramAnalysis) -> XPMGMProfileProposal {
        var categories = [Kind: [XPMProgramPad]]()
        for pad in analysis.pads where !pad.isEmpty {
            if let kind = classify(pad) { categories[kind, default: []].append(pad) }
        }
        var direct: [UInt8: UInt8] = [:]
        var evidence: [XPMMappingEvidence] = []
        var review = [String]()
        for kind in Kind.allCases {
            guard let pads = categories[kind] else { continue }
            guard pads.count == 1, let pad = pads.first else {
                review.append("Multiple pads match \(kind.rawValue); no automatic GM mapping was created.")
                continue
            }
            let name = representativeName(pad)
            for gm in kind.gmNotes {
                direct[gm] = pad.note
                evidence.append(.init(
                    gmNote: gm,
                    targetNote: pad.note,
                    padIndex: pad.index,
                    sampleName: name,
                    confidence: .medium
                ))
            }
        }
        let silent = analysis.pads.first(where: \.isEmpty)?.note
        if silent == nil { review.append("No empty pad was found; choose a silent MIDI note manually.") }
        return XPMGMProfileProposal(direct: direct, fallback: [:], silentNote: silent, evidence: evidence.sorted { $0.gmNote < $1.gmNote }, reviewRequired: review.sorted())
    }

    private enum Kind: String, CaseIterable { case kick, sideStick, snare, closedHat, openHat, pedalHat, floorTom, midTom, highMidTom, highTom, rideBow, rideBell, crash1, crash2
        var gmNotes: [UInt8] { switch self { case .kick: [35,36]; case .sideStick:[37]; case .snare:[38]; case .closedHat:[42]; case .pedalHat:[44]; case .floorTom:[41,43]; case .midTom:[45,47]; case .openHat:[46]; case .highMidTom:[48]; case .highTom:[50]; case .crash1:[49]; case .rideBow:[51,59]; case .rideBell:[53]; case .crash2:[57] } }
    }
    private static func representativeName(_ pad: XPMProgramPad) -> String {
        pad.layers.compactMap(\.sampleName).first
            ?? pad.layers.compactMap(\.sampleFile).first
            ?? "pad \(pad.index)"
    }

    private static func classify(_ pad: XPMProgramPad) -> Kind? {
        let populatedLayers = pad.layers.filter { $0.sampleFile != nil }
        let names = populatedLayers.compactMap { $0.sampleName ?? $0.sampleFile }
        guard names.count == populatedLayers.count, !names.isEmpty else { return nil }
        let kinds = names.compactMap(classifyName)
        guard kinds.count == names.count, let first = kinds.first, kinds.allSatisfy({ $0 == first }) else {
            return nil
        }
        return first
    }

    private static func classifyName(_ rawName: String) -> Kind? {
        let tokens = rawName.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let name = " " + tokens.joined(separator: " ") + " "
        func hasToken(_ token: String) -> Bool { tokens.contains(token) }
        func hasPhrase(_ phrase: String) -> Bool { name.contains(" \(phrase) ") }

        if hasToken("kick") || hasPhrase("bass drum") { return .kick }
        if hasPhrase("side stick") || hasPhrase("cross stick") { return .sideStick }
        if hasPhrase("closed hat") || hasPhrase("closed hi hat") || hasPhrase("hat cs") { return .closedHat }
        if hasPhrase("open hat") || hasPhrase("open hi hat") || hasPhrase("hat os") { return .openHat }
        if hasPhrase("pedal hat") || hasPhrase("hat pedal") { return .pedalHat }
        if hasPhrase("floor tom") { return .floorTom }
        if hasPhrase("mid tom") { return .midTom }
        if hasPhrase("high tom 2") || hasPhrase("hi mid tom") { return .highMidTom }
        if hasPhrase("high tom") { return .highTom }
        if hasToken("ride") && hasToken("bell") { return .rideBell }
        if hasToken("ride") && hasToken("bow") { return .rideBow }
        if hasToken("crash") && (hasToken("cr2") || hasToken("crash2") || hasPhrase("crash 2")) { return .crash2 }
        if hasToken("crash") && (hasToken("cr1") || hasToken("crash1") || hasPhrase("crash 1")) { return .crash1 }
        if hasToken("snare") && !["rim", "side", "alt"].contains(where: hasToken) { return .snare }
        return nil
    }
}
