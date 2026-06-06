import SwiftUI

// MARK: - Color Tokens

struct KoraColors {
    static let Teal = Color(hex: "#0D9488")
    static let TealDark = Color(hex: "#0F766E")
    static let Cyan = Color(hex: "#06B6D4")
    static let TealBright = Color(hex: "#2DD4BF")

    static let SuccessGreen = Color(hex: "#16A34A")
    static let SuccessGreenDark = Color(hex: "#15803D")
    static let SuccessGreenLight = Color(hex: "#DCFCE7")
    static let SuccessGreenBorder = Color(hex: "#BBF7D0")

    static let ErrorRed = Color(hex: "#DC2626")
    static let ErrorRedDark = Color(hex: "#B91C1C")
    static let ErrorRedLight = Color(hex: "#FEF2F2")
    static let ErrorRedBorder = Color(hex: "#FECACA")

    static let WarningAmber = Color(hex: "#D97706")
    static let WarningAmberDark = Color(hex: "#92400E")
    static let WarningAmberLight = Color(hex: "#FEF3C7")
    static let WarningAmberBorder = Color(hex: "#FDE68A")
    static let WarningYellowLight = Color(hex: "#FEF9C3")

    static let InfoBlue = Color(hex: "#0284C7")
    static let InfoBlueDark = Color(hex: "#0369A1")
    static let InfoBlueLight = Color(hex: "#E0F2FE")
    static let InfoBlueBorder = Color(hex: "#BAE6FD")

    static let Purple = Color(hex: "#9333EA")
    static let PurpleLight = Color(hex: "#F3E8FF")
    static let Indigo = Color(hex: "#4F46E5")
    static let IndigoLight = Color(hex: "#E0E7FF")

    static let DarkBg = Color(hex: "#111111")
    static let DarkSurface = Color(hex: "#1A1A1A")

    static let Surface = Color(hex: "#F8FAFB")
    static let SurfaceLight = Color(hex: "#F9FAFB")
    static let SelectedBg = Color(hex: "#F0FDFA")
    static let CloseButtonBg = Color(hex: "#F3F4F6")
    static let BorderLight = Color(hex: "#E5E7EB")
    static let ProgressTrack = Color(hex: "#E0E0E0")

    static let TextPrimary = Color(hex: "#111111")
    static let TextSecondary = Color(hex: "#888888")
    static let TextTertiary = Color(hex: "#666666")
    static let TextMuted = Color(hex: "#999999")
    static let TextDark = Color(hex: "#333333")
    static let TextSubtle = Color(hex: "#374151")

    static let tealGradient = LinearGradient(
        colors: [Teal, TealDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let redGradient = LinearGradient(
        colors: [ErrorRed, ErrorRedDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let blueGradient = LinearGradient(
        colors: [InfoBlue, InfoBlueDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let successGradient = LinearGradient(
        colors: [SuccessGreen, SuccessGreenDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Button Variants

enum KoraButtonVariant {
    case tealGradient, darkOutline, whiteOutline
}

struct KoraButton: View {
    let text: String
    let action: () -> Void
    var variant: KoraButtonVariant = .tealGradient
    var enabled: Bool = true
    var trailingIcon: (() -> AnyView)? = nil

    var body: some View {
        Button(action: enabled ? action : {}) {
            HStack(spacing: 8) {
                Text(text)
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.2)
                if let icon = trailingIcon {
                    icon()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .foregroundColor(foregroundColor)
            .background(backgroundView)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(borderView)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1.0 : 0.6)
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch variant {
        case .tealGradient:
            KoraColors.tealGradient
        case .darkOutline:
            Color.clear
        case .whiteOutline:
            Color.white
        }
    }

    @ViewBuilder
    private var borderView: some View {
        switch variant {
        case .tealGradient:
            EmptyView()
        case .darkOutline:
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.15), lineWidth: 2)
        case .whiteOutline:
            RoundedRectangle(cornerRadius: 16)
                .stroke(KoraColors.BorderLight, lineWidth: 2)
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .tealGradient, .darkOutline:
            return .white
        case .whiteOutline:
            return KoraColors.TextSubtle
        }
    }
}

// MARK: - Step Progress Bar

struct StepProgressBar: View {
    var total: Int = 5
    var current: Int
    var isDark: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...total, id: \.self) { step in
                let trackColor = isDark ? Color.white.opacity(0.15) : KoraColors.ProgressTrack

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(trackColor)
                        if step < current {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(KoraColors.Teal)
                        } else if step == current {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(KoraColors.Teal)
                                .frame(width: geo.size.width * 0.6)
                        }
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current) of \(total)")
    }
}

// MARK: - Score Card

struct ScoreCard: View {
    let score: Int
    let badge: String
    let gradient: LinearGradient

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Overall Score")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(badge)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Spacer().frame(height: 12)

            Text("\(score)%")
                .font(.system(size: 36, weight: .heavy))
                .tracking(-1)
                .foregroundColor(.white)

            Spacer().frame(height: 8)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.2))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white)
                        .frame(width: geo.size.width * CGFloat(score) / 100)
                }
            }
            .frame(height: 6)
        }
        .padding(16)
        .background(gradient)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 24)
    }
}

