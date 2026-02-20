import UIKit
import Accelerate

struct AntiSpoofResult {
    let isLikelyReal: Bool
    let textureScore: Double      // 0-1, higher = more texture (real)
    let frequencyScore: Double    // 0-1, higher = natural frequency distribution
    let colorScore: Double        // 0-1, higher = natural color variation
    let overallScore: Double      // weighted average
}

final class AntiSpoofCheck {

    private let spoofThreshold = 0.35

    func analyze(_ image: UIImage) -> AntiSpoofResult {
        guard let cgImage = image.cgImage else {
            return AntiSpoofResult(isLikelyReal: false, textureScore: 0, frequencyScore: 0, colorScore: 0, overallScore: 0)
        }

        let texture = analyzeTexture(cgImage)
        let frequency = analyzeFrequency(cgImage)
        let color = analyzeColorDistribution(cgImage)

        // Weighted average: texture most important for print detection
        let overall = texture * 0.45 + frequency * 0.30 + color * 0.25

        return AntiSpoofResult(
            isLikelyReal: overall >= spoofThreshold,
            textureScore: texture,
            frequencyScore: frequency,
            colorScore: color,
            overallScore: overall
        )
    }

    func analyzeTexture(_ image: CGImage) -> Double {
        // Downsample to 64x64 grayscale
        let size = 64
        guard let context = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }

        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let data = context.data else { return 0 }
        let buffer = data.assumingMemoryBound(to: UInt8.self)

        // Compute Laplacian variance
        var laplacianSum: Double = 0
        var laplacianSumSq: Double = 0
        var count: Double = 0

        for y in 1..<(size - 1) {
            for x in 1..<(size - 1) {
                let idx = y * size + x
                let center = Double(buffer[idx])
                let top = Double(buffer[idx - size])
                let bottom = Double(buffer[idx + size])
                let left = Double(buffer[idx - 1])
                let right = Double(buffer[idx + 1])

                let laplacian = -4 * center + top + bottom + left + right
                laplacianSum += laplacian
                laplacianSumSq += laplacian * laplacian
                count += 1
            }
        }

        guard count > 0 else { return 0 }
        let mean = laplacianSum / count
        let variance = (laplacianSumSq / count) - (mean * mean)

        // Normalize: typical real face variance ~50-500, spoof ~0-30
        // Map to 0-1 with sigmoid-like curve
        let normalized = min(variance / 200.0, 1.0)
        return normalized
    }

    func analyzeFrequency(_ image: CGImage) -> Double {
        // Downsample to 64x64 grayscale
        let size = 64
        guard let context = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }

        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let data = context.data else { return 0 }
        let buffer = data.assumingMemoryBound(to: UInt8.self)

        // Convert to Float array for vDSP
        var floatData = [Float](repeating: 0, count: size * size)
        for i in 0..<(size * size) {
            floatData[i] = Float(buffer[i]) / 255.0
        }

        // Compute row-wise energy at different frequency bands
        // High-frequency energy ratio indicates natural vs screen content
        var lowEnergy: Float = 0
        var highEnergy: Float = 0

        for y in 0..<size {
            let rowStart = y * size

            // Simple frequency analysis: differences between adjacent pixels
            for x in 0..<(size - 1) {
                let diff = abs(floatData[rowStart + x + 1] - floatData[rowStart + x])
                if x < size / 2 {
                    lowEnergy += diff
                } else {
                    highEnergy += diff
                }
            }
        }

        let totalEnergy = lowEnergy + highEnergy
        guard totalEnergy > 0 else { return 0 }

        // Real faces have more balanced frequency distribution
        // Screens/prints tend to have less high-frequency content
        let highFreqRatio = Double(highEnergy / totalEnergy)

        // Normalize: expect ~0.3-0.5 for real, ~0.1-0.25 for screen
        return min(highFreqRatio * 2.5, 1.0)
    }

    func analyzeColorDistribution(_ image: CGImage) -> Double {
        let size = 64
        guard let context = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }

        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let data = context.data else { return 0 }
        let buffer = data.assumingMemoryBound(to: UInt8.self)

        let pixelCount = size * size

        // Convert to YCbCr-like and compute chrominance std dev
        var cbValues = [Double]()
        var crValues = [Double]()
        cbValues.reserveCapacity(pixelCount)
        crValues.reserveCapacity(pixelCount)

        for i in 0..<pixelCount {
            let offset = i * 4
            let r = Double(buffer[offset])
            let g = Double(buffer[offset + 1])
            let b = Double(buffer[offset + 2])

            // Simplified YCbCr conversion
            let cb = 128 + (-0.169 * r - 0.331 * g + 0.500 * b)
            let cr = 128 + (0.500 * r - 0.419 * g - 0.081 * b)

            cbValues.append(cb)
            crValues.append(cr)
        }

        // Compute standard deviation for each channel
        let cbStdDev = standardDeviation(cbValues)
        let crStdDev = standardDeviation(crValues)

        // Real skin has wider chroma variance (std dev ~10-30)
        // Printed photos have narrower (~3-10)
        let combinedStdDev = (cbStdDev + crStdDev) / 2.0

        // Normalize to 0-1
        return min(combinedStdDev / 20.0, 1.0)
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let count = Double(values.count)
        let mean = values.reduce(0, +) / count
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / count
        return sqrt(variance)
    }
}
