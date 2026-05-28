import SwiftUI

/// REQ-003 · Visual onboarding guides, implemented as native SwiftUI Canvas
/// drawings so animations run on the platform renderer (no WebView / no
/// SMIL). 1:1 port of the koraidv-android Compose Canvas implementation at
/// `koraidv-android/koraidv/src/main/kotlin/com/koraidv/sdk/ui/compose/VisualGuides.kt`.
///
/// All guides draw on a 320×240 logical canvas. The wrapper [VisualGuide]
/// handles aspect-ratio sizing so callers can drop it into any width.
///
/// Gated by `Configuration.showVisualGuides`. When the flag is off, callers
/// should fall back to the existing minimal-icon UI.

/// The guide shown at a given step of the flow.
enum VisualGuideKind {
    case docFront
    case docBack
    case selfie
    case nfcScan
    case livenessTurnRight
    case livenessTurnLeft
    case livenessLookUp
    case livenessLookDown
    case livenessSmile
    case livenessBlink
}

/// Map the SDK's `ChallengeType` to the matching liveness guide.
func challengeToGuide(_ challenge: ChallengeType) -> VisualGuideKind {
    switch challenge {
    case .turnLeft: return .livenessTurnLeft
    case .turnRight: return .livenessTurnRight
    case .nodUp: return .livenessLookUp
    case .nodDown: return .livenessLookDown
    case .smile: return .livenessSmile
    case .blink: return .livenessBlink
    }
}

// MARK: - Logical canvas + palette (shared with Android concept SVGs)

private let LOGICAL_WIDTH: CGFloat = 320
private let LOGICAL_HEIGHT: CGFloat = 240

private extension Color {
    static let brandNavy = Color(red: 26.0/255, green: 35.0/255, blue: 126.0/255)
    static let brandNavySoft = Color(red: 26.0/255, green: 35.0/255, blue: 126.0/255).opacity(0.6)
    static let brandNavyGhost = Color(red: 26.0/255, green: 35.0/255, blue: 126.0/255).opacity(0.3)
    static let cardBgA = Color(red: 227.0/255, green: 242.0/255, blue: 253.0/255)
    static let cardBgB = Color(red: 187.0/255, green: 222.0/255, blue: 251.0/255)
    static let cardBackA = Color(red: 245.0/255, green: 245.0/255, blue: 245.0/255)
    static let cardBackB = Color(red: 207.0/255, green: 216.0/255, blue: 220.0/255)
    static let cardBackInk = Color(red: 38.0/255, green: 50.0/255, blue: 56.0/255)
    static let goldAmber = Color(red: 255.0/255, green: 179.0/255, blue: 0.0/255)
    static let skinHi = Color(red: 244.0/255, green: 199.0/255, blue: 161.0/255)
    static let skinLo = Color(red: 201.0/255, green: 160.0/255, blue: 127.0/255)
    static let hairBrown = Color(red: 62.0/255, green: 39.0/255, blue: 35.0/255)
    static let eyeInk = Color(red: 38.0/255, green: 50.0/255, blue: 56.0/255)
    static let lip = Color(red: 141.0/255, green: 91.0/255, blue: 63.0/255)
    static let neck = Color(red: 207.0/255, green: 216.0/255, blue: 220.0/255)
    static let passportA = Color(red: 27.0/255, green: 94.0/255, blue: 32.0/255)
    static let passportB = Color(red: 46.0/255, green: 125.0/255, blue: 50.0/255)
    static let phoneA = Color(red: 69.0/255, green: 90.0/255, blue: 100.0/255)
    static let phoneB = Color(red: 38.0/255, green: 50.0/255, blue: 56.0/255)
    static let screenBg = Color(red: 13.0/255, green: 71.0/255, blue: 161.0/255)
    static let nfcCyan = Color(red: 0.0/255, green: 229.0/255, blue: 255.0/255)
    static let noGlassesRed = Color(red: 198.0/255, green: 40.0/255, blue: 40.0/255)
    static let cheekGlow = Color(red: 232.0/255, green: 168.0/255, blue: 124.0/255)
}

// MARK: - Entry point

/// Renders the concept art appropriate to `kind` at a 4:3 aspect ratio.
/// Caller controls the width.
struct VisualGuide: View {
    let kind: VisualGuideKind

