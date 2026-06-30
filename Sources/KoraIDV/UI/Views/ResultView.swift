import SwiftUI

// MARK: - Processing Screen (Screen 10)

struct ProcessingScreen: View {
    let steps: [ProcessingStepItem]

    // Calm "breathing" pulse for the shield badge — a single, slow
    // opacity fade instead of the old three-ring swirl. (BanffPay
    // 2026-06-29: the spinning-rings loader read as a jarring "swirl"
    // after liveness; we already removed the equivalent swirl from the
    // selfie/liveness ovals. The per-step ProgressView spinners below
    // carry the "work is happening" signal.)
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Calm static shield badge (no rotation), gentle pulse only.
            ZStack {
                Circle()
                    .fill(KoraColors.Teal.opacity(0.12))
                    .frame(width: 96, height: 96)
                Circle()
                    .stroke(KoraColors.Teal.opacity(0.35), lineWidth: 2)
                    .frame(width: 96, height: 96)
                Image(systemName: "shield.checkered")
                    .font(.system(size: 34))
                    .foregroundColor(KoraColors.Teal)
            }
            .scaleEffect(pulse ? 1.04 : 0.96)
            .opacity(pulse ? 1.0 : 0.85)
            .accessibilityHidden(true)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }

            Spacer().frame(height: 32)

            Text(L10n.tr("koraidv.result.processing.title"))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .accessibilityAddTraits(.isHeader)

            Text(L10n.tr("koraidv.result.processing.subtitle"))
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))
                .padding(.top, 4)

            Spacer().frame(height: 32)

            // Processing steps
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 12) {
                        ZStack {
                            if step.status == .done {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(KoraColors.Teal)
                            } else if step.status == .active {
                                // Calm pulsing dot instead of the spinning
                                // iOS ProgressView — the spinner was the last
                                // remaining "swirl" on the post-liveness screen
                                // (BanffPay 2026-06-29).
                                ActiveStepDot()
                            } else {
                                Circle()
                                    .fill(Color.white.opacity(0.15))
                                    .frame(width: 20, height: 20)
                            }
                        }
                        .frame(width: 20, height: 20)

                        Text(step.label)
                            .font(.system(size: 15))
                            .foregroundColor(step.status == .pending ? .white.opacity(0.4) : .white)
                    }
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        // **v1.9.0-rc6.3 — fill the screen.** Previously the VStack
        // sized to its content (rings + text + steps) and `.background`
        // painted only that area, leaving the parent navigation
        // controller's empty space visible on the sides and top/bottom
        // (Stratum Remit 2026-06-06: "the ui looks awkward... dark
        // band in the middle, empty on the sides"). `.frame(maxWidth/
        // maxHeight: .infinity)` makes the VStack expand to fill its
        // parent so `.background` paints edge-to-edge. `.ignoresSafeArea`
        // extends the dark color into the safe-area insets (status bar
        // and home indicator) for a true full-screen look.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KoraColors.DarkBg.ignoresSafeArea())
    }
}

struct ProcessingStepItem {
    let label: String
    let status: ProcessingStepStatus
}

enum ProcessingStepStatus {
    case done, active, pending
}

