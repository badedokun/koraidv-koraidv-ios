import Foundation
import UIKit
import CoreMedia
import CoreVideo
import MLKitTextRecognition
import MLKitVision

/// Document detection result.
///
/// Wire-compatible with v1.8.x consumers — no field changes since the
/// CameraManager / DocumentCaptureView pipeline depends on this shape.
/// Internal implementation in v1.9.0 switched from Apple Vision's
/// `VNDetectDocumentSegmentationRequest` to Google ML Kit's text
/// recognition for behavioral parity with koraidv-android.
struct DocumentDetectionResult {
    let confidence: Float
    let corners: [CGPoint]
    let isStable: Bool
    /// User-facing guidance when the document is detected but its framing
    /// would produce a poor capture. `nil` when framing is acceptable.
    /// Caller (DocumentCaptureView) suppresses auto-capture firing when
    /// this is non-nil regardless of stability.
    let qualityGuidance: String?
    /// Bounding box in pixel coordinates (analysis image space).
    let boundingBox: CGRect
}

/// Document scanner using Google ML Kit Text Recognition.
///
/// **v1.9.0 — architectural reset.** Previously this used Apple Vision's
/// `VNDetectDocumentSegmentationRequest` (geometric document edge
/// segmentation), but its output varied dramatically across iPhone
/// device generations (12 vs 13 Pro vs 15 Pro Max — different sensors,
/// different ISPs, different segmentation behavior). Five rounds of
/// threshold tuning (v1.8.6-rc1 through rc5, 2026-06-01 to 2026-06-04)
/// could not find a single set of confidence + coverage + stability
/// thresholds that worked across the iOS device fleet. Meanwhile
/// koraidv-android using ML Kit text recognition has been shipping
/// cleanly across the Android fleet with no per-device tuning.
///
/// Rather than continue iterating on the wrong abstraction, v1.9.0
/// switches iOS to the same detection library Android uses. The Swift
/// code below is a line-by-line port of
/// `koraidv-android/koraidv/src/main/kotlin/com/koraidv/sdk/capture/DocumentScanner.kt`
/// with the same constants (`stabilityTolerance = 0.10`,
/// `stabilityThreshold = 1`, `noDetectionThreshold = 3`,
/// `minCoverage = 0.35`, `maxCoverage = 0.85`, 10% bbox padding). Same
/// thresholds work because the underlying detector is now the same.
final class DocumentScanner {

    // MARK: - State

    /// Most recent corners (analysis-image pixel coords) from a frame
    /// that passed the text-block detection. Used by checkStability to
    /// compute frame-to-frame corner displacement.
    private var lastCorners: [CGPoint]?

    /// Consecutive stable frame count. When `>= stabilityThreshold` the
    /// detection is considered stable and auto-capture may fire.
    private var stabilityCounter = 0

    /// Consecutive no-detection frame count. When `>= noDetectionThreshold`
    /// the cached `lastDetectionResult` is cleared so the next valid
    /// detection starts a fresh burst.
    private var noDetectionCounter = 0

    /// Most recent successful detection result. Returned to callers
    /// (synchronously, as a cached value) while ML Kit processes new
    /// frames asynchronously. Cleared when noDetectionCounter exceeds
    /// threshold OR resetStability() is called.
    private var lastDetectionResult: DocumentDetectionResult?

    /// Set to true while ML Kit is processing a frame; subsequent frames
    /// short-circuit and return the cached result rather than queueing.
    /// Prevents recognition latency from amplifying frame rate.
    private var isAnalyzing = false

    // MARK: - Thresholds (mirror koraidv-android DocumentScanner.kt)

    /// 3 consecutive missed frames tolerated before resetting state.
    /// Matches Android. Without this, transient ML Kit dropouts on busy
    /// backgrounds would reset the caller's firstDetectedTime and
    /// prevent the 3-second force-capture deadline from elapsing.
    private let noDetectionThreshold = 3