    var body: some View {
        // Static base (no animation needed for doc/selfie/nfc-static).
        // Animated guides re-render via TimelineView below.
        if needsAnimation(kind) {
            TimelineView(.animation) { context in
                Canvas { ctx, size in
                    let sx = size.width / LOGICAL_WIDTH
                    let sy = size.height / LOGICAL_HEIGHT
                    ctx.scaleBy(x: sx, y: sy)
                    let phase = phaseFor(date: context.date, durationMs: durationMs(kind))
                    drawAnimated(into: &ctx, kind: kind, phase: phase)
                }
            }
            .aspectRatio(320.0 / 240.0, contentMode: .fit)
        } else {
            Canvas { ctx, size in
                let sx = size.width / LOGICAL_WIDTH
                let sy = size.height / LOGICAL_HEIGHT
                ctx.scaleBy(x: sx, y: sy)
                drawStatic(into: &ctx, kind: kind)
            }
            .aspectRatio(320.0 / 240.0, contentMode: .fit)
        }
    }
}

private func needsAnimation(_ kind: VisualGuideKind) -> Bool {
    switch kind {
    case .docFront, .docBack, .selfie: return false
    default: return true
    }
}

private func durationMs(_ kind: VisualGuideKind) -> Double {
    switch kind {
    case .livenessBlink: return 1600
    default: return 2400
    }
}

/// 0..1 phase derived from wall clock, easing roughly equivalent to
/// EaseInOutSine via the triangle() helper used by the per-guide drawers.
private func phaseFor(date: Date, durationMs: Double) -> CGFloat {
    let seconds = date.timeIntervalSinceReferenceDate
    let cycle = (seconds * 1000).truncatingRemainder(dividingBy: durationMs)
    return CGFloat(cycle / durationMs)
}

private func drawStatic(into ctx: inout GraphicsContext, kind: VisualGuideKind) {
    switch kind {
    case .docFront: drawDocFront(into: &ctx)
    case .docBack: drawDocBack(into: &ctx)
    case .selfie: drawSelfie(into: &ctx)
    case .nfcScan: drawNfcScan(into: &ctx, nfcWavePhase: 0)
    default: break
    }
}

private func drawAnimated(into ctx: inout GraphicsContext, kind: VisualGuideKind, phase: CGFloat) {
    switch kind {
    case .nfcScan: drawNfcScan(into: &ctx, nfcWavePhase: phase)
    case .livenessTurnRight: drawHeadTurn(into: &ctx, phase: phase, right: true)
    case .livenessTurnLeft: drawHeadTurn(into: &ctx, phase: phase, right: false)
    case .livenessLookUp: drawLookVertical(into: &ctx, phase: phase, up: true)
    case .livenessLookDown: drawLookVertical(into: &ctx, phase: phase, up: false)
    case .livenessSmile: drawSmile(into: &ctx, phase: phase)
    case .livenessBlink: drawBlink(into: &ctx, phase: phase)
    default: break
    }
}

// MARK: - Shared pose elements

