// Draws the app icon (the ring and the orange dot of the Tauri app's
// src-tauri/icons/icon.png) into the asset catalog, sharp at every size.
// Run from apple/ after changing the drawing:
//
//   swift scripts/app-icon.swift
//
// iPhone: one opaque 1024pt square, full bleed (iOS rounds the corners itself).
// Mac: Apple's icon grid, a rounded square of 824/1024 with a soft shadow,
// at each size the Mac asks for.

import AppKit

let out = URL(fileURLWithPath: "Nowboard/Assets.xcassets/AppIcon.appiconset")

// Measured on the Tauri icon, as fractions of its rounded square.
let paper = CGColor(srgbRed: 0xEF / 255, green: 0xEE / 255, blue: 0xE9 / 255, alpha: 1)
let ink = CGColor(srgbRed: 0x23 / 255, green: 0x23 / 255, blue: 0x22 / 255, alpha: 1)
let orange = CGColor(srgbRed: 0xEC / 255, green: 0x6A / 255, blue: 0x21 / 255, alpha: 1)
let ringRadius = 96.0 / 448, ringWidth = 22.0 / 448
let dotCenter = CGPoint(x: 332.5 / 448, y: 127.5 / 448), dotRadius = 35.0 / 448

/// The ring and the dot inside `square` (y down, as in the PNG).
func drawMark(in c: CGContext, square: CGRect) {
    let s = square.width
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: square.minX + x * s, y: square.maxY - y * s) }
    c.setStrokeColor(ink)
    c.setLineWidth(ringWidth * s)
    c.strokeEllipse(in: CGRect(origin: pt(0.5 - ringRadius, 0.5 + ringRadius), size: CGSize(width: 2 * ringRadius * s, height: 2 * ringRadius * s)))
    c.setFillColor(orange)
    let d = pt(dotCenter.x, dotCenter.y)
    c.fillEllipse(in: CGRect(x: d.x - dotRadius * s, y: d.y - dotRadius * s, width: 2 * dotRadius * s, height: 2 * dotRadius * s))
}

func write(_ name: String, size: Int, opaque: Bool, draw: (CGContext, CGFloat) -> Void) {
    let alpha: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
    let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: alpha.rawValue)!
    draw(c, CGFloat(size))
    let rep = NSBitmapImageRep(cgImage: c.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

write("ios-1024.png", size: 1024, opaque: true) { c, s in
    c.setFillColor(paper)
    c.fill(CGRect(x: 0, y: 0, width: s, height: s))
    drawMark(in: c, square: CGRect(x: 0, y: 0, width: s, height: s))
}

for size in [16, 32, 64, 128, 256, 512, 1024] {
    write("mac-\(size).png", size: size, opaque: false) { c, s in
        let k = s / 1024
        let square = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
        let shape = CGPath(roundedRect: square, cornerWidth: 185 * k, cornerHeight: 185 * k, transform: nil)
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 24 * k, color: CGColor(gray: 0, alpha: 0.3))
        c.setFillColor(paper)
        c.addPath(shape)
        c.fillPath()
        c.restoreGState()
        drawMark(in: c, square: square)
    }
}

// Which file is which: iOS takes one 1024 image, the Mac every size at 1x and 2x.
var images: [[String: String]] = [["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "ios-1024.png"]]
for pt in [16, 32, 128, 256, 512] {
    images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "1x", "filename": "mac-\(pt).png"])
    images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "2x", "filename": "mac-\(pt * 2).png"])
}
let json = try! JSONSerialization.data(withJSONObject: ["images": images, "info": ["author": "xcode", "version": 1]],
                                       options: [.prettyPrinted, .sortedKeys])
try! json.write(to: out.appendingPathComponent("Contents.json"))
print("wrote", out.path)
