import SwiftUI

/// Instruction screen shown between front and back document capture
struct FlipDocumentView: View {
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            StepProgressBar(total: 5, current: 3, isDark: true)

            DarkScreenHeader(
                title: L10n.tr("koraidv.flip.title"),
                onClose: onCancel
            )

            Spacer()

            VStack(spacing: 32) {
                // Flip icon
                ZStack {
                    Circle()
                        .fill(KoraColors.Teal.opacity(0.15))
                        .frame(width: 120, height: 120)

                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundColor(KoraColors.Teal)
                }

                VStack(spacing: 12) {
                    Text(L10n.tr("koraidv.flip.heading"))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text(L10n.tr("koraidv.flip.description"))
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .frame(maxWidth: 280)
                }

                // Step pills
                HStack(spacing: 8) {
                    StepPill(
                        text: L10n.tr("koraidv.capture.step.front"),
                        state: .done
                    )
                    StepPill(
                        text: L10n.tr("koraidv.capture.step.back"),
                        state: .active
                    )
                }
            }

            Spacer()

            // Continue button
            KoraButton(
                text: L10n.tr("koraidv.flip.continue"),
                action: onContinue
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(KoraColors.DarkBg)
    }
}
