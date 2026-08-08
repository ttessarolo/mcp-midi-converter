import Foundation
import Testing
import zlib
@testable import MPCMidiConverterCore

struct XPMProgramAnalyzerTests {
    @Test("Reads MPC3 gzip ACVS JSON, pad notes, and velocity layers")
    func readsACVS() throws {
        let result = try XPMProgramAnalyzer.analyze(gzip(Data(acvsJSON().utf8)))
        #expect(result.format == .mpc3ACVSJSON)
        #expect(result.formatVersion == "3.9.1.2")
        #expect(result.programName == "Synthetic Kit")
        #expect(result.pads.count == 128)
        #expect(result.pads[0].note == 0)
        #expect(result.pads[0].layers[0].sampleFile == "Acoustic Kick 01.wav")
        #expect(result.pads[0].layers[0].velocityStart == 1)
        #expect(result.pads[0].layers[0].velocityEnd == 127)
        #expect(result.pads[1].isEmpty)
    }

    @Test("Proposes only direct mappings and an empty-pad silent note")
    func proposesConservatively() throws {
        let result = try XPMProgramAnalyzer.analyze(gzip(Data(acvsJSON().utf8)))
        let proposal = XPMGMProfileProposer.propose(from: result)
        #expect(proposal.direct[35] == 0)
        #expect(proposal.direct[36] == 0)
        #expect(proposal.fallback.isEmpty)
        #expect(proposal.silentNote == 1)
        #expect(proposal.evidence.allSatisfy { $0.confidence == .medium })
    }

    @Test("Requires every populated layer to agree and an explicit crash number")
    func rejectsAmbiguousRoleNames() {
        var pads = (0..<128).map {
            XPMProgramPad(index: $0, note: UInt8($0), layers: [])
        }
        pads[0] = XPMProgramPad(index: 0, note: 0, layers: [
            .init(sampleName: "Kick 01", sampleFile: "Kick 01.wav", velocityStart: 0, velocityEnd: 63),
            .init(sampleName: "Snare 02", sampleFile: "Snare 02.wav", velocityStart: 64, velocityEnd: 127)
        ])
        pads[1] = XPMProgramPad(index: 1, note: 1, layers: [
            .init(sampleName: "Crash", sampleFile: "Crash.wav", velocityStart: 0, velocityEnd: 127)
        ])
        pads[2] = XPMProgramPad(index: 2, note: 2, layers: [
            .init(sampleName: "Crash CR1 01", sampleFile: "Crash CR1 01.wav", velocityStart: 0, velocityEnd: 63),
            .init(sampleName: "Crash CR1 02", sampleFile: "Crash CR1 02.wav", velocityStart: 64, velocityEnd: 127)
        ])
        let proposal = XPMGMProfileProposer.propose(
            from: XPMProgramAnalysis(programName: "Review", format: .mpc3ACVSJSON, pads: pads)
        )
        #expect(proposal.direct[35] == nil)
        #expect(proposal.direct[36] == nil)
        #expect(proposal.direct[49] == 2)
    }

    @Test("Fails closed on duplicate notes and malformed ACVS")
    func rejectsInvalidPrograms() throws {
        #expect(throws: XPMProgramAnalysisError.self) {
            try XPMProgramAnalyzer.analyze(Data("not an xpm".utf8))
        }
        #expect(throws: XPMProgramAnalysisError.self) {
            try XPMProgramAnalyzer.analyze(gzip(Data(acvsJSON(duplicateFirstNote: true).utf8)))
        }
    }

    @Test("Reads legacy XML and rejects an incomplete pad set")
    func readsLegacyXML() throws {
        let padNotes = (1...128).map { number in
            "<PadNote number=\"\(number)\"><Note>\(number - 1)</Note></PadNote>"
        }.joined()
        let instruments = (1...128).map { number in
            number == 1
                ? "<Instrument number=\"1\"><Layers><Layer><SampleName>Kick</SampleName><VelStart>0</VelStart><VelEnd>127</VelEnd></Layer></Layers></Instrument>"
                : "<Instrument number=\"\(number)\"><Layers/></Instrument>"
        }.joined()
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MPCVObject><Version><File_Version>2.1</File_Version></Version><Program type="Drum">
        <ProgramName>Legacy</ProgramName><PadNoteMap>\(padNotes)</PadNoteMap><Instruments>\(instruments)</Instruments>
        </Program></MPCVObject>
        """
        let result = try XPMProgramAnalyzer.analyze(Data(xml.utf8))
        #expect(result.format == .legacyXML)
        #expect(result.formatVersion == "2.1")
        #expect(result.programName == "Legacy")
        #expect(result.pads[0].layers.first?.sampleFile == "Kick.WAV")
        #expect(throws: XPMProgramAnalysisError.self) {
            try XPMProgramAnalyzer.analyze(Data("<MPCVObject><Program type=\"Drum\"><PadNoteMap/></Program></MPCVObject>".utf8))
        }
    }
}

private func acvsJSON(duplicateFirstNote: Bool = false) -> String {
    let notes = (0..<128).map { index -> String in
        let value = duplicateFirstNote && index == 1 ? 0 : index
        return "\"value\(index)\":\(value)"
    }.joined(separator: ",")
    let pads = (0..<128).map { index -> String in
        if index == 0 {
            return "\"value0\":{\"layersv\":[{\"sampleName\":\"Acoustic Kick 01\",\"sampleFile\":\"Acoustic Kick 01.wav\",\"velocityStart\":1,\"velocityEnd\":127}]}"
        }
        return "\"value\(index)\":{\"layersv\":[]}"
    }.joined(separator: ",")
    return """
    ACVS
    3.9.1.2
    SerialisableProgramData
    json
    Linux
    {"data":{"name":"Synthetic Kit","padNoteMap":{"noteForPad":{\(notes)}},"samples":{\(pads)}}}
    """
}

private func gzip(_ input: Data) -> Data {
    var stream = z_stream()
    precondition(deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK)
    defer { deflateEnd(&stream) }
    return input.withUnsafeBytes { raw in
        stream.next_in = UnsafeMutablePointer<Bytef>(mutating: raw.bindMemory(to: Bytef.self).baseAddress)
        stream.avail_in = uInt(input.count)
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        repeat {
            let status: Int32 = buffer.withUnsafeMutableBytes { raw in
                stream.next_out = raw.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(raw.count)
                return deflate(&stream, Z_FINISH)
            }
            output.append(buffer, count: buffer.count - Int(stream.avail_out))
            if status == Z_STREAM_END { return output }
            precondition(status == Z_OK)
        } while true
    }
}