    /// **v1.9.0-rc6.7** — raised from 1 to 3 consecutive stable frames.
    /// Stratum Remit 2026-06-07 cross-doc test: passport capture fired
    /// before the document was fully framed because a single stable
    /// frame was enough to satisfy the trigger. With 3 consecutive
    /// stable frames (~100ms at 30fps), the user has to actually
    /// settle the document into position rather than just briefly
    /// passing through a stable detection. Android still uses 1
    /// because its viewfinder + countdown UI gives more pre-capture
    /// time; iOS doesn't, so a stricter stability requirement
    /// substitutes for the missing dwell.
    private let stabilityThreshold = 3

    /// 10% relative corner displacement tolerance per axis. Matches
    /// Android. Real-world handheld jitter on a phone moves corners
    /// by ~5–10% per frame; tighter thresholds (we tried 0.02 absolute
    /// in v1.8.x) never converge.
    private let stabilityTolerance: CGFloat = 0.10

    /// Coverage thresholds: text-bbox area / frame area.
    ///
    /// **v1.9.0-rc3 calibration note.** Android uses `minCoverage = 0.35`.
    /// iOS uses `0.18`. This is the one threshold that *intentionally*
    /// diverges from Android — and it's the right divergence, because
    /// the threshold is hardware-coupled to camera field-of-view.
    /// iPhone 13 Pro's main wide-angle has a narrower FOV than typical
    /// Android flagships, so the same physical document fills
    /// proportionally less of the iOS viewfinder. Stratum Remit's
    /// rc2 device test (2026-06-06, 985 captured frames at normal
    /// hand-distance framing) measured text-coverage clustered at
    /// 0.20–0.25 with maxima around 0.30 — never reaching the 0.35
    /// Android threshold. The auto-capture deadline never elapsed,
    /// "Move closer" guidance persisted indefinitely.
    ///
    /// Twin behavior between iOS and Android is preserved at the
    /// *output* layer (auto-capture fires at appropriate framing on
    /// both platforms) by tuning *input* calibration for hardware
    /// difference — same pattern as differing ISO/exposure settings
    /// producing equivalent images on different sensors. The text-block
    /// methodology is identical to Android's `DocumentScanner.kt`; only
    /// this FOV-calibration constant is iOS-specific.
    ///
    /// The risk QA flagged — lower threshold lets through smaller
    /// documents that produce worse OCR — is mitigated by the backend's
    /// document-quality scoring (completeness / resolution / sharpness
    /// per `quality_engine`). The SDK's job is "is there a document";
    /// the backend's job is "is what was captured usable." Don't
    /// re-add SDK-side quality gating just because the threshold
    /// dropped — let the backend reject and trigger retake.
    ///
    /// Upper bound (0.85) stays at Android parity — "clipped at frame
    /// edges" is a geometric concept, not FOV-dependent.
    private let minCoverage: CGFloat = 0.18
    private let maxCoverage: CGFloat = 0.85

    // MARK: - Recognizer

    private let textRecognizer = TextRecognizer.textRecognizer(
        options: TextRecognizerOptions()
    )

    // MARK: - Detection

