import Foundation
import zlib

/// A read-only description of an MPC program extracted from an XPM file.
public struct XPMProgramAnalysis: Sendable, Equatable {
    public let programName: String
    public let format: XPMProgramFormat
    public let formatVersion: String?
    public let pads: [XPMProgramPad]
    public let warnings: [String]

    public init(
        programName: String,
        format: XPMProgramFormat,
        formatVersion: String? = nil,
        pads: [XPMProgramPad],
        warnings: [String] = []
    ) {
        self.programName = programName
        self.format = format
        self.formatVersion = formatVersion
        self.pads = pads
        self.warnings = warnings
    }
}

public enum XPMProgramFormat: String, Sendable, Equatable {
    case mpc3ACVSJSON
    case legacyXML
}

/// A physical/logical MPC pad. `note` is the MIDI note assigned by the program.
public struct XPMProgramPad: Sendable, Equatable, Identifiable {
    public let index: Int
    public let note: UInt8
    public let layers: [XPMProgramLayer]

    public var id: Int { index }
    public var isEmpty: Bool { layers.allSatisfy { $0.sampleFile == nil } }

    public init(index: Int, note: UInt8, layers: [XPMProgramLayer]) {
        self.index = index
        self.note = note
        self.layers = layers
    }
}

/// A sample layer. Empty MPC layers are represented by a `nil` sample file.
public struct XPMProgramLayer: Sendable, Equatable {
    public let sampleName: String?
    public let sampleFile: String?
    public let velocityStart: UInt8?
    public let velocityEnd: UInt8?

    public init(sampleName: String?, sampleFile: String?, velocityStart: UInt8?, velocityEnd: UInt8?) {
        self.sampleName = sampleName
        self.sampleFile = sampleFile
        self.velocityStart = velocityStart
        self.velocityEnd = velocityEnd
    }
}

public enum XPMProgramAnalysisError: LocalizedError, Equatable {
    case unsupportedContainer
    case malformedACVSHeader
    case malformedJSON
    case malformedXML
    case missingField(String)
    case invalidNote(Int)
    case duplicateNote(UInt8)
    case invalidPadCount(Int)
    case invalidVelocity(Int)
    case invalidVelocityRange(start: UInt8, end: UInt8)
    case malformedLayer
    case decompressedDataTooLarge
    case noPopulatedPads

    public var errorDescription: String? {
        switch self {
        case .unsupportedContainer: "The XPM file is neither MPC3 ACVS gzip data nor legacy XML."
        case .malformedACVSHeader: "The MPC3 ACVS header is malformed or unsupported."
        case .malformedJSON: "The MPC3 ACVS payload is not valid JSON."
        case .malformedXML: "The legacy XPM payload is not valid XML."
        case let .missingField(field): "The XPM file is missing required field \(field)."
        case let .invalidNote(note): "The XPM file contains invalid MIDI note \(note)."
        case let .duplicateNote(note): "The XPM file assigns MIDI note \(note) to more than one pad."
        case let .invalidPadCount(count): "The XPM file contains \(count) pads; exactly 128 are required."
        case let .invalidVelocity(value): "The XPM file contains invalid velocity \(value)."
        case let .invalidVelocityRange(start, end): "The XPM layer velocity range \(start)-\(end) is invalid."
        case .malformedLayer: "The XPM file contains a malformed sample layer."
        case .decompressedDataTooLarge: "The decompressed XPM payload exceeds the 64 MiB safety limit."
        case .noPopulatedPads: "The XPM does not contain any populated sample pads."
        }
    }
}

/// Parses MPC3 ACVS+JSON and legacy XML programs without writing to disk.
public enum XPMProgramAnalyzer {
    private static let maximumDecompressedSize = 64 * 1_024 * 1_024

