import Foundation
import Testing
@testable import MPCMidiConverterCore

struct StandardMIDIRewriterTests {
    private let fallbackConfiguration = MIDITranslationConfiguration(
        profile: .bfdPop113,
        unavailableNotePolicy: .musicalFallback,
        channels: .generalMIDIPercussion
    )

    @Test("Rewrites only note keys and preserves every other byte")
    func bytePreservingRewrite() throws {
        let track = trackChunk([
            0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20, // Tempo meta-event.
            0x00, 0x99, 36, 100,                         // Kick: maps to itself.
            0x0A, 38, 110,                               // Running-status snare.
            0x00, 0x89, 36, 64,                          // Explicit Note Off.
            0x00, 38, 64,                                // Running-status Note Off.
            0x00, 0x90, 38, 90,                          // Channel 1: untouched.
            0x00, 0xF0, 0x03, 0x01, 0x02, 0x03,          // SysEx.
            0x00, 0xA9, 42, 70,                          // Poly key pressure follows key map.
            0x00, 0xFF, 0x2F, 0x00                       // End of Track.
        ])
        let input = midiFile(format: 1, tracks: [track])

        let result = try StandardMIDIRewriter.rewrite(input, configuration: fallbackConfiguration)

        #expect(result.data.count == input.count)
        #expect(result.report.parsedTrackCount == 1)
        #expect(result.report.eligibleEvents == 5)
        #expect(result.report.changedEvents == 3)
        #expect(result.report.directEvents == 5)
        #expect(result.report.polyphonicKeyPressureEvents == 1)

        let before = [UInt8](input)
        let after = [UInt8](result.data)
        let actualChanged = Set(before.indices.filter { before[$0] != after[$0] })
        #expect(actualChanged == result.changedByteOffsets)
        #expect(actualChanged.count == 3)
        for offset in before.indices where !actualChanged.contains(offset) {
            #expect(before[offset] == after[offset])
        }
    }

    @Test("Maps Note On velocity zero as a note event")
    func noteOnVelocityZero() throws {
        let input = midiFile(tracks: [trackChunk([
            0x00, 0x99, 38, 0,
            0x00, 0xFF, 0x2F, 0x00
        ])])
        let result = try StandardMIDIRewriter.rewrite(input, configuration: fallbackConfiguration)
        #expect(result.report.eligibleEvents == 1)
        #expect(result.report.changedEvents == 1)
        #expect([UInt8](result.data).containsSubsequence([0x99, 37, 0]))
    }

    @Test("Applies fallback, silence and keep policies distinctly")
    func unavailablePolicies() throws {
        let input = midiFile(tracks: [trackChunk([
            0x00, 0x99, 39, 100, // Hand Clap: declared fallback.
            0x00, 54, 90,         // Tambourine: no source sound.
            0x00, 0xFF, 0x2F, 0x00
        ])])

        let fallback = try StandardMIDIRewriter.rewrite(
            input,
            configuration: MIDITranslationConfiguration(
                profile: .bfdPop113,
                unavailableNotePolicy: .musicalFallback
            )
        )
        #expect(fallback.report.fallbackEvents == 1)
        #expect(fallback.report.silencedEvents == 1)
        #expect(noteKeys(in: fallback.data) == [41, 0])

        let silence = try StandardMIDIRewriter.rewrite(
            input,
            configuration: MIDITranslationConfiguration(
                profile: .bfdPop113,
                unavailableNotePolicy: .silence
            )
        )
        #expect(silence.report.fallbackEvents == 0)
        #expect(silence.report.silencedEvents == 2)
        #expect(noteKeys(in: silence.data) == [0, 0])

        let keep = try StandardMIDIRewriter.rewrite(
            input,
            configuration: MIDITranslationConfiguration(
                profile: .bfdPop113,
                unavailableNotePolicy: .keepOriginal
            )
        )
        #expect(keep.report.keptOriginalEvents == 2)
        #expect(noteKeys(in: keep.data) == [39, 54])
    }