    /// Detect document presence in a video sample buffer.
    ///
    /// Async via completion handler. While ML Kit is processing a frame,
    /// subsequent calls receive the cached `lastDetectionResult`
    /// synchronously (or nil if no detection yet) — same pattern as
    /// Android's `detectDocument(imageProxy)` which returns
    /// `lastDetectionResult` while ML Kit processes in the background.
    ///
    /// Caller: `DocumentCaptureViewModel.cameraManager(_:didOutput:)`.
    /// Caller orientation: video output is configured for `.portrait`
    /// connection orientation, so the sample buffer's pixel buffer
    /// dimensions are already in portrait coordinate space at the
    /// `.high` session preset (1080 wide × 1920 tall).
    func detectDocument(in sampleBuffer: CMSampleBuffer, completion: @escaping (DocumentDetectionResult?) -> Void) {
        if isAnalyzing {
            // Frame dropped — return cached result so caller's burst stays alive.
            completion(lastDetectionResult)
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            completion(lastDetectionResult)
            return
        }

        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        let visionImage = VisionImage(buffer: sampleBuffer)
        // **v1.9.0-rc2 fix.** CameraManager configures the video output
        // connection with `videoOrientation = .portrait`, which causes
        // AVFoundation to physically rotate the sample buffer to portrait
        // before delivery. The pixel buffer arrives at 1080w × 1920h,
        // already display-oriented. Setting `.right` here in rc1 was
        // double-rotating: ML Kit rotated the already-portrait buffer
        // 90° more, processed a landscape image, and returned text
        // frames in 1920×1080 coords. Clamping those against our
        // width=1080/height=1920 then truncated the bbox, collapsing
        // coverage well below the 0.35 threshold and triggering false
        // "Move closer" guidance at framing where Android auto-captures
        // cleanly. The buffer is already upright — use `.up`. Reference
        // to AVFoundation rotation behavior in CameraManager.swift:297.
        visionImage.orientation = .up

        isAnalyzing = true

        textRecognizer.process(visionImage) { [weak self] result, error in
            guard let self = self else { return }
            defer { self.isAnalyzing = false }

            if let error = error {
                KoraIDV.log("DocumentScanner exit: ml-kit-error — \(error.localizedDescription)")
                completion(self.lastDetectionResult)
                return
            }

            guard let text = result else {
                KoraIDV.log("DocumentScanner exit: no-result")
                completion(self.lastDetectionResult)
                return
            }

            let blockCount = text.blocks.count

            if blockCount >= 1 {
                self.noDetectionCounter = 0

                // **v1.9.1** — spatial-outlier filter on text blocks.
                //
                // Before aggregating block frames into a single bbox, drop
                // outlier blocks whose centroid is far from the dense
                // document cluster. Without this, ML Kit's noisy text
                // recognition on patterned backgrounds (Olabode iPhone 12
                // 2026-06-08: NJ DL on a stained tablecloth) intermittently
                // detected 1-2 spurious text blocks in the background and
                // the naive minX/minY/maxX/maxY union stretched the bbox
                // from the actual document to those false positives —
                // producing a near-full-frame bbox and effectively no
                // crop in the review screen. Real documents have many
                // tightly-clustered text blocks; spurious detections are
                // isolated. Compute the median block centroid as the
                // cluster anchor and reject blocks whose distance to the
                // anchor exceeds 1.5x the median distance, with a 10%
                // frame-dimension floor on the cutoff to avoid being too
                // aggressive on documents with naturally spread text
                // (passport biopages).
                let allFrames = text.blocks.map { $0.frame }
                let effectiveFrames: [CGRect]
                if allFrames.count >= 3 {
                    let centroids = allFrames.map { CGPoint(x: $0.midX, y: $0.midY) }
                    let sortedXs = centroids.map { $0.x }.sorted()
                    let sortedYs = centroids.map { $0.y }.sorted()
                    let anchor = CGPoint(x: sortedXs[sortedXs.count / 2],
                                         y: sortedYs[sortedYs.count / 2])
                    let distances = centroids.map { hypot($0.x - anchor.x, $0.y - anchor.y) }
                    let sortedDistances = distances.sorted()
                    let medianDistance = sortedDistances[sortedDistances.count / 2]
                    let cutoff = max(medianDistance * 1.5, min(width, height) * 0.1)
                    let kept = zip(allFrames, distances).filter { $1 <= cutoff }.map { $0.0 }
                    effectiveFrames = kept.isEmpty ? allFrames : kept
                } else {
                    // 1-2 blocks: nothing to cluster against. Use as-is.
                    effectiveFrames = allFrames
                }

                // Aggregate kept frames into a single bbox.
                // minX/minY/maxX/maxY across the cluster, then 10% padding.
                var minX = width
                var minY = height
                var maxX: CGFloat = 0
                var maxY: CGFloat = 0

                for frame in effectiveFrames {
                    minX = min(minX, frame.minX)
                    minY = min(minY, frame.minY)
                    maxX = max(maxX, frame.maxX)
                    maxY = max(maxY, frame.maxY)
                }

                // Snapshot raw bbox for diagnostic logging — QA needs to
                // see the unpadded text-block union to verify the
                // coverage divergence root-caused in rc1.
                let rawMinX = minX
                let rawMinY = minY
                let rawMaxX = maxX
                let rawMaxY = maxY
                let rawArea = (rawMaxX - rawMinX) * (rawMaxY - rawMinY)

                // 10% padding (same as Android — earlier branchless
                // single-block logic that synthesized a 70%-wide centered
                // box was removed there; we don't reintroduce it).
                let padX = (maxX - minX) * 0.10
                let padY = (maxY - minY) * 0.10
                minX = max(0, minX - padX)
                minY = max(0, minY - padY)
                maxX = min(width, maxX + padX)
                maxY = min(height, maxY + padY)

                let corners: [CGPoint] = [
                    CGPoint(x: minX, y: minY), // top-left
                    CGPoint(x: maxX, y: minY), // top-right
                    CGPoint(x: maxX, y: maxY), // bottom-right
                    CGPoint(x: minX, y: maxY), // bottom-left
                ]
                let boundingBox = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

                let isStable = self.checkStability(corners: corners)

                // Coverage = text bbox area / frame area.
                let textArea = (maxX - minX) * (maxY - minY)
                let imageArea = width * height
                let coverage = imageArea > 0 ? textArea / imageArea : 0

                // Confidence:
                //   single block fallback → fixed 0.55
                //   multi block → 0.5 + min(coverage, 0.5), capped at 0.99
                let confidence: Float
                if blockCount == 1 {
                    confidence = 0.55
                } else {
                    let scaled = min(0.99, 0.5 + min(Double(coverage), 0.5))
                    confidence = Float(scaled)
                }

                // Coverage + edge guidance — caller suppresses
                // auto-capture when non-nil.
                //
                // **v1.9.0-rc6.7** — added edge-detection guidance.
                // Stratum Remit 2026-06-07: "when the doc is completely
                // inside the frame, the message still says move closer
                // to the doc, which is the point the camera was
                // supposed to snap." Root cause: coverage is text-bbox
                // area / frame area. A document can be fully framed
                // but have small text relative to the frame (passport
                // biopage, DL back) so coverage stays below threshold,
                // pushing the user to "move closer" — which then makes
                // them clip the edges. Edge-touch is a separate signal:
                // if the text bbox touches a frame edge (within 2%
                // margin), the document extends past that edge —
                // user should pull back, not push closer. This breaks
                // the loop.
                let edgePad: CGFloat = max(width, height) * 0.02
                let touchesEdge = rawMinX < edgePad ||
                                  rawMinY < edgePad ||
                                  rawMaxX > (width - edgePad) ||
                                  rawMaxY > (height - edgePad)
                let qualityGuidance: String?
                if touchesEdge {
                    qualityGuidance = "Fit the entire document inside the frame"
                } else if coverage < self.minCoverage {
                    qualityGuidance = "Move closer to the document"
                } else if coverage > self.maxCoverage {
                    qualityGuidance = "Move further from the document"
                } else {
                    qualityGuidance = nil
                }

                let detection = DocumentDetectionResult(
                    confidence: confidence,
                    corners: corners,
                    isStable: isStable,
                    qualityGuidance: qualityGuidance,
                    boundingBox: boundingBox
                )

                // rc2 diagnostic: emit full coverage chain so QA can
                // cross-check against Android logs at the same framing.
                // Order: frame dims → raw bbox dims/area → padded bbox
                // dims/area → coverage → guidance decision.
                KoraIDV.log(String(
                    format: "DocumentScanner coverage: frame=%.0fx%.0f rawBbox=%.0fx%.0f (area=%.0f) paddedBbox=%.0fx%.0f (area=%.0f) frameArea=%.0f coverage=%.4f",
                    Float(width), Float(height),
                    Float(rawMaxX - rawMinX), Float(rawMaxY - rawMinY), Float(rawArea),
                    Float(maxX - minX), Float(maxY - minY), Float(textArea),
                    Float(imageArea), Float(coverage)
                ))
                KoraIDV.log("DocumentScanner exit: success — blocks=\(blockCount) confidence=\(confidence) coverage=\(String(format: "%.2f", Float(coverage))) isStable=\(isStable) guidance=\(qualityGuidance ?? "nil")")

                self.lastDetectionResult = detection
                // rc6.1: snapshot the analysis image dimensions so
                // `lastBoundsFractional()` can normalize the bbox.
                self.lastAnalysisImageSize = CGSize(width: width, height: height)
                completion(detection)
            } else {
                // No text blocks detected in this frame. Increment miss
                // counter; only clear cached state once threshold reached.
                self.noDetectionCounter += 1
                if self.noDetectionCounter >= self.noDetectionThreshold {
                    KoraIDV.log("DocumentScanner exit: no-text-blocks — \(self.noDetectionCounter) consecutive misses, clearing cache")
                    self.lastCorners = nil
                    self.stabilityCounter = 0
                    self.lastDetectionResult = nil
                } else {
                    KoraIDV.log("DocumentScanner exit: no-text-blocks — transient miss \(self.noDetectionCounter)/\(self.noDetectionThreshold), returning cached")
                }
                completion(self.lastDetectionResult)
            }
        }
    }

