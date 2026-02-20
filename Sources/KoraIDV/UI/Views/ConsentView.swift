import SwiftUI

/// Consent screen view - matches mockup screen 1
struct ConsentView: View {
    let configuration: Configuration
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar (step 1/5)
            StepProgressBar(total: 5, current: 1)

            // Close button header
            HStack {
                LightCloseButton(action: onDecline)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            // Scrollable body
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Teal gradient icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    colors: [KoraColors.Teal, KoraColors.Cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 72, height: 72)

                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                    }
                    .accessibilityHidden(true)

                    Spacer().frame(height: 24)

                    // Title
                    Text(L10n.tr("koraidv.consent.title"))
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-0.5)
                        .foregroundColor(KoraColors.TextPrimary)
                        .accessibilityAddTraits(.isHeader)

                    Spacer().frame(height: 8)

                    // Description
                    Text(L10n.tr("koraidv.consent.description"))
                        .font(.system(size: 15))
                        .foregroundColor(KoraColors.TextTertiary)
                        .lineSpacing(4)

                    Spacer().frame(height: 28)

                    // Consent items
                    VStack(spacing: 16) {
                        ConsentItem(
                            iconName: "creditcard.fill",
                            iconBg: KoraColors.InfoBlueLight,
                            iconTint: KoraColors.InfoBlue,
                            title: L10n.tr("koraidv.consent.item.id.title"),
                            subtitle: L10n.tr("koraidv.consent.item.id.subtitle")
                        )
                        ConsentItem(
                            iconName: "person.fill",
                            iconBg: KoraColors.SuccessGreenLight,
                            iconTint: KoraColors.SuccessGreen,
                            title: L10n.tr("koraidv.consent.item.selfie.title"),
                            subtitle: L10n.tr("koraidv.consent.item.selfie.subtitle")
                        )
                        ConsentItem(
                            iconName: "eye.fill",
                            iconBg: KoraColors.PurpleLight,
                            iconTint: KoraColors.Purple,
                            title: L10n.tr("koraidv.consent.item.liveness.title"),
                            subtitle: L10n.tr("koraidv.consent.item.liveness.subtitle")
                        )
                    }
                }
                .padding(.horizontal, 24)
            }

            // Bottom action area
            VStack(spacing: 12) {
                KoraButton(
                    text: L10n.tr("koraidv.consent.button"),
                    action: onAccept,
                    trailingIcon: {
                        AnyView(
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        )
                    }
                )
                .accessibilityHint("Double tap to begin verification")

                Text(L10n.tr("koraidv.consent.privacy"))
                    .font(.system(size: 12))
                    .foregroundColor(KoraColors.TextMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Color.white)
    }
}

// MARK: - Consent Item

private struct ConsentItem: View {
    let iconName: String
    let iconBg: Color
    let iconTint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundColor(iconTint)
                .frame(width: 40, height: 40)
                .background(iconBg)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(KoraColors.TextPrimary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(KoraColors.TextSecondary)
                    .lineSpacing(2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KoraColors.Surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}
