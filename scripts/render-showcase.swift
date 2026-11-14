#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// Renders a 2x Retina showcase storyboard for SnapClip and emits raw RGBA frames
// (plus optional keyframe poster PNGs) for ffmpeg encoding.

struct SceneConfig {
    let logicalWidth: CGFloat = 960
    let logicalHeight: CGFloat = 540
    let scale: CGFloat = 2
    let fps: Double = 25
    let duration: Double = 7.6
}

func clamp(_ x: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double {
    min(max(x, lo), hi)
}

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
    a + (b - a) * CGFloat(t)
}

func easeInOutCubic(_ t: Double) -> Double {
    let u = clamp(t)
    return u < 0.5 ? 4 * u * u * u : 1 - pow(-2 * u + 2, 3) / 2
}

/// Critically damped (or gently underdamped) spring curve per Apple Designing Fluid Interfaces.
func springOut(_ t: Double, response: Double = 0.34, damping: Double = 1.0) -> Double {
    let u = max(0, t)
    if u == 0 { return 0 }
    let omega = (2 * Double.pi) / max(response, 0.05)
    if damping >= 0.999 {
        return clamp(1 - exp(-omega * u) * (1 + omega * u), 0, 1)
    }
    let zeta = damping
    let omegaD = omega * sqrt(1 - zeta * zeta)
    return 1 - exp(-zeta * omega * u) * (cos(omegaD * u) + (zeta * omega / omegaD) * sin(omegaD * u))
}

func windowSegment(_ time: Double, start: Double, end: Double) -> Double {
    guard end > start else { return time >= end ? 1 : 0 }
    return clamp((time - start) / (end - start))
}

func drawRoundedRect(_ rect: NSRect, radius: CGFloat, fill: NSColor?, stroke: NSColor? = nil, lineWidth: CGFloat = 1) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    if let fill {
        fill.setFill()
        path.fill()
    }
    if let stroke {
        path.lineWidth = lineWidth
        stroke.setStroke()
        path.stroke()
    }
}

func drawMacWindowChrome(
    rect: NSRect,
    radius: CGFloat,
    title: String,
    bodyColor: NSColor,
    titleBarColor: NSColor,
    borderColor: NSColor
) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 22
    shadow.set()
    drawRoundedRect(rect, radius: radius, fill: bodyColor)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    titleBarColor.setFill()
    NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 34).fill()
    borderColor.withAlphaComponent(0.75).setFill()
    NSRect(x: rect.minX, y: rect.minY + 34, width: rect.width, height: 1).fill()
    NSGraphicsContext.restoreGraphicsState()

    drawRoundedRect(rect, radius: radius, fill: nil, stroke: borderColor, lineWidth: 1)

    let colors = [
        NSColor(calibratedRed: 1.0, green: 0.37, blue: 0.34, alpha: 1),
        NSColor(calibratedRed: 1.0, green: 0.74, blue: 0.18, alpha: 1),
        NSColor(calibratedRed: 0.15, green: 0.79, blue: 0.25, alpha: 1)
    ]
    for (idx, color) in colors.enumerated() {
        let dot = NSRect(x: rect.minX + 14 + CGFloat(idx) * 18, y: rect.minY + 11.5, width: 11, height: 11)
        color.setFill()
        NSBezierPath(ovalIn: dot).fill()
    }

    drawCenteredText(
        title,
        in: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 34),
        size: 11.5,
        weight: .medium,
        color: NSColor(calibratedRed: 0.35, green: 0.39, blue: 0.46, alpha: 1)
    )
}

func drawText(
    _ text: String,
    at point: NSPoint,
    size: CGFloat,
    weight: NSFont.Weight = .regular,
    color: NSColor,
    monospaced: Bool = false
) {
    let font = monospaced
        ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        : NSFont.systemFont(ofSize: size, weight: weight)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color
    ]
    (text as NSString).draw(at: point, withAttributes: attrs)
}

func drawCenteredText(
    _ text: String,
    in rect: NSRect,
    size: CGFloat,
    weight: NSFont.Weight = .semibold,
    color: NSColor,
    monospaced: Bool = false
) {
    let font = monospaced
        ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        : NSFont.systemFont(ofSize: size, weight: weight)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color
    ]
    let textSize = (text as NSString).size(withAttributes: attrs)
    let origin = NSPoint(
        x: rect.midX - textSize.width / 2,
        y: rect.midY - textSize.height / 2
    )
    (text as NSString).draw(at: origin, withAttributes: attrs)
}

func drawSymbol(
    _ name: String,
    in rect: NSRect,
    color: NSColor,
    pointSize: CGFloat,
    weight: NSFont.Weight = .semibold
) {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
    let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    let symbol = base.withSymbolConfiguration(cfg) ?? base
    let aspect = symbol.size.width / max(symbol.size.height, 1)
    let targetW: CGFloat
    let targetH: CGFloat
    if aspect >= 1 {
        targetW = rect.width
        targetH = rect.width / aspect
    } else {
        targetH = rect.height
        targetW = rect.height * aspect
    }
    let aligned = NSRect(
        x: rect.midX - targetW / 2,
        y: rect.midY - targetH / 2,
        width: targetW,
        height: targetH
    )
    symbol.draw(
        in: aligned,
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0,
        respectFlipped: true,
        hints: nil
    )
}