    @Test("Default touches channel 10 only; all-channels mode is explicit")
    func channelSelection() throws {
        let input = midiFile(tracks: [trackChunk([
            0x00, 0x90, 38, 100,
            0x00, 0x99, 38, 100,
            0x00, 0xFF, 0x2F, 0x00
        ])])

        let channel10 = try StandardMIDIRewriter.rewrite(
            input,
            configuration: fallbackConfiguration
        )
        #expect(noteKeys(in: channel10.data) == [38, 37])

        let all = try StandardMIDIRewriter.rewrite(
            input,
            configuration: MIDITranslationConfiguration(
                profile: .bfdPop113,
                channels: .allChannels
            )
        )
        #expect(noteKeys(in: all.data) == [37, 37])
    }

    @Test("Preserves unknown chunks and parses multiple tracks")
    func multipleTracksAndUnknownChunks() throws {
        let unknown = chunk(id: "XFIH", payload: [1, 2, 3, 4, 5])
        let first = trackChunk([0, 0x99, 42, 100, 0, 0xFF, 0x2F, 0])
        let second = trackChunk([0, 0x99, 46, 100, 0, 0xFF, 0x2F, 0])
        let input = midiFile(format: 2, chunks: [unknown, first, second], declaredTracks: 2)

        let result = try StandardMIDIRewriter.rewrite(input, configuration: fallbackConfiguration)
        #expect(result.report.format == 2)
        #expect(result.report.parsedTrackCount == 2)
        #expect([UInt8](result.data).containsSubsequence(Array("XFIH".utf8) + [0, 0, 0, 5, 1, 2, 3, 4, 5]))
    }

