#!/usr/bin/env swift
// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("Resources/AppIcon.png")
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
let bounds = NSRect(origin: .zero, size: size)
NSColor.clear.setFill()
bounds.fill()
let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 40, dy: 40), xRadius: 212, yRadius: 212)
let gradient = NSGradient(colors: [NSColor(calibratedRed: 0.025, green: 0.075, blue: 0.16, alpha: 1), NSColor(calibratedRed: 0.055, green: 0.16, blue: 0.25, alpha: 1)])!
gradient.draw(in: background, angle: 60)

NSColor(calibratedRed: 0.38, green: 0.74, blue: 0.78, alpha: 0.32).setStroke()
for radius in [250.0, 335.0] {
    let orbit = NSBezierPath(ovalIn: NSRect(x: 512 - radius, y: 512 - radius * 0.65, width: radius * 2, height: radius * 1.3))
    orbit.lineWidth = 4
    orbit.stroke()
}

func sphere(center: CGPoint, radius: CGFloat, color: NSColor) {
    let glow = NSShadow()
    glow.shadowColor = color.withAlphaComponent(0.65)
    glow.shadowBlurRadius = radius * 0.6
    glow.shadowOffset = .zero
    NSGraphicsContext.saveGraphicsState()
    glow.set()
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
    NSGraphicsContext.restoreGraphicsState()
    let highlight = NSGradient(colors: [NSColor.white.withAlphaComponent(0.45), color])!
    highlight.draw(in: NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), angle: -55)
}
sphere(center: CGPoint(x: 341, y: 656), radius: 95, color: NSColor(calibratedRed: 1.0, green: 0.77, blue: 0.38, alpha: 1))
sphere(center: CGPoint(x: 696, y: 592), radius: 69, color: NSColor(calibratedRed: 1.0, green: 0.43, blue: 0.28, alpha: 1))
sphere(center: CGPoint(x: 474, y: 307), radius: 49, color: NSColor(calibratedRed: 0.61, green: 0.84, blue: 1.0, alpha: 1))
sphere(center: CGPoint(x: 786, y: 360), radius: 16, color: NSColor(calibratedRed: 0.36, green: 0.88, blue: 0.72, alpha: 1))

let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedDigitSystemFont(ofSize: 39, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.96, alpha: 0.82),
    .kern: 7
]
let label = NSAttributedString(string: "10 000", attributes: attributes)
label.draw(at: NSPoint(x: (1024 - label.size().width) / 2, y: 123))
image.unlockFocus()
guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("无法生成图标") }
try png.write(to: output)
// ICNS contains PNG representations and an 8-byte, big-endian chunk header.
// Write the container directly so regeneration does not depend on iconutil.
func bigEndianBytes(_ value: UInt32) -> Data {
    var bigEndian = value.bigEndian
    return withUnsafeBytes(of: &bigEndian) { Data($0) }
}
var chunks = Data()
for (type, pixels) in [("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024)] {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("无法分配图标图像") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let representation = rep.representation(using: .png, properties: [:]) else { fatalError("无法编码图标图像") }
    chunks.append(Data(type.utf8))
    chunks.append(bigEndianBytes(UInt32(representation.count + 8)))
    chunks.append(representation)
}
var icon = Data("icns".utf8)
icon.append(bigEndianBytes(UInt32(chunks.count + 8)))
icon.append(chunks)
try icon.write(to: root.appendingPathComponent("Resources/AppIcon.icns"))
print(output.path)
