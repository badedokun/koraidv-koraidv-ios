import SwiftUI
import UIKit
import AVFoundation

// MARK: - Camera Preview View

/// SwiftUI bridge to the AVFoundation camera preview.
///
/// v1.8.6: rewritten to use `CameraPreviewUIView` (see CameraManager.swift),
/// whose root layer IS an `AVCaptureVideoPreviewLayer`. UIKit's layout system
/// resizes the layer automatically as the SwiftUI parent resolves geometry.
///
/// The previous pattern (`UIView(frame: .zero)` + `addSublayer` + manual
/// frame management in `updateUIView`) left the preview layer at zero-size
/// because `updateUIView` doesn't fire on initial bounds resolution — every
/// document/selfie/liveness preview rendered dark to the user. See the
/// `CameraPreviewUIView` docstring for the full root cause.
///
/// Reused by `SelfieCaptureView` — fixing this struct fixes selfie preview
/// automatically (it's the same UIViewRepresentable).
///
/// **Lives in its own file (not DocumentCaptureView.swift) so the SPM unit-test
/// target can use it.** DocumentCaptureView.swift is excluded from the SPM
/// target because it depends on the ML-Kit `DocumentScanner`; this preview
/// wrapper has no ML Kit dependency, so keeping it here lets `SelfieCaptureView`
/// (and the SPM build) compile without pulling in ML Kit.
struct CameraPreviewView: UIViewRepresentable {
    let cameraManager: CameraManager

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.videoPreviewLayer.session = cameraManager.captureSession
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // No-op: UIKit auto-resizes the preview layer as the view's bounds
        // change because the layer IS the root layer.
    }
}
