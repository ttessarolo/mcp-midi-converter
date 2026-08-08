import Foundation

public enum StandardMIDIRewriter {
    public static func rewrite(
        _ input: Data,
        configuration: MIDITranslationConfiguration
    ) throws -> MIDIConversionResult {
        try configuration.profile.validate()
        var bytes = [UInt8](input)
        guard bytes.count >= 14 else {
            throw MIDIConversionError.fileTooShort
        }
        guard chunkID(bytes, at: 0) == "MThd" else {
            throw MIDIConversionError.missingHeaderChunk
        }

        let headerLength = try uint32(bytes, at: 4)
        guard headerLength >= 6 else {
            throw MIDIConversionError.invalidHeaderLength(headerLength)
        }
        let headerEnd = 8 + Int(headerLength)
        guard headerEnd <= bytes.count else {
            throw MIDIConversionError.truncatedChunk(id: "MThd", declaredLength: headerLength)
        }

        let format = try uint16(bytes, at: 8)
        guard format <= 2 else {
            throw MIDIConversionError.unsupportedFormat(format)
        }
        let declaredTrackCount = try uint16(bytes, at: 10)
        var report = MIDIConversionReport(format: format, declaredTrackCount: declaredTrackCount)
        var changedByteOffsets = Set<Int>()
        var parsedTrackCount = 0
        var cursor = headerEnd

        while cursor < bytes.count {
            guard cursor + 8 <= bytes.count else {
                throw MIDIConversionError.truncatedChunkHeader(offset: cursor)
            }
            let id = chunkID(bytes, at: cursor)
            let length = try uint32(bytes, at: cursor + 4)
            let payloadStart = cursor + 8
            let (payloadEnd, overflow) = payloadStart.addingReportingOverflow(Int(length))
            guard !overflow, payloadEnd <= bytes.count else {
                throw MIDIConversionError.truncatedChunk(id: id, declaredLength: length)
            }

            if id == "MTrk" {
                parsedTrackCount += 1
                try rewriteTrack(
                    bytes: &bytes,
                    start: payloadStart,
                    end: payloadEnd,
                    configuration: configuration,
                    report: &report,
                    changedByteOffsets: &changedByteOffsets
                )
            }
            cursor = payloadEnd
        }

        guard parsedTrackCount == Int(declaredTrackCount) else {
            throw MIDIConversionError.trackCountMismatch(
                declared: declaredTrackCount,
                parsed: parsedTrackCount
            )
        }

        return MIDIConversionResult(
            data: Data(bytes),
            report: report.withParsedTrackCount(parsedTrackCount),
            changedByteOffsets: changedByteOffsets
        )
    }

    private static func rewriteTrack(
        bytes: inout [UInt8],
        start: Int,
        end: Int,
        configuration: MIDITranslationConfiguration,
        report: inout MIDIConversionReport,
        changedByteOffsets: inout Set<Int>
    ) throws {
        var cursor = start
        var runningStatus: UInt8?

        while cursor < end {
            _ = try readVariableLengthQuantity(bytes, cursor: &cursor, end: end)
            guard cursor < end else {
                throw MIDIConversionError.truncatedEvent(offset: cursor)
            }

            let eventOffset = cursor
            let firstByte = bytes[cursor]
            let status: UInt8

            if firstByte & 0x80 != 0 {
                status = firstByte
                cursor += 1
                if status < 0xF0 {
                    runningStatus = status
                }
            } else {
                guard let previousStatus = runningStatus else {
                    throw MIDIConversionError.missingRunningStatus(offset: cursor)
                }
                status = previousStatus
            }

            if status < 0xF0 {
                let messageType = status & 0xF0
                let channel = status & 0x0F
                let dataLength = (messageType == 0xC0 || messageType == 0xD0) ? 1 : 2
                guard cursor + dataLength <= end else {
                    throw MIDIConversionError.truncatedEvent(offset: eventOffset)
                }
                for index in cursor..<(cursor + dataLength) where bytes[index] & 0x80 != 0 {
                    throw MIDIConversionError.invalidDataByte(offset: index, value: bytes[index])
                }

                let isNoteMessage = messageType == 0x80 || messageType == 0x90
                let isPolyphonicKeyPressure = messageType == 0xA0
                let shouldRemapKey = isNoteMessage
                    || (isPolyphonicKeyPressure && configuration.remapPolyphonicKeyPressure)

                if shouldRemapKey, configuration.channels.includes(zeroBasedChannel: channel) {
                    let noteOffset = cursor
                    let sourceNote = bytes[noteOffset]
                    let decision = configuration.profile.decision(
                        for: sourceNote,
                        policy: configuration.unavailableNotePolicy
                    )
                    if decision.target != sourceNote {
                        bytes[noteOffset] = decision.target
                        changedByteOffsets.insert(noteOffset)
                    }
                    report.register(
                        decision,
                        changed: decision.target != sourceNote,
                        polyphonicKeyPressure: isPolyphonicKeyPressure
                    )
                }
                cursor += dataLength
                continue
            }

            runningStatus = nil
            switch status {
            case 0xFF:
                guard cursor < end else {
                    throw MIDIConversionError.truncatedEvent(offset: eventOffset)
                }
                cursor += 1 // Meta-event type.
                let length = try readVariableLengthQuantity(bytes, cursor: &cursor, end: end)
                guard length <= UInt32(end - cursor) else {
                    throw MIDIConversionError.truncatedEvent(offset: eventOffset)
                }
                cursor += Int(length)
            case 0xF0, 0xF7:
                let length = try readVariableLengthQuantity(bytes, cursor: &cursor, end: end)
                guard length <= UInt32(end - cursor) else {
                    throw MIDIConversionError.truncatedEvent(offset: eventOffset)
                }
                cursor += Int(length)
            default:
                throw MIDIConversionError.unsupportedSystemStatus(
                    offset: eventOffset,
                    status: status
                )
            }
        }
    }

    private static func readVariableLengthQuantity(
        _ bytes: [UInt8],
        cursor: inout Int,
        end: Int
    ) throws -> UInt32 {
        let start = cursor
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard cursor < end else {
                throw MIDIConversionError.truncatedVariableLengthQuantity(offset: start)
            }
            let byte = bytes[cursor]
            cursor += 1
            value = (value << 7) | UInt32(byte & 0x7F)
            if byte & 0x80 == 0 {
                return value
            }
        }
        throw MIDIConversionError.oversizedVariableLengthQuantity(offset: start)
    }

    private static func chunkID(_ bytes: [UInt8], at offset: Int) -> String {
        guard offset >= 0, offset + 4 <= bytes.count else { return "????" }
        return String(decoding: bytes[offset..<(offset + 4)], as: UTF8.self)
    }

    private static func uint16(_ bytes: [UInt8], at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= bytes.count else {
            throw MIDIConversionError.fileTooShort
        }
        return (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    private static func uint32(_ bytes: [UInt8], at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= bytes.count else {
            throw MIDIConversionError.fileTooShort
        }
        return (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }
}
