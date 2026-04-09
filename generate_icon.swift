#!/usr/bin/env swift
import AppKit

// Draws the CalendarUpcoming icon onto a CGContext.
// CG coordinate origin: bottom-left. So y=0 is the bottom of the image.
func drawIcon(ctx: CGContext, s: CGFloat) {
    let cs = CGColorSpaceCreateDeviceRGB()

    // ── 1. Background: blue gradient rounded rect ─────────────────────────────
    let bgRadius = s * 0.22
    let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                        cornerWidth: bgRadius, cornerHeight: bgRadius, transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let bgGrad = CGGradient(
        colorsSpace: cs,
        colors: [CGColor(red: 0.30, green: 0.52, blue: 1.00, alpha: 1),   // light-blue, top
                 CGColor(red: 0.08, green: 0.27, blue: 0.76, alpha: 1)] as CFArray, // deep-blue, bottom
        locations: [0, 1])!
    // Lighter at top (y=s in CG), darker at bottom (y=0)
    ctx.drawLinearGradient(bgGrad,
                           start: CGPoint(x: s / 2, y: s),
                           end:   CGPoint(x: s / 2, y: 0),
                           options: [])
    ctx.restoreGState()

    // ── 2. White calendar body ────────────────────────────────────────────────
    let pad   = s * 0.115
    let calX  = pad
    let calY  = pad * 0.9
    let calW  = s - pad * 2
    let calH  = s - pad * 1.8
    let calR  = s * 0.07

    let calPath = CGPath(roundedRect: CGRect(x: calX, y: calY, width: calW, height: calH),
                         cornerWidth: calR, cornerHeight: calR, transform: nil)
    ctx.addPath(calPath)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillPath()

    // ── 3. Blue header bar (top 26% of calendar) ─────────────────────────────
    let hdrH    = calH * 0.27
    let hdrRect = CGRect(x: calX, y: calY + calH - hdrH, width: calW, height: hdrH)
    ctx.saveGState()
    ctx.addPath(calPath)
    ctx.clip()
    let hdrGrad = CGGradient(
        colorsSpace: cs,
        colors: [CGColor(red: 0.20, green: 0.44, blue: 0.92, alpha: 1),
                 CGColor(red: 0.14, green: 0.34, blue: 0.80, alpha: 1)] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(hdrGrad,
                           start: CGPoint(x: s / 2, y: hdrRect.maxY),
                           end:   CGPoint(x: s / 2, y: hdrRect.minY),
                           options: [])
    ctx.restoreGState()

    // ── 4. Binding rings (two donuts peeking above the header) ────────────────
    let ringR   = s * 0.042
    let ringY   = calY + calH - hdrH * 0.18
    for ringX in [calX + calW * 0.31, calX + calW * 0.69] {
        // outer white disc
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
        ctx.addEllipse(in: CGRect(x: ringX - ringR, y: ringY - ringR,
                                   width: ringR * 2, height: ringR * 2))
        ctx.fillPath()
        // inner hole (background colour, approximated)
        ctx.setFillColor(CGColor(red: 0.22, green: 0.46, blue: 0.90, alpha: 1))
        let ir = ringR * 0.52
        ctx.addEllipse(in: CGRect(x: ringX - ir, y: ringY - ir,
                                   width: ir * 2, height: ir * 2))
        ctx.fillPath()
    }

    // ── 5. Header text suggestion (thin white bar) ────────────────────────────
    let barH = s * 0.022
    let barW = calW * 0.48
    let barX = calX + calW * 0.12
    let barY = calY + calH - hdrH * 0.62
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
    let barPath = CGPath(roundedRect: CGRect(x: barX, y: barY, width: barW, height: barH),
                          cornerWidth: barH / 2, cornerHeight: barH / 2, transform: nil)
    ctx.addPath(barPath)
    ctx.fillPath()

    // ── 6. Day grid: 7 cols × 3 rows of small circles ─────────────────────────
    let gm    = s * 0.055
    let gridX = calX + gm
    let gridY = calY + gm
    let gridW = calW - gm * 2
    let gridH = calH - hdrH - gm * 2
    let cols  = 7
    let rows  = 3
    let cellW = gridW / CGFloat(cols)
    let cellH = gridH / CGFloat(rows)
    let dotR  = min(cellW, cellH) * 0.29

    for row in 0 ..< rows {
        for col in 0 ..< cols {
            let cx = gridX + CGFloat(col) * cellW + cellW / 2
            let cy = gridY + CGFloat(row) * cellH + cellH / 2

            // Highlight: row 2 (top row visually, because CG y goes up), col 2
            let highlight = (row == 2 && col == 2)

            if highlight {
                // Blue disc behind the dot
                ctx.setFillColor(CGColor(red: 0.20, green: 0.44, blue: 0.95, alpha: 1))
                ctx.addEllipse(in: CGRect(x: cx - dotR * 1.55, y: cy - dotR * 1.55,
                                           width: dotR * 3.1, height: dotR * 3.1))
                ctx.fillPath()
                // White dot in center
                ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                ctx.addEllipse(in: CGRect(x: cx - dotR * 0.75, y: cy - dotR * 0.75,
                                           width: dotR * 1.5, height: dotR * 1.5))
                ctx.fillPath()
            } else {
                ctx.setFillColor(CGColor(red: 0.71, green: 0.82, blue: 0.97, alpha: 1))
                ctx.addEllipse(in: CGRect(x: cx - dotR, y: cy - dotR,
                                           width: dotR * 2, height: dotR * 2))
                ctx.fillPath()
            }
        }
    }

    // ── 7. Clock badge (bottom-right corner of the icon) ──────────────────────
    let bR  = s * 0.175
    let bCX = s - pad * 0.25 - bR
    let bCY = pad * 0.25 + bR

    // Shadow
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.015),
                  blur: s * 0.05,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.28))

    // White disc
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.addEllipse(in: CGRect(x: bCX - bR, y: bCY - bR, width: bR * 2, height: bR * 2))
    ctx.fillPath()

    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // Clock face
    ctx.setFillColor(CGColor(red: 0.18, green: 0.42, blue: 0.94, alpha: 1))
    let fR = bR * 0.80
    ctx.addEllipse(in: CGRect(x: bCX - fR, y: bCY - fR, width: fR * 2, height: fR * 2))
    ctx.fillPath()

    // Clock hands
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineWidth(s * 0.017)
    ctx.setLineCap(.round)

    // Hour hand (~10 o'clock position, pointing up-left)
    ctx.move(to: CGPoint(x: bCX, y: bCY))
    ctx.addLine(to: CGPoint(x: bCX - fR * 0.38, y: bCY + fR * 0.38))
    ctx.strokePath()

    // Minute hand (pointing straight up, ~12)
    ctx.move(to: CGPoint(x: bCX, y: bCY))
    ctx.addLine(to: CGPoint(x: bCX, y: bCY + fR * 0.58))
    ctx.strokePath()

    // Centre dot
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    let cdr = s * 0.014
    ctx.addEllipse(in: CGRect(x: bCX - cdr, y: bCY - cdr, width: cdr * 2, height: cdr * 2))
    ctx.fillPath()
}

