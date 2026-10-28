// Draws MoodMix's app icon: a vinyl record with a Spotify-green label and a waveform.
// Usage: swift scripts/make-icon.swift <output.png> [--mac]
//   iOS: a full-bleed opaque square (iOS rounds the corners).
//   --mac: the same art on a rounded-square tile with the standard margin, on a transparent canvas.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let mac = CommandLine.arguments.contains("--mac")
// iOS icons must be fully opaque; the Mac tile needs a transparent margin around it.
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: mac ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)!
if mac {
    // macOS icon grid: an 824 px rounded square centered on the 1024 px canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil))
    ctx.setFillColor(CGColor(gray: 0.04, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil))
    ctx.clip()
    ctx.translateBy(x: tile.minX, y: tile.minY)
    ctx.scaleBy(x: tile.width / size, y: tile.height / size)
}
let green = CGColor(red: 0.118, green: 0.843, blue: 0.376, alpha: 1)
let center = CGPoint(x: size / 2, y: size / 2)

func radial(_ colors: [CGColor], _ locations: [CGFloat], at point: CGPoint, radius: CGFloat) {
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
    // No drawsAfterEndLocation: past `radius` the gradient must not paint over the rest of the icon.
    ctx.drawRadialGradient(gradient, startCenter: point, startRadius: 0, endCenter: point, endRadius: radius, options: [])
}

// Background: dark grey at the top fading to near-black, with a faint green tint.
let background = CGGradient(colorsSpace: space,
                            colors: [CGColor(red: 0.10, green: 0.16, blue: 0.12, alpha: 1), CGColor(red: 0.03, green: 0.03, blue: 0.035, alpha: 1)] as CFArray,
                            locations: [0, 1])!
ctx.drawLinearGradient(background, start: CGPoint(x: size / 2, y: size), end: CGPoint(x: size / 2, y: 0), options: [])
radial([green.copy(alpha: 0.28)!, green.copy(alpha: 0)!], [0, 1], at: CGPoint(x: size / 2, y: size * 0.9), radius: size * 0.75)

// Record with a drop shadow.
let disc = size * 0.40
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.02), blur: size * 0.05, color: CGColor(gray: 0, alpha: 0.7))
ctx.setFillColor(CGColor(gray: 0.03, alpha: 1))
ctx.fillEllipse(in: CGRect(x: center.x - disc, y: center.y - disc, width: disc * 2, height: disc * 2))
ctx.restoreGState()
radial([CGColor(gray: 0.17, alpha: 1), CGColor(gray: 0.05, alpha: 1), CGColor(gray: 0.02, alpha: 1)], [0, 0.7, 1], at: center, radius: disc)

// Grooves.
let label = disc * 0.42
var r = disc * 0.96
var i = 0
while r > label * 1.08 {
    ctx.setStrokeColor(CGColor(gray: 1, alpha: i % 2 == 0 ? 0.075 : 0.035))
    ctx.setLineWidth(size * 0.0025)
    ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    r -= disc * 0.045
    i += 1
}

// Light catching the grooves: two soft wedges.
for (start, end) in [(CGFloat.pi * 0.15, CGFloat.pi * 0.42), (CGFloat.pi * 1.15, CGFloat.pi * 1.42)] {
    ctx.saveGState()
    ctx.move(to: center)
    ctx.addArc(center: center, radius: disc * 0.99, startAngle: start, endAngle: end, clockwise: false)
    ctx.closePath()
    ctx.clip()
    radial([CGColor(gray: 1, alpha: 0.0), CGColor(gray: 1, alpha: 0.13), CGColor(gray: 1, alpha: 0.0)], [0.35, 0.75, 1], at: center, radius: disc)
    ctx.restoreGState()
}

// Rim.
ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.14))
ctx.setLineWidth(size * 0.004)
ctx.strokeEllipse(in: CGRect(x: center.x - disc, y: center.y - disc, width: disc * 2, height: disc * 2))

// Green label with a waveform.
ctx.setFillColor(green)
ctx.fillEllipse(in: CGRect(x: center.x - label, y: center.y - label, width: label * 2, height: label * 2))
radial([CGColor(gray: 1, alpha: 0.18), CGColor(gray: 1, alpha: 0)], [0, 1], at: CGPoint(x: center.x - label * 0.3, y: center.y + label * 0.35), radius: label)
let bars: [CGFloat] = [0.30, 0.62, 0.95, 0.62, 0.30]
let barWidth = label * 0.12
let gap = label * 0.075
let total = CGFloat(bars.count) * barWidth + CGFloat(bars.count - 1) * gap
ctx.setFillColor(CGColor(gray: 0, alpha: 0.88))
for (index, h) in bars.enumerated() {
    let height = label * 1.15 * h
    let x = center.x - total / 2 + CGFloat(index) * (barWidth + gap)
    ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: center.y - height / 2, width: barWidth, height: height),
                       cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
}
ctx.fillPath()

let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL,
                                                  UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
CGImageDestinationFinalize(destination)