/// Renders the full-size `352x184` UI card scaled cleanly into any destination rectangle,
/// so both thumbnails and pasted previews look like real bitmap captures rather than reflowed text.
func drawScaledCaptureSnapshot(in destRect: NSRect, cornerRadius: CGFloat = 8, alpha: CGFloat = 1.0) {
    let canonicalW: CGFloat = 352
    let canonicalH: CGFloat = 184
    guard destRect.width > 1, destRect.height > 1 else { return }

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: destRect, xRadius: cornerRadius, yRadius: cornerRadius).addClip()

    let sx = destRect.width / canonicalW
    let sy = destRect.height / canonicalH
    if let ctx = NSGraphicsContext.current?.cgContext {
        ctx.translateBy(x: destRect.minX, y: destRect.minY)
        ctx.scaleBy(x: sx, y: sy)
    }

    let localRect = NSRect(x: 0, y: 0, width: canonicalW, height: canonicalH)
    NSColor(calibratedWhite: 0.99, alpha: alpha).setFill()
    localRect.fill()

    drawText(
        "Build Timing",
        at: NSPoint(x: 16, y: 14),
        size: 12.5,
        weight: .semibold,
        color: NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.16, alpha: alpha)
    )
    drawText(
        "arm64 release",
        at: NSPoint(x: canonicalW - 98, y: 15),
        size: 10.5,
        weight: .medium,
        color: NSColor(calibratedRed: 0.38, green: 0.43, blue: 0.52, alpha: alpha),
        monospaced: true
    )

    let bars: [(String, CGFloat, NSColor)] = [
        ("Core", 0.56, NSColor(calibratedRed: 0.16, green: 0.45, blue: 0.88, alpha: alpha)),
        ("UI", 0.36, NSColor(calibratedRed: 0.16, green: 0.45, blue: 0.88, alpha: 0.78 * alpha)),
        ("Tests", 0.78, NSColor(calibratedRed: 0.15, green: 0.65, blue: 0.42, alpha: alpha)),
        ("Pkg", 0.46, NSColor(calibratedRed: 0.25, green: 0.32, blue: 0.43, alpha: 0.85 * alpha))
    ]

    let barAreaTop: CGFloat = 46
    let rowHeight: CGFloat = 33
    let barTrackX: CGFloat = 66
    let barTrackMaxW: CGFloat = canonicalW - 84

    for (idx, item) in bars.enumerated() {
        let y = barAreaTop + CGFloat(idx) * rowHeight
        drawText(
            item.0,
            at: NSPoint(x: 16, y: y + 1),
            size: 11,
            weight: .medium,
            color: NSColor(calibratedRed: 0.32, green: 0.36, blue: 0.44, alpha: alpha)
        )
        let trackRect = NSRect(x: barTrackX, y: y + 2, width: barTrackMaxW, height: 11)
        drawRoundedRect(
            trackRect,
            radius: 3.5,
            fill: NSColor(calibratedRed: 0.91, green: 0.93, blue: 0.96, alpha: alpha)
        )
        let fillRect = NSRect(x: barTrackX, y: y + 2, width: barTrackMaxW * item.1, height: 11)
        drawRoundedRect(fillRect, radius: 3.5, fill: item.2)
    }

    NSGraphicsContext.restoreGraphicsState()
}

func drawKeycapPill(_ keys: [String], origin: NSPoint, alpha: Double, activePress: Bool = false) {
    guard alpha > 0.01 else { return }
    let a = CGFloat(alpha)
    let keyW: CGFloat = 26
    let keyH: CGFloat = 24
    let gap: CGFloat = 5
    let pad: CGFloat = 7
    let totalW = pad * 2 + CGFloat(keys.count) * keyW + CGFloat(max(keys.count - 1, 0)) * gap
    let pillRect = NSRect(x: origin.x, y: origin.y, width: totalW, height: keyH + pad * 2)

    drawRoundedRect(
        pillRect,
        radius: 10,
        fill: NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.12, alpha: 0.90 * a),
        stroke: NSColor.white.withAlphaComponent(0.18 * a),
        lineWidth: 1
    )

    for (idx, label) in keys.enumerated() {
        let kr = NSRect(
            x: pillRect.minX + pad + CGFloat(idx) * (keyW + gap),
            y: pillRect.minY + pad + (activePress ? 1 : 0),
            width: keyW,
            height: keyH - (activePress ? 1 : 0)
        )
        let keyFill = activePress
            ? NSColor(calibratedRed: 0.19, green: 0.48, blue: 0.94, alpha: a)
            : NSColor(calibratedRed: 0.21, green: 0.24, blue: 0.30, alpha: a)
        drawRoundedRect(
            kr,
            radius: 5,
            fill: keyFill,
            stroke: NSColor.white.withAlphaComponent(0.22 * a),
            lineWidth: 1
        )
        drawCenteredText(
            label,
            in: kr,
            size: 11.5,
            weight: .semibold,
            color: NSColor.white.withAlphaComponent(a)
        )
    }
}

func drawArrowCursor(at point: NSPoint, alpha: CGFloat = 1) {
    guard alpha > 0.01 else { return }
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.42 * alpha)
    shadow.shadowOffset = NSSize(width: 1, height: -2)
    shadow.shadowBlurRadius = 3
    shadow.set()

    let path = NSBezierPath()
    path.move(to: point)
    path.line(to: NSPoint(x: point.x, y: point.y + 18))
    path.line(to: NSPoint(x: point.x + 4.5, y: point.y + 14))
    path.line(to: NSPoint(x: point.x + 8.5, y: point.y + 21))
    path.line(to: NSPoint(x: point.x + 11.2, y: point.y + 19.6))
    path.line(to: NSPoint(x: point.x + 7.2, y: point.y + 12.6))
    path.line(to: NSPoint(x: point.x + 12.5, y: point.y + 12.6))
    path.close()

    NSColor(calibratedWhite: 0.08, alpha: alpha).setFill()
    path.fill()
    path.lineWidth = 1.3
    NSColor.white.withAlphaComponent(alpha).setStroke()
    path.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