/// Draws a head with eyes/eyebrows/nose/mouth at the current origin
/// (expected to be the face centre). `eyeDx` shifts pupils horizontally,
/// `eyeDy` vertically; `mouthCurve` bends the mouth stroke 0..1.
/// `eyeLidClose` collapses the eye vertically 0..1 (used by blink).
/// `cheekGlow` fades the blush circles 0..1 (used by smile).
private func drawHeadBase(
    into ctx: inout GraphicsContext,
    eyeDx: CGFloat = 0,
    eyeDy: CGFloat = 0,
    mouthCurve: CGFloat = 0,
    eyeLidClose: CGFloat = 0,
    cheekGlow: CGFloat = 0,
    showTeeth: CGFloat = 0
) {
    // Shoulder/neck hint
    var shoulderPath = Path()
    shoulderPath.move(to: CGPoint(x: -40, y: 60))
    shoulderPath.addQuadCurve(to: CGPoint(x: -68, y: 90), control: CGPoint(x: -40, y: 78))
    shoulderPath.addLine(to: CGPoint(x: 68, y: 90))
    shoulderPath.addQuadCurve(to: CGPoint(x: 40, y: 60), control: CGPoint(x: 40, y: 78))
    shoulderPath.closeSubpath()
    ctx.fill(shoulderPath, with: .color(.neck.opacity(0.5)))

    // Head oval — radial gradient for subtle 3D
    let headRect = CGRect(x: -42, y: -60, width: 84, height: 108)
    let headShading = GraphicsContext.Shading.radialGradient(
        Gradient(colors: [.skinHi, .skinLo]),
        center: CGPoint(x: 0, y: -24),
        startRadius: 0,
        endRadius: 58
    )
    ctx.fill(Path(ellipseIn: headRect), with: headShading)

    // Hair cap
    var hairPath = Path()
    hairPath.move(to: CGPoint(x: -40, y: -30))
    hairPath.addQuadCurve(to: CGPoint(x: 0, y: -70), control: CGPoint(x: -40, y: -70))
    hairPath.addQuadCurve(to: CGPoint(x: 40, y: -30), control: CGPoint(x: 40, y: -70))
    hairPath.addQuadCurve(to: CGPoint(x: 0, y: -48), control: CGPoint(x: 30, y: -48))
    hairPath.addQuadCurve(to: CGPoint(x: -40, y: -30), control: CGPoint(x: -30, y: -48))
    hairPath.closeSubpath()
    ctx.fill(hairPath, with: .color(.hairBrown.opacity(0.8)))

    // Eyebrows
    drawLine(into: &ctx, from: CGPoint(x: -20, y: -14), to: CGPoint(x: -8, y: -15), color: .hairBrown, width: 2)
    drawLine(into: &ctx, from: CGPoint(x: 8, y: -15), to: CGPoint(x: 20, y: -14), color: .hairBrown, width: 2)

    // Eyes — vertically-scaled ovals (ry shrinks with eyeLidClose)
    let eyeRy = 2.5 * (1 - eyeLidClose)
    if eyeRy > 0.25 {
        ctx.fill(
            Path(ellipseIn: CGRect(x: -14 + eyeDx - 3.5, y: -4 + eyeDy - eyeRy, width: 7, height: eyeRy * 2)),
            with: .color(.eyeInk)
        )
        ctx.fill(
            Path(ellipseIn: CGRect(x: 14 + eyeDx - 3.5, y: -4 + eyeDy - eyeRy, width: 7, height: eyeRy * 2)),
            with: .color(.eyeInk)
        )
    }
    if eyeLidClose > 0.7 {
        let alpha = min(max((eyeLidClose - 0.7) / 0.3, 0), 1)
        drawLine(into: &ctx, from: CGPoint(x: -18, y: -4), to: CGPoint(x: -10, y: -4), color: .eyeInk.opacity(alpha), width: 1.5)
        drawLine(into: &ctx, from: CGPoint(x: 10, y: -4), to: CGPoint(x: 18, y: -4), color: .eyeInk.opacity(alpha), width: 1.5)
    }

    // Nose
    var nosePath = Path()
    nosePath.move(to: CGPoint(x: 0, y: -3))
    nosePath.addQuadCurve(to: CGPoint(x: 0, y: 11), control: CGPoint(x: -3, y: 7))
    ctx.stroke(nosePath, with: .color(.lip.opacity(0.55)), lineWidth: 1.5)

    // Cheeks (smile glow)
    if cheekGlow > 0.02 {
        ctx.fill(
            Path(ellipseIn: CGRect(x: -33, y: 5, width: 10, height: 10)),
            with: .color(.cheekGlow.opacity(cheekGlow * 0.45))
        )
        ctx.fill(
            Path(ellipseIn: CGRect(x: 23, y: 5, width: 10, height: 10)),
            with: .color(.cheekGlow.opacity(cheekGlow * 0.45))
        )
    }

    // Mouth — base curve opens into a smile as mouthCurve grows
    let half = 10 + 8 * mouthCurve
    let curveY = 20 - 2 * mouthCurve
    let dipY = 5 + 9 * mouthCurve
    var mouthPath = Path()
    mouthPath.move(to: CGPoint(x: -half, y: curveY))
    mouthPath.addQuadCurve(to: CGPoint(x: half, y: curveY), control: CGPoint(x: 0, y: curveY + dipY))
    ctx.stroke(mouthPath, with: .color(.lip), lineWidth: 2)

    // Teeth hint at peak smile
    if showTeeth > 0.05 {
        ctx.fill(
            Path(roundedRect: CGRect(x: -10, y: 18, width: 20, height: 4), cornerRadius: 1),
            with: .color(.white.opacity(showTeeth * 0.65))
        )
    }
}

