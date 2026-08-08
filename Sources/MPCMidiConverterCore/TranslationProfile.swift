import Foundation

public struct TranslationProfile: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let source: String
    public let target: String
    public let gmRange: ClosedRange<UInt8>
    public let silentNote: UInt8
    public let direct: [UInt8: UInt8]
    public let fallback: [UInt8: UInt8]

    public init(
        id: String,
        name: String,
        description: String,
        source: String,
        target: String,
        gmRange: ClosedRange<UInt8>,
        silentNote: UInt8,
        direct: [UInt8: UInt8],
        fallback: [UInt8: UInt8]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.source = source
        self.target = target
        self.gmRange = gmRange
        self.silentNote = silentNote
        self.direct = direct
        self.fallback = fallback
    }

    public static let bfdPop113 = TranslationProfile(
        id: "akai-mpc-bfd-pop-113",
        name: "Akai MPC - BFD Pop Kit 113",
        description: "Profilo misurato dal Drum Program Acoustic-Kit-BFD Pop Kit 113 salvato da MPC 3.9.1.2.",
        source: "General MIDI Level 1 percussion",
        target: "Akai MPC Acoustic-Kit-BFD Pop Kit 113",
        gmRange: 35...81,
        silentNote: 0,
        direct: [
            35: 36, // Acoustic Bass Drum -> Kick
            36: 36, // Bass Drum 1 -> Kick
            37: 42, // Side Stick -> Snare SS
            38: 37, // Acoustic Snare -> Snare Hit
            41: 44, // Low Floor Tom -> Floor Tom
            42: 38, // Closed Hi-Hat -> Closed Hat
            43: 44, // High Floor Tom -> Floor Tom
            44: 43, // Pedal Hi-Hat -> Pedal Hat
            45: 45, // Low Tom -> Mid Tom
            46: 39, // Open Hi-Hat -> Open Hat
            47: 45, // Low-Mid Tom -> Mid Tom
            48: 46, // Hi-Mid Tom -> High Tom 2
            49: 50, // Crash Cymbal 1 -> Crash 1
            50: 47, // High Tom -> High Tom
            51: 48, // Ride Cymbal 1 -> Ride Bow
            53: 49, // Ride Bell -> Ride Bell
            57: 51, // Crash Cymbal 2 -> Crash 2
            59: 48  // Ride Cymbal 2 -> Ride Bow
        ],
        fallback: [
            39: 41, // Hand Clap -> Rim Shot
            40: 40, // Electric Snare -> Alt Snare
            52: 51, // Chinese Cymbal -> Crash 2
            55: 50, // Splash Cymbal -> Crash 1
            56: 49  // Cowbell -> Ride Bell
        ]
    )

    public static let builtIns: [TranslationProfile] = [
        .bfdPop113
    ]

    public static func load(from url: URL) throws -> TranslationProfile {
        let data = try Data(contentsOf: url)
        let document = try JSONDecoder().decode(ProfileDocument.self, from: data)
        return try document.makeProfile()
    }

    public func validate() throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProfileError.missingIdentity
        }
        guard gmRange.lowerBound <= 127,
              gmRange.upperBound <= 127,
              silentNote <= 127 else {
            throw ProfileError.invalidRangeOrSilentNote
        }
        for (source, target) in direct.merging(fallback, uniquingKeysWith: { first, _ in first }) {
            guard source <= 127, gmRange.contains(source), target <= 127 else {
                throw ProfileError.invalidMapping(
                    source: String(source),
                    target: Int(target)
                )
            }
        }
        let duplicateSources = Set(direct.keys).intersection(fallback.keys)
        guard duplicateSources.isEmpty else {
            throw ProfileError.overlappingMappings(duplicateSources.sorted())
        }
    }

    public func decision(for note: UInt8, policy: UnavailableNotePolicy) -> MappingDecision {
        guard gmRange.contains(note) else {
            return MappingDecision(source: note, target: note, kind: .outsideGMRange)
        }
        if let target = direct[note] {
            return MappingDecision(source: note, target: target, kind: .direct)
        }
        if policy == .musicalFallback, let target = fallback[note] {
            return MappingDecision(source: note, target: target, kind: .fallback)
        }
        switch policy {
        case .musicalFallback, .silence:
            return MappingDecision(source: note, target: silentNote, kind: .silenced)
        case .keepOriginal:
            return MappingDecision(source: note, target: note, kind: .keptOriginal)
        }
    }
}

