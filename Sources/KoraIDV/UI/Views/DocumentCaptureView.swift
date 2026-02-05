import SwiftUI
import AVFoundation

/// Document capture view
struct DocumentCaptureView: View {
    let documentType: DocumentType
    let side: DocumentSide
    let theme: KoraTheme
    let onCapture: (Data) -> Void
    let onCancel: () -> Void

    @StateObject private var viewModel = DocumentCaptureViewModel()
    @State private var showManualCapture = false

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(cameraManager: viewModel.cameraManager)
                .ignoresSafeArea()

            // Overlay
            VStack {
                // Header
                headerView

                Spacer()

                // Document frame overlay
                documentFrameView

                Spacer()

                // Instructions
                instructionsView

                // Capture button
                captureButtonView
            }

            // Loading overlay
            if viewModel.isProcessing {
                processingOverlay
            }
        }
        .onAppear {
            viewModel.startCapture(onCapture: onCapture)
        }
        .onDisappear {
            viewModel.stopCapture()
        }
        .koraTheme(theme)
    }

    private var headerView: some View {
        HStack {
            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.3))
                    .clipShape(Circle())
            }

            Spacer()

            VStack(spacing: 2) {
                Text(side == .front ? "Front of Document" : "Back of Document")
                    .font(theme.headlineFont)
                    .foregroundColor(.white)

                Text(documentType.displayName)
                    .font(theme.captionFont)
                    .foregroundColor(.white.opacity(0.8))
            }

            Spacer()

            // Spacer for balance
            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.black.opacity(0.6), Color.clear]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var documentFrameView: some View {
        GeometryReader { geometry in
            let frameWidth = geometry.size.width - 40
            let frameHeight = frameWidth * 0.63 // ID card aspect ratio

            ZStack {
                // Darkened background
                Color.black.opacity(0.5)
                    .mask(
                        Rectangle()
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .frame(width: frameWidth, height: frameHeight)
                                    .blendMode(.destinationOut)
                            )
                    )

                // Document frame
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        viewModel.isDocumentDetected ? theme.successColor : Color.white,
                        lineWidth: 3
                    )
                    .frame(width: frameWidth, height: frameHeight)

                // Corner guides
                DocumentCornerGuides(
                    width: frameWidth,
                    height: frameHeight,
                    color: viewModel.isDocumentDetected ? theme.successColor : Color.white
                )
            }
        }
    }

    private var instructionsView: some View {
        VStack(spacing: 8) {
            if let feedback = viewModel.feedbackMessage {
                Text(feedback)
                    .font(theme.bodyFont)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
            } else {
                Text("Position document within the frame")
                    .font(theme.bodyFont)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
            }
        }
        .padding(.bottom, 20)
    }

    private var captureButtonView: some View {
        HStack(spacing: 40) {
            // Manual capture toggle
            Button {
                showManualCapture.toggle()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: showManualCapture ? "a.circle.fill" : "a.circle")
                        .font(.system(size: 24))
                    Text("Manual")
                        .font(theme.smallFont)
                }
                .foregroundColor(.white)
            }

            // Capture button
            Button {
                viewModel.captureManually()
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 72, height: 72)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 60, height: 60)
                }
            }
            .disabled(!showManualCapture && !viewModel.isDocumentDetected)

            // Flash toggle
            Button {
                viewModel.toggleFlash()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: viewModel.isFlashOn ? "bolt.fill" : "bolt.slash")
                        .font(.system(size: 24))
                    Text("Flash")
                        .font(theme.smallFont)
                }
                .foregroundColor(.white)
            }
        }
        .padding(.bottom, 40)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.clear, Color.black.opacity(0.6)]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))

                Text("Processing...")
                    .font(theme.bodyFont)
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - Document Corner Guides

struct DocumentCornerGuides: View {
    let width: CGFloat
    let height: CGFloat
    let color: Color

    private let cornerLength: CGFloat = 30
    private let lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            // Top left
            CornerShape(position: .topLeft, length: cornerLength)
                .stroke(color, lineWidth: lineWidth)

            // Top right
            CornerShape(position: .topRight, length: cornerLength)
                .stroke(color, lineWidth: lineWidth)

            // Bottom left
            CornerShape(position: .bottomLeft, length: cornerLength)
                .stroke(color, lineWidth: lineWidth)

            // Bottom right
            CornerShape(position: .bottomRight, length: cornerLength)
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

    func toggleFlash() {
        isFlashOn.toggle()
        // Flash toggle implementation would go here
    }
}

extension DocumentCaptureViewModel: CameraManagerDelegate {
    func cameraManager(_ manager: CameraManager, didCapturePhoto imageData: Data) {
        isCapturing = false

        // Validate quality
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
                        // Auto-capture when stable
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