/// Dashed oval + tick marks that frame the face in selfie + liveness.
private func drawFaceFrame(into ctx: inout GraphicsContext) {
    let rect = CGRect(x: 160 - 72, y: 115 - 88, width: 144, height: 176)
    let style = StrokeStyle(lineWidth: 2.5, dash: [8, 6])
    ctx.stroke(Path(ellipseIn: rect), with: .color(.brandNavy.opacity(0.5)), style: style)
}

// MARK: - 1 · Document Front

private func drawDocFront(into ctx: inout GraphicsContext) {
    // Dashed capture frame
    let frameStyle = StrokeStyle(lineWidth: 3, dash: [8, 6])
    ctx.stroke(
        Path(roundedRect: CGRect(x: 40, y: 60, width: 240, height: 150), cornerRadius: 12),
        with: .color(.brandNavy.opacity(0.6)),
        style: frameStyle
    )

    // Corner brackets
    let brackets: [[CGPoint]] = [
        [CGPoint(x: 50, y: 75), CGPoint(x: 50, y: 60), CGPoint(x: 65, y: 60)],
        [CGPoint(x: 270, y: 60), CGPoint(x: 285, y: 60), CGPoint(x: 285, y: 75)],
        [CGPoint(x: 50, y: 195), CGPoint(x: 50, y: 210), CGPoint(x: 65, y: 210)],
        [CGPoint(x: 285, y: 195), CGPoint(x: 285, y: 210), CGPoint(x: 270, y: 210)],
    ]
    for pts in brackets {
        for i in 0..<(pts.count - 1) {
            drawLine(into: &ctx, from: pts[i], to: pts[i + 1], color: .brandNavy, width: 4)
        }
    }

    // Card (slight tilt -2°)
    var sub = ctx
    sub.translateBy(x: 70, y: 85)
    sub.translateBy(x: 100, y: 60)
    sub.rotate(by: .degrees(-2))
    sub.translateBy(x: -100, y: -60)

    let cardShading = GraphicsContext.Shading.linearGradient(
        Gradient(colors: [.cardBgA, .cardBgB]),
        startPoint: .zero,
        endPoint: CGPoint(x: 0, y: 120)
    )
    sub.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 200, height: 120), cornerRadius: 10), with: cardShading)
    sub.stroke(
        Path(roundedRect: CGRect(x: 0, y: 0, width: 200, height: 120), cornerRadius: 10),
        with: .color(.brandNavy),
        lineWidth: 1.5
    )
    // Photo box
    sub.fill(
        Path(roundedRect: CGRect(x: 12, y: 14, width: 50, height: 60), cornerRadius: 4),
        with: .color(Color(red: 144.0/255, green: 202.0/255, blue: 249.0/255))
    )
    // Face silhouette in photo
    sub.fill(
        Path(ellipseIn: CGRect(x: 27, y: 26, width: 20, height: 20)),
        with: .color(.brandNavy.opacity(0.4))
    )
    var bustPath = Path()
    bustPath.move(to: CGPoint(x: 22, y: 70))
    bustPath.addQuadCurve(to: CGPoint(x: 52, y: 70), control: CGPoint(x: 37, y: 52))
    bustPath.addLine(to: CGPoint(x: 52, y: 74))
    bustPath.addLine(to: CGPoint(x: 22, y: 74))
    bustPath.closeSubpath()
    sub.fill(bustPath, with: .color(.brandNavy.opacity(0.4)))
    // Text lines
    sub.fill(Path(roundedRect: CGRect(x: 74, y: 20, width: 110, height: 6), cornerRadius: 3), with: .color(.brandNavy.opacity(0.5)))
    sub.fill(Path(roundedRect: CGRect(x: 74, y: 32, width: 90, height: 5), cornerRadius: 2.5), with: .color(.brandNavy.opacity(0.35)))
    sub.fill(Path(roundedRect: CGRect(x: 74, y: 42, width: 100, height: 5), cornerRadius: 2.5), with: .color(.brandNavy.opacity(0.35)))
    sub.fill(Path(roundedRect: CGRect(x: 74, y: 56, width: 80, height: 5), cornerRadius: 2.5), with: .color(.brandNavy.opacity(0.35)))
    // Chip
    sub.fill(Path(roundedRect: CGRect(x: 14, y: 88, width: 20, height: 16), cornerRadius: 2), with: .color(.goldAmber.opacity(0.85)))
    // MRZ
    sub.fill(Path(CGRect(x: 12, y: 108, width: 176, height: 3)), with: .color(.brandNavy.opacity(0.35)))

    // Sun (drawn on main context, not sub)
    drawSun(into: &ctx, center: CGPoint(x: 25, y: 25))
}

