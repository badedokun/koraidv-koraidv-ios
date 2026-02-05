import SwiftUI

/// Verification result view
struct ResultView: View {
    let verification: Verification
    let theme: KoraTheme
    let onDone: () -> Void

    @Environment(\.koraTheme) private var envTheme

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Result icon
            resultIcon

            // Title
            Text(resultTitle)
                .font(theme.titleFont)
                .foregroundColor(theme.textColor)
                .padding(.top, 24)

            // Subtitle
            Text(resultSubtitle)
                .font(theme.bodyFont)
                .foregroundColor(theme.secondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 8)

            // Details card
            if verification.status == .approved {
                detailsCard
            }

            Spacer()

            // Done button
            Button(action: onDone) {
                Text("Done")
                    .font(theme.bodyFont.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(theme.primaryColor)
                    .cornerRadius(theme.cornerRadius)
            }
            .padding(theme.padding)
        }
        .background(theme.backgroundColor)
        .koraTheme(theme)
    }

    private var resultIcon: some View {
        ZStack {
            Circle()
                .fill(resultColor.opacity(0.1))
                .frame(width: 120, height: 120)

            Circle()
                .fill(resultColor.opacity(0.2))
                .frame(width: 90, height: 90)

            Image(systemName: resultIconName)
                .font(.system(size: 48, weight: .medium))
                .foregroundColor(resultColor)
        }
    }

    private var resultColor: Color {
        switch verification.status {
        case .approved:
            return theme.successColor
        case .rejected:
            return theme.errorColor
        case .reviewRequired:
            return theme.warningColor
        case .processing:
            return theme.primaryColor
        default:
            return theme.secondaryTextColor
        }
    }

    private var resultIconName: String {
        switch verification.status {
        case .approved:
            return "checkmark.circle.fill"
        case .rejected:
            return "xmark.circle.fill"
        case .reviewRequired:
            return "exclamationmark.triangle.fill"
        case .processing:
            return "clock.fill"
        default:
            return "questionmark.circle.fill"
        }
    }

    private var resultTitle: String {
        switch verification.status {
        case .approved:
            return "Verification Successful"
        case .rejected:
            return "Verification Failed"
        case .reviewRequired:
            return "Review Required"
        case .processing:
            return "Processing"
        default:
            return "Verification Status"
        }
    }

    private var resultSubtitle: String {
        switch verification.status {
        case .approved:
            return "Your identity has been successfully verified."
        case .rejected:
            return "We couldn't verify your identity. Please try again or contact support."
        case .reviewRequired:
            return "Your verification requires manual review. We'll notify you of the result."
        case .processing:
            return "Your verification is being processed. This may take a few moments."
        default:
            return "Your verification is in progress."
        }
    }

    @ViewBuilder
    private var detailsCard: some View {
        if let docVerification = verification.documentVerification {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "person.text.rectangle")
                        .foregroundColor(theme.primaryColor)
                    Text("Verified Information")
                        .font(theme.headlineFont)
                        .foregroundColor(theme.textColor)
                }

                VStack(alignment: .leading, spacing: 12) {
                    if let firstName = docVerification.firstName,
                       let lastName = docVerification.lastName {
                        detailRow(label: "Name", value: "\(firstName) \(lastName)")
                    }

                    if let dob = docVerification.dateOfBirth {
                        detailRow(label: "Date of Birth", value: formatDate(dob))
                    }

                    if let docNumber = docVerification.documentNumber {
                        detailRow(label: "Document", value: maskDocumentNumber(docNumber))
                    }
                }
            }
            .padding()
            .background(theme.surfaceColor)
            .cornerRadius(theme.cornerRadius)
            .padding(.horizontal, theme.padding)
            .padding(.top, 32)
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(theme.captionFont)
                .foregroundColor(theme.secondaryTextColor)
                .frame(width: 100, alignment: .leading)

            Text(value)
                .font(theme.bodyFont)
                .foregroundColor(theme.textColor)
        }
    }

    private func formatDate(_ dateString: String) -> String {
        // Simple date formatting - in production would use DateFormatter
        if dateString.count == 6 {
            return MRZReader.formatDate(dateString) ?? dateString
        }
        return dateString
    }

    private func maskDocumentNumber(_ number: String) -> String {
        guard number.count > 4 else { return "****" }
        let suffix = String(number.suffix(4))
        let masked = String(repeating: "*", count: number.count - 4)
        return masked + suffix
    }
}

// MARK: - Error View

struct ErrorView: View {
    let error: KoraError
    let theme: KoraTheme
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Error icon
            ZStack {
                Circle()
                    .fill(theme.errorColor.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(theme.errorColor)
            }

            // Title
            Text("Something went wrong")
                .font(theme.titleFont)
                .foregroundColor(theme.textColor)

            // Error message
            Text(error.localizedDescription)
                .font(theme.bodyFont)
                .foregroundColor(theme.secondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Recovery suggestion
            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(theme.captionFont)
                    .foregroundColor(theme.secondaryTextColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                Button(action: onRetry) {
                    Text("Try Again")
                        .font(theme.bodyFont.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(theme.primaryColor)
                        .cornerRadius(theme.cornerRadius)
                }

                Button(action: onCancel) {
                    Text("Cancel")
                        .font(theme.bodyFont)
                        .foregroundColor(theme.secondaryTextColor)
                }
            }
            .padding(theme.padding)
        }
        .background(theme.backgroundColor)
        .koraTheme(theme)
    }
}

// MARK: - Loading View

struct LoadingView: View {
    let message: String

    @Environment(\.koraTheme) private var theme

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text(message)
                .font(theme.bodyFont)
                .foregroundColor(theme.textColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.3))
    }
}