// MARK: - Score Metric Row

enum MetricStatus {
    case pass, fail, borderline
}

struct ScoreMetric {
    let label: String
    let score: Int
    let iconName: String
    let status: MetricStatus
    var errorMessage: String? = nil
}

struct ScoreMetricRow: View {
    let metric: ScoreMetric

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: metric.iconName)
                .font(.system(size: 16))
                .foregroundColor(iconColor)
                .frame(width: 34, height: 34)
                .background(iconBgColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(metric.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(KoraColors.TextPrimary)
                    Spacer()
                    Text("\(metric.score)%")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(scoreColor)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barTrackColor)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(scoreColor)
                            .frame(width: geo.size.width * CGFloat(metric.score) / 100)
                    }
                }
                .frame(height: 4)

                if let error = metric.errorMessage {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(scoreColor)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(bgColor)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            borderOverlay
        )
    }

    private var bgColor: Color {
        switch metric.status {
        case .pass: return KoraColors.Surface
        case .fail: return KoraColors.ErrorRedLight
        case .borderline: return Color(hex: "#FFFBEB")
        }
    }

    private var iconBgColor: Color {
        switch metric.status {
        case .pass: return KoraColors.SuccessGreenLight
        case .fail: return KoraColors.ErrorRedBorder
        case .borderline: return KoraColors.WarningAmberLight
        }
    }

    private var iconColor: Color {
        switch metric.status {
        case .pass: return KoraColors.SuccessGreen
        case .fail: return KoraColors.ErrorRed
        case .borderline: return KoraColors.WarningAmber
        }
    }

    private var scoreColor: Color {
        switch metric.status {
        case .pass: return KoraColors.SuccessGreen
        case .fail: return KoraColors.ErrorRed
        case .borderline: return KoraColors.WarningAmber
        }
    }

    private var barTrackColor: Color {
        switch metric.status {
        case .pass: return KoraColors.BorderLight
        case .fail: return KoraColors.ErrorRedBorder
        case .borderline: return KoraColors.WarningAmberBorder
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        switch metric.status {
        case .fail:
            HStack {
                Rectangle().fill(KoraColors.ErrorRed).frame(width: 3)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        case .borderline:
            HStack {
                Rectangle().fill(KoraColors.WarningAmber).frame(width: 3)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        case .pass:
            EmptyView()
        }
    }
}

// MARK: - Dark Screen Header

struct DarkScreenHeader: View {
    let title: String
    var subtitle: String? = nil
    let onClose: () -> Void

    var body: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Close")

            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity)

            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }
}

// MARK: - Guidance Pill

enum GuidancePillVariant {
    case scanning, ready
}

struct GuidancePill: View {
    let text: String
    var variant: GuidancePillVariant = .scanning

    @State private var dotOpacity: Double = 1.0

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .opacity(dotOpacity)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                        dotOpacity = 0.5
                    }
                }

            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(textColor)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(bgColor)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var bgColor: Color {
        switch variant {
        case .scanning: return KoraColors.Teal.opacity(0.15)
        case .ready: return Color(hex: "#10B981").opacity(0.15)
        }
    }

    private var textColor: Color {
        switch variant {
        case .scanning: return KoraColors.TealBright
        case .ready: return Color(hex: "#34D399")
        }
    }

    private var dotColor: Color { textColor }
}

// MARK: - Icon Circle

struct IconCircle: View {
    let iconName: String
    let bgColor: Color
    let iconColor: Color
    var size: CGFloat = 56
    var iconSize: CGFloat = 36
    var outerRingColor: Color? = nil

    var body: some View {
        ZStack {
            if let ringColor = outerRingColor {
                Circle()
                    .stroke(ringColor, lineWidth: 2)
                    .frame(width: size + 16, height: size + 16)
            }

            Circle()
                .fill(bgColor)
                .frame(width: size, height: size)

            Image(systemName: iconName)
                .font(.system(size: iconSize * 0.6, weight: .medium))
                .foregroundColor(iconColor)
        }
    }
}

// MARK: - Light Buttons

struct LightCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(KoraColors.TextTertiary)
                .frame(width: 36, height: 36)
                .background(KoraColors.CloseButtonBg)
                .clipShape(Circle())
        }
        .accessibilityLabel("Close")
    }
}

struct LightBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(KoraColors.TextTertiary)
                .frame(width: 36, height: 36)
                .background(KoraColors.CloseButtonBg)
                .clipShape(Circle())
        }
        .accessibilityLabel("Go back")
    }
}

// MARK: - Review Quality Check

struct ReviewQualityCheck: View {
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(hex: "#34D399"))
                .frame(width: 16, height: 16)

            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

// MARK: - Step Pill

enum StepPillState {
    case active, inactive, done
}