// MARK: - 2 · Document Back

private func drawDocBack(into ctx: inout GraphicsContext) {
    // Flip arc — dashed semicircle hinting at "flip to back side"
    let arcCenter = CGPoint(x: 160, y: 120)
    let arcRect = CGRect(x: arcCenter.x - 95, y: arcCenter.y - 55, width: 190, height: 110)
    var arcPath = Path()
    arcPath.addArc(
        center: CGPoint(x: arcRect.midX, y: arcRect.midY),
        radius: arcRect.width / 2,
        startAngle: .degrees(160),
        endAngle: .degrees(160 + 220),
        clockwise: false,
        transform: CGAffineTransform(scaleX: 1, y: arcRect.height / arcRect.width)
            .translatedBy(x: 0, y: arcRect.midY * (arcRect.width / arcRect.height - 1) / 1)
    )
    // Simpler: just stroke an elliptical arc by sampling
    arcPath = makeArcPath(rect: arcRect, startDegrees: 160, sweepDegrees: 220)
    ctx.stroke(
        arcPath,
        with: .color(.brandNavy.opacity(0.35)),
        style: StrokeStyle(lineWidth: 4, dash: [6, 6])
    )

    // Capture frame
    ctx.stroke(
        Path(roundedRect: CGRect(x: 40, y: 60, width: 240, height: 150), cornerRadius: 12),
        with: .color(.brandNavy.opacity(0.6)),
        style: StrokeStyle(lineWidth: 3, dash: [8, 6])
    )

    // Card back (light tilt +2°)
    var sub = ctx
    sub.translateBy(x: 70, y: 85)
    sub.translateBy(x: 100, y: 60)
    sub.rotate(by: .degrees(2))
    sub.translateBy(x: -100, y: -60)

    let bg = GraphicsContext.Shading.linearGradient(
        Gradient(colors: [.cardBackA, .cardBackB]),
        startPoint: .zero,
        endPoint: CGPoint(x: 0, y: 120)
    )
    sub.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 200, height: 120), cornerRadius: 10), with: bg)
    sub.stroke(
        Path(roundedRect: CGRect(x: 0, y: 0, width: 200, height: 120), cornerRadius: 10),
        with: .color(Color(red: 69.0/255, green: 90.0/255, blue: 100.0/255)),
        lineWidth: 1.5
    )
    // Magnetic stripe
    sub.fill(Path(CGRect(x: 10, y: 14, width: 180, height: 24)), with: .color(.cardBackInk))
    // Barcode lines
    let barWidths: [CGFloat] = [2, 1, 3, 1, 2, 2, 1, 3, 1, 2, 2, 1, 3, 1, 2, 2, 1, 3, 1, 2, 1, 3, 1, 2, 2]
    var x: CGFloat = 12
    for w in barWidths {
        sub.fill(Path(CGRect(x: x, y: 52, width: w, height: 36)), with: .color(.cardBackInk))
        x += w + 3
    }
    // MRZ lines
    let mrzColor = Color(red: 69.0/255, green: 90.0/255, blue: 100.0/255).opacity(0.6)
    sub.fill(Path(CGRect(x: 10, y: 96, width: 180, height: 4)), with: .color(mrzColor))
    sub.fill(Path(CGRect(x: 10, y: 104, width: 170, height: 4)), with: .color(mrzColor))
}

// MARK: - 3 · Selfie

