#!/usr/bin/env swift
import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let scriptURL = URL(fileURLWithPath: #filePath)
let repositoryRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let stackRoot = repositoryRoot
    .appendingPathComponent("ReplayXI/Assets.xcassets/AppIcon.solidimagestack")

let size = 1_024
let colourSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func colour(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colourSpace, components: [red, green, blue, alpha])!
}

func makeContext() -> CGContext {
    CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: colourSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

func writeLayer(_ relativePath: String, draw: (CGContext) -> Void) throws {
    let context = makeContext()
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    draw(context)
    let outputURL = stackRoot.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
              outputURL as CFURL,
              UTType.png.identifier as CFString,
              1,
              nil
          ) else {
        throw NSError(domain: "ReplayXIIcon", code: 1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "ReplayXIIcon", code: 2)
    }
}

try writeLayer("Back.solidimagestacklayer/Content.imageset/replayxi-back.png") { context in
    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    context.setFillColor(colour(0.012, 0.045, 0.032))
    context.fill(bounds)

    let gradient = CGGradient(
        colorsSpace: colourSpace,
        colors: [colour(0.06, 0.24, 0.14), colour(0.01, 0.04, 0.03)] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        gradient,
        startCenter: CGPoint(x: 760, y: 760),
        startRadius: 0,
        endCenter: CGPoint(x: 560, y: 520),
        endRadius: 850,
        options: [.drawsAfterEndLocation]
    )

    context.setFillColor(colour(0.08, 0.30, 0.17, 0.38))
    for index in 0..<8 where index.isMultiple(of: 2) {
        context.fill(CGRect(x: CGFloat(index) * 128, y: 0, width: 128, height: 1_024))
    }
}

try writeLayer("Middle.solidimagestacklayer/Content.imageset/replayxi-middle.png") { context in
    context.setStrokeColor(colour(0.90, 0.93, 0.82, 0.82))
    context.setLineWidth(18)
    context.addPath(
        CGPath(
            roundedRect: CGRect(x: 150, y: 125, width: 724, height: 774),
            cornerWidth: 30,
            cornerHeight: 30,
            transform: nil
        )
    )
    context.strokePath()

    context.move(to: CGPoint(x: 150, y: 512))
    context.addLine(to: CGPoint(x: 874, y: 512))
    context.strokePath()
    context.strokeEllipse(in: CGRect(x: 405, y: 405, width: 214, height: 214))

    context.setStrokeColor(colour(0.20, 0.92, 0.88, 0.95))
    context.setLineWidth(26)
    context.setLineCap(.round)
    context.move(to: CGPoint(x: 260, y: 360))
    context.addCurve(
        to: CGPoint(x: 750, y: 690),
        control1: CGPoint(x: 390, y: 350),
        control2: CGPoint(x: 610, y: 575)
    )
    context.strokePath()

    context.setFillColor(colour(1.0, 0.38, 0.08))
    context.move(to: CGPoint(x: 742, y: 690))
    context.addLine(to: CGPoint(x: 670, y: 663))
    context.addLine(to: CGPoint(x: 710, y: 613))
    context.closePath()
    context.fillPath()
}

try writeLayer("Front.solidimagestacklayer/Content.imageset/replayxi-front.png") { context in
    let badge = CGPath(
        roundedRect: CGRect(x: 310, y: 310, width: 404, height: 404),
        cornerWidth: 104,
        cornerHeight: 104,
        transform: nil
    )
    context.addPath(badge)
    context.setFillColor(colour(0.78, 0.94, 0.19))
    context.fillPath()

    let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 210, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): colour(0.01, 0.035, 0.025)
    ]
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: "XI", attributes: attributes)
    )
    let textBounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
    context.textPosition = CGPoint(
        x: 512 - textBounds.width / 2 - textBounds.minX,
        y: 512 - textBounds.height / 2 - textBounds.minY
    )
    CTLineDraw(line, context)
}

print("Generated Replay XI visionOS icon layers in \(stackRoot.path)")