public enum UnavailableNotePolicy: String, CaseIterable, Identifiable, Sendable {
    case musicalFallback
    case silence
    case keepOriginal

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .musicalFallback:
            "Fallback musicali; altrimenti silenzio"
        case .silence:
            "Solo mapping primari; resto in silenzio"
        case .keepOriginal:
            "Mantieni le note non disponibili (avanzato)"
        }
    }

    public var explanation: String {
        switch self {
        case .musicalFallback:
            "Usa sostituzioni sensate per clap, electric snare e piatti; le altre percussioni mancanti vengono inviate a un pad vuoto."
        case .silence:
            "Usa soltanto i mapping primari dichiarati dal profilo; tutti gli altri strumenti vengono inviati a un pad vuoto."
        case .keepOriginal:
            "Lascia invariato il numero delle note senza equivalente. Sul kit di destinazione potrebbero attivare suoni errati."
        }
    }
}

public enum MIDIChannelSelection: String, CaseIterable, Identifiable, Sendable {
    case generalMIDIPercussion
    case allChannels

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .generalMIDIPercussion:
            "Solo canale 10 GM (consigliato)"
        case .allChannels:
            "Tutti i canali (file contenente solo batteria)"
        }
    }

    func includes(zeroBasedChannel: UInt8) -> Bool {
        switch self {
        case .generalMIDIPercussion:
            zeroBasedChannel == 9
        case .allChannels:
            true
        }
    }
}

public struct MIDITranslationConfiguration: Sendable {
    public let profile: TranslationProfile
    public let unavailableNotePolicy: UnavailableNotePolicy
    public let channels: MIDIChannelSelection
    public let remapPolyphonicKeyPressure: Bool

    public init(
        profile: TranslationProfile,
        unavailableNotePolicy: UnavailableNotePolicy = .musicalFallback,
        channels: MIDIChannelSelection = .generalMIDIPercussion,
        remapPolyphonicKeyPressure: Bool = true
    ) {
        self.profile = profile
        self.unavailableNotePolicy = unavailableNotePolicy
        self.channels = channels
        self.remapPolyphonicKeyPressure = remapPolyphonicKeyPressure
    }
}

public struct MappingDecision: Equatable, Sendable {
    public let source: UInt8
    public let target: UInt8
    public let kind: MappingKind
}

public enum MappingKind: String, Sendable {
    case direct
    case fallback
    case silenced
    case keptOriginal
    case outsideGMRange
}

private struct ProfileDocument: Decodable {
    let id: String
    let name: String
    let description: String
    let source: String
    let target: String
    let gmRange: [Int]
    let silentNote: Int
    let direct: [String: Int]
    let fallback: [String: Int]

    func makeProfile() throws -> TranslationProfile {
        guard gmRange.count == 2,
              let lower = UInt8(exactly: gmRange[0]),
              let upper = UInt8(exactly: gmRange[1]),
              lower <= upper,
              upper <= 127,
              let silent = UInt8(exactly: silentNote),
              silent <= 127 else {
            throw ProfileError.invalidRangeOrSilentNote
        }
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProfileError.missingIdentity
        }
        let directMap = try parseMap(direct, within: lower...upper)
        let fallbackMap = try parseMap(fallback, within: lower...upper)
        let duplicateSources = Set(directMap.keys).intersection(fallbackMap.keys)
        guard duplicateSources.isEmpty else {
            throw ProfileError.overlappingMappings(duplicateSources.sorted())
        }
        let profile = TranslationProfile(
            id: id,
            name: name,
            description: description,
            source: source,
            target: target,
            gmRange: lower...upper,
            silentNote: silent,
            direct: directMap,
            fallback: fallbackMap
        )
        try profile.validate()
        return profile
    }

    private func parseMap(
        _ input: [String: Int],
        within sourceRange: ClosedRange<UInt8>
    ) throws -> [UInt8: UInt8] {
        try Dictionary(uniqueKeysWithValues: input.map { source, target in
            guard let sourceNumber = Int(source),
                  let sourceNote = UInt8(exactly: sourceNumber),
                  sourceRange.contains(sourceNote),
                  let targetNote = UInt8(exactly: target),
                  targetNote <= 127 else {
                throw ProfileError.invalidMapping(source: source, target: target)
            }
            return (sourceNote, targetNote)
        })
    }
}

public enum ProfileError: LocalizedError {
    case invalidRangeOrSilentNote
    case missingIdentity
    case invalidMapping(source: String, target: Int)
    case overlappingMappings([UInt8])

    public var errorDescription: String? {
        switch self {
        case .invalidRangeOrSilentNote:
            "Il profilo contiene un intervallo GM o una nota silenziosa non validi."
        case .missingIdentity:
            "Il profilo deve avere id e nome non vuoti."
        case let .invalidMapping(source, target):
            "Il profilo contiene una traduzione MIDI non valida: \(source) -> \(target)."
        case let .overlappingMappings(notes):
            "Le note \(notes.map(String.init).joined(separator: ", ")) compaiono sia nelle corrispondenze dirette sia nei fallback."
        }
    }
}
