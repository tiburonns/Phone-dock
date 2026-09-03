import AppKit
import Foundation
let input = CommandLine.arguments[1], output = CommandLine.arguments[2]
let source = NSImage(contentsOfFile: input)!
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
source.draw(in: NSRect(x: 0, y: 0, width: 256, height: 256))
NSGraphicsContext.restoreGraphicsState()
let png = bitmap.representation(using: .png, properties: [:])!
var ico = Data([0,0,1,0,1,0,0,0,0,0,1,0,32,0])
for value in [UInt32(png.count), UInt32(22)] {
    var little = value.littleEndian
    withUnsafeBytes(of: &little) { ico.append(contentsOf: $0) }
}
ico.append(png)
try ico.write(to: URL(fileURLWithPath: output))
