import SwiftUI
import UIKit
import AVFoundation

/// Document capture view - matches mockup screens 4-6
struct DocumentCaptureView: View {
    let documentType: DocumentType
    let side: DocumentSide
    let theme: KoraTheme
    let onCapture: (Data) -> Void
    let onCancel: () -> Void

    @StateObject private var viewModel = DocumentCaptureViewModel()
    @State private var showReview = false
    @State private var capturedImageData: Data?

    var body: some View {
        ZStack {
            if showReview, let imageData = capturedImageData {
                documentReviewView(imageData: imageData)
            } else {
                documentCaptureView
            }
        }
        .onAppear {
            viewModel.startCapture { imageData in
                capturedImageData = imageData
                showReview = true
            }
        }
        .onDisappear {
            viewModel.stopCapture()
        }
    }

    // MARK: - Capture View

    private var documentCaptureView: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(cameraManager: viewModel.cameraManager)
                .ignoresSafeArea()

            // Dark overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar (step 3/5, dark)
                StepProgressBar(total: 5, current: 3, isDark: true)

                // Header
                DarkScreenHeader(
                    title: side == .front ? "Front of ID" : "Back of ID",
                    subtitle: documentType.displayName,
                    onClose: onCancel
                )

                Spacer()

                // Document viewfinder
                documentViewfinder

                Spacer().frame(height: 16)

                // Step pills
                HStack(spacing: 8) {
                    StepPill(
                        text: "Front",
                        state: side == .front ? .active : .done
                    )
                    if documentType.requiresBack {
                        StepPill(
                            text: "Back",
                            state: side == .back ? .active : .inactive
                        )
                    }
                }

                Spacer().frame(height: 16)

                // Guidance pill
                GuidancePill(
                    text: viewModel.isDocumentDetected ? "Hold steady..." : "Scanning document...",
                    variant: viewModel.isDocumentDetected ? .ready : .scanning
                )

                Spacer().frame(height: 40)
            }

            // Processing overlay
            if viewModel.isProcessing {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .accentColor(.white)
                    Text("Processing...")
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                }
            }
        }
        .background(KoraColors.DarkBg)
    }

    private var documentViewfinder: some View {
        GeometryReader { geometry in
            let maxWidth: CGFloat = min(342, geometry.size.width - 48)
            let frameHeight = maxWidth / 1.586

            ZStack {
                // Document frame
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        viewModel.isDocumentDetected ? KoraColors.Teal : Color.white.opacity(0.3),
                        lineWidth: 2
                    )
                    .frame(width: maxWidth, height: frameHeight)

                // Corner brackets
                CornerBrackets(
                    width: maxWidth,
                    height: frameHeight,
                    color: KoraColors.Teal,
                    length: 28,
                    lineWidth: 3
                )

                // Scan line animation
                if !viewModel.isDocumentDetected {
                    ScanLineView()
                        .frame(width: maxWidth - 20, height: frameHeight - 20)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 250)
    }

    // MARK: - Review View

    private func documentReviewView(imageData: Data) -> some View {
        VStack(spacing: 0) {
            StepProgressBar(total: 5, current: 3, isDark: true)

            DarkScreenHeader(
                title: "Review your photo",
                onClose: onCancel
            )

            Spacer()

            // Review card
            VStack(spacing: 16) {
                if let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 300, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                ReviewBadge(text: "Good quality")

                // Quality checks
                HStack(spacing: 20) {
                    ReviewQualityCheck(label: "Sharp")
                    ReviewQualityCheck(label: "Well-lit")
                    ReviewQualityCheck(label: "No glare")
                }
            }

            Spacer()

            // Buttons
            HStack(spacing: 12) {
                KoraButton(
                    text: "Retake",
                    action: {
                        showReview = false
                        capturedImageData = nil
                    },
                    variant: .darkOutline
                )
                .frame(maxWidth: .infinity)

                KoraButton(
                    text: "Looks good",
                    action: { onCapture(imageData) }
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(KoraColors.DarkBg)
    }
}

// MARK: - Scan Line

private struct ScanLineView: View {
    @State private var offset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            KoraColors.Teal.opacity(0),
                            KoraColors.Teal.opacity(0.4),
                            KoraColors.Teal.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)
                .offset(y: offset)
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                        offset = geo.size.height
                    }
                }
        }
    }
}

