import Foundation
import Vision
import AVFoundation

/// Face tracking result
struct FaceTrackingResult {
    let face: DetectedFace
    let isStable: Bool
    let framesSinceLost: Int
}

/// Face tracker delegate
protocol FaceTrackerDelegate: AnyObject {
    func faceTracker(_ tracker: FaceTracker, didUpdate result: FaceTrackingResult)
    func faceTrackerDidLoseFace(_ tracker: FaceTracker)
}

/// Face Tracker for continuous face tracking
final class FaceTracker {

    // MARK: - Properties

    weak var delegate: FaceTrackerDelegate?

    private let faceDetector = FaceDetector()
    private var lastFace: DetectedFace?
    private var stabilityHistory: [DetectedFace] = []
    private var framesSinceLost = 0

    /// Number of frames to consider for stability
    private let stabilityWindowSize = 5

    /// Maximum movement threshold for stability (normalized)
    private let stabilityThreshold: CGFloat = 0.02

    /// Maximum frames without face before considered lost
    private let maxFramesWithoutFace = 10

    /// Whether tracking is active
    private(set) var isTracking = false

    // MARK: - Public Methods

    /// Start tracking
    func startTracking() {
        isTracking = true
        reset()
    }

    /// Stop tracking
    func stopTracking() {
        isTracking = false
        reset()
    }

    /// Process a video frame
    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isTracking else { return }

        faceDetector.detectFaces(in: sampleBuffer) { [weak self] result in
            guard let self = self else { return }

            if let faceResult = result, let face = faceResult.faces.first {
                self.handleFaceDetected(face)
            } else {
                self.handleFaceLost()
            }
        }
    }

    /// Process an image
    func processImage(_ image: UIImage) {
        guard isTracking else { return }

        faceDetector.detectFaces(in: image) { [weak self] result in
            guard let self = self else { return }

            if let faceResult = result, let face = faceResult.faces.first {
                self.handleFaceDetected(face)
            } else {
                self.handleFaceLost()
            }
        }
    }

    /// Reset tracker state
    func reset() {
        lastFace = nil
        stabilityHistory = []
        framesSinceLost = 0
    }

    // MARK: - Private Methods

    private func handleFaceDetected(_ face: DetectedFace) {
        framesSinceLost = 0
        lastFace = face

        // Add to stability history
        stabilityHistory.append(face)
        if stabilityHistory.count > stabilityWindowSize {
            stabilityHistory.removeFirst()
        }

        // Check stability
        let isStable = checkStability()

        let result = FaceTrackingResult(
            face: face,
            isStable: isStable,
            framesSinceLost: 0
        )

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.faceTracker(self, didUpdate: result)
        }
    }

    private func handleFaceLost() {
        framesSinceLost += 1

        if framesSinceLost >= maxFramesWithoutFace {
            stabilityHistory = []
            lastFace = nil

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.faceTrackerDidLoseFace(self)
            }
        }
    }

    private func checkStability() -> Bool {
        guard stabilityHistory.count >= stabilityWindowSize else {
            return false
        }

        // Check if face position is stable
        let recentFaces = stabilityHistory.suffix(stabilityWindowSize)

        for i in 1..<recentFaces.count {
            let prev = recentFaces[recentFaces.index(recentFaces.startIndex, offsetBy: i - 1)]
            let curr = recentFaces[recentFaces.index(recentFaces.startIndex, offsetBy: i)]

            let centerDiff = centerDistance(prev.boundingBox, curr.boundingBox)
            let sizeDiff = sizeDistance(prev.boundingBox, curr.boundingBox)

            if centerDiff > stabilityThreshold || sizeDiff > stabilityThreshold {
                return false
            }
        }

        return true
    }

    private func centerDistance(_ r1: CGRect, _ r2: CGRect) -> CGFloat {
        let c1 = CGPoint(x: r1.midX, y: r1.midY)
        let c2 = CGPoint(x: r2.midX, y: r2.midY)

        let dx = c1.x - c2.x
        let dy = c1.y - c2.y

        return sqrt(dx * dx + dy * dy)
    }

    private func sizeDistance(_ r1: CGRect, _ r2: CGRect) -> CGFloat {
        let w = abs(r1.width - r2.width)
        let h = abs(r1.height - r2.height)

        return max(w, h)
    }
}

// MARK: - Face Position Analysis

extension FaceTracker {

    /// Analyze face position relative to a guide frame
    func analyzeFacePosition(
        face: DetectedFace,
        guideFrame: CGRect,
        imageSize: CGSize
    ) -> FacePositionAnalysis {
        // Normalize face bounding box
        let normalizedFace = CGRect(
            x: face.boundingBox.origin.x / imageSize.width,
            y: face.boundingBox.origin.y / imageSize.height,
            width: face.boundingBox.width / imageSize.width,
            height: face.boundingBox.height / imageSize.height
        )

        // Calculate center offset
        let faceCenterX = normalizedFace.midX
        let faceCenterY = normalizedFace.midY
        let guideCenterX = guideFrame.midX
        let guideCenterY = guideFrame.midY

        let horizontalOffset = faceCenterX - guideCenterX
        let verticalOffset = faceCenterY - guideCenterY

        // Calculate size ratio
        let sizeRatio = normalizedFace.width / guideFrame.width

        // Determine guidance
        var guidance: [FacePositionGuidance] = []

        if abs(horizontalOffset) > 0.1 {
            guidance.append(horizontalOffset > 0 ? .moveLeft : .moveRight)
        }

        if abs(verticalOffset) > 0.1 {
            guidance.append(verticalOffset > 0 ? .moveUp : .moveDown)
        }

        if sizeRatio < 0.7 {
            guidance.append(.moveCloser)
        } else if sizeRatio > 1.3 {
            guidance.append(.moveBack)
        }

        // Check if within guide
        let isWithinGuide = abs(horizontalOffset) <= 0.15 &&
                           abs(verticalOffset) <= 0.15 &&
                           sizeRatio >= 0.7 &&
                           sizeRatio <= 1.3

        return FacePositionAnalysis(
            horizontalOffset: horizontalOffset,
            verticalOffset: verticalOffset,
            sizeRatio: sizeRatio,
            isWithinGuide: isWithinGuide,
            guidance: guidance
        )
    }
}

/// Face position analysis result
struct FacePositionAnalysis {
    let horizontalOffset: CGFloat
    let verticalOffset: CGFloat
    let sizeRatio: CGFloat
    let isWithinGuide: Bool
    let guidance: [FacePositionGuidance]
}

/// Face position guidance
enum FacePositionGuidance {
    case moveLeft
    case moveRight
    case moveUp
    case moveDown
    case moveCloser
    case moveBack
    case holdStill

    var instruction: String {
        switch self {
        case .moveLeft: return "Move left"
        case .moveRight: return "Move right"
        case .moveUp: return "Move up"
        case .moveDown: return "Move down"
        case .moveCloser: return "Move closer"
        case .moveBack: return "Move back"
        case .holdStill: return "Hold still"
        }
    }
}
