#!/usr/bin/env swift
import AppKit
import Foundation

let canvasSize = 1024
let outputPath = CommandLine.arguments.dropFirst().first ?? "Assets/AppIcon.png"

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvasSize,
    pixelsHigh: canvasSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Unable to create icon bitmap")
}

guard let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Unable to create icon graphics context")
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func stroke(_ path: NSBezierPath, color strokeColor: NSColor, width: CGFloat) {
    strokeColor.setStroke()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
graphics.cgContext.setAllowsAntialiasing(true)
graphics.cgContext.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))

let tileRect = NSRect(x: 82, y: 82, width: 860, height: 860)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 198, yRadius: 198)
graphics.cgContext.saveGState()
graphics.cgContext.setShadow(
    offset: CGSize(width: 0, height: -22),
    blur: 34,
    color: color(0, 0, 0, 0.28).cgColor
)
color(20, 24, 28).setFill()
tile.fill()
graphics.cgContext.restoreGState()

color(55, 65, 73).setStroke()
tile.lineWidth = 8
tile.stroke()

let dialRect = NSRect(x: 211, y: 211, width: 602, height: 602)
let dial = NSBezierPath(ovalIn: dialRect)
color(31, 38, 44).setFill()
dial.fill()
color(69, 82, 91).setStroke()
dial.lineWidth = 9
dial.stroke()

let tickColor = color(101, 116, 126, 0.62)
for angle in stride(from: 0.0, to: 360.0, by: 45.0) {
    let radians = CGFloat(angle * Double.pi / 180)
    let inner = CGFloat(250)
    let outer = CGFloat(276)
    let center = CGPoint(x: 512, y: 512)
    let path = NSBezierPath()
    path.move(to: CGPoint(
        x: center.x + cos(radians) * inner,
        y: center.y + sin(radians) * inner
    ))
    path.line(to: CGPoint(
        x: center.x + cos(radians) * outer,
        y: center.y + sin(radians) * outer
    ))
    stroke(path, color: tickColor, width: 14)
}

let download = NSBezierPath()
download.move(to: NSPoint(x: 386, y: 681))
download.line(to: NSPoint(x: 386, y: 397))
download.move(to: NSPoint(x: 300, y: 483))
download.line(to: NSPoint(x: 386, y: 397))
download.line(to: NSPoint(x: 472, y: 483))
stroke(download, color: color(77, 220, 166), width: 54)

let upload = NSBezierPath()
upload.move(to: NSPoint(x: 638, y: 343))
upload.line(to: NSPoint(x: 638, y: 627))
upload.move(to: NSPoint(x: 552, y: 541))
upload.line(to: NSPoint(x: 638, y: 627))
upload.line(to: NSPoint(x: 724, y: 541))
stroke(upload, color: color(255, 119, 105), width: 54)

let activity = NSBezierPath()
activity.move(to: NSPoint(x: 283, y: 277))
activity.curve(
    to: NSPoint(x: 741, y: 277),
    controlPoint1: NSPoint(x: 405, y: 232),
    controlPoint2: NSPoint(x: 619, y: 322)
)
stroke(activity, color: color(98, 194, 231, 0.68), width: 18)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode icon PNG")
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: outputURL, options: .atomic)
print("Generated \(outputURL.path)")
