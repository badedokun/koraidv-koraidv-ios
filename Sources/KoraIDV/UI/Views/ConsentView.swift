import SwiftUI

/// Consent screen view
struct ConsentView: View {
    let configuration: Configuration
    let onAccept: () -> Void
    let onDecline: () -> Void

    @Environment(\.koraTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introSection
                    dataCollectionSection
                    privacySection
                }
                .padding(theme.padding)
            }

            // Footer with buttons
            footerSection
        }
        .background(theme.backgroundColor)
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 48))
                .foregroundColor(theme.primaryColor)

            Text("Identity Verification")
                .font(theme.titleFont)
                .foregroundColor(theme.textColor)

            Text("We need to verify your identity to continue")
                .font(theme.bodyFont)
                .foregroundColor(theme.secondaryTextColor)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(theme.surfaceColor)
    }

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What you'll need")
                .font(theme.headlineFont)
                .foregroundColor(theme.textColor)

            VStack(alignment: .leading, spacing: 8) {
                checklistItem(icon: "doc.text.fill", text: "A valid government-issued ID")
                checklistItem(icon: "camera.fill", text: "A device with a camera")
                checklistItem(icon: "lightbulb.fill", text: "Good lighting conditions")
            }
        }
    }

    private var dataCollectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Information we collect")
                .font(theme.headlineFont)
                .foregroundColor(theme.textColor)

            VStack(alignment: .leading, spacing: 8) {
                bulletItem("Photos of your identity document")
                bulletItem("A selfie for face matching")
                bulletItem("Liveness check to confirm you're a real person")
            }
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your privacy")
                .font(theme.headlineFont)
                .foregroundColor(theme.textColor)

            Text("Your data is encrypted and stored securely. We only use your information for identity verification purposes and in accordance with our privacy policy.")
                .font(theme.bodyFont)
                .foregroundColor(theme.secondaryTextColor)
        }
    }

    private var footerSection: some View {
        VStack(spacing: 12) {
            Button {
                onAccept()
            } label: {
                Text("Accept & Continue")
                    .font(theme.bodyFont.weight(Font.Weight.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(theme.primaryColor)
                    .cornerRadius(theme.cornerRadius)
            }

            Button {
                onDecline()
            } label: {
                Text("Decline")
                    .font(theme.bodyFont)
                    .foregroundColor(theme.secondaryTextColor)
            }
            .padding(.bottom, 8)
        }
        .padding(theme.padding)
        .background(theme.backgroundColor)
    }

    private func checklistItem(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(theme.primaryColor)
                .frame(width: 32)

            Text(text)
                .font(theme.bodyFont)
                .foregroundColor(theme.textColor)
        }
    }

    private func bulletItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(theme.primaryColor)
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            Text(text)
                .font(theme.bodyFont)
                .foregroundColor(theme.secondaryTextColor)
        }
    }
}
