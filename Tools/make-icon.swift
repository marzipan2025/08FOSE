// make-icon.swift — shape a full-bleed square master into a macOS icon.
//
// macOS (unlike iOS) does NOT round app-icon corners automatically; it draws
// the artwork as-is. Bake the rounded silhouette into the art so Finder and
// Dock use the same visible shape.
//
//   usage: swift Tools/make-icon.swift <source.png> <out.png>

import AppKit
import CoreGraphics

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <src.png> <out.png>\n".utf8))
    exit(2)
}
let srcPath = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]

guard let src = NSImage(contentsOfFile: srcPath),
      let srcCG = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("cannot read \(srcPath)\n".utf8))
    exit(1)
}

let canvas: CGFloat = 1024
let radius: CGFloat = 230

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(
    data: nil, width: Int(canvas), height: Int(canvas),
    bitsPerComponent: 8, bytesPerRow: 0, space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

ctx.interpolationQuality = .high
ctx.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

let bodyRect = CGRect(x: 0, y: 0, width: canvas, height: canvas)
let path = CGPath(roundedRect: bodyRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.addPath(path)
ctx.clip()
ctx.draw(srcCG, in: bodyRect)

guard let out = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: out)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: outPath))