struct StepPill: View {
    let text: String
    let state: StepPillState

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(textColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var bgColor: Color {
        switch state {
        case .active: return KoraColors.Teal
        case .inactive: return Color.white.opacity(0.08)
        case .done: return KoraColors.Teal.opacity(0.2)
        }
    }

    private var textColor: Color {
        switch state {
        case .active: return .white
        case .inactive: return .white.opacity(0.4)
        case .done: return KoraColors.TealBright
        }
    }
}

// MARK: - Challenge Progress Dots

struct ChallengeDots: View {
    var total: Int = 3
    var currentIndex: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(dotColor(for: index))
                    .frame(width: 10, height: 10)
            }
        }
    }

    private func dotColor(for index: Int) -> Color {
        if index < currentIndex {
            return KoraColors.Teal
        } else if index == currentIndex {
            return KoraColors.TealBright
        } else {
            return Color.white.opacity(0.15)
        }
    }
}

// MARK: - Countdown Badge

struct CountdownBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 40, height: 40)
            .background(KoraColors.ErrorRed)
            .clipShape(Circle())
    }
}

// MARK: - Review Badge

struct ReviewBadge: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: "#34D399"))
                .frame(width: 6, height: 6)

            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "#34D399"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(hex: "#10B981").opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityLabel(text)
    }
}

// MARK: - Score Breakdown Helper

struct ScoreBreakdown {
    let liveness: Int
    let nameMatch: Int
    let documentQuality: Int
    let selfieMatch: Int
    let overallScore: Int

    static func compute(from verification: Verification) -> ScoreBreakdown {
        // **v1.9.0-rc5.2 — overall + nameMatch fix.**
        //
        // rc5 already fixed the per-metric scale issue (read from typed
        // `verification.scores` instead of multiplying
        // `faceVerification.matchScore` by 100). Stratum Remit's
        // 2026-06-06 rc5.1 device test surfaced two more math bugs in
        // the same function:
        //
        // 1. **Overall was displaying `riskScore` directly.** Backend
        //    sends `riskScore = int(100 - final_score)` — i.e. the
        //    *inverse* of overall. For a verification with
        //    `final_score = 73.62`, backend sent `riskScore = 26`, and
        //    iOS rendered "Overall Score: 26%" with all individual
        //    metrics 72/82/92/0. User correctly flagged "the math is
        //    not right": (0+82+92+72)/4 = 61 expected, 26 displayed.
        //    Fix: invert riskScore (`100 - risk`) to recover overall.
        //    Fallback to `scores.overall` (IDV-only) when riskScore
        //    absent.
        //
        // 2. **Name Match was derived from `faceMatch + 10`.** A
        //    placeholder from before the backend emitted a typed
        //    nameMatch score. Same verification: server had
        //    `nameMatch: 100`, iOS displayed 92 (82+10). Fix: read
        //    `scores.nameMatch` directly.
        //
        // All four displayed metrics now come from the same typed
        // 0-100 source (`scores`). Old fallback path preserved for
        // backends that don't emit `scores` (defensive only — current
        // backend always emits on /complete).
        let scores = verification.scores
        let livenessScore: Int
        let faceScore: Int
        let docScore: Int
        let nameScore: Int
        let overallScore: Int

        if let scores = scores {
            livenessScore = Int(scores.liveness)
            faceScore = Int(scores.faceMatch)
            docScore = Int(scores.documentAuth)
            nameScore = Int(scores.nameMatch)
            // Prefer `100 - riskScore` over `scores.overall` because
            // riskScore is derived from `final_score` (post-compliance
            // blend) which is what the backend's auto-reject decision
            // actually used. `scores.overall` is IDV-only and would
            // understate the user-perceived "overall" by the compliance
            // weight. Falls back to scores.overall if riskScore absent.
            if let risk = verification.riskScore {
                overallScore = max(0, min(100, 100 - risk))
            } else {
                overallScore = Int(scores.overall)
            }
        } else {
            // Legacy fallback for backends that don't emit `scores`.
            // Keeps the old multiply-by-100 path (those wire shapes
            // used 0-1 floats) and the derived nameMatch.
            livenessScore = Int((verification.livenessVerification?.livenessScore ?? 0) * 100)
            faceScore = Int((verification.faceVerification?.matchScore ?? 0) * 100)
            docScore = Int((verification.documentVerification?.authenticityScore ?? 0) * 100)
            nameScore = faceScore > 0 ? min(faceScore + 10, 100) : 0
            // Even on the legacy path, riskScore is the inverse of
            // overall — preserve the invert semantic. The prior code
            // erroneously assigned riskScore directly to overall.
            if let risk = verification.riskScore {
                overallScore = max(0, min(100, 100 - risk))
            } else {
                overallScore = (livenessScore + nameScore + docScore + faceScore) / 4
            }
        }

        return ScoreBreakdown(
            liveness: livenessScore,
            nameMatch: nameScore,
            documentQuality: docScore,
            selfieMatch: faceScore,
            overallScore: overallScore
        )
    }
}