private func drawSelfie(into ctx: inout GraphicsContext) {
    drawFaceFrame(into: &ctx)
    var sub = ctx
    sub.translateBy(x: 160, y: 115)
    drawHeadBase(into: &sub)
    drawSun(into: &ctx, center: CGPoint(x: 28, y: 30))
    drawNoGlassesGlyph(into: &ctx, center: CGPoint(x: 292, y: 30))
}

// MARK: - 4 · NFC Scan

private func drawNfcScan(into ctx: inout GraphicsContext, nfcWavePhase: CGFloat) {
    // Passport booklet
    var passport = ctx
    passport.translateBy(x: 50, y: 110)
    let passportShading = GraphicsContext.Shading.linearGradient(
        Gradient(colors: [.passportA, .passportB]),
        startPoint: .zero,
        endPoint: CGPoint(x: 0, y: 100)
    )
    passport.fill(
        Path(roundedRect: CGRect(x: 0, y: 0, width: 140, height: 100), cornerRadius: 6),
        with: passportShading
    )
    passport.stroke(
        Path(roundedRect: CGRect(x: 4, y: 4, width: 132, height: 92), cornerRadius: 4),
        with: .color(.goldAmber.opacity(0.8)),
        lineWidth: 1.5
    )
    // Crest
    passport.stroke(
        Path(ellipseIn: CGRect(x: 54, y: 24, width: 32, height: 32)),
        with: .color(.goldAmber),
        lineWidth: 1.5
    )
    var crest = Path()
    crest.move(to: CGPoint(x: 62, y: 35))
    crest.addLine(to: CGPoint(x: 70, y: 27))
    crest.addLine(to: CGPoint(x: 78, y: 35))
    crest.addLine(to: CGPoint(x: 70, y: 52))
    crest.closeSubpath()
    passport.fill(crest, with: .color(.goldAmber))

    // Phone
    var phone = ctx
    phone.translateBy(x: 140, y: 38)
    let phoneShading = GraphicsContext.Shading.linearGradient(
        Gradient(colors: [.phoneA, .phoneB]),
        startPoint: .zero,
        endPoint: CGPoint(x: 0, y: 140)
    )
    phone.fill(
        Path(roundedRect: CGRect(x: 0, y: 0, width: 76, height: 140), cornerRadius: 14),
        with: phoneShading
    )
    phone.fill(
        Path(roundedRect: CGRect(x: 5, y: 8, width: 66, height: 124), cornerRadius: 10),
        with: .color(.screenBg)
    )
    phone.fill(
        Path(ellipseIn: CGRect(x: 36, y: 4, width: 4, height: 4)),
        with: .color(Color(red: 144.0/255, green: 202.0/255, blue: 249.0/255))
    )

    // NFC waves (three nested arcs, staggered phase)
    let waveOrigin = CGPoint(x: 178, y: 38)
    for i in 0..<3 {
        let staggered = (nfcWavePhase + CGFloat(i) * 0.22).truncatingRemainder(dividingBy: 1)
        let alpha = waveAlpha(staggered)
        let r: CGFloat = 14 + CGFloat(i) * 10
        let arcPath = makeArcPath(
            rect: CGRect(x: waveOrigin.x - r, y: waveOrigin.y - r, width: r * 2, height: r * 2),
            startDegrees: 200, sweepDegrees: 140
        )
        ctx.stroke(arcPath, with: .color(.nfcCyan.opacity(alpha)), lineWidth: 2.5)
    }

    // Directional nudge arrow
    drawLine(into: &ctx, from: CGPoint(x: 220, y: 115), to: CGPoint(x: 244, y: 115), color: .brandNavy.opacity(0.75), width: 3)
    var arrow = Path()
    arrow.move(to: CGPoint(x: 248, y: 115))
    arrow.addLine(to: CGPoint(x: 240, y: 110))
    arrow.addLine(to: CGPoint(x: 240, y: 120))
    arrow.closeSubpath()
    ctx.fill(arrow, with: .color(.brandNavy.opacity(0.75)))
}

private func waveAlpha(_ t: CGFloat) -> CGFloat {
    // Fade in-out bell curve so the ping feels like a real ping
    max(0, CGFloat(sin(Double(t) * .pi)))
}

