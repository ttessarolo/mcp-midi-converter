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
            "Il file è troppo corto per essere uno Standard MIDI File."
        case .missingHeaderChunk:
            "Il file non inizia con il chunk MIDI MThd."
        case let .invalidHeaderLength(length):
            "Il chunk MThd dichiara una lunghezza non valida (\(length))."
        case let .unsupportedFormat(format):
            "Il formato MIDI \(format) non è supportato; sono validi SMF 0, 1 e 2."
        case let .truncatedChunkHeader(offset):
            "Header di chunk troncato all'offset \(offset)."
        case let .truncatedChunk(id, length):
            "Il chunk \(id) è troncato rispetto alla lunghezza dichiarata \(length)."
        case let .trackCountMismatch(declared, parsed):
            "Il file dichiara \(declared) tracce MTrk ma ne contiene \(parsed)."
        case let .truncatedVariableLengthQuantity(offset):
            "Valore MIDI a lunghezza variabile troncato all'offset \(offset)."
        case let .oversizedVariableLengthQuantity(offset):
            "Valore MIDI a lunghezza variabile oltre il limite di 4 byte all'offset \(offset)."
        case let .missingRunningStatus(offset):
            "Evento MIDI senza status né running status all'offset \(offset)."
        case let .invalidDataByte(offset, value):
            "Byte dati MIDI non valido 0x\(String(value, radix: 16)) all'offset \(offset)."
        case let .truncatedEvent(offset):
            "Evento MIDI troncato all'offset \(offset)."
        case let .unsupportedSystemStatus(offset, status):
            "Status di sistema 0x\(String(status, radix: 16)) non ammesso in SMF all'offset \(offset)."
        }
    }
}