// MARK: - Corner Brackets

struct CornerBrackets: View {
    let width: CGFloat
    let height: CGFloat
    let color: Color
    var length: CGFloat = 28
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            CornerShape(position: .topLeft, length: length)
                .stroke(color, lineWidth: lineWidth)
            CornerShape(position: .topRight, length: length)
                .stroke(color, lineWidth: lineWidth)
            CornerShape(position: .bottomLeft, length: length)
                .stroke(color, lineWidth: lineWidth)
            CornerShape(position: .bottomRight, length: length)
                .stroke(color, lineWidth: lineWidth)
        }
        .frame(width: width, height: height)
    }
}

struct CornerShape: Shape {
    enum Position {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    let position: Position
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        switch position {
        case .topLeft:
            path.move(to: CGPoint(x: 0, y: length))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: length, y: 0))
        case .topRight:
            path.move(to: CGPoint(x: rect.width - length, y: 0))
            path.addLine(to: CGPoint(x: rect.width, y: 0))
            path.addLine(to: CGPoint(x: rect.width, y: length))
        case .bottomLeft:
            path.move(to: CGPoint(x: 0, y: rect.height - length))
            path.addLine(to: CGPoint(x: 0, y: rect.height))
            path.addLine(to: CGPoint(x: length, y: rect.height))
        case .bottomRight:
            path.move(to: CGPoint(x: rect.width - length, y: rect.height))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height - length))
        }

        return path
    }
}

// MARK: - Camera Preview View

struct CameraPreviewView: UIViewRepresentable {
    let cameraManager: CameraManager

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = cameraManager.createPreviewLayer(for: view)
        view.layer.addSublayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiView.bounds
        }
    }
}

// MARK: - View Model

class DocumentCaptureViewModel: ObservableObject {
    @Published var isDocumentDetected = false
    @Published var feedbackMessage: String?
    @Published var isProcessing = false
    @Published var isFlashOn = false

    let cameraManager = CameraManager()
    private let documentScanner = DocumentScanner()
    private let qualityValidator = QualityValidator()

    private var onCapture: ((Data) -> Void)?
    private var isCapturing = false

    func startCapture(onCapture: @escaping (Data) -> Void) {
        self.onCapture = onCapture

        cameraManager.delegate = self
        cameraManager.requestPermission { [weak self] granted in
            guard granted else {
                self?.feedbackMessage = "Camera access required"
                return
            }

            self?.cameraManager.configure(position: .back) { result in
                if case .success = result {
                    self?.cameraManager.start()
                }
            }
        }
    }

    func stopCapture() {
        cameraManager.stop()
    }

    func captureManually() {
        guard !isCapturing else { return }
        isCapturing = true
        isProcessing = true
        cameraManager.capturePhoto()
    }
}

extension DocumentCaptureViewModel: CameraManagerDelegate {
    func cameraManager(_ manager: CameraManager, didCapturePhoto imageData: Data) {
        isCapturing = false

        guard let image = UIImage(data: imageData) else {
            DispatchQueue.main.async {
                self.isProcessing = false
                self.feedbackMessage = "Invalid image. Try again."
            }
            return
        }

        let validation = qualityValidator.validateDocumentImage(image)

        DispatchQueue.main.async {
            self.isProcessing = false

            if validation.isValid {
                self.onCapture?(imageData)
            } else {
                self.feedbackMessage = validation.issues.first?.message ?? "Quality check failed"
            }
        }
    }

    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer) {
        guard !isCapturing else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        documentScanner.detectDocument(in: pixelBuffer) { [weak self] result in
            DispatchQueue.main.async {
                if let result = result {
                    self?.isDocumentDetected = true

                    if result.isStable {
                        self?.feedbackMessage = "Hold steady..."
                        if self?.isCapturing == false {
                            self?.captureManually()
                        }
                    } else {
                        self?.feedbackMessage = nil
                    }
                } else {
                    self?.isDocumentDetected = false
                    self?.feedbackMessage = "Position document within the frame"
                }
            }
        }
    }

    func cameraManager(_ manager: CameraManager, didFail error: KoraError) {
        DispatchQueue.main.async {
            self.isProcessing = false
            self.feedbackMessage = error.localizedDescription
        }
    }
}