func drawCrosshairCursor(at point: NSPoint, alpha: CGFloat = 1) {
    guard alpha > 0.01 else { return }
    NSGraphicsContext.saveGraphicsState()
    let ring = NSRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18)
    NSColor(calibratedWhite: 0.05, alpha: 0.35 * alpha).setFill()
    NSBezierPath(ovalIn: ring).fill()
    NSColor.white.withAlphaComponent(0.85 * alpha).setStroke()
    let ringPath = NSBezierPath(ovalIn: ring)
    ringPath.lineWidth = 1.0
    ringPath.stroke()

    let cross = NSBezierPath()
    cross.move(to: NSPoint(x: point.x - 13, y: point.y))
    cross.line(to: NSPoint(x: point.x + 13, y: point.y))
    cross.move(to: NSPoint(x: point.x, y: point.y - 13))
    cross.line(to: NSPoint(x: point.x, y: point.y + 13))
    cross.lineWidth = 1.2
    cross.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

/// Draws the exact visual structure of `ThumbnailPreviewView` from `SnapClipUI`.
func drawSnapClipPreviewCard(
    frame cardRect: NSRect,
    hoverProgress: Double,
    cardAlpha: Double
) {
    guard cardAlpha > 0.01 else { return }
    let alpha = CGFloat(cardAlpha)
    let hover = CGFloat(hoverProgress)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45 * alpha)
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.shadowBlurRadius = 18
    shadow.set()

    let borderAlpha = (0.35 + (0.65 - 0.35) * hover) * alpha
    drawRoundedRect(
        cardRect,
        radius: 12,
        fill: NSColor(calibratedWhite: 0.12, alpha: 0.94 * alpha),
        stroke: NSColor.white.withAlphaComponent(borderAlpha),
        lineWidth: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    // Inner thumbnail content (4pt inset, 8pt radius matching ThumbnailPreviewView.swift)
    let insetRect = cardRect.insetBy(dx: 4, dy: 4)
    drawRoundedRect(insetRect, radius: 8, fill: NSColor(calibratedWhite: 0.99, alpha: alpha))
    drawScaledCaptureSnapshot(in: insetRect, cornerRadius: 8, alpha: alpha)

    // Top-left "Copied" pill matching ThumbnailPreviewView.drawCopiedBadge()
    let pillRect = NSRect(x: cardRect.minX + 10, y: cardRect.minY + 10, width: 50, height: 18)
    drawRoundedRect(
        pillRect,
        radius: 6,
        fill: NSColor(calibratedWhite: 0.05, alpha: 0.78 * alpha)
    )
    drawCenteredText(
        "Copied",
        in: pillRect,
        size: 10,
        weight: .semibold,
        color: NSColor.white.withAlphaComponent(alpha)
    )

    // Top-right quick actions ("trash" and "xmark") fading in cleanly on hover
    if hover > 0.02 {
        let btnSize: CGFloat = 22
        let pad: CGFloat = 8
        let closeRect = NSRect(
            x: cardRect.maxX - btnSize - pad,
            y: cardRect.minY + pad,
            width: btnSize,
            height: btnSize
        )
        let trashRect = NSRect(
            x: closeRect.minX - btnSize - 6,
            y: closeRect.minY,
            width: btnSize,
            height: btnSize
        )
        for (btnRect, symbol) in [(trashRect, "trash"), (closeRect, "xmark")] {
            drawRoundedRect(
                btnRect,
                radius: 11,
                fill: NSColor(calibratedWhite: 0.08, alpha: 0.84 * hover * alpha)
            )
            let symRect = btnRect.insetBy(dx: 6, dy: 6)
            drawSymbol(symbol, in: symRect, color: .white.withAlphaComponent(hover * alpha), pointSize: 10, weight: .bold)
        }
    }
}

