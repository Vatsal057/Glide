import AppKit

// Glide README hero — the app icon (AppIcon.svg / render_icon.swift) opened out
// into a 2:1 banner. Same lilac-to-violet gradient, same white ripple spreading
// from one off-center fingertip, same soft top light. The only change is the
// aspect ratio: the ripple keeps expanding past the edges instead of being
// clipped by a squircle, which is what makes it read as a wide header rather
// than a stretched icon.
//
// Deliberately textless — the README's own H1 carries the name.

func hex(_ s: String) -> NSColor {
    var h = s; if h.hasPrefix("#") { h.removeFirst() }
    let v = UInt32(h, radix: 16) ?? 0
    return NSColor(srgbRed: CGFloat((v>>16)&0xff)/255, green: CGFloat((v>>8)&0xff)/255,
                   blue: CGFloat(v&0xff)/255, alpha: 1)
}

// Lifted from AppIcon.svg's own palette.
let topColor    = hex("#c7bde7")   // soft lilac
let bottomColor = hex("#9887c9")   // muted violet
let ringColor   = NSColor.white

func render(w: CGFloat, h: CGFloat) -> Data {
    let pxW = Int(w), pxH = Int(h)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: pxW, height: pxH, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)

    // Rounded banner, so it sits in the README as a card rather than a hard block.
    let radius = h * 0.055
    let bounds = CGRect(x: 0, y: 0, width: w, height: h)
    let card = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(card); ctx.clip()

    // ── Gradient, top-to-bottom, exactly as the icon ──
    let grad = CGGradient(colorsSpace: cs, colors: [topColor.cgColor, bottomColor.cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])

    // ── Gentle top light for soft depth (icon's own treatment) ──
    let light = CGGradient(colorsSpace: cs,
                           colors: [NSColor(white: 1, alpha: 0.16).cgColor,
                                    NSColor(white: 1, alpha: 0).cgColor] as CFArray,
                           locations: [0, 1])!
    ctx.drawRadialGradient(light,
                           startCenter: CGPoint(x: w * 0.5, y: h * 0.95), startRadius: 0,
                           endCenter: CGPoint(x: w * 0.5, y: h * 0.95), endRadius: h * 1.1, options: [])

    // ── The ripple ──
    // Sized so the whole motif is legible at a glance, the way it is inside the
    // icon's squircle. Zoomed in any further and the rings stop reading as a
    // ripple and start reading as abstract wallpaper.
    // Origin sits left of center and slightly low, mirroring the icon's own
    // off-center touch point, which gives the rings room to travel across the
    // banner's extra width.
    let c = CGPoint(x: w * 0.40, y: h * 0.48)

    // The icon's five rings: bold and white, fading and thinning as they spread.
    let ringRadii: [CGFloat] = [0.085, 0.170, 0.265, 0.370, 0.485].map { $0 * h }
    for (i, r) in ringRadii.enumerated() {
        let t = CGFloat(i) / CGFloat(ringRadii.count - 1)
        ctx.setStrokeColor(ringColor.withAlphaComponent(0.92 * (1 - t * 0.62)).cgColor)
        ctx.setLineWidth(h * (0.0165 - 0.0068 * t))
        ctx.addArc(center: c, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()
    }

    // Two faint outriders running off the edges, so the extra width a banner has
    // reads as the ripple still travelling rather than as empty space.
    for (i, r) in [0.62 * h, 0.79 * h].enumerated() {
        ctx.setStrokeColor(ringColor.withAlphaComponent(i == 0 ? 0.22 : 0.12).cgColor)
        ctx.setLineWidth(h * (0.0072 - 0.0022 * CGFloat(i)))
        ctx.addArc(center: c, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()
    }

    // Fingertip touch dot.
    ctx.setFillColor(ringColor.cgColor)
    ctx.addArc(center: c, radius: h * 0.032, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.fillPath()

    let img = ctx.makeImage()!
    return NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
}

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "hero.png"
try! render(w: 2400, h: 1200).write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