    // MARK: - Stability

    /// Per-axis relative-tolerance corner stability check. Mirrors
    /// Android's `Math.abs(corners[i].x - last[i].x) / corners[i].x.coerceAtLeast(1f)`.
    ///
    /// Soft counter behavior (also matches Android): on stable frame,
    /// increment counter; on unstable frame, decrement (don't fully
    /// reset). Keeps the stability burst alive through brief jitter.
    private func checkStability(corners: [CGPoint]) -> Bool {
        guard let last = lastCorners, last.count == corners.count else {
            lastCorners = corners
            stabilityCounter = 1
            return false
        }

        var isStable = true
        for i in corners.indices {
            let dx = abs(corners[i].x - last[i].x) / max(corners[i].x, 1)
            let dy = abs(corners[i].y - last[i].y) / max(corners[i].y, 1)
            if dx > stabilityTolerance || dy > stabilityTolerance {
                isStable = false
                break
            }
        }

        if isStable {
            stabilityCounter += 1
        } else {
            stabilityCounter = max(0, stabilityCounter - 1)
        }

        lastCorners = corners

        return stabilityCounter >= stabilityThreshold
    }

    /// Reset stability tracking. Called by the caller after a retake or
    /// when re-entering the capture flow.
    func resetStability() {
        lastCorners = nil
        stabilityCounter = 0
        noDetectionCounter = 0
        lastDetectionResult = nil
        lastAnalysisImageSize = .zero
    }