func renderFrame(time: Double, config: SceneConfig) -> Data {
    let pixelW = Int(config.logicalWidth * config.scale)
    let pixelH = Int(config.logicalHeight * config.scale)

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelW,
        pixelsHigh: pixelH,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: pixelW * 4,
        bitsPerPixel: 32
    ), let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else {
        fatalError("Unable to allocate bitmap context")
    }

    // Flip context vertically so all geometry uses intuitive top-left coordinates at 2x Retina scale.
    ctx.translateBy(x: 0, y: CGFloat(pixelH))
    ctx.scaleBy(x: config.scale, y: -config.scale)

    let flippedGC = NSGraphicsContext(cgContext: ctx, flipped: true)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = flippedGC

    let canvas = NSRect(x: 0, y: 0, width: config.logicalWidth, height: config.logicalHeight)

    // 1. Calm macOS slate desktop background
    let bgGradient = NSGradient(
        starting: NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.16, alpha: 1),
        ending: NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.22, alpha: 1)
    )
    bgGradient?.draw(in: canvas, angle: 90)

    // Subtle macOS Menu Bar
    let menuBar = NSRect(x: 0, y: 0, width: config.logicalWidth, height: 26)
    NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 0.90).setFill()
    menuBar.fill()
    NSColor.white.withAlphaComponent(0.08).setFill()
    NSRect(x: 0, y: 25, width: config.logicalWidth, height: 1).fill()

    drawText("SnapClip", at: NSPoint(x: 16, y: 5), size: 12, weight: .semibold, color: .white)
    drawText("Window  Edit  Help", at: NSPoint(x: 84, y: 5.5), size: 11.5, weight: .regular, color: NSColor.white.withAlphaComponent(0.68))
    drawText("Tue 13:10", at: NSPoint(x: config.logicalWidth - 72, y: 5.5), size: 11.5, weight: .medium, color: NSColor.white.withAlphaComponent(0.82))

    // 2. Left Window (Source App to capture)
    let leftWin = NSRect(x: 36, y: 64, width: 392, height: 344)
    drawMacWindowChrome(
        rect: leftWin,
        radius: 11,
        title: "Dashboard.app",
        bodyColor: NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.985, alpha: 1),
        titleBarColor: NSColor(calibratedRed: 0.92, green: 0.94, blue: 0.96, alpha: 1),
        borderColor: NSColor(calibratedRed: 0.78, green: 0.82, blue: 0.87, alpha: 1)
    )

    drawText(
        "Release Summary",
        at: NSPoint(x: leftWin.minX + 20, y: leftWin.minY + 50),
        size: 14,
        weight: .semibold,
        color: NSColor(calibratedRed: 0.11, green: 0.14, blue: 0.19, alpha: 1)
    )
    drawText(
        "Drag across a region to capture and paste",
        at: NSPoint(x: leftWin.minX + 20, y: leftWin.minY + 71),
        size: 11,
        weight: .regular,
        color: NSColor(calibratedRed: 0.42, green: 0.47, blue: 0.55, alpha: 1)
    )

    let targetCard = NSRect(x: leftWin.minX + 20, y: leftWin.minY + 98, width: 352, height: 184)
    drawRoundedRect(
        targetCard,
        radius: 8,
        fill: NSColor.white,
        stroke: NSColor(calibratedRed: 0.83, green: 0.86, blue: 0.90, alpha: 1),
        lineWidth: 1
    )
    drawScaledCaptureSnapshot(in: targetCard, cornerRadius: 8)

    drawText(
        "24 tests passing  •  universal arm64 + x86_64",
        at: NSPoint(x: leftWin.minX + 20, y: leftWin.maxY - 34),
        size: 10.5,
        weight: .medium,
        color: NSColor(calibratedRed: 0.40, green: 0.46, blue: 0.54, alpha: 1),
        monospaced: true
    )

    // 3. Right Window (Target Editor waiting for Cmd+V, positioned cleanly above the bottom-right preview zone)
    let rightWin = NSRect(x: 452, y: 64, width: 356, height: 308)
    drawMacWindowChrome(
        rect: rightWin,
        radius: 11,
        title: "Notes  •  PR #14",
        bodyColor: NSColor.white,
        titleBarColor: NSColor(calibratedRed: 0.94, green: 0.955, blue: 0.975, alpha: 1),
        borderColor: NSColor(calibratedRed: 0.78, green: 0.82, blue: 0.87, alpha: 1)
    )

    drawText(
        "Updated screenshot timing:",
        at: NSPoint(x: rightWin.minX + 20, y: rightWin.minY + 50),
        size: 12.5,
        weight: .medium,
        color: NSColor(calibratedRed: 0.14, green: 0.17, blue: 0.22, alpha: 1)
    )

    // Timeline transitions
    let marqueeSelect = windowSegment(time, start: 0.45, end: 1.35)
    let captureFired = time >= 1.40
    let flashProgress = captureFired ? clamp(1 - (time - 1.40) / 0.18) : 0
    let previewEnter = captureFired ? springOut(time - 1.46, response: 0.28, damping: 1.0) : 0
    let previewExit = time >= 5.15 ? easeInOutCubic(windowSegment(time, start: 5.15, end: 5.45)) : 0
    let desktopEnter = captureFired ? springOut(time - 1.48, response: 0.30, damping: 0.88) : 0
    let pasteProgress = time >= 3.15 ? springOut(time - 3.15, response: 0.24, damping: 1.0) : 0
    let hoverProgress = time >= 4.05 && time < 5.20
        ? clamp(windowSegment(time, start: 4.05, end: 4.22))
        : (time >= 5.20 ? clamp(1 - windowSegment(time, start: 5.20, end: 5.35)) : 0)

    let loopFadeOut = time >= 7.25 ? windowSegment(time, start: 7.25, end: 7.60) : 0

    // Caret before paste
    if pasteProgress < 0.05 {
        let blink = Int(time * 2.2) % 2 == 0
        if blink {
            NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.96, alpha: 1).setFill()
            NSRect(x: rightWin.minX + 20, y: rightWin.minY + 78, width: 2, height: 15).fill()
        }
    }

    // Pasted image appearing in Notes / PR composer on Cmd+V
    if pasteProgress > 0.01 {
        let pAlpha = CGFloat(clamp(pasteProgress * (1 - loopFadeOut)))
        let yOffset = lerp(8, 0, pasteProgress)
        let pastedBox = NSRect(
            x: rightWin.minX + 20,
            y: rightWin.minY + 78 + yOffset,
            width: 316,
            height: 165
        )
        drawRoundedRect(
            pastedBox,
            radius: 8,
            fill: NSColor.white.withAlphaComponent(pAlpha),
            stroke: NSColor(calibratedRed: 0.78, green: 0.83, blue: 0.89, alpha: pAlpha),
            lineWidth: 1
        )
        drawScaledCaptureSnapshot(in: pastedBox.insetBy(dx: 2, dy: 2), cornerRadius: 6, alpha: pAlpha)
        drawText(
            "Pasted from clipboard (PNG + TIFF)",
            at: NSPoint(x: rightWin.minX + 20, y: pastedBox.maxY + 12),
            size: 11,
            weight: .medium,
            color: NSColor(calibratedRed: 0.14, green: 0.56, blue: 0.34, alpha: pAlpha)
        )
    }

    // 4. Desktop PNG File appearing immediately top-right (zero 5-second delay)
    if desktopEnter > 0.01 {
        let dAlpha = CGFloat(clamp(desktopEnter * (1 - loopFadeOut)))
        let dScale = lerp(0.88, 1.0, desktopEnter)
        let fileCenter = NSPoint(x: 886, y: 92)
        let cardW = 88 * dScale
        let cardH = 48 * dScale
        let iconBox = NSRect(
            x: fileCenter.x - cardW / 2,
            y: fileCenter.y - cardH / 2,
            width: cardW,
            height: cardH
        )
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.30 * dAlpha)
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.shadowBlurRadius = 10
        shadow.set()
        drawRoundedRect(
            iconBox,
            radius: 6,
            fill: NSColor.white.withAlphaComponent(0.96 * dAlpha),
            stroke: NSColor.white.withAlphaComponent(0.75 * dAlpha),
            lineWidth: 1.5
        )
        NSGraphicsContext.restoreGraphicsState()

        drawScaledCaptureSnapshot(in: iconBox.insetBy(dx: 2.5, dy: 2.5), cornerRadius: 4, alpha: dAlpha)
        let labelPill = NSRect(x: 830, y: 124, width: 112, height: 18)
        drawRoundedRect(labelPill, radius: 4, fill: NSColor(calibratedWhite: 0.08, alpha: 0.72 * dAlpha))
        drawCenteredText(
            "Screenshot.png",
            in: labelPill,
            size: 10,
            weight: .medium,
            color: .white.withAlphaComponent(dAlpha)
        )
    }

    // 5. Screenshot Marquee Selection during Cmd+Shift+4
    let selStart = NSPoint(x: targetCard.minX - 6, y: targetCard.minY - 6)
    let selEnd = NSPoint(x: targetCard.maxX + 6, y: targetCard.maxY + 6)
    if time >= 0.45 && time < 1.62 {
        let tSel = easeInOutCubic(marqueeSelect)
        let curW = max(12, (selEnd.x - selStart.x) * CGFloat(tSel))
        let curH = max(12, (selEnd.y - selStart.y) * CGFloat(tSel))
        let marquee = NSRect(x: selStart.x, y: selStart.y, width: curW, height: curH)

        let mAlpha = time < 1.40 ? 1.0 : flashProgress
        NSColor(calibratedRed: 0.16, green: 0.47, blue: 0.94, alpha: 0.10 * CGFloat(mAlpha)).setFill()
        marquee.fill()

        NSGraphicsContext.saveGraphicsState()
        let borderPath = NSBezierPath(rect: marquee)
        borderPath.lineWidth = 1.25
        NSColor.white.withAlphaComponent(0.95 * CGFloat(mAlpha)).setStroke()
        borderPath.stroke()
        NSGraphicsContext.restoreGraphicsState()

        if time < 1.40 {
            let dimPill = NSRect(x: marquee.maxX - 72, y: marquee.maxY + 6, width: 72, height: 18)
            drawRoundedRect(dimPill, radius: 5, fill: NSColor(calibratedWhite: 0.08, alpha: 0.85))
            drawCenteredText(
                "\(Int(curW)) × \(Int(curH))",
                in: dimPill,
                size: 9.5,
                weight: .semibold,
                color: .white,
                monospaced: true
            )
        }
        if flashProgress > 0.01 {
            NSColor.white.withAlphaComponent(0.35 * CGFloat(flashProgress)).setFill()
            marquee.fill()
        }
    }

    // 6. SnapClip Floating Preview Panel bottom-right (matches real 204x112 aspect for captured 352x184)
    let finalW: CGFloat = 204
    let finalH: CGFloat = 114
    let restX = config.logicalWidth - finalW - 22
    let restY = config.logicalHeight - finalH - 22
    if previewEnter > 0.01 && previewExit < 0.99 {
        let enterOffset = lerp(finalW + 30, 0, previewEnter)
        let exitOffset = lerp(0, finalW + 40, previewExit)
        let cardAlpha = clamp(previewEnter) * clamp(1 - previewExit) * (1 - loopFadeOut)
        let cardFrame = NSRect(
            x: restX + enterOffset + exitOffset,
            y: restY,
            width: finalW,
            height: finalH
        )
        drawSnapClipPreviewCard(frame: cardFrame, hoverProgress: hoverProgress, cardAlpha: cardAlpha)
    }

    // 7. Quiet contextual status bar bottom-left + shortcut keycaps
    let stepText: String
    let accentDot: NSColor
    if time < 1.40 {
        stepText = "1. Capture with macOS shortcut (Cmd+Shift+4)"
        accentDot = NSColor(calibratedRed: 0.25, green: 0.56, blue: 0.98, alpha: 1)
    } else if time < 3.15 {
        stepText = "2. Saved to Desktop + copied PNG & TIFF instantly"
        accentDot = NSColor(calibratedRed: 0.18, green: 0.78, blue: 0.44, alpha: 1)
    } else if time < 4.05 {
        stepText = "3. Paste straight into any app (Cmd+V)"
        accentDot = NSColor(calibratedRed: 0.18, green: 0.78, blue: 0.44, alpha: 1)
    } else {
        stepText = "4. Hover preview for Trash / Close, or swipe to dismiss"
        accentDot = NSColor(calibratedRed: 0.85, green: 0.88, blue: 0.94, alpha: 1)
    }

    let statusPill = NSRect(x: 36, y: 472, width: 416, height: 34)
    drawRoundedRect(
        statusPill,
        radius: 9,
        fill: NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.12, alpha: 0.88),
        stroke: NSColor.white.withAlphaComponent(0.14),
        lineWidth: 1
    )
    let dotRect = NSRect(x: statusPill.minX + 14, y: statusPill.midY - 4, width: 8, height: 8)
    accentDot.setFill()
    NSBezierPath(ovalIn: dotRect).fill()
    drawText(
        stepText,
        at: NSPoint(x: statusPill.minX + 30, y: statusPill.minY + 9),
        size: 12,
        weight: .medium,
        color: NSColor.white.withAlphaComponent(0.92)
    )

    if time >= 0.25 && time < 1.70 {
        let ka = min(windowSegment(time, start: 0.25, end: 0.40), 1 - windowSegment(time, start: 1.50, end: 1.70))
        drawKeycapPill(["⌘", "⇧", "4"], origin: NSPoint(x: 36, y: 424), alpha: ka, activePress: time >= 1.32 && time <= 1.48)
    } else if time >= 2.75 && time < 3.65 {
        let ka = min(windowSegment(time, start: 2.75, end: 2.90), 1 - windowSegment(time, start: 3.45, end: 3.65))
        drawKeycapPill(["⌘", "V"], origin: NSPoint(x: 472, y: 396), alpha: ka, activePress: time >= 3.05 && time <= 3.25)
    }

    // 8. Cursor choreography
    let cursorPos: NSPoint
    let useCrosshair: Bool
    if time < 0.45 {
        let t = easeInOutCubic(windowSegment(time, start: 0.0, end: 0.45))
        cursorPos = NSPoint(x: lerp(220, selStart.x, t), y: lerp(330, selStart.y, t))
        useCrosshair = time > 0.30
    } else if time < 1.42 {
        let t = easeInOutCubic(marqueeSelect)
        cursorPos = NSPoint(x: lerp(selStart.x, selEnd.x, t), y: lerp(selStart.y, selEnd.y, t))
        useCrosshair = true
    } else if time < 2.90 {
        let t = easeInOutCubic(windowSegment(time, start: 1.55, end: 2.50))
        cursorPos = NSPoint(x: lerp(selEnd.x, 540, t), y: lerp(selEnd.y, 175, t))
        useCrosshair = false
    } else if time < 4.10 {
        let t = easeInOutCubic(windowSegment(time, start: 3.45, end: 4.10))
        cursorPos = NSPoint(x: lerp(540, restX + 100, t), y: lerp(175, restY + 62, t))
        useCrosshair = false
    } else if time < 5.05 {
        let t = easeInOutCubic(windowSegment(time, start: 4.35, end: 4.85))
        cursorPos = NSPoint(
            x: lerp(restX + 100, restX + finalW - 19, t),
            y: lerp(restY + 62, restY + 19, t)
        )
        useCrosshair = false
    } else {
        let t = easeInOutCubic(windowSegment(time, start: 5.05, end: 5.65))
        cursorPos = NSPoint(
            x: lerp(restX + finalW - 19, restX + finalW + 6, t),
            y: restY + 19
        )
        useCrosshair = false
    }

    if useCrosshair {
        drawCrosshairCursor(at: cursorPos)
    } else {
        drawArrowCursor(at: cursorPos)
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let rawPtr = rep.bitmapData else {
        fatalError("Missing bitmapData")
    }
    return Data(bytes: rawPtr, count: pixelW * pixelH * 4)
}

