import AppKit

// Glide app icon — calm "gesture ripple": soft lavender squircle, white rings
// spreading from an off-center fingertip touch.

func hex(_ s: String) -> NSColor {
    var h = s; if h.hasPrefix("#") { h.removeFirst() }
    let v = UInt32(h, radix: 16) ?? 0
    return NSColor(srgbRed: CGFloat((v>>16)&0xff)/255, green: CGFloat((v>>8)&0xff)/255,
                   blue: CGFloat(v&0xff)/255, alpha: 1)
}

let topColor    = hex("#C9BEEA")   // soft lilac
let bottomColor = hex("#9481C9")   // muted violet
let ringColor   = NSColor.white

func render(size: CGFloat) -> Data {
    let px = Int(size)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)

    // Squircle background (Big Sur continuous corner ≈ 22.37% of side).
    let inset = size * 0.055
    let side  = size - 2*inset
    let rect  = CGRect(x: inset, y: inset, width: side, height: side)
    let radius = side * 0.2237
    let bg = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(bg); ctx.clip()

    // Gradient fill.
    let grad = CGGradient(colorsSpace: cs, colors: [topColor.cgColor, bottomColor.cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

    // Gentle top light for soft depth.
    let light = CGGradient(colorsSpace: cs,
                           colors: [NSColor(white: 1, alpha: 0.16).cgColor,
                                    NSColor(white: 1, alpha: 0).cgColor] as CFArray,
                           locations: [0, 1])!
    ctx.drawRadialGradient(light,
                           startCenter: CGPoint(x: size*0.5, y: size*0.9), startRadius: 0,
                           endCenter: CGPoint(x: size*0.5, y: size*0.9), endRadius: size*0.7, options: [])

    // Ripple from an off-center touch point (lower-left). Rings spread outward,
    // fading and thinning; the squircle clips the far arcs like a real ripple.
    let c = CGPoint(x: size*0.37, y: size*0.40)
    let ringRadii: [CGFloat] = [0.13, 0.27, 0.42, 0.58, 0.74].map { $0 * side }
    for (i, r) in ringRadii.enumerated() {
        let t = CGFloat(i) / CGFloat(ringRadii.count - 1)
        let alpha = 0.92 * (1 - t*0.66)
        ctx.setStrokeColor(ringColor.withAlphaComponent(alpha).cgColor)
        ctx.setLineWidth(size * (0.021 - 0.008*t))
        ctx.addArc(center: c, radius: r, startAngle: 0, endAngle: .pi*2, clockwise: false)
        ctx.strokePath()
    }
    // Fingertip touch dot.
    ctx.setFillColor(ringColor.cgColor)
    ctx.addArc(center: c, radius: size*0.045, startAngle: 0, endAngle: .pi*2, clockwise: false)
    ctx.fillPath()

    ctx.restoreGState()

    let img = ctx.makeImage()!
    return NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
}

// Args: <outDir> [preview|iconset]
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let mode   = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "preview"

func write(_ size: CGFloat, _ name: String) {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    try! render(size: size).write(to: url)
}

if mode == "iconset" {
    // Apple .iconset required set.
    let specs: [(CGFloat, String)] = [
        (16,  "icon_16x16.png"),    (32,  "icon_16x16@2x.png"),
        (32,  "icon_32x32.png"),    (64,  "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),  (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),  (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),  (1024,"icon_512x512@2x.png"),
    ]
    for (s, n) in specs { write(s, n) }
    print("iconset written to \(outDir)")
} else {
    write(256, "preview.png")
    print("preview written")
}