// MARK: - 5/6 · Head turn right / left

private func drawHeadTurn(into ctx: inout GraphicsContext, phase: CGFloat, right: Bool) {
    drawFaceFrame(into: &ctx)
    let s = triangle(phase)
    var sub = ctx
    sub.translateBy(x: 160, y: 115)
    let scaleX = 1 - 0.45 * s
    let eyeDx = 6 * s * (right ? 1 : -1)
    sub.scaleBy(x: scaleX, y: 1)
    drawHeadBase(into: &sub, eyeDx: eyeDx)
    drawHorizontalArrow(into: &ctx, right: right)
}

// MARK: - 7/8 · Look up / look down

private func drawLookVertical(into ctx: inout GraphicsContext, phase: CGFloat, up: Bool) {
    drawFaceFrame(into: &ctx)
    let s = triangle(phase)
    let dy = 10 * s * (up ? -1 : 1)
    let scaleY = 1 - 0.12 * s
    let eyeDy = 4 * s * (up ? -1 : 1)
    var sub = ctx
    sub.translateBy(x: 160, y: 115 + dy)
    sub.scaleBy(x: 1, y: scaleY)
    drawHeadBase(into: &sub, eyeDy: eyeDy)
    drawVerticalArrow(into: &ctx, up: up)
}

// MARK: - 9 · Smile

private func drawSmile(into ctx: inout GraphicsContext, phase: CGFloat) {
    drawFaceFrame(into: &ctx)
    let s = triangle(phase)
    var sub = ctx
    sub.translateBy(x: 160, y: 115)
    drawHeadBase(into: &sub, mouthCurve: s, cheekGlow: s, showTeeth: s)

    // Smile reaction chip (top-right)
    var chip = ctx
    chip.translateBy(x: 275, y: 40)
    chip.stroke(Path(ellipseIn: CGRect(x: -16, y: -16, width: 32, height: 32)), with: .color(.brandNavy), lineWidth: 2.5)
    chip.fill(Path(ellipseIn: CGRect(x: -6.5, y: -4.5, width: 3, height: 3)), with: .color(.brandNavy))
    chip.fill(Path(ellipseIn: CGRect(x: 3.5, y: -4.5, width: 3, height: 3)), with: .color(.brandNavy))
    var sp = Path()
    sp.move(to: CGPoint(x: -6, y: 4))
    sp.addQuadCurve(to: CGPoint(x: 6, y: 4), control: CGPoint(x: 0, y: 10))
    chip.stroke(sp, with: .color(.brandNavy), lineWidth: 2)
}

// MARK: - 10 · Blink

private func drawBlink(into ctx: inout GraphicsContext, phase: CGFloat) {
    drawFaceFrame(into: &ctx)
    let s = triangle(phase)
    var sub = ctx
    sub.translateBy(x: 160, y: 115)
    drawHeadBase(into: &sub, eyeLidClose: s)
}

// MARK: - Reusable glyphs

private func drawSun(into ctx: inout GraphicsContext, center: CGPoint) {
    ctx.fill(Path(ellipseIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)), with: .color(.goldAmber))
    let rays: [(CGPoint, CGPoint)] = [
        (CGPoint(x: 0, y: -13), CGPoint(x: 0, y: -10)),
        (CGPoint(x: 0, y: 10), CGPoint(x: 0, y: 13)),
        (CGPoint(x: -13, y: 0), CGPoint(x: -10, y: 0)),
        (CGPoint(x: 10, y: 0), CGPoint(x: 13, y: 0)),
        (CGPoint(x: -9, y: -9), CGPoint(x: -7, y: -7)),
        (CGPoint(x: 7, y: 7), CGPoint(x: 9, y: 9)),
        (CGPoint(x: 9, y: -9), CGPoint(x: 7, y: -7)),
        (CGPoint(x: -7, y: 7), CGPoint(x: -9, y: 9)),
    ]
    for (a, b) in rays {
        drawLine(
            into: &ctx,
            from: CGPoint(x: center.x + a.x, y: center.y + a.y),
            to: CGPoint(x: center.x + b.x, y: center.y + b.y),
            color: .goldAmber, width: 2
        )
    }
}