// ── Render at given pixel size ────────────────────────────────────────────────
func renderIcon(pixels: Int) -> Data? {
    guard let bmp = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: NSColorSpaceName.deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }

    guard let ctx = NSGraphicsContext(bitmapImageRep: bmp)?.cgContext else { return nil }
    drawIcon(ctx: ctx, s: CGFloat(pixels))
    return bmp.representation(using: NSBitmapImageRep.FileType.png, properties: [:])
}

// ── Main ──────────────────────────────────────────────────────────────────────
let destDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

let sizes: [(String, Int)] = [
    ("icon_16x16.png",      16),
    ("icon_16x16@2x.png",   32),
    ("icon_32x32.png",      32),
    ("icon_32x32@2x.png",   64),
    ("icon_128x128.png",   128),
    ("icon_128x128@2x.png",256),
    ("icon_256x256.png",   256),
    ("icon_256x256@2x.png",512),
    ("icon_512x512.png",   512),
    ("icon_512x512@2x.png",1024),
]

for (filename, pixels) in sizes {
    if let data = renderIcon(pixels: pixels) {
        let url = URL(fileURLWithPath: destDir).appendingPathComponent(filename)
        try! data.write(to: url)
        print("✓  \(filename)  (\(pixels)px)")
    } else {
        print("✗  Failed: \(filename)")
    }
}
print("Done.")