/// Calm "in progress" indicator for the active processing step — a teal
/// dot that gently breathes (scale + opacity), with NO rotation. Replaces
/// the spinning iOS `ProgressView`, which read as a "swirl" after the
/// liveness check (BanffPay 2026-06-29).
struct ActiveStepDot: View {
    @State private var pulse = false
    var body: some View {
        Circle()
            .fill(KoraColors.Teal)
            .frame(width: 14, height: 14)
            .scaleEffect(pulse ? 1.0 : 0.6)
            .opacity(pulse ? 1.0 : 0.5)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Success Screen (Screen 11)

struct SuccessScreen: View {
    let verification: Verification
    let onDone: () -> Void

    var body: some View {
        let scores = ScoreBreakdown.compute(from: verification)
        let metrics = buildMetrics(scores: scores)

        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 40)

                // Green check icon
                IconCircle(
                    iconName: "checkmark",
                    bgColor: KoraColors.SuccessGreen,
                    iconColor: .white,
                    outerRingColor: KoraColors.SuccessGreenBorder
                )
                .accessibilityHidden(true)

                Spacer().frame(height: 20)

                Text(L10n.tr("koraidv.result.approved.title"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(KoraColors.TextPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text(L10n.tr("koraidv.result.approved.subtitle"))
                    .font(.system(size: 14))
                    .foregroundColor(KoraColors.TextSecondary)
                    .padding(.top, 4)

                Spacer().frame(height: 24)

                // Score card
                ScoreCard(
                    score: scores.overallScore,
                    badge: L10n.tr("koraidv.score.passed"),
                    gradient: KoraColors.tealGradient
                )
                .accessibilityLabel("Overall score: \(scores.overallScore) percent. Passed")

                Spacer().frame(height: 16)

                // Metric rows
                VStack(spacing: 8) {
                    ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                        ScoreMetricRow(metric: metric)
                            .accessibilityLabel("\(metric.label): \(metric.score) percent. \(metric.status == .pass ? "Passed" : "Failed")")
                    }
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 32)

                // Done button
                KoraButton(text: L10n.tr("koraidv.result.approved.button"), action: onDone)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
        }
        .background(Color.white)
    }

    private func buildMetrics(scores: ScoreBreakdown) -> [ScoreMetric] {
        var metrics: [ScoreMetric] = [
            ScoreMetric(label: L10n.tr("koraidv.score.liveness"), score: scores.liveness, iconName: "eye.fill", status: scores.liveness >= 70 ? .pass : .fail),
        ]
        // Screening (compliance) — shown only when the backend ran it, matching
        // the Android result view (cross-platform parity, 2026-06-22).
        if let screening = scores.screening {
            metrics.append(ScoreMetric(label: L10n.tr("koraidv.score.screening"), score: screening, iconName: "shield.fill", status: screening >= 70 ? .pass : .fail))
        }
        metrics.append(contentsOf: [
            ScoreMetric(label: L10n.tr("koraidv.score.name_match"), score: scores.nameMatch, iconName: "checkmark.circle.fill", status: scores.nameMatch >= 70 ? .pass : .fail),
            // Doc quality + selfie pass-floor is 60 (not 70) — color must match,
            // or a passed metric shows red (BanffPay 2026-06-22). Selfie also
            // gets an amber band over the 45-60 manual-review zone.
            ScoreMetric(label: L10n.tr("koraidv.score.document_quality"), score: scores.documentQuality, iconName: "creditcard.fill", status: scores.documentQuality >= 60 ? .pass : .fail),
            ScoreMetric(label: L10n.tr("koraidv.score.selfie_match"), score: scores.selfieMatch, iconName: "person.fill", status: scores.selfieMatch >= 60 ? .pass : (scores.selfieMatch >= 45 ? .borderline : .fail)),
        ])
        return metrics
    }
}

// MARK: - Rejected Screen (Screen 12)

struct RejectedScreen: View {
    let verification: Verification
    let onRetry: () -> Void

    var body: some View {
        let scores = ScoreBreakdown.compute(from: verification)
        let metrics = buildMetrics(scores: scores)

        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 40)

                // Red X icon
                IconCircle(
                    iconName: "xmark",
                    bgColor: KoraColors.ErrorRed,
                    iconColor: .white,
                    outerRingColor: KoraColors.ErrorRedBorder
                )
                .accessibilityHidden(true)

                Spacer().frame(height: 20)

                Text(L10n.tr("koraidv.result.rejected.title"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(KoraColors.TextPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text(L10n.tr("koraidv.result.rejected.subtitle"))
                    .font(.system(size: 14))
                    .foregroundColor(KoraColors.TextSecondary)
                    .padding(.top, 4)

                // **v1.9.0-rc6.7** — Surface the backend's
                // `decisionReason` prominently. Without this, users hit
                // by hard-reject rules (country mismatch, doc-type
                // mismatch, expired-doc backstops) saw only the
                // generic "couldn't verify" + score breakdown and
                // misread the lowest-scoring metric as the cause.
                // Stratum Remit 2026-06-07 cross-doc test: rejection
                // for "selected NG, scanned US" was actually about
                // country mismatch but the user saw Selfie Match 57%
                // and tried to fix lighting. Displaying the backend's
                // specific reason eliminates that confusion.
                if let reason = verification.decisionReason, !reason.isEmpty {
                    Text(reason)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(KoraColors.ErrorRed)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                        .padding(.horizontal, 32)
                        .accessibilityLabel("Rejection reason: \(reason)")
                }

                Spacer().frame(height: 24)

                // Score card
                ScoreCard(
                    score: scores.overallScore,
                    badge: L10n.tr("koraidv.score.rejected"),
                    gradient: KoraColors.redGradient
                )
                .accessibilityLabel("Overall score: \(scores.overallScore) percent. Rejected")

                Spacer().frame(height: 16)

                // Metric rows
                VStack(spacing: 8) {
                    ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                        ScoreMetricRow(metric: metric)
                            .accessibilityLabel("\(metric.label): \(metric.score) percent. \(metric.status == .pass ? "Passed" : "Failed")")
                    }
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 32)

                // Try again button
                KoraButton(text: L10n.tr("koraidv.result.rejected.button"), action: onRetry)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
        }
        .background(Color.white)
    }

    private func buildMetrics(scores: ScoreBreakdown) -> [ScoreMetric] {
        var metrics: [ScoreMetric] = [
            ScoreMetric(
                label: L10n.tr("koraidv.score.liveness"), score: scores.liveness, iconName: "eye.fill",
                status: scores.liveness >= 70 ? .pass : .fail,
                errorMessage: scores.liveness < 70 ? L10n.tr("koraidv.score.error.liveness") : nil
            ),
        ]
        // Screening (compliance) — shown when the backend ran it (Android parity).
        if let screening = scores.screening {
            metrics.append(ScoreMetric(
                label: L10n.tr("koraidv.score.screening"), score: screening, iconName: "shield.fill",
                status: screening >= 70 ? .pass : .fail
            ))
        }
        metrics.append(contentsOf: [
            ScoreMetric(
                label: L10n.tr("koraidv.score.name_match"), score: scores.nameMatch, iconName: "checkmark.circle.fill",
                status: scores.nameMatch >= 70 ? .pass : .fail,
                errorMessage: scores.nameMatch < 70 ? L10n.tr("koraidv.score.error.name") : nil
            ),
            ScoreMetric(
                label: L10n.tr("koraidv.score.document_quality"), score: scores.documentQuality, iconName: "creditcard.fill",
                status: scores.documentQuality >= 60 ? .pass : .fail,
                errorMessage: scores.documentQuality < 60 ? L10n.tr("koraidv.score.error.document") : nil
            ),
            ScoreMetric(
                label: L10n.tr("koraidv.score.selfie_match"), score: scores.selfieMatch, iconName: "person.fill",
                status: scores.selfieMatch >= 60 ? .pass : (scores.selfieMatch >= 45 ? .borderline : .fail),
                errorMessage: scores.selfieMatch < 45 ? L10n.tr("koraidv.score.error.selfie") : nil
            ),
        ])
        return metrics
    }
}

// MARK: - Expired Document Screen (Screen 13)

struct ExpiredDocumentScreen: View {
    let verification: Verification
    let onRetry: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 40)

                // Amber warning icon
                IconCircle(
                    iconName: "exclamationmark.triangle.fill",
                    bgColor: KoraColors.WarningAmber,
                    iconColor: .white,
                    outerRingColor: KoraColors.WarningAmberBorder
                )
                .accessibilityHidden(true)

                Spacer().frame(height: 20)

                Text(L10n.tr("koraidv.result.expired.title"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(KoraColors.TextPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text(L10n.tr("koraidv.result.expired.subtitle"))
                    .font(.system(size: 14))
                    .foregroundColor(KoraColors.TextSecondary)
                    .padding(.top, 4)

                Spacer().frame(height: 24)

                // Expiry details card
                VStack(alignment: .leading, spacing: 12) {
                    if let docType = verification.documentVerification?.documentType {
                        HStack {
                            Text(L10n.tr("koraidv.result.expired.doc_type"))
                                .font(.system(size: 13))
                                .foregroundColor(KoraColors.TextSecondary)
                            Spacer()
                            Text(docType)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(KoraColors.TextPrimary)
                        }
                    }

                    if let country = verification.documentVerification?.issuingCountry {
                        HStack {
                            Text(L10n.tr("koraidv.result.expired.country"))
                                .font(.system(size: 13))
                                .foregroundColor(KoraColors.TextSecondary)
                            Spacer()
                            Text(country)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(KoraColors.TextPrimary)
                        }
                    }

                    if let expDate = verification.documentVerification?.expirationDate {
                        HStack {
                            Text(L10n.tr("koraidv.result.expired.date"))
                                .font(.system(size: 13))
                                .foregroundColor(KoraColors.TextSecondary)
                            Spacer()
                            Text(expDate)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(KoraColors.ErrorRed)
                        }
                    }
                }
                .padding(16)
                .background(KoraColors.WarningAmberLight)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(KoraColors.WarningAmberBorder, lineWidth: 1)
                )
                .padding(.horizontal, 24)

                Spacer().frame(height: 24)

                // Guidance tips
                VStack(alignment: .leading, spacing: 16) {
                    GuidanceTip(number: 1, text: L10n.tr("koraidv.result.expired.tip1"))
                    GuidanceTip(number: 2, text: L10n.tr("koraidv.result.expired.tip2"))
                    GuidanceTip(number: 3, text: L10n.tr("koraidv.result.expired.tip3"))
                }
                .padding(.horizontal, 24)
                .accessibilityElement(children: .combine)

                Spacer().frame(height: 32)

                // Button
                KoraButton(text: L10n.tr("koraidv.result.expired.button"), action: onRetry)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
        }
        .background(Color.white)
    }
}

// MARK: - Manual Review Screen (Screen 14)

struct ManualReviewScreen: View {
    let verification: Verification
    let onDone: () -> Void

