import AVFoundation
import AppKit

struct ExtractedFrame {
    let image: NSImage
    let timestamp: CMTime
}

class FrameExtractor {
    func extractFrames(from url: URL, count: Int, progressCallback: @escaping (Double) -> Void) async throws -> [ExtractedFrame] {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)
        
        // Skip intro/outro (5% each)
        let skipStart = totalSeconds * 0.05
        let skipEnd = totalSeconds * 0.05
        let usableDuration = totalSeconds - skipStart - skipEnd
        
        guard usableDuration > 0 else {
            throw NSError(domain: "FrameExtractor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Video too short"])
        }
        
        // Oversample 1.5x for speed (was 2x, still gives good distinctness with our efficient algorithm)
        let candidateCount = Int(Double(count) * 1.5)
        var candidateTimes: [CMTime] = []
        
        for i in 0..<candidateCount {
            let timeInSeconds = skipStart + (usableDuration / Double(candidateCount + 1)) * Double(i + 1)
            let time = CMTime(seconds: timeInSeconds, preferredTimescale: 600)
            candidateTimes.append(time)
        }
        
        let extractStartTime = CFAbsoluteTimeGetCurrent()
        
        // Extract candidate frames
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480) // High quality to avoid upscaling in final output
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        
        var candidateFrames: [ExtractedFrame] = []
        
        for (index, time) in candidateTimes.enumerated() {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            candidateFrames.append(ExtractedFrame(image: nsImage, timestamp: time))
            
            progressCallback(Double(index) / Double(candidateTimes.count))
        }
        
        let extractTime = CFAbsoluteTimeGetCurrent() - extractStartTime
        print("⏱️  Frame extraction took: \(String(format: "%.2f", extractTime))s for \(candidateCount) frames")
        
        let selectionStartTime = CFAbsoluteTimeGetCurrent()
        
        // Select most distinct frames
        let selectedFrames = await selectDistinctFrames(from: candidateFrames, count: count)
        
        let selectionTime = CFAbsoluteTimeGetCurrent() - selectionStartTime
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        
        print("⏱️  Frame selection took: \(String(format: "%.2f", selectionTime))s")
        print("⏱️  TOTAL for \(url.lastPathComponent): \(String(format: "%.2f", totalTime))s (\(count) final frames from \(candidateCount) candidates)")
        print("")
        
        progressCallback(1.0)
        return selectedFrames
    }
    
    private func selectDistinctFrames(from candidates: [ExtractedFrame], count: Int) async -> [ExtractedFrame] {
        guard candidates.count > count else { return candidates }
        
        // OPTIMIZATION: Skip distinctness algorithm for small grids (≤9 frames)
        // Just return evenly-spaced frames - much faster with negligible quality difference
        if count <= 9 {
            let step = Double(candidates.count) / Double(count)
            let selectedIndices = (0..<count).map { index in
                min(Int(Double(index) * step), candidates.count - 1)
            }
            return selectedIndices.map { candidates[$0] }
        }
        
        print("🎬 Starting distinctness selection: \(candidates.count) candidates → \(count) needed")
        
        // OPTIMIZATION: Compute all metrics sequentially to avoid thread explosion
        let frameMetrics = computeMetricsSequentially(for: candidates)
        
        guard frameMetrics.count > count else {
            print("⚠️ Not enough valid frames, using all candidates")
            return candidates
        }
        
        // Filter out extremely dark or bright frames (likely fades/transitions)
        // Also filter out frames with very low edge density (solid colors/blank frames)
        // And filter out frames with low color variance (uniform/gradient backgrounds)
        let validFrames = frameMetrics.filter { metric in
            let hasGoodBrightness = metric.brightness > 0.15 && metric.brightness < 0.85
            let hasContent = metric.edges > 0.05  // Increased threshold - must have visible detail
            let hasVariety = metric.variance > 0.01  // Must have color variation (not solid/gradient)
            return hasGoodBrightness && hasContent && hasVariety
        }
        
        // If brightness filter removed too many frames, use all candidates
        let framesToScore: [(index: Int, histogram: [Double], edges: Double, brightness: Double, variance: Double)]
        if validFrames.count < count {
            print("⚠️ Brightness filter too aggressive (\(validFrames.count) < \(count)), using all \(frameMetrics.count) frames")
            framesToScore = frameMetrics
        } else {
            print("🔍 Brightness filter: \(frameMetrics.count) → \(validFrames.count) frames (removed \(frameMetrics.count - validFrames.count) fade/transition frames)")
            framesToScore = validFrames
        }
        
        // OPTIMIZATION: Fast sample-based comparison with synchronous scoring
        // Avoid nested TaskGroups which cause thread explosion when processing multiple videos
        
        let sampleCount = min(4, framesToScore.count / 5) // Reduced to 4 samples
        let sampleIndices = selectRepresentativeSamples(from: framesToScore, count: sampleCount)
        
        print("🎯 Using \(sampleIndices.count) representative samples for comparison")
        
        // Fast synchronous scoring - no nested parallelism
        var scores: [(index: Int, score: Double)] = []
        
        for metric in framesToScore {
            var totalScore = 0.0
            
            for sampleIdx in sampleIndices {
                let sample = framesToScore[sampleIdx]
                
                // Skip self-comparison
                if metric.index == sample.index {
                    continue
                }
                
                // Simplified scoring: only histogram difference (fastest metric)
                let histDiff = histogramDifference(metric.histogram, sample.histogram)
                
                // Add brightness difference for variety
                let brightDiff = abs(metric.brightness - sample.brightness)
                
                // Simplified weighted score (removed expensive edge calculations)
                let compositeScore = (histDiff * 0.7) + (brightDiff * 0.3)
                
                totalScore += compositeScore
            }
            
            let avgScore = sampleIndices.count > 0 ? totalScore / Double(sampleIndices.count) : 0
            scores.append((index: metric.index, score: avgScore))
        }
        
        // Sort by distinctness score (higher = more distinct)
        scores.sort { $0.score > $1.score }
        
        print("📊 Selected \(count) most distinct frames (avg score: \(String(format: "%.3f", scores.prefix(count).map { $0.score }.reduce(0, +) / Double(count))))")
        
        // Take top N distinct frames and sort by original time order
        let selectedIndices = scores.prefix(count).map { $0.index }.sorted()
        return selectedIndices.map { candidates[$0] }
    }
    
    // OPTIMIZATION: Select representative samples for comparison
    // Chooses frames that are evenly distributed and have diverse characteristics
    private func selectRepresentativeSamples(from frames: [(index: Int, histogram: [Double], edges: Double, brightness: Double, variance: Double)], count: Int) -> [Int] {
        guard frames.count > count else {
            return frames.indices.map { $0 }
        }
        
        // Strategy: Evenly space samples across the video timeline
        // This ensures we capture diversity across the entire video
        let step = Double(frames.count) / Double(count)
        var samples: [Int] = []
        
        for i in 0..<count {
            let index = min(Int(Double(i) * step + step / 2.0), frames.count - 1)
            samples.append(index)
        }
        
        return samples
    }
    
    // OPTIMIZATION: Sequential metric computation to avoid thread explosion
    // When processing multiple videos concurrently, parallel metric computation
    // creates too many threads (5 videos × 84 frames = 420 concurrent tasks)
    private func computeMetricsSequentially(for candidates: [ExtractedFrame]) -> [(index: Int, histogram: [Double], edges: Double, brightness: Double, variance: Double)] {
        var results: [(index: Int, histogram: [Double], edges: Double, brightness: Double, variance: Double)] = []
        
        for (index, candidate) in candidates.enumerated() {
            guard let histogram = computeHistogram(candidate.image),
                  let edges = computeEdgeDensity(candidate.image),
                  let brightness = computeBrightness(candidate.image),
                  let variance = computeColorVariance(candidate.image) else {
                continue
            }
            results.append((index: index, histogram: histogram, edges: edges, brightness: brightness, variance: variance))
        }
        
        return results
    }
    
    private func histogramDifference(_ hist1: [Double], _ hist2: [Double]) -> Double {
        var diff = 0.0
        for i in 0..<min(hist1.count, hist2.count) {
            diff += abs(hist1[i] - hist2[i])
        }
        return diff
    }
    
    private func compareFrames(_ img1: NSImage, _ img2: NSImage) -> Double {
        // Legacy method - kept for backward compatibility
        guard let hist1 = computeHistogram(img1),
              let hist2 = computeHistogram(img2) else {
            return 0.0
        }
        return histogramDifference(hist1, hist2)
    }
    
    private func computeHistogram(_ image: NSImage) -> [Double]? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let width = 24  // Reduced from 32 (44% fewer pixels)
        let height = 24
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Simple 16-bin histogram (4 bins per channel: R, G, B, brightness)
        var histogram = [Double](repeating: 0, count: 16)
        
        for i in stride(from: 0, to: pixelData.count, by: bytesPerPixel) {
            let r = Double(pixelData[i])
            let g = Double(pixelData[i + 1])
            let b = Double(pixelData[i + 2])
            let brightness = (r + g + b) / 3.0
            
            histogram[Int(r / 64)] += 1
            histogram[4 + Int(g / 64)] += 1
            histogram[8 + Int(b / 64)] += 1
            histogram[12 + Int(brightness / 64)] += 1
        }
        
        // Normalize
        let total = Double(width * height)
        return histogram.map { $0 / total }
    }
    
    private func computeEdgeDensity(_ image: NSImage) -> Double? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let width = 24  // Reduced from 32
        let height = 24
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = width
        
        var pixelData = [UInt8](repeating: 0, count: width * height)
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Simple Sobel edge detection
        var edgeCount = 0.0
        let threshold: UInt8 = 30
        
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = y * width + x
                
                // Horizontal gradient
                let gx = Int(pixelData[idx + 1]) - Int(pixelData[idx - 1])
                
                // Vertical gradient
                let gy = Int(pixelData[idx + width]) - Int(pixelData[idx - width])
                
                // Gradient magnitude
                let magnitude = sqrt(Double(gx * gx + gy * gy))
                
                if magnitude > Double(threshold) {
                    edgeCount += 1
                }
            }
        }
        
        // Normalize by total pixels
        return edgeCount / Double(width * height)
    }
    
    private func computeBrightness(_ image: NSImage) -> Double? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let width = 24  // Reduced from 32
        let height = 24
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var totalBrightness = 0.0
        
        for i in stride(from: 0, to: pixelData.count, by: bytesPerPixel) {
            let r = Double(pixelData[i]) / 255.0
            let g = Double(pixelData[i + 1]) / 255.0
            let b = Double(pixelData[i + 2]) / 255.0
            
            // Relative luminance
            let brightness = 0.299 * r + 0.587 * g + 0.114 * b
            totalBrightness += brightness
        }
        
        return totalBrightness / Double(width * height)
    }
    
    private func computeColorVariance(_ image: NSImage) -> Double? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let width = 24  // Reduced from 32
        let height = 24
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Calculate variance in RGB channels
        var rValues: [Double] = []
        var gValues: [Double] = []
        var bValues: [Double] = []
        
        for i in stride(from: 0, to: pixelData.count, by: bytesPerPixel) {
            rValues.append(Double(pixelData[i]) / 255.0)
            gValues.append(Double(pixelData[i + 1]) / 255.0)
            bValues.append(Double(pixelData[i + 2]) / 255.0)
        }
        
        let rVariance = calculateVariance(rValues)
        let gVariance = calculateVariance(gValues)
        let bVariance = calculateVariance(bValues)
        
        // Return average variance across channels
        return (rVariance + gVariance + bVariance) / 3.0
    }
    
    private func calculateVariance(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        
        let mean = values.reduce(0, +) / Double(values.count)
        let squaredDiffs = values.map { pow($0 - mean, 2) }
        return squaredDiffs.reduce(0, +) / Double(values.count)
    }
}
