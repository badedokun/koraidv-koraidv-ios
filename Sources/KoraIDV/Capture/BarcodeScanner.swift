import Foundation
import Vision
import CoreImage

/// On-device barcode decoder for the back side of identity documents.
///
/// The KoraIDV pipeline cascades through three decoders in priority order:
///   1. **This class (Apple Vision)** — runs on the captured back-side
///      image before upload. When it succeeds, the decoded AAMVA payload
///      travels to the server in `UploadDocumentBackRequest.decodedBarcodePayload`
///      and the server skips image decoding entirely.
///   2. **zxing-cpp** (server-side) — primary decoder when the client failed.
///   3. **pdf417decoder** (server-side) — fallback for captures zxing-cpp
///      can't read.
///
/// Why decode on-device when the server can do it? Three reasons:
///   - **Latency**: phone decode finishes in ~50-200 ms vs. ~1-3 s server
///     round-trip + cascade (image upload + ml-service work).
///   - **Cost**: zero ml-service compute on the happy path.
///   - **Reliability**: Vision's PDF417 implementation ships with the OS
///     and is hardened by Apple Wallet / Pay use cases. Empirically more
///     robust on real phone captures than either zxing-cpp or pdf417decoder.
///
/// When this fails, we silently send the image to the server — no user
/// impact, just a slower path.
///
/// Restricted to PDF417 today (US/CA driver's licenses). The same
/// `VNDetectBarcodesRequest` symbology list also covers QR (Nigeria
/// voter's card), DataMatrix (some EU permits), and Aztec — extending
/// later is one line.
///
/// See `docs/architecture/idv-decode-roadmap.md` Phase 3.
public final class BarcodeScanner {

    public init() {}

    /// Attempt to decode a PDF417 barcode from the supplied JPEG/PNG-encoded
    /// image data. Returns the raw AAMVA payload as a single string
    /// (newline-separated records, exactly the form the server's AAMVA
    /// parser expects) or `nil` when no barcode was found or decoding
    /// failed.
    ///
    /// Synchronous wrapper over `VNDetectBarcodesRequest`. Vision is
    /// thread-safe and fast enough that callers don't need to dispatch
    /// off the main thread for a single request, but they may.
    public func decodePdf417(imageData: Data) -> String? {
        guard let cgImage = makeCGImage(from: imageData) else {
            return nil
        }
        return decodePdf417(cgImage: cgImage)
    }

    /// Decode directly from a CGImage. Useful when the caller has already
    /// produced one (e.g. from a CMSampleBuffer in CameraManager) and
    /// doesn't want the JPEG round-trip.
    public func decodePdf417(cgImage: CGImage) -> String? {
        let request = VNDetectBarcodesRequest()
        // Restrict to PDF417: Vision will happily detect every Code128,
        // QR, EAN, and Aztec on the document otherwise — slowing decode
        // and risking false positives on the small Code128 strip that
        // also appears on US DLs.
        if #available(iOS 15.0, macOS 12.0, *) {
            request.symbologies = [.pdf417]
        } else {
            request.symbologies = [.PDF417]
        }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            // Vision can throw transient errors on malformed images.
            // We don't escalate — the server cascade will pick it up.
            return nil
        }
        guard let observations = request.results else { return nil }
        for observation in observations {
            if let payload = observation.payloadStringValue, !payload.isEmpty {
                return payload
            }
        }
        return nil
    }

    private func makeCGImage(from data: Data) -> CGImage? {
        guard let provider = CGDataProvider(data: data as CFData) else {
            return nil
        }
        // Try JPEG first (most common from the camera pipeline), then PNG.
        if let img = CGImage(jpegDataProviderSource: provider,
                             decode: nil,
                             shouldInterpolate: true,
                             intent: .defaultIntent) {
            return img
        }
        if let img = CGImage(pngDataProviderSource: provider,
                             decode: nil,
                             shouldInterpolate: true,
                             intent: .defaultIntent) {
            return img
        }
        // Fallback via CIImage which handles a wider set of formats.
        guard let ciImage = CIImage(data: data) else { return nil }
        let context = CIContext()
        return context.createCGImage(ciImage, from: ciImage.extent)
    }
}