    var body: some View {
        let scores = ScoreBreakdown.compute(from: verification)
        let metrics = buildMetrics(scores: scores)

        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 40)

                // Blue clock icon
                IconCircle(
                    iconName: "clock.fill",
                    bgColor: KoraColors.InfoBlue,
                    iconColor: .white,
                    outerRingColor: KoraColors.InfoBlueBorder
                )
                .accessibilityHidden(true)

                Spacer().frame(height: 20)

                Text(L10n.tr("koraidv.result.review.title"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(KoraColors.TextPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text(L10n.tr("koraidv.result.review.subtitle"))
                    .font(.system(size: 14))
                    .foregroundColor(KoraColors.TextSecondary)
                    .padding(.top, 4)

                Spacer().frame(height: 24)

                // Score card
                ScoreCard(
                    score: scores.overallScore,
                    badge: L10n.tr("koraidv.score.review"),
                    gradient: KoraColors.blueGradient
                )
                .accessibilityLabel("Overall score: \(scores.overallScore) percent. Under review")

                Spacer().frame(height: 16)

                // Metric rows
                VStack(spacing: 8) {
                    ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                        ScoreMetricRow(metric: metric)
                            .accessibilityLabel("\(metric.label): \(metric.score) percent. \(metric.status == .pass ? "Passed" : metric.status == .borderline ? "Under review" : "Failed")")
                    }
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 32)

                // Got it button
                KoraButton(text: L10n.tr("koraidv.result.review.button"), action: onDone)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
        }
        .background(Color.white)
    }