    /// **v1.9.0-rc6.1** — analysis image dimensions captured alongside the
    /// most recent `lastDetectionResult`. Stored so `lastBoundsFractional`
    /// can express the detected bbox in 0–1 normalized coordinates,
    /// allowing the photo-capture path (different pixel dimensions if
    /// the photo output ever differs from the video output, though
    /// currently both are 1080×1920 post-`normalizeToPortrait`) to map
    /// the bbox onto the captured photo by scaling with the photo
    /// dimensions.
    ///
    /// Mirrors Android's `lastImageWidth` / `lastImageHeight` at
    /// `koraidv-android/.../DocumentScanner.kt:30`.
    private var lastAnalysisImageSize: CGSize = .zero

    /// **v1.9.0-rc6.1** — most recent detection bounding box in
    /// 0–1 normalized coordinates relative to the analysis image, or
    /// nil if no detection yet. Caller (CameraManager photo-capture
    /// path) scales by the captured photo's dimensions to get a tight
    /// crop region around the document.
    ///
    /// This is the permanent fix for the "DL too small in review
    /// screen" issue. Previous attempts:
    /// - rc4 and earlier: no crop, photo arrived sensor-native landscape
    ///   with DL sideways
    /// - rc5: centered ID-1 aspect crop, clipped face/name because
    ///   the geometric center was below where the user placed the DL
    /// - rc5.1: reverted rc5; DL whole but small
    /// - rc6.1: bbox-based crop using THE ACTUAL DETECTED DOCUMENT
    ///   LOCATION — what should have been done from the start
    ///
    /// Mirrors Android's `getLastBoundsFractional()` at
    /// `koraidv-android/.../DocumentScanner.kt:237`.
    func lastBoundsFractional() -> CGRect? {
        let size = lastAnalysisImageSize
        guard size.width > 0, size.height > 0,
              let box = lastDetectionResult?.boundingBox
        else {
            return nil
        }
        return CGRect(
            x: max(0, min(1, box.minX / size.width)),
            y: max(0, min(1, box.minY / size.height)),
            width: max(0, min(1, box.width / size.width)),
            height: max(0, min(1, box.height / size.height))
        )
    }
}
