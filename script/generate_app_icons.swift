#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = root.appendingPathComponent("Resources/Brand/PhoneDock/AppIcon-Source.png")

guard let source = NSImage(contentsOf: sourceURL) else {
    fputs("Could not read \(sourceURL.path)\n", stderr)
    exit(1)
}

let brandBackground = CGColor(red: 0.4, green: 0.314, blue: 0.847, alpha: 1)
var sourceRect = NSRect(origin: .zero, size: source.size)
guard let sourceImage = source.cgImage(forProposedRect: &sourceRect, context: nil, hints: nil) else {
    fputs("Could not decode the source image.\n", stderr)
    exit(1)
}

func writeIcon(size: Int, relativePath: String) throws {
    let isMac = relativePath.hasPrefix("Mac/")
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: isMac ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { throw CocoaError(.fileWriteUnknown) }
    context.interpolationQuality = .high
    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    let bounds = isMac ? canvas.insetBy(dx: CGFloat(size) * 0.08, dy: CGFloat(size) * 0.08) : canvas
    if isMac {
        let radius = bounds.width * 0.225
        context.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
    }
    context.setFillColor(brandBackground)
    context.fill(bounds)
    context.draw(sourceImage, in: bounds)
    guard let rendered = context.makeImage() else {
        throw CocoaError(.fileWriteUnknown)
    }
    let destinationURL = root.appendingPathComponent(relativePath)
    guard let destination = CGImageDestinationCreateWithURL(
        destinationURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(destination, rendered, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

let macIcons: [(Int, String)] = [
    (16, "AppIcon-16.png"),
    (32, "AppIcon-16@2x.png"),
    (32, "AppIcon-32.png"),
    (64, "AppIcon-32@2x.png"),
    (128, "AppIcon-128.png"),
    (256, "AppIcon-128@2x.png"),
    (256, "AppIcon-256.png"),
    (512, "AppIcon-256@2x.png"),
    (512, "AppIcon-512.png"),
    (1024, "AppIcon-512@2x.png")
]

for (size, name) in macIcons {
    try writeIcon(size: size, relativePath: "Mac/Assets.xcassets/AppIcon.appiconset/\(name)")
}
try writeIcon(size: 1024, relativePath: "Mobile/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")

print("Generated Phone Dock icons: masked macOS icons and opaque iOS icon.")