    private func buildMetrics(scores: ScoreBreakdown) -> [ScoreMetric] {
        let selfieStatus: MetricStatus = scores.selfieMatch >= 60 ? .pass : (scores.selfieMatch >= 45 ? .borderline : .fail)
        var metrics: [ScoreMetric] = [
            ScoreMetric(label: L10n.tr("koraidv.score.liveness"), score: scores.liveness, iconName: "eye.fill", status: scores.liveness >= 70 ? .pass : .borderline),
        ]
        // Screening (compliance) — shown when the backend ran it (Android parity).
        if let screening = scores.screening {
            metrics.append(ScoreMetric(label: L10n.tr("koraidv.score.screening"), score: screening, iconName: "shield.fill", status: screening >= 70 ? .pass : .borderline))
        }
        metrics.append(contentsOf: [
            ScoreMetric(label: L10n.tr("koraidv.score.name_match"), score: scores.nameMatch, iconName: "checkmark.circle.fill", status: scores.nameMatch >= 70 ? .pass : .borderline),
            ScoreMetric(label: L10n.tr("koraidv.score.document_quality"), score: scores.documentQuality, iconName: "creditcard.fill", status: scores.documentQuality >= 70 ? .pass : .borderline),
            ScoreMetric(label: L10n.tr("koraidv.score.selfie_match"), score: scores.selfieMatch, iconName: selfieStatus == .borderline ? "info.circle.fill" : "person.fill", status: selfieStatus),
        ])
        return metrics
    }
}

// MARK: - Guidance Tip

private struct GuidanceTip: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(KoraColors.Teal)
                .frame(width: 24, height: 24)
                .background(KoraColors.SelectedBg)
                .clipShape(Circle())

