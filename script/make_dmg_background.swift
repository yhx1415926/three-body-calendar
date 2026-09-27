#!/usr/bin/env swift
// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let outputURL = root.appendingPathComponent("Resources/DmgBackground.png")
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1440,
                                    pixelsHigh: 860, bitsPerSample: 8, samplesPerPixel: 4,
                                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                    bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("无法生成 DMG 背景")
}
let canvas = NSRect(x: 0, y: 0, width: 720, height: 430)
bitmap.size = canvas.size // Finder displays this 144 DPI image at 720 × 430 points.
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
context.cgContext.scaleBy(x: 2, y: 2)

let navy = NSColor(calibratedRed: 0.027, green: 0.070, blue: 0.133, alpha: 1)
let teal = NSColor(calibratedRed: 0.29, green: 0.78, blue: 0.81, alpha: 1)
let pale = NSColor(calibratedRed: 0.89, green: 0.97, blue: 1, alpha: 1)
NSGradient(colors: [navy, NSColor(calibratedRed: 0.063, green: 0.151, blue: 0.228, alpha: 1)])!
    .draw(in: canvas, angle: -23)

for (radius, alpha) in [(275.0, 0.10), (350.0, 0.08), (440.0, 0.055)] {
    let orbit = NSBezierPath(ovalIn: NSRect(x: 360 - radius, y: 210 - radius * 0.43,
                                         width: radius * 2, height: radius * 0.86))
    orbit.lineWidth = 1
    teal.withAlphaComponent(alpha).setStroke()
    orbit.stroke()
}
var seed: UInt64 = 0x5448524545424f44
func random() -> CGFloat {
    seed = seed &* 2862933555777941757 &+ 3037000493
    return CGFloat(seed % 10000) / 10000
}
for _ in 0..<80 {
    let point = CGPoint(x: 26 + random() * 668, y: 25 + random() * 380)
    let radius = random() > 0.88 ? 1.25 : 0.65
    pale.withAlphaComponent(0.12 + random() * 0.25).setFill()
    NSBezierPath(ovalIn: NSRect(x: point.x, y: point.y, width: radius * 2, height: radius * 2)).fill()
}

func label(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat,
           weight: NSFont.Weight, color: NSColor, tracking: CGFloat = 0) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .kern: tracking
    ]
    NSAttributedString(string: value, attributes: attributes).draw(at: NSPoint(x: x, y: y))
}

// Restrict the liquid-glass material to the two icon backplates.
for x in [70.0, 434.0] {
    let panel = NSRect(x: x, y: 118, width: 216, height: 174)
    let shape = NSBezierPath(roundedRect: panel, xRadius: 27, yRadius: 27)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = 18
    shadow.shadowOffset = NSSize(width: 0, height: -7)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.white.withAlphaComponent(0.42).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    // A consistent translucent surface leaves the stars and orbits faintly visible.
    NSColor(calibratedRed: 0.82, green: 0.93, blue: 1, alpha: 0.05).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    shape.lineWidth = 1.4
    pale.withAlphaComponent(0.78).setStroke()
    shape.stroke()
    let innerEdge = NSBezierPath(roundedRect: panel.insetBy(dx: 2, dy: 2),
                                 xRadius: 25, yRadius: 25)
    innerEdge.lineWidth = 0.8
    pale.withAlphaComponent(0.22).setStroke()
    innerEdge.stroke()
}

let dash = NSBezierPath(roundedRect: NSRect(x: 45, y: 345, width: 40, height: 3),
                        xRadius: 1.5, yRadius: 1.5)
teal.setFill()
dash.fill()
label("三体人的万年历", x: 45, y: 362, size: 22, weight: .semibold,
      color: pale, tracking: 0.6)
label("TRISOLARIS CALENDAR  /  1.2.0", x: 45, y: 324, size: 10,
      weight: .medium, color: teal.withAlphaComponent(0.78), tracking: 1.25)

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 315, y: 205))
arrow.line(to: NSPoint(x: 403, y: 205))
arrow.move(to: NSPoint(x: 390, y: 218))
arrow.line(to: NSPoint(x: 403, y: 205))
arrow.line(to: NSPoint(x: 390, y: 192))
arrow.lineWidth = 2.5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
teal.withAlphaComponent(0.95).setStroke()
arrow.stroke()

let line = NSBezierPath()
line.move(to: NSPoint(x: 45, y: 82))
line.line(to: NSPoint(x: 675, y: 82))
line.lineWidth = 1
pale.withAlphaComponent(0.14).setStroke()
line.stroke()
label("拖动左侧应用到右侧“应用程序”文件夹", x: 45, y: 46, size: 14,
      weight: .medium, color: pale.withAlphaComponent(0.90))
label("DRAG TO INSTALL", x: 558, y: 47, size: 9, weight: .semibold,
      color: teal.withAlphaComponent(0.76), tracking: 1)

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("无法编码 DMG 背景")
}
try png.write(to: outputURL)
print(outputURL.path)