    public static func analyze(_ data: Data) throws -> XPMProgramAnalysis {
        if data.starts(with: [0x1F, 0x8B]) {
            return try analyzeACVS(try gzipInflate(data))
        }
        if let text = String(data: data, encoding: .utf8), text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
            return try analyzeLegacyXML(data)
        }
        throw XPMProgramAnalysisError.unsupportedContainer
    }

    private static func analyzeACVS(_ decoded: Data) throws -> XPMProgramAnalysis {
        guard let text = String(data: decoded, encoding: .utf8) else { throw XPMProgramAnalysisError.malformedACVSHeader }
        let lines = text.components(separatedBy: "\n")
        guard lines.count >= 6,
              lines[0].trimmingCharacters(in: .whitespacesAndNewlines) == "ACVS",
              !lines[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              lines[2].trimmingCharacters(in: .whitespacesAndNewlines) == "SerialisableProgramData",
              lines[3].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "json" else {
            throw XPMProgramAnalysisError.malformedACVSHeader
        }
        let jsonText = lines.dropFirst(5).joined(separator: "\n")
        guard let root = try? JSONSerialization.jsonObject(with: Data(jsonText.utf8)) as? [String: Any],
              let dataObject = root["data"] as? [String: Any] else {
            throw XPMProgramAnalysisError.malformedJSON
        }
        let name = (dataObject["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { throw XPMProgramAnalysisError.missingField("data.name") }
        guard let noteMap = ((dataObject["padNoteMap"] as? [String: Any])?["noteForPad"] as? [String: Any]) else {
            throw XPMProgramAnalysisError.missingField("data.padNoteMap.noteForPad")
        }
        let notes = try indexedIntegers(noteMap, field: "data.padNoteMap.noteForPad")
        guard let samples = dataObject["samples"] else { throw XPMProgramAnalysisError.missingField("data.samples") }
        let layerNodes = findLayerNodes(in: samples)
        guard layerNodes.count == 128 else { throw XPMProgramAnalysisError.invalidPadCount(layerNodes.count) }
        let pads = try makePads(notes: notes, layerNodes: layerNodes)
        guard pads.contains(where: { !$0.isEmpty }) else { throw XPMProgramAnalysisError.noPopulatedPads }
        return XPMProgramAnalysis(
            programName: name,
            format: .mpc3ACVSJSON,
            formatVersion: lines[1].trimmingCharacters(in: .whitespacesAndNewlines),
            pads: pads
        )
    }

    private static func indexedIntegers(_ object: [String: Any], field: String) throws -> [Int] {
        var values = Array(repeating: -1, count: 128)
        for (key, raw) in object {
            guard key.hasPrefix("value"), let index = Int(key.dropFirst(5)), index >= 0, index < 128,
                  let value = raw as? Int else { throw XPMProgramAnalysisError.missingField(field) }
            values[index] = value
        }
        guard !values.contains(-1) else { throw XPMProgramAnalysisError.missingField(field) }
        return values
    }

    private static func findLayerNodes(in value: Any) -> [[String: Any]] {
        if let object = value as? [String: Any] {
            if object["layersv"] is [Any] { return [object] }
            return object.keys.sorted(by: indexedKeyOrder).flatMap { findLayerNodes(in: object[$0] as Any) }
        }
        if let array = value as? [Any] { return array.flatMap(findLayerNodes) }
        return []
    }

    private static func indexedKeyOrder(_ lhs: String, _ rhs: String) -> Bool {
        func number(_ key: String) -> Int? { key.hasPrefix("value") ? Int(key.dropFirst(5)) : nil }
        switch (number(lhs), number(rhs)) {
        case let (a?, b?): return a < b
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil): return lhs < rhs
        }
    }

    private static func makePads(notes: [Int], layerNodes: [[String: Any]]) throws -> [XPMProgramPad] {
        guard notes.count == 128, layerNodes.count == 128 else { throw XPMProgramAnalysisError.invalidPadCount(layerNodes.count) }
        var seen = Set<UInt8>()
        return try zip(notes.indices, zip(notes, layerNodes)).map { index, pair in
            guard let note = UInt8(exactly: pair.0), note <= 127 else { throw XPMProgramAnalysisError.invalidNote(pair.0) }
            guard seen.insert(note).inserted else { throw XPMProgramAnalysisError.duplicateNote(note) }
            guard let rawLayers = pair.1["layersv"] as? [Any] else { throw XPMProgramAnalysisError.malformedLayer }
            return XPMProgramPad(index: index, note: note, layers: try rawLayers.map(makeLayer))
        }
    }

    private static func makeLayer(_ raw: Any) throws -> XPMProgramLayer {
        guard let object = raw as? [String: Any] else { throw XPMProgramAnalysisError.malformedLayer }
        let sampleFile = nonEmpty(object["sampleFile"] as? String)
        let sampleName = nonEmpty(object["sampleName"] as? String)
        if sampleFile == nil, sampleName != nil { throw XPMProgramAnalysisError.malformedLayer }
        let start = try velocity(object["velocityStart"])
        let end = try velocity(object["velocityEnd"])
        if let start, let end, start > end { throw XPMProgramAnalysisError.invalidVelocityRange(start: start, end: end) }
        return XPMProgramLayer(sampleName: sampleName, sampleFile: sampleFile, velocityStart: start, velocityEnd: end)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private static func velocity(_ value: Any?) throws -> UInt8? {
        guard let value else { return nil }
        guard let integer = value as? Int, let result = UInt8(exactly: integer), result <= 127 else {
            throw XPMProgramAnalysisError.invalidVelocity(value as? Int ?? -1)
        }
        return result
    }

    private static func gzipInflate(_ compressed: Data) throws -> Data {
        var stream = z_stream()
        let result = inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard result == Z_OK else { throw XPMProgramAnalysisError.malformedACVSHeader }
        defer { inflateEnd(&stream) }
        return try compressed.withUnsafeBytes { rawBuffer in
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: rawBuffer.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(compressed.count)
            var output = Data()
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            repeat {
                let status: Int32 = buffer.withUnsafeMutableBytes { buffer in
                    stream.next_out = buffer.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(buffer.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                output.append(buffer, count: buffer.count - Int(stream.avail_out))
                guard output.count <= maximumDecompressedSize else {
                    throw XPMProgramAnalysisError.decompressedDataTooLarge
                }
                if status == Z_STREAM_END { return output }
                guard status == Z_OK else { throw XPMProgramAnalysisError.malformedACVSHeader }
            } while true
        }
    }

    private static func analyzeLegacyXML(_ data: Data) throws -> XPMProgramAnalysis {
        let delegate = LegacyXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            if parser.parserError != nil { throw XPMProgramAnalysisError.malformedXML }
            throw XPMProgramAnalysisError.malformedXML
        }
        if let error = delegate.error { throw error }
        guard delegate.sawMPCObject, delegate.sawDrumProgram else {
            throw XPMProgramAnalysisError.malformedXML
        }
        guard delegate.padNotes.count == 128 else {
            throw XPMProgramAnalysisError.invalidPadCount(delegate.padNotes.count)
        }
        let notes = try (1...128).map { padNumber -> Int in
            guard let note = delegate.padNotes[padNumber] else {
                throw XPMProgramAnalysisError.invalidPadCount(delegate.padNotes.count)
            }
            return note
        }
        let nodes = (1...128).map { padNumber -> [String: Any] in
            let layers: [[String: Any]] = (delegate.layersByInstrument[padNumber] ?? []).map { layer in
                var item: [String: Any] = [:]
                if let name = layer.sampleName { item["sampleName"] = name }
                if let file = layer.sampleFile { item["sampleFile"] = file }
                if let start = layer.velocityStart { item["velocityStart"] = Int(start) }
                if let end = layer.velocityEnd { item["velocityEnd"] = Int(end) }
                return item
            }
            return ["layersv": layers]
        }
        let name = delegate.programName ?? "Imported legacy MPC drum program"
        let pads = try makePads(notes: notes, layerNodes: nodes)
        guard pads.contains(where: { !$0.isEmpty }) else { throw XPMProgramAnalysisError.noPopulatedPads }
        return XPMProgramAnalysis(
            programName: name,
            format: .legacyXML,
            formatVersion: delegate.formatVersion,
            pads: pads
        )
    }
}

private final class LegacyXMLDelegate: NSObject, XMLParserDelegate {
    struct LayerDraft {
        var sampleName: String?
        var sampleFile: String?
        var velocityStart: UInt8?
        var velocityEnd: UInt8?
    }

    var programName: String?
    var formatVersion: String?
    var padNotes: [Int: Int] = [:]
    var layersByInstrument: [Int: [XPMProgramLayer]] = [:]
    var error: XPMProgramAnalysisError?
    var sawMPCObject = false
    var sawDrumProgram = false

    private var elementStack: [String] = []
    private var text = ""
    private var currentPadNumber: Int?
    private var currentInstrumentNumber: Int?
    private var currentLayer: LayerDraft?

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        elementStack.append(name)
        text = ""
        switch name {
        case "MPCVObject":
            sawMPCObject = true
        case "Program":
            sawDrumProgram = attributes["type"] == "Drum"
        case "PadNote" where elementStack.dropLast().last == "PadNoteMap":
            guard let raw = attributes["number"], let number = Int(raw), (1...128).contains(number) else {
                error = .malformedXML
                return
            }
            currentPadNumber = number
        case "Instrument" where elementStack.dropLast().last == "Instruments":
            guard let raw = attributes["number"], let number = Int(raw), (1...128).contains(number) else {
                error = .malformedXML
                return
            }
            currentInstrumentNumber = number
        case "Layer" where currentInstrumentNumber != nil:
            currentLayer = LayerDraft()
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "ProgramName" where !value.isEmpty:
            programName = value
        case "File_Version" where !value.isEmpty:
            formatVersion = value
        case "Note" where currentPadNumber != nil:
            guard let number = currentPadNumber, let note = Int(value) else {
                error = .malformedXML
                break
            }
            if padNotes.updateValue(note, forKey: number) != nil {
                error = .malformedXML
            }
        case "SampleName" where currentLayer != nil:
            currentLayer?.sampleName = value.isEmpty ? nil : value
        case "SampleFile" where currentLayer != nil:
            currentLayer?.sampleFile = value.isEmpty ? nil : value
        case "VelStart" where currentLayer != nil:
            currentLayer?.velocityStart = parseVelocity(value)
        case "VelEnd" where currentLayer != nil:
            currentLayer?.velocityEnd = parseVelocity(value)
        case "Layer":
            if let instrument = currentInstrumentNumber, let layer = currentLayer {
                let sampleFile = layer.sampleFile ?? layer.sampleName.map { $0 + ".WAV" }
                if let start = layer.velocityStart, let end = layer.velocityEnd, start > end {
                    error = .invalidVelocityRange(start: start, end: end)
                }
                layersByInstrument[instrument, default: []].append(
                    XPMProgramLayer(
                        sampleName: layer.sampleName,
                        sampleFile: sampleFile,
                        velocityStart: layer.velocityStart,
                        velocityEnd: layer.velocityEnd
                    )
                )
            }
            currentLayer = nil
        case "PadNote":
            currentPadNumber = nil
        case "Instrument":
            currentInstrumentNumber = nil
        default:
            break
        }
        if !elementStack.isEmpty { elementStack.removeLast() }
        text = ""
    }

    private func parseVelocity(_ text: String) -> UInt8? {
        guard let value = Int(text), let velocity = UInt8(exactly: value), velocity <= 127 else {
            error = .invalidVelocity(Int(text) ?? -1)
            return nil
        }
        return velocity
    }
}