func renderSocialPreviewFrame() -> Data {
    let pixelW = 1280
    let pixelH = 640

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelW,
        pixelsHigh: pixelH,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: pixelW * 4,
        bitsPerPixel: 32
    ), let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else {
        fatalError("Unable to allocate social preview bitmap context")
    }

    ctx.translateBy(x: 0, y: CGFloat(pixelH))
    ctx.scaleBy(x: 1, y: -1)

    let flippedGC = NSGraphicsContext(cgContext: ctx, flipped: true)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = flippedGC

    let canvas = NSRect(x: 0, y: 0, width: CGFloat(pixelW), height: CGFloat(pixelH))
    let bgGradient = NSGradient(
        starting: NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.13, alpha: 1),
        ending: NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.21, alpha: 1)
    )
    bgGradient?.draw(in: canvas, angle: 115)

    // Outer frame border inside GitHub OpenGraph safe area
    drawRoundedRect(
        canvas.insetBy(dx: 24, dy: 24),
        radius: 20,
        fill: NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.14, alpha: 0.55),
        stroke: NSColor.white.withAlphaComponent(0.10),
        lineWidth: 1
    )

    // Left column: clear product value proposition and install command
    let metaPill = NSRect(x: 68, y: 68, width: 344, height: 30)
    drawRoundedRect(
        metaPill,
        radius: 8,
        fill: NSColor(calibratedRed: 0.14, green: 0.18, blue: 0.24, alpha: 0.95),
        stroke: NSColor.white.withAlphaComponent(0.14),
        lineWidth: 1
    )
    drawCenteredText(
        "macOS 14+   •   MIT License   •   Zero Permissions",
        in: metaPill,
        size: 12.5,
        weight: .medium,
        color: NSColor(calibratedRed: 0.78, green: 0.84, blue: 0.93, alpha: 1)
    )

    drawText(
        "SnapClip",
        at: NSPoint(x: 68, y: 118),
        size: 56,
        weight: .bold,
        color: .white
    )

    drawText(
        "Copy macOS screenshots to the clipboard",
        at: NSPoint(x: 68, y: 196),
        size: 24,
        weight: .medium,
        color: NSColor(calibratedRed: 0.90, green: 0.93, blue: 0.97, alpha: 1)
    )
    drawText(
        "and Desktop at the same time.",
        at: NSPoint(x: 68, y: 229),
        size: 24,
        weight: .medium,
        color: NSColor(calibratedRed: 0.90, green: 0.93, blue: 0.97, alpha: 1)
    )

    let bullets = [
        "Removes the 5-second macOS thumbnail write delay",
        "No Screen Recording or Accessibility permissions",
        "Non-blocking corner card with Trash, Close, and drag-out"
    ]
    for (idx, line) in bullets.enumerated() {
        let rowY = CGFloat(288 + idx * 34)
        let checkBadge = NSRect(x: 68, y: rowY + 1, width: 20, height: 20)
        drawRoundedRect(
            checkBadge,
            radius: 6,
            fill: NSColor(calibratedRed: 0.15, green: 0.62, blue: 0.39, alpha: 0.24),
            stroke: NSColor(calibratedRed: 0.22, green: 0.82, blue: 0.50, alpha: 0.55),
            lineWidth: 1
        )
        drawSymbol(
            "checkmark",
            in: checkBadge.insetBy(dx: 4.5, dy: 4.5),
            color: NSColor(calibratedRed: 0.28, green: 0.90, blue: 0.56, alpha: 1),
            pointSize: 10,
            weight: .bold
        )
        drawText(
            line,
            at: NSPoint(x: 98, y: rowY + 1),
            size: 15.5,
            weight: .regular,
            color: NSColor(calibratedRed: 0.80, green: 0.85, blue: 0.92, alpha: 1)
        )
    }

    let termBox = NSRect(x: 68, y: 416, width: 556, height: 92)
    drawRoundedRect(
        termBox,
        radius: 12,
        fill: NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.09, alpha: 0.96),
        stroke: NSColor.white.withAlphaComponent(0.15),
        lineWidth: 1
    )
    drawText(
        "$ brew install aklkbqx/snapclip/snapclip",
        at: NSPoint(x: termBox.minX + 18, y: termBox.minY + 19),
        size: 15,
        weight: .medium,
        color: NSColor(calibratedRed: 0.42, green: 0.90, blue: 0.62, alpha: 1),
        monospaced: true
    )
    drawText(
        "$ snapclip install",
        at: NSPoint(x: termBox.minX + 18, y: termBox.minY + 49),
        size: 15,
        weight: .medium,
        color: NSColor(calibratedRed: 0.90, green: 0.93, blue: 0.98, alpha: 1),
        monospaced: true
    )

    drawText(
        "github.com/aklkbqx/snapclip",
        at: NSPoint(x: 68, y: 536),
        size: 14,
        weight: .medium,
        color: NSColor(calibratedRed: 0.54, green: 0.60, blue: 0.70, alpha: 1),
        monospaced: true
    )

    // Right column: crisp macOS desktop viewport showing Desktop file + Paste + Hover Preview
    let stage = NSRect(x: 672, y: 68, width: 540, height: 504)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: stage, xRadius: 16, yRadius: 16).addClip()

    let stageGrad = NSGradient(
        starting: NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.21, alpha: 1),
        ending: NSColor(calibratedRed: 0.19, green: 0.23, blue: 0.29, alpha: 1)
    )
    stageGrad?.draw(in: stage, angle: 90)

    let stageMenu = NSRect(x: stage.minX, y: stage.minY, width: stage.width, height: 28)
    NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 0.92).setFill()
    stageMenu.fill()
    drawText("SnapClip", at: NSPoint(x: stage.minX + 16, y: stage.minY + 6), size: 12, weight: .semibold, color: .white)
    drawText("Cmd+Shift+4", at: NSPoint(x: stage.maxX - 96, y: stage.minY + 6.5), size: 11, weight: .medium, color: NSColor.white.withAlphaComponent(0.75), monospaced: true)

    // Editor window showing pasted PNG + TIFF
    let editorWin = NSRect(x: stage.minX + 24, y: stage.minY + 52, width: 344, height: 274)
    drawMacWindowChrome(
        rect: editorWin,
        radius: 11,
        title: "Pull Request #14",
        bodyColor: .white,
        titleBarColor: NSColor(calibratedRed: 0.94, green: 0.955, blue: 0.975, alpha: 1),
        borderColor: NSColor(calibratedRed: 0.78, green: 0.82, blue: 0.87, alpha: 1)
    )
    let pastedSnap = NSRect(x: editorWin.minX + 18, y: editorWin.minY + 50, width: 308, height: 160)
    drawRoundedRect(
        pastedSnap,
        radius: 8,
        fill: .white,
        stroke: NSColor(calibratedRed: 0.80, green: 0.84, blue: 0.90, alpha: 1),
        lineWidth: 1
    )
    drawScaledCaptureSnapshot(in: pastedSnap.insetBy(dx: 2, dy: 2), cornerRadius: 6)
    drawText(
        "Pasted from clipboard (PNG + TIFF)",
        at: NSPoint(x: editorWin.minX + 18, y: pastedSnap.maxY + 12),
        size: 11.5,
        weight: .semibold,
        color: NSColor(calibratedRed: 0.13, green: 0.56, blue: 0.34, alpha: 1)
    )

    // Saved Desktop icon top-right
    let iconBox = NSRect(x: stage.maxX - 124, y: stage.minY + 58, width: 96, height: 54)
    drawRoundedRect(
        iconBox,
        radius: 6,
        fill: NSColor.white.withAlphaComponent(0.96),
        stroke: NSColor.white.withAlphaComponent(0.80),
        lineWidth: 1.5
    )
    drawScaledCaptureSnapshot(in: iconBox.insetBy(dx: 2.5, dy: 2.5), cornerRadius: 4)
    let iconLabel = NSRect(x: stage.maxX - 134, y: iconBox.maxY + 7, width: 116, height: 20)
    drawRoundedRect(iconLabel, radius: 5, fill: NSColor(calibratedWhite: 0.07, alpha: 0.78))
    drawCenteredText("Screenshot.png", in: iconLabel, size: 10.5, weight: .medium, color: .white)

    // Floating corner preview card with hover Trash + Close visible
    let previewRect = NSRect(x: stage.maxX - 266, y: stage.maxY - 178, width: 242, height: 154)
    drawSnapClipPreviewCard(frame: previewRect, hoverProgress: 1.0, cardAlpha: 1.0)
    drawArrowCursor(at: NSPoint(x: previewRect.maxX - 41, y: previewRect.minY + 26))

    NSGraphicsContext.restoreGraphicsState()
    drawRoundedRect(stage, radius: 16, fill: nil, stroke: NSColor.white.withAlphaComponent(0.16), lineWidth: 1)

    NSGraphicsContext.restoreGraphicsState()

    guard let rawPtr = rep.bitmapData else {
        fatalError("Missing social preview bitmapData")
    }
    return Data(bytes: rawPtr, count: pixelW * pixelH * 4)
}

