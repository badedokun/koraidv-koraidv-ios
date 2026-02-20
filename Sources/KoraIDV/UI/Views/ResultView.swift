import SwiftUI

// MARK: - Processing Screen (Screen 10)

struct ProcessingScreen: View {
    let steps: [ProcessingStepItem]

    @State private var outerRotation: Double = 0
    @State private var innerRotation: Double = 0
    @State private var coreRotation: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Spinning rings
            ZStack {
                // Outer ring
                Circle()
                    .trim(from: 0.2, to: 0.8)
                    .stroke(KoraColors.Teal.opacity(0.3), lineWidth: 3)
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(outerRotation))

                // Inner ring
                Circle()
                    .trim(from: 0.3, to: 0.7)
                    .stroke(KoraColors.Teal.opacity(0.5), lineWidth: 3)
                    .frame(width: 90, height: 90)
                    .rotationEffect(.degrees(innerRotation))

                // Core ring
                Circle()
                    .trim(from: 0.1, to: 0.9)
                    .stroke(KoraColors.Teal, lineWidth: 3)
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(coreRotation))

                // Shield icon
                Image(systemName: "shield.checkered")
                    .font(.system(size: 24))
                    .foregroundColor(KoraColors.Teal)
            }
            .accessibilityHidden(true)
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    outerRotation = 360
                }
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    innerRotation = -360
                }
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    coreRotation = 360
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
                                ProgressView()
                                    .accentColor(KoraColors.Teal)
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
        .background(KoraColors.DarkBg)
    }
}

struct ProcessingStepItem {
    let label: String
    let status: ProcessingStepStatus
}

enum ProcessingStepStatus {
    case done, active, pending
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
        [
            ScoreMetric(label: L10n.tr("koraidv.score.liveness"), score: scores.liveness, iconName: "eye.fill", status: scores.liveness >= 70 ? .pass : .fail),
            ScoreMetric(label: L10n.tr("koraidv.score.name_match"), score: scores.nameMatch, iconName: "checkmark.circle.fill", status: scores.nameMatch >= 70 ? .pass : .fail),
            ScoreMetric(label: L10n.tr("koraidv.score.document_quality"), score: scores.documentQuality, iconName: "creditcard.fill", status: scores.documentQuality >= 70 ? .pass : .fail),
            ScoreMetric(label: L10n.tr("koraidv.score.selfie_match"), score: scores.selfieMatch, iconName: "person.fill", status: scores.selfieMatch >= 70 ? .pass : .fail),
        ]
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
        [
            ScoreMetric(
                label: L10n.tr("koraidv.score.liveness"), score: scores.liveness, iconName: "eye.fill",
                status: scores.liveness >= 70 ? .pass : .fail,
                errorMessage: scores.liveness < 70 ? L10n.tr("koraidv.score.error.liveness") : nil
            ),
            ScoreMetric(
                label: L10n.tr("koraidv.score.name_match"), score: scores.nameMatch, iconName: "checkmark.circle.fill",
                status: scores.nameMatch >= 70 ? .pass : .fail,
                errorMessage: scores.nameMatch < 70 ? L10n.tr("koraidv.score.error.name") : nil
            ),
            ScoreMetric(
                label: L10n.tr("koraidv.score.document_quality"), score: scores.documentQuality, iconName: "creditcard.fill",
                status: scores.documentQuality >= 70 ? .pass : .fail,
                errorMessage: scores.documentQuality < 70 ? L10n.tr("koraidv.score.error.document") : nil
            ),
            ScoreMetric(
                label: L10n.tr("koraidv.score.selfie_match"), score: scores.selfieMatch, iconName: "person.fill",
                status: scores.selfieMatch >= 70 ? .pass : .fail,
                errorMessage: scores.selfieMatch < 70 ? L10n.tr("koraidv.score.error.selfie") : nil
            ),
        ]
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
        let selfieStatus: MetricStatus = scores.selfieMatch >= 70 ? .pass : (scores.selfieMatch >= 50 ? .borderline : .fail)
        return [
            ScoreMetric(label: L10n.tr("koraidv.score.liveness"), score: scores.liveness, iconName: "eye.fill", status: scores.liveness >= 70 ? .pass : .borderline),
            ScoreMetric(label: L10n.tr("koraidv.score.name_match"), score: scores.nameMatch, iconName: "checkmark.circle.fill", status: scores.nameMatch >= 70 ? .pass : .borderline),
            ScoreMetric(label: L10n.tr("koraidv.score.document_quality"), score: scores.documentQuality, iconName: "creditcard.fill", status: scores.documentQuality >= 70 ? .pass : .borderline),
            ScoreMetric(label: L10n.tr("koraidv.score.selfie_match"), score: scores.selfieMatch, iconName: selfieStatus == .borderline ? "info.circle.fill" : "person.fill", status: selfieStatus),
        ]
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

// MARK: - Backward Compatibility

struct ResultView: View {
    let verification: Verification
    let theme: KoraTheme
    let onDone: () -> Void

    var body: some View {
        switch verification.status {
        case .approved:
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