            Text(text)
                .font(.system(size: 14))
                .foregroundColor(KoraColors.TextTertiary)
                .lineSpacing(2)
        }
    }
}

// MARK: - Error View

struct ErrorView: View {
    let error: KoraError
    let theme: KoraTheme
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Error icon
            IconCircle(
                iconName: "exclamationmark.circle.fill",
                bgColor: KoraColors.ErrorRed,
                iconColor: .white,
                outerRingColor: KoraColors.ErrorRedBorder
            )
            .accessibilityHidden(true)

            Spacer().frame(height: 20)

            Text(L10n.tr("koraidv.result.error.title"))
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(KoraColors.TextPrimary)
                .accessibilityAddTraits(.isHeader)

            Text(error.localizedDescription)
                .font(.system(size: 15))
                .foregroundColor(KoraColors.TextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 8)

            if let suggestion = error.recoverySuggestion {
                // Guidance card
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 16))
                        .foregroundColor(KoraColors.WarningAmber)

                    Text(suggestion)
                        .font(.system(size: 14))
                        .foregroundColor(KoraColors.TextTertiary)
                        .lineSpacing(2)
                }
                .padding(16)
                .background(KoraColors.WarningAmberLight)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .accessibilityElement(children: .combine)
            }

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                KoraButton(text: L10n.tr("koraidv.result.error.retry"), action: onRetry)

                KoraButton(
                    text: L10n.tr("koraidv.result.error.cancel"),
                    action: onCancel,
                    variant: .whiteOutline
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.white)
    }
}

// MARK: - Loading View

