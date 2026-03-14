#if canImport(CoreNFC)
import SwiftUI
import CoreNFC

/// SwiftUI view for NFC passport chip scanning
@available(iOS 14.0, *)
struct NFCPassportView: View {

    // MARK: - Properties

    let bacKeyData: BACKeyData
    let theme: KoraTheme
    let onSuccess: (NFCPassportData) -> Void
    let onSkip: () -> Void
    let onCancel: () -> Void

    @State private var readingState: NFCReadingState = .waiting
    @State private var reader: NFCPassportReader?
    @State private var passportData: NFCPassportData?
    @State private var errorMessage: String?
    @State private var pulseAnimation = false

    // MARK: - Body

    var body: some View {
        ZStack {
            theme.backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView

                Spacer()

                // Content based on state
                contentView

                Spacer()

                // Action buttons
                actionButtons
            }
            .padding(.horizontal, theme.padding)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(theme.secondaryTextColor)
                }
                Spacer()
            }
            .padding(.top, 16)

            Text("Read Passport Chip")
                .font(theme.titleFont)
                .foregroundColor(theme.textColor)

            Text("This adds an extra layer of security by reading the encrypted chip in your passport.")
                .font(theme.captionFont)
                .foregroundColor(theme.secondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch readingState {
        case .waiting:
            waitingView
        case .authenticating:
            progressView(title: "Authenticating...", detail: "Verifying passport credentials", progress: 0.2)
        case .reading(let progress):
            progressView(title: "Reading chip data...", detail: "Keep your phone steady", progress: progress)
        case .verifying:
            progressView(title: "Verifying data...", detail: "Checking passport authenticity", progress: 0.9)
        case .success:
            successView
        case .error(let message):
            errorView(message: message)
        }
    }

    // MARK: - Waiting View

    private var waitingView: some View {
        VStack(spacing: 24) {
            // NFC icon with pulse animation
            ZStack {
                // Pulse rings
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(theme.primaryColor.opacity(pulseAnimation ? 0.0 : 0.3), lineWidth: 2)
                        .frame(width: CGFloat(100 + index * 40), height: CGFloat(100 + index * 40))
                        .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                        .animation(
                            Animation.easeInOut(duration: 2.0)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.3),
                            value: pulseAnimation
                        )
                }

                // NFC icon
                Image(systemName: "wave.3.right")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(theme.primaryColor)
                    .frame(width: 80, height: 80)
                    .background(
                        Circle()
                            .fill(theme.primaryColor.opacity(0.1))
                    )
            }
            .frame(height: 200)
            .onAppear { pulseAnimation = true }

            VStack(spacing: 12) {
                Text("Hold your phone to the passport")
                    .font(theme.headlineFont)
                    .foregroundColor(theme.textColor)

                Text("Place the top of your iPhone on the data page of your passport (the page with your photo).")
                    .font(theme.captionFont)
                    .foregroundColor(theme.secondaryTextColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            // Passport illustration
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 20))
                    .foregroundColor(theme.primaryColor)

                Image(systemName: "arrow.right")
                    .font(.system(size: 14))
                    .foregroundColor(theme.secondaryTextColor)

                Image(systemName: "iphone")
                    .font(.system(size: 20))
                    .foregroundColor(theme.primaryColor)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .background(
                RoundedRectangle(cornerRadius: theme.cornerRadius / 2)
                    .fill(theme.surfaceColor)
            )
        }
    }

    // MARK: - Progress View

    private func progressView(title: String, detail: String, progress: Double) -> some View {
        VStack(spacing: 24) {
            // Animated circle progress
            ZStack {
                Circle()
                    .stroke(theme.surfaceColor, lineWidth: 6)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(
                        theme.primaryColor,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: progress)

                Image(systemName: "wave.3.right")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(theme.primaryColor)
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(theme.headlineFont)
                    .foregroundColor(theme.textColor)

                Text(detail)
                    .font(theme.captionFont)
                    .foregroundColor(theme.secondaryTextColor)
            }

            // Warning to keep phone steady
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(theme.warningColor)

                Text("Do not move your phone")
                    .font(theme.smallFont)
                    .foregroundColor(theme.warningColor)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.warningColor.opacity(0.1))
            )
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(theme.successColor)

            VStack(spacing: 8) {
                Text("Chip Read Successfully")
                    .font(theme.headlineFont)
                    .foregroundColor(theme.textColor)

                if let data = passportData {
                    VStack(spacing: 4) {
                        if data.passiveAuthPassed {
                            Label("Data verified", systemImage: "checkmark.shield.fill")
                                .font(theme.captionFont)
                                .foregroundColor(theme.successColor)
                        }

                        if data.faceImageData != nil {
                            Label("Face image extracted", systemImage: "person.crop.circle.fill")
                                .font(theme.captionFont)
                                .foregroundColor(theme.successColor)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(theme.errorColor)

            VStack(spacing: 8) {
                Text("Reading Failed")
                    .font(theme.headlineFont)
                    .foregroundColor(theme.textColor)

                Text(message)
                    .font(theme.captionFont)
                    .foregroundColor(theme.secondaryTextColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            switch readingState {
            case .waiting:
                // Start reading button
                Button(action: startReading) {
                    HStack {
                        Image(systemName: "wave.3.right")
                        Text("Start Reading")
                    }
                    .font(theme.bodyFont)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: theme.cornerRadius)
                            .fill(theme.primaryColor)
                    )
                }

                // Skip button
                Button(action: onSkip) {
                    Text("Skip this step")
                        .font(theme.captionFont)
                        .foregroundColor(theme.secondaryTextColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }

            case .success:
                // Continue button
                Button(action: {
                    if let data = passportData {
                        onSuccess(data)
                    }
                }) {
                    Text("Continue")
                        .font(theme.bodyFont)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: theme.cornerRadius)
                                .fill(theme.primaryColor)
                        )
                }

            case .error:
                // Retry button
                Button(action: {
                    readingState = .waiting
                    errorMessage = nil
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Try Again")
                    }
                    .font(theme.bodyFont)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: theme.cornerRadius)
                            .fill(theme.primaryColor)
                    )
                }

                // Skip button
                Button(action: onSkip) {
                    Text("Skip this step")
                        .font(theme.captionFont)
                        .foregroundColor(theme.secondaryTextColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }

            default:
                // Reading in progress — no buttons
                EmptyView()
            }
        }
        .padding(.bottom, 32)
    }

    // MARK: - Actions

    private func startReading() {
        guard NFCTagReaderSession.readingAvailable else {
            readingState = .error("NFC is not available on this device.")
            return
        }

        let passportReader = NFCPassportReader(bacKeyData: bacKeyData)
        self.reader = passportReader

        readingState = .authenticating

        passportReader.startReading { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    self.passportData = data
                    self.readingState = .success

                case .failure(let error):
                    switch error {
                    case .userCancelled:
                        self.readingState = .waiting
                    default:
                        self.readingState = .error(error.localizedDescription)
                    }
                }
            }
        }
    }
}

#endif // canImport(CoreNFC)