func writePosterPNG(frameData: Data, width: Int, height: Int, to url: URL) throws {
    let bytes = [UInt8](frameData)
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let cgImage = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: true,
        intent: .defaultIntent
    )!
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "SnapClipRender", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed PNG encode"])
    }
    try png.write(to: url)
}

let args = Array(CommandLine.arguments.dropFirst())
var posterPath: String?
var socialPreviewPath: String?
var rawOutputPath: String?
var keyframeDir: String?
var index = 0
while index < args.count {
    switch args[index] {
    case "--poster":
        index += 1
        if index < args.count { posterPath = args[index] }
    case "--social-preview":
        index += 1
        if index < args.count { socialPreviewPath = args[index] }
    case "--raw-out":
        index += 1
        if index < args.count { rawOutputPath = args[index] }
    case "--keyframes-dir":
        index += 1
        if index < args.count { keyframeDir = args[index] }
    default:
        break
    }
    index += 1
}

if let socialPreviewPath {
    let socialBytes = renderSocialPreviewFrame()
    try writePosterPNG(frameData: socialBytes, width: 1280, height: 640, to: URL(fileURLWithPath: socialPreviewPath))
}

let config = SceneConfig()
let totalFrames = Int(round(config.duration * config.fps))
let pixelW = Int(config.logicalWidth * config.scale)
let pixelH = Int(config.logicalHeight * config.scale)