struct LoadingView: View {
    let message: String

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                // Pulsing icon
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 48))
                    .foregroundColor(KoraColors.Teal)

                Circle()
                    .stroke(KoraColors.Teal.opacity(0.3), lineWidth: 2)
                    .frame(width: 80, height: 80)

                ProgressView()
                    .scaleEffect(1.2)
                    .accentColor(KoraColors.Teal)
                    .frame(width: 100, height: 100)
            }
            .accessibilityHidden(true)

            Spacer().frame(height: 24)

            Text(message)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(KoraColors.TextPrimary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

// MARK: - Simplified Result Screens (REQ-005)

/// Success / Failed / Review screens that show only the outcome — no scores,
/// no metrics. Used when `Configuration.resultPageMode == .simplified`.

struct SimplifiedSuccessScreen: View {
    let messages: ResultPageMessages?
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(KoraColors.SuccessGreen.opacity(0.12))
                    .frame(width: 96, height: 96)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [KoraColors.SuccessGreen, Color(red: 5/255, green: 150/255, blue: 105/255)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            }
            Text(messages?.successTitle ?? "Verification Successful")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(KoraColors.TextPrimary)
                .padding(.top, 16)
            Text(messages?.successMessage ?? "Your identity has been successfully verified. You can now proceed.")
                .font(.system(size: 16))
                .foregroundColor(KoraColors.TextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .padding(.top, 8)
            Spacer()
            Button(action: onDone) {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(KoraColors.Teal)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

struct SimplifiedFailedScreen: View {
    let messages: ResultPageMessages?
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(KoraColors.ErrorRed.opacity(0.12))
                    .frame(width: 96, height: 96)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [KoraColors.ErrorRed, Color(red: 185/255, green: 28/255, blue: 28/255)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                Image(systemName: "xmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            }
            Text(messages?.failedTitle ?? "Verification Failed")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(KoraColors.TextPrimary)
                .padding(.top, 16)
            Text(messages?.failedMessage ?? "We could not verify your identity. Please try again with a valid document.")
                .font(.system(size: 16))
                .foregroundColor(KoraColors.TextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .padding(.top, 8)
            Spacer()
            Button(action: onRetry) {
                Text("Try Again")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(KoraColors.Teal)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

struct SimplifiedReviewScreen: View {
    let verification: Verification
    let messages: ResultPageMessages?
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(KoraColors.WarningAmber.opacity(0.12))
                    .frame(width: 96, height: 96)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [KoraColors.WarningAmber, Color(red: 180/255, green: 83/255, blue: 9/255)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                Image(systemName: "clock.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            }
            Text(messages?.reviewTitle ?? "Verification Under Review")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(KoraColors.TextPrimary)
                .padding(.top, 16)
            Text(messages?.reviewMessage ?? "Your verification requires additional review. We will notify you of the result.")
                .font(.system(size: 16))
                .foregroundColor(KoraColors.TextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .padding(.top, 8)
            // Reference number
            HStack(spacing: 4) {
                Text("Reference:")
                    .font(.system(size: 12))
                    .foregroundColor(KoraColors.TextSecondary)
                Text(String(verification.id.prefix(8)))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(KoraColors.TextPrimary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(KoraColors.InfoBlue.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(KoraColors.InfoBlue.opacity(0.30), lineWidth: 1)
            )
            .cornerRadius(8)
            .padding(.top, 24)
            Spacer()
            Button(action: onDone) {
                Text("Got It")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(KoraColors.Teal)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

// MARK: - Backward Compatibility

struct ResultView: View {
    let verification: Verification
    let theme: KoraTheme
    let onDone: () -> Void

    var body: some View {
        switch verification.status {
        // **v1.9.0-rc6.3** — `.verified` is the backend's wire string
        // for auto-approve (added in rc6.2 to VerificationStatus enum).
        // Without this case, the switch fell into the `default` branch
        // and rendered ProcessingScreen forever — Stratum Remit's
        // 2026-06-06 rc6.2 test was stuck on "Verifying your identity /
        // Processing verification" 1+ minute after `/complete` returned
        // 200 with the approved verification. Same route as `.approved`:
        // show the SuccessScreen. Legacy `.approved` retained for older
        // backends.
        case .verified, .approved:
            SuccessScreen(verification: verification, onDone: onDone)
        case .rejected:
            RejectedScreen(verification: verification, onRetry: onDone)
        case .expired:
            ExpiredDocumentScreen(verification: verification, onRetry: onDone)
        case .reviewRequired:
            ManualReviewScreen(verification: verification, onDone: onDone)
        default:
            ProcessingScreen(steps: [
                ProcessingStepItem(label: "Processing verification", status: .active),
            ])
        }
    }
}