    @Test("Preserves safe trailing whitespace and rejects unknown trailing bytes")
    func trailingPadding() throws {
        let base = midiFile(tracks: [trackChunk([
            0x00, 0x99, 38, 100,
            0x00, 0xFF, 0x2F, 0x00
        ])])
        var padded = base
        let padding = Data([0x0A, 0x0A, 0x0D, 0x20, 0x09])
        padded.append(padding)

        let result = try StandardMIDIRewriter.rewrite(
            padded,
            configuration: fallbackConfiguration
        )

        #expect(result.data.count == padded.count)
        #expect(result.data.suffix(padding.count) == padding)
        #expect(result.report.parsedTrackCount == 1)
        #expect(noteKeys(in: result.data) == [37])

        var invalidTail = base
        invalidTail.append(contentsOf: [0x0A, 0x01])
        #expect(throws: MIDIConversionError.self) {
            try StandardMIDIRewriter.rewrite(
                invalidTail,
                configuration: fallbackConfiguration
            )
        }
    }

    @Test("Rejects running status after a meta event")
    func runningStatusInterruptedByMetaEvent() {
        let input = midiFile(tracks: [trackChunk([
            0, 0x99, 38, 100,
            0, 0xFF, 0x01, 0x01, 0x41,
            0, 38, 100
        ])])
        #expect(throws: MIDIConversionError.self) {
            try StandardMIDIRewriter.rewrite(input, configuration: fallbackConfiguration)
        }
    }

    @Test("Rejects oversized and truncated variable-length quantities")
    func invalidVariableLengthQuantities() {
        let oversized = midiFile(tracks: [trackChunk([0x81, 0x80, 0x80, 0x80, 0x00])])
        #expect(throws: MIDIConversionError.self) {
            try StandardMIDIRewriter.rewrite(oversized, configuration: fallbackConfiguration)
        }

        let truncated = midiFile(tracks: [trackChunk([0x81])])
        #expect(throws: MIDIConversionError.self) {
            try StandardMIDIRewriter.rewrite(truncated, configuration: fallbackConfiguration)
        }
    }

    @Test("Rejects malformed headers, track counts and forbidden system events")
    func malformedFiles() {
        #expect(throws: MIDIConversionError.self) {
            try StandardMIDIRewriter.rewrite(Data([1, 2, 3]), configuration: fallbackConfiguration)
        }

        let wrongTrackCount = midiFile(
            chunks: [trackChunk([0, 0xFF, 0x2F, 0])],
            declaredTracks: 2
        )
        #expect(throws: MIDIConversionError.self) {
            try StandardMIDIRewriter.rewrite(wrongTrackCount, configuration: fallbackConfiguration)
        }

        let forbiddenStatus = midiFile(tracks: [trackChunk([0, 0xF1, 0])])
        #expect(throws: MIDIConversionError.self) {
            try StandardMIDIRewriter.rewrite(forbiddenStatus, configuration: fallbackConfiguration)
        }
    }

    @Test("Output naming adds -mpc and refuses collisions by default")
    func outputNamingAndCollision() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("Song.Name.mid")
        try Data([1, 2, 3]).write(to: input)
        let expected = directory.appendingPathComponent("Song.Name-mpc.mid")
        #expect(try OutputFile.url(for: input) == expected)
        #expect(try OutputFile.write(Data([4]), for: input, overwrite: false) == expected)
        #expect(throws: OutputFileError.self) {
            try OutputFile.write(Data([5]), for: input, overwrite: false)
        }
        _ = try OutputFile.write(Data([6]), for: input, overwrite: true)
        #expect(try Data(contentsOf: expected) == Data([6]))
    }

    @Test("Concurrent writers cannot replace an output when overwrite is disabled")
    func concurrentOutputCollision() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("Race.mid")
        try Data().write(to: input)
        let outcomes = await withTaskGroup(of: RaceOutcome.self) { group in
            for marker in UInt8(0)..<UInt8(32) {
                group.addTask {
                    do {
                        _ = try OutputFile.write(
                            Data(repeating: marker, count: 4_096),
                            for: input,
                            overwrite: false
                        )
                        return .success(marker)
                    } catch OutputFileError.outputAlreadyExists {
                        return .collision
                    } catch {
                        return .unexpected(error.localizedDescription)
                    }
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        let winners = outcomes.compactMap { outcome -> UInt8? in
            if case let .success(marker) = outcome { return marker }
            return nil
        }
        let unexpected = outcomes.compactMap { outcome -> String? in
            if case let .unexpected(message) = outcome { return message }
            return nil
        }
        #expect(winners.count == 1)
        #expect(unexpected.isEmpty)
        let output = try OutputFile.url(for: input)
        #expect(try Data(contentsOf: output) == Data(repeating: winners[0], count: 4_096))
    }

    @Test("Loads validated external profile JSON")
    func externalProfile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let json = """
        {
          "id":"test", "name":"Test", "description":"Test profile",
          "source":"GM", "target":"MPC", "gmRange":[35,81], "silentNote":0,
          "direct":{"36":40}, "fallback":{"39":41}
        }
        """
        try Data(json.utf8).write(to: url)
        let profile = try TranslationProfile.load(from: url)
        #expect(profile.direct[36] == 40)
        #expect(profile.fallback[39] == 41)
    }

    @Test("Rejects ambiguous or out-of-range profile mappings")
    func invalidExternalProfiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("profiles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let overlap = directory.appendingPathComponent("overlap.json")
        try Data("""
        {
          "id":"overlap", "name":"Overlap", "description":"Test",
          "source":"GM", "target":"MPC", "gmRange":[35,81], "silentNote":0,
          "direct":{"36":40}, "fallback":{"36":41}
        }
        """.utf8).write(to: overlap)
        #expect(throws: ProfileError.self) {
            try TranslationProfile.load(from: overlap)
        }

        let outOfRange = directory.appendingPathComponent("out-of-range.json")
        try Data("""
        {
          "id":"range", "name":"Range", "description":"Test",
          "source":"GM", "target":"MPC", "gmRange":[35,81], "silentNote":0,
          "direct":{"34":40}, "fallback":{}
        }
        """.utf8).write(to: outOfRange)
        #expect(throws: ProfileError.self) {
            try TranslationProfile.load(from: outOfRange)
        }

        let invalidSilentNote = directory.appendingPathComponent("invalid-silent.json")
        try Data("""
        {
          "id":"silent", "name":"Silent", "description":"Test",
          "source":"GM", "target":"MPC", "gmRange":[35,81], "silentNote":200,
          "direct":{}, "fallback":{}
        }
        """.utf8).write(to: invalidSilentNote)
        #expect(throws: ProfileError.self) {
            try TranslationProfile.load(from: invalidSilentNote)
        }
    }

    @Test("Refuses invalid MIDI data bytes from a programmatic profile")
    func invalidProgrammaticProfile() {
        let invalidProfile = TranslationProfile(
            id: "invalid-runtime",
            name: "Invalid runtime profile",
            description: "Test",
            source: "GM",
            target: "MPC",
            gmRange: 35...81,
            silentNote: 200,
            direct: [38: 200],
            fallback: [:]
        )
        let input = midiFile(tracks: [trackChunk([
            0x00, 0x99, 38, 100,
            0x00, 0xFF, 0x2F, 0x00
        ])])
        #expect(throws: ProfileError.self) {
            try StandardMIDIRewriter.rewrite(
                input,
                configuration: MIDITranslationConfiguration(profile: invalidProfile)
            )
        }
    }

    @Test("Exports a profile as canonical JSON that loads without losing mappings")
    func profileJSONRoundTrip() throws {
        let data = try TranslationProfile.bfdPop113.jsonData()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile-roundtrip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("profile.json")
        try data.write(to: file)

        let decoded = try TranslationProfile.load(from: file)
        #expect(decoded == .bfdPop113)
        #expect(String(decoding: data, as: UTF8.self).contains("\"35\" : 36"))
    }
}