let posterFrameIndex = Int(round(4.65 * config.fps))
let keyframeIndices: [Int: String] = [
    Int(round(1.05 * config.fps)): "keyframe-1-marquee.png",
    Int(round(2.30 * config.fps)): "keyframe-2-instant.png",
    posterFrameIndex: "keyframe-3-hover.png"
]

var outHandle: FileHandle?
if let rawOutputPath {
    FileManager.default.createFile(atPath: rawOutputPath, contents: nil)
    outHandle = FileHandle(forWritingAtPath: rawOutputPath)
}

if let keyframeDir {
    try FileManager.default.createDirectory(atPath: keyframeDir, withIntermediateDirectories: true)
}

for frameIndex in 0..<totalFrames {
    let wantPoster = (frameIndex == posterFrameIndex && posterPath != nil)
    let wantKeyframe = (keyframeDir != nil && keyframeIndices[frameIndex] != nil)
    if outHandle == nil && !wantPoster && !wantKeyframe {
        continue
    }

    let time = Double(frameIndex) / config.fps
    let frameBytes = renderFrame(time: time, config: config)
    outHandle?.write(frameBytes)

    if wantPoster, let posterPath {
        try writePosterPNG(frameData: frameBytes, width: pixelW, height: pixelH, to: URL(fileURLWithPath: posterPath))
    }
    if let keyframeDir, let name = keyframeIndices[frameIndex] {
        let kfURL = URL(fileURLWithPath: keyframeDir).appendingPathComponent(name)
        try writePosterPNG(frameData: frameBytes, width: pixelW, height: pixelH, to: kfURL)
    }
}

outHandle?.closeFile()
