import UIKit

/// Document-side presentation-attack detection.
///
/// **v1.9.1-rc2 (2026-06-08)** — added after Olabode @ BanffPay reported
/// that both iOS and Android accepted a document scanned from another
/// digital screen (laptop, phone) as if it were a real physical card.
/// Prior to v1.9.1-rc2 the document path had no anti-spoof at all; only
/// blur / brightness / glare were validated.
///
/// **This is a starting-point heuristic, not the long-term answer.**
/// v1.10 will replace it with a proper ML model (likely a small CNN
/// trained on real vs screen-capture document pairs) or server-side FFT
/// moire detection. The heuristic here catches the egregious cases (a
/// phone camera pointed at a laptop screen displaying a document) while
/// being conservative enough to rarely false-reject real captures.
///
/// **The signal**: edge-density coefficient of variation across spatial
/// blocks of the image.
///
///  - Real documents have spatial inhomogeneity in edge content: text
///    regions have lots of edges (ink against background), blank regions
///    (margins, photo cutouts, plain card surface) have few edges. The
///    coefficient of variation (stddev/mean) of per-block edge density
///    across the image is HIGH.
///
///  - Screen-captured documents inherit the LCD/OLED subpixel grid in
///    every pixel of the captured image. The subpixel grid contributes
///    a uniform high-frequency texture to ALL regions of the captured
///    image, including supposedly-blank background. The CoV of edge
///    density across blocks is LOW because every block has roughly the
///    same density (the subpixel-grid contribution dominates).
///
/// Conservative `minEdgeDensityCoV = 0.30` threshold favours false
/// negatives over false positives — better to let a real screen capture
/// through (caught by manual review or by other checks) than to reject
/// a real document on a patterned background.
final class DocumentSpoofCheck {

    /// Result of a document spoof analysis.
    struct Result {
        /// Whether the image is likely a photo of a screen displaying a
        /// document, rather than a real physical document.
        let isLikelyScreen: Bool

        /// Per-block edge-density coefficient of variation. Higher values
        /// indicate more spatial inhomogeneity (typical of real documents).
        /// Lower values indicate uniform edge density (typical of screens).
        /// Exposed for diagnostics + future calibration.
        let edgeDensityCoV: Double
    }

    // MARK: - Tuning constants

    /// Side length of the downsampled analysis image (pixels). Power of 2
    /// for clean block alignment. 256 is enough resolution to expose
    /// subpixel-grid patterns without overwhelming CPU on older devices.
    private let analysisSize = 256

    /// Side length of each analysis block (pixels). 32×32 gives an 8×8
    /// grid of blocks across the analysis image (64 blocks total).
    private let blockSize = 32

    /// Sobel-like gradient magnitude threshold above which a pixel is
    /// counted as an "edge" pixel. Tuned on grayscale 0–255 input.
    private let edgeThreshold = 30

    /// CoV below this value triggers `isLikelyScreen = true`. Conservative
    /// — chosen to almost never false-reject real documents on plain
    /// backgrounds (where CoV is typically 0.6+) while still catching
    /// obvious screen captures (where CoV is typically 0.10–0.25).
    /// Documents on patterned backgrounds may register in the 0.30–0.50
    /// range and pass through.
    private let minEdgeDensityCoV: Double = 0.30

    // MARK: - Analysis

    func analyze(_ image: UIImage) -> Result {
        guard let cgImage = image.cgImage else {
            return Result(isLikelyScreen: false, edgeDensityCoV: 0)
        }

        // Downsample to fixed analysis size in grayscale. We want a
        // consistent pixel scale across input devices so the edge
        // threshold + block size are meaningful.
        guard let context = CGContext(
            data: nil,
            width: analysisSize,
            height: analysisSize,
            bitsPerComponent: 8,
            bytesPerRow: analysisSize,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return Result(isLikelyScreen: false, edgeDensityCoV: 0)
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: analysisSize, height: analysisSize))

        guard let data = context.data else {
            return Result(isLikelyScreen: false, edgeDensityCoV: 0)
        }
        let buffer = data.assumingMemoryBound(to: UInt8.self)

        // Compute per-block edge density. For each block, count the
        // pixels whose Sobel-approximate gradient magnitude (|dx| + |dy|)
        // exceeds edgeThreshold.
        let blocksPerSide = analysisSize / blockSize
        var blockDensities: [Double] = []
        blockDensities.reserveCapacity(blocksPerSide * blocksPerSide)

        for by in 0..<blocksPerSide {
            for bx in 0..<blocksPerSide {
                let blockX = bx * blockSize
                let blockY = by * blockSize
                var edgeCount = 0
                // Skip 1-pixel border within block to allow neighbour reads.
                for y in (blockY + 1)..<(blockY + blockSize - 1) {
                    for x in (blockX + 1)..<(blockX + blockSize - 1) {
                        let idx = y * analysisSize + x
                        let center = Int(buffer[idx])
                        let right = Int(buffer[idx + 1])
                        let bottom = Int(buffer[idx + analysisSize])
                        let dx = abs(right - center)
                        let dy = abs(bottom - center)
                        if (dx + dy) > edgeThreshold {
                            edgeCount += 1
                        }
                    }
                }
                blockDensities.append(Double(edgeCount))
            }
        }

        // Coefficient of variation = stddev / mean. Use guard against
        // mean=0 (rare, would mean a completely flat image).
        guard !blockDensities.isEmpty else {
            return Result(isLikelyScreen: false, edgeDensityCoV: 0)
        }
        let mean = blockDensities.reduce(0, +) / Double(blockDensities.count)
        guard mean > 0 else {
            return Result(isLikelyScreen: false, edgeDensityCoV: 0)
        }
        let variance = blockDensities
            .map { ($0 - mean) * ($0 - mean) }
            .reduce(0, +) / Double(blockDensities.count)
        let stddev = sqrt(variance)
        let cov = stddev / mean

        return Result(
            isLikelyScreen: cov < minEdgeDensityCoV,
            edgeDensityCoV: cov
        )
    }
}
