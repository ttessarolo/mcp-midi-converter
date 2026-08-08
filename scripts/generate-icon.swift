#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate-icon.swift output.png\n", stderr)
    exit(64)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 1024,
    pixelsHigh: 1024,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("failed to create bitmap context\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
defer { NSGraphicsContext.restoreGraphicsState() }
context.imageInterpolation = .high
let outer = NSBezierPath(
    roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928),
    xRadius: 205,
    yRadius: 205
)
let gradient = NSGradient(
    colors: [
        NSColor(calibratedRed: 0.05, green: 0.16, blue: 0.34, alpha: 1),
        NSColor(calibratedRed: 0.10, green: 0.49, blue: 0.91, alpha: 1),
        NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.72, alpha: 1)
    ]
)!
gradient.draw(in: outer, angle: -40)

NSColor.white.withAlphaComponent(0.16).setStroke()
outer.lineWidth = 14
outer.stroke()

let arrow = "→" as NSString
let arrowAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 250, weight: .bold),
    .foregroundColor: NSColor.white.withAlphaComponent(0.92)
]
let arrowSize = arrow.size(withAttributes: arrowAttributes)
arrow.draw(
    at: NSPoint(x: (1024 - arrowSize.width) / 2, y: 392),
    withAttributes: arrowAttributes
)

func drawLabel(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 148, weight: .black),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph
    ]
    (value as NSString).draw(
        in: NSRect(x: x, y: y, width: width, height: 180),
        withAttributes: attributes
    )
}

drawLabel("GM", x: 92, y: 478, width: 340)
drawLabel("MPC", x: 570, y: 478, width: 370)

let subtitle = "MIDI" as NSString
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
subtitle.draw(
    in: NSRect(x: 180, y: 224, width: 664, height: 160),
    withAttributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 120, weight: .bold),
        .foregroundColor: NSColor.white.withAlphaComponent(0.86),
        .paragraphStyle: paragraph
    ]
)

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to render icon\n", stderr)
    exit(1)
}
try png.write(to: outputURL, options: .atomic)
