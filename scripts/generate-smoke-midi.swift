#!/usr/bin/env swift

import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("Uso: generate-smoke-midi.swift input.mid expected.mid\n".utf8))
    exit(64)
}

func be16(_ value: UInt16) -> [UInt8] {
    [UInt8(value >> 8), UInt8(value & 0xFF)]
}

func be32(_ value: UInt32) -> [UInt8] {
    [
        UInt8((value >> 24) & 0xFF),
        UInt8((value >> 16) & 0xFF),
        UInt8((value >> 8) & 0xFF),
        UInt8(value & 0xFF)
    ]
}

func midiFile(noteKeys: [UInt8]) -> Data {
    precondition(noteKeys.count == 6)
    var track: [UInt8] = [
        0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20
    ]
    for (index, note) in noteKeys.enumerated() {
        track += index == 0
            ? [0x00, 0x99, note, 100]
            : [0x78, note, UInt8(100 - index)]
    }
    track += [0x00, 0x89, noteKeys[0], 64]
    track += [0x00, 0xFF, 0x2F, 0x00]

    var bytes = Array("MThd".utf8)
    bytes += be32(6)
    bytes += be16(0)
    bytes += be16(1)
    bytes += be16(480)
    bytes += Array("MTrk".utf8)
    bytes += be32(UInt32(track.count))
    bytes += track
    return Data(bytes)
}

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let expected = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(
    at: input.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try midiFile(noteKeys: [36, 38, 42, 46, 49, 51]).write(to: input)
try midiFile(noteKeys: [36, 37, 38, 39, 50, 48]).write(to: expected)
