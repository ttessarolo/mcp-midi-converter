import Foundation

public enum MIDIConversionError: LocalizedError, Equatable {
    case fileTooShort
    case missingHeaderChunk
    case invalidHeaderLength(UInt32)
    case unsupportedFormat(UInt16)
    case truncatedChunkHeader(offset: Int)
    case truncatedChunk(id: String, declaredLength: UInt32)
    case trackCountMismatch(declared: UInt16, parsed: Int)
    case truncatedVariableLengthQuantity(offset: Int)
    case oversizedVariableLengthQuantity(offset: Int)
    case missingRunningStatus(offset: Int)
    case invalidDataByte(offset: Int, value: UInt8)
    case truncatedEvent(offset: Int)
    case unsupportedSystemStatus(offset: Int, status: UInt8)

    public var errorDescription: String? {
        switch self {
        case .fileTooShort:
            "The file is too short to be a Standard MIDI File."
        case .missingHeaderChunk:
            "The file does not start with an MThd chunk."
        case let .invalidHeaderLength(length):
            "The MThd chunk declares an invalid length (\(length))."
        case let .unsupportedFormat(format):
            "MIDI format \(format) is unsupported; SMF 0, 1, and 2 are accepted."
        case let .truncatedChunkHeader(offset):
            "Truncated chunk header at offset \(offset)."
        case let .truncatedChunk(id, length):
            "Chunk \(id) is shorter than its declared length of \(length)."
        case let .trackCountMismatch(declared, parsed):
            "The file declares \(declared) MTrk chunks but contains \(parsed)."
        case let .truncatedVariableLengthQuantity(offset):
            "Truncated MIDI variable-length quantity at offset \(offset)."
        case let .oversizedVariableLengthQuantity(offset):
            "MIDI variable-length quantity exceeds four bytes at offset \(offset)."
        case let .missingRunningStatus(offset):
            "MIDI event has no status or running status at offset \(offset)."
        case let .invalidDataByte(offset, value):
            "Invalid MIDI data byte 0x\(String(value, radix: 16)) at offset \(offset)."
        case let .truncatedEvent(offset):
            "Truncated MIDI event at offset \(offset)."
        case let .unsupportedSystemStatus(offset, status):
            "System status 0x\(String(status, radix: 16)) is not allowed in an SMF at offset \(offset)."
        }
    }
}