private func drawNoGlassesGlyph(into ctx: inout GraphicsContext, center: CGPoint) {
    let grey = Color(red: 84.0/255, green: 110.0/255, blue: 122.0/255)
    ctx.stroke(Path(ellipseIn: CGRect(x: center.x - 14, y: center.y - 6, width: 12, height: 12)), with: .color(grey), lineWidth: 2)
    ctx.stroke(Path(ellipseIn: CGRect(x: center.x + 2, y: center.y - 6, width: 12, height: 12)), with: .color(grey), lineWidth: 2)
    drawLine(into: &ctx, from: CGPoint(x: center.x - 2, y: center.y), to: CGPoint(x: center.x + 2, y: center.y), color: grey, width: 2)
    drawLine(into: &ctx, from: CGPoint(x: center.x - 16, y: center.y - 10), to: CGPoint(x: center.x + 16, y: center.y + 10), color: .noGlassesRed, width: 2.5)
}

private func drawHorizontalArrow(into ctx: inout GraphicsContext, right: Bool) {
    let y: CGFloat = 115
    let tipX: CGFloat = right ? 281 : 39
    let tailX: CGFloat = right ? 251 : 69
    let lineEnd: CGFloat = tipX - (right ? 6 : -6)
    drawLine(into: &ctx, from: CGPoint(x: tailX, y: y), to: CGPoint(x: lineEnd, y: y), color: .brandNavy, width: 4)
    var head = Path()
    head.move(to: CGPoint(x: tipX, y: y))
    head.addLine(to: CGPoint(x: right ? tipX - 10 : tipX + 10, y: y - 7))
    head.addLine(to: CGPoint(x: right ? tipX - 10 : tipX + 10, y: y + 7))
    head.closeSubpath()
    ctx.fill(head, with: .color(.brandNavy))
}

private func drawVerticalArrow(into ctx: inout GraphicsContext, up: Bool) {
    let x: CGFloat = 160
    let tipY: CGFloat = up ? 14 : 226
    let tailY: CGFloat = up ? 44 : 196
    let lineEnd: CGFloat = tipY + (up ? 6 : -6)
    drawLine(into: &ctx, from: CGPoint(x: x, y: tailY), to: CGPoint(x: x, y: lineEnd), color: .brandNavy, width: 4)
    var head = Path()
    head.move(to: CGPoint(x: x, y: tipY))
    head.addLine(to: CGPoint(x: x - 7, y: up ? tipY + 10 : tipY - 10))
    head.addLine(to: CGPoint(x: x + 7, y: up ? tipY + 10 : tipY - 10))
    head.closeSubpath()
    ctx.fill(head, with: .color(.brandNavy))
}

/// 0 → 1 → 0 triangular ease — matches the SVG SMIL keyTimes 0, 0.5, 1 shape.
private func triangle(_ phase: CGFloat) -> CGFloat {
    let t = min(max(phase * 2, 0), 2)
    return t <= 1 ? t : 2 - t
}

// MARK: - Helpers (SwiftUI shims)

private func drawLine(into ctx: inout GraphicsContext, from: CGPoint, to: CGPoint, color: Color, width: CGFloat) {
    var p = Path()
    p.move(to: from)
    p.addLine(to: to)
    ctx.stroke(p, with: .color(color), lineWidth: width)
}

/// Construct an elliptical-arc Path. SwiftUI's `Path.addArc` only handles
/// circles natively; for ellipses we approximate via bezier-segment sampling.
private func makeArcPath(rect: CGRect, startDegrees: CGFloat, sweepDegrees: CGFloat) -> Path {
    var p = Path()
    let cx = rect.midX
    let cy = rect.midY
    let rx = rect.width / 2
    let ry = rect.height / 2
    let segments = max(8, Int(abs(sweepDegrees) / 5))
    for i in 0...segments {
        let frac = CGFloat(i) / CGFloat(segments)
        let degrees = startDegrees + sweepDegrees * frac
        let radians = degrees * .pi / 180
        let x = cx + rx * cos(radians)
        let y = cy + ry * sin(radians)
        if i == 0 {
            p.move(to: CGPoint(x: x, y: y))
        } else {
            p.addLine(to: CGPoint(x: x, y: y))
        }
    }
    return p
}