private enum RaceOutcome: Sendable {
    case success(UInt8)
    case collision
    case unexpected(String)
}

private func midiFile(format: UInt16 = 1, tracks: [[UInt8]]) -> Data {
    midiFile(format: format, chunks: tracks, declaredTracks: UInt16(tracks.count))
}

private func midiFile(
    format: UInt16 = 1,
    chunks: [[UInt8]],
    declaredTracks: UInt16
) -> Data {
    var bytes = Array("MThd".utf8)
    bytes += be32(6)
    bytes += be16(format)
    bytes += be16(declaredTracks)
    bytes += be16(480)
    chunks.forEach { bytes += $0 }
    return Data(bytes)
}

private func trackChunk(_ payload: [UInt8]) -> [UInt8] {
    chunk(id: "MTrk", payload: payload)
}

private func chunk(id: String, payload: [UInt8]) -> [UInt8] {
    Array(id.utf8) + be32(UInt32(payload.count)) + payload
}

private func be16(_ value: UInt16) -> [UInt8] {
    [UInt8(value >> 8), UInt8(value & 0xFF)]
}

private func be32(_ value: UInt32) -> [UInt8] {
    [
        UInt8((value >> 24) & 0xFF),
        UInt8((value >> 16) & 0xFF),
        UInt8((value >> 8) & 0xFF),
        UInt8(value & 0xFF)
    ]
}

private func noteKeys(in data: Data) -> [UInt8] {
    let bytes = [UInt8](data)
    var result: [UInt8] = []
    var index = 14
    var runningStatus: UInt8?
    while index + 8 <= bytes.count {
        let id = String(decoding: bytes[index..<(index + 4)], as: UTF8.self)
        let length = Int(UInt32(bytes[index + 4]) << 24
            | UInt32(bytes[index + 5]) << 16
            | UInt32(bytes[index + 6]) << 8
            | UInt32(bytes[index + 7]))
        let end = index + 8 + length
        if id != "MTrk" {
            index = end
            continue
        }
        var cursor = index + 8
        while cursor < end {
            while cursor < end, bytes[cursor] & 0x80 != 0 { cursor += 1 }
            cursor += 1
            guard cursor < end else { break }
            let status: UInt8
            if bytes[cursor] & 0x80 != 0 {
                status = bytes[cursor]
                cursor += 1
                if status < 0xF0 { runningStatus = status }
            } else if let runningStatus {
                status = runningStatus
            } else {
                break
            }
            let type = status & 0xF0
            if status == 0xFF {
                runningStatus = nil
                cursor += 1
                let length = Int(bytes[cursor])
                cursor += 1 + length
            } else if status == 0xF0 || status == 0xF7 {
                runningStatus = nil
                let length = Int(bytes[cursor])
                cursor += 1 + length
            } else {
                let dataLength = (type == 0xC0 || type == 0xD0) ? 1 : 2
                if type == 0x80 || type == 0x90 {
                    result.append(bytes[cursor])
                }
                cursor += dataLength
            }
        }
        index = end
    }
    return result
}

private extension Array where Element == UInt8 {
    func containsSubsequence(_ subsequence: [UInt8]) -> Bool {
        guard !subsequence.isEmpty, subsequence.count <= count else { return false }
        return indices.dropLast(subsequence.count - 1).contains { start in
            Array(self[start..<(start + subsequence.count)]) == subsequence
        }
    }
}
