import Foundation

public struct MIDIConversionReport: Equatable, Sendable {
    public let format: UInt16
    public let declaredTrackCount: UInt16
    public let parsedTrackCount: Int
    public var eligibleEvents: Int
    public var changedEvents: Int
    public var directEvents: Int
    public var fallbackEvents: Int
    public var silencedEvents: Int
    public var keptOriginalEvents: Int
    public var outsideRangeEvents: Int
    public var polyphonicKeyPressureEvents: Int
    public var sourceNoteCounts: [UInt8: Int]

    init(format: UInt16, declaredTrackCount: UInt16) {
        self.format = format
        self.declaredTrackCount = declaredTrackCount
        self.parsedTrackCount = 0
        self.eligibleEvents = 0
        self.changedEvents = 0
        self.directEvents = 0
        self.fallbackEvents = 0
        self.silencedEvents = 0
        self.keptOriginalEvents = 0
        self.outsideRangeEvents = 0
        self.polyphonicKeyPressureEvents = 0
        self.sourceNoteCounts = [:]
    }

    init(
        format: UInt16,
        declaredTrackCount: UInt16,
        parsedTrackCount: Int,
        eligibleEvents: Int,
        changedEvents: Int,
        directEvents: Int,
        fallbackEvents: Int,
        silencedEvents: Int,
        keptOriginalEvents: Int,
        outsideRangeEvents: Int,
        polyphonicKeyPressureEvents: Int,
        sourceNoteCounts: [UInt8: Int]
    ) {
        self.format = format
        self.declaredTrackCount = declaredTrackCount
        self.parsedTrackCount = parsedTrackCount
        self.eligibleEvents = eligibleEvents
        self.changedEvents = changedEvents
        self.directEvents = directEvents
        self.fallbackEvents = fallbackEvents
        self.silencedEvents = silencedEvents
        self.keptOriginalEvents = keptOriginalEvents
        self.outsideRangeEvents = outsideRangeEvents
        self.polyphonicKeyPressureEvents = polyphonicKeyPressureEvents
        self.sourceNoteCounts = sourceNoteCounts
    }

    mutating func register(_ decision: MappingDecision, changed: Bool, polyphonicKeyPressure: Bool) {
        eligibleEvents += 1
        if changed {
            changedEvents += 1
        }
        if polyphonicKeyPressure {
            polyphonicKeyPressureEvents += 1
        }
        sourceNoteCounts[decision.source, default: 0] += 1
        switch decision.kind {
        case .direct:
            directEvents += 1
        case .fallback:
            fallbackEvents += 1
        case .silenced:
            silencedEvents += 1
        case .keptOriginal:
            keptOriginalEvents += 1
        case .outsideGMRange:
            outsideRangeEvents += 1
        }
    }

    func withParsedTrackCount(_ count: Int) -> MIDIConversionReport {
        MIDIConversionReport(
            format: format,
            declaredTrackCount: declaredTrackCount,
            parsedTrackCount: count,
            eligibleEvents: eligibleEvents,
            changedEvents: changedEvents,
            directEvents: directEvents,
            fallbackEvents: fallbackEvents,
            silencedEvents: silencedEvents,
            keptOriginalEvents: keptOriginalEvents,
            outsideRangeEvents: outsideRangeEvents,
            polyphonicKeyPressureEvents: polyphonicKeyPressureEvents,
            sourceNoteCounts: sourceNoteCounts
        )
    }
}

public struct MIDIConversionResult: Sendable {
    public let data: Data
    public let report: MIDIConversionReport
    public let changedByteOffsets: Set<Int>
}
