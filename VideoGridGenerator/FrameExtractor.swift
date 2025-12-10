import AVFoundation
import AppKit

struct ExtractedFrame {
    let image: NSImage
    let timestamp: CMTime
}

class FrameExtractor {
    func extractFrames(from url: URL, count: Int, progressCallback: @escaping (Double) -> Void) async throws -> [ExtractedFrame] {
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
        
        // Oversample 2x instead of 3x (still good results, 33% faster)
        let candidateCount = count * 2
        var candidateTimes: [CMTime] = []
        
        for i in 0..<candidateCount {
            let timeInSeconds = skipStart + (usableDuration / Double(candidateCount + 1)) * Double(i + 1)
            let time = CMTime(seconds: timeInSeconds, preferredTimescale: 600)
            candidateTimes.append(time)
        }
        
        // Extract candidate frames
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400) // Reduced from 800x800 (4x fewer pixels)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        
        var candidateFrames: [ExtractedFrame] = []
        
        for (index, time) in candidateTimes.enumerated() {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            candidateFrames.append(ExtractedFrame(image: nsImage, timestamp: time))
            
            progressCallback(Double(index) / Double(candidateTimes.count))
        }
        
        // Select most distinct frames
        let selectedFrames = selectDistinctFrames(from: candidateFrames, count: count)
        
        progressCallback(1.0)
        return selectedFrames
    }
    
    private func selectDistinctFrames(from candidates: [ExtractedFrame], count: Int) -> [ExtractedFrame] {
        guard candidates.count > count else { return candidates }
        
        print("🎬 Starting distinctness selection: \(candidates.count) candidates → \(count) needed")
        
        // Calculate metrics - use concurrent processing for speed
        let frameMetrics: [(index: Int, histogram: [Double], edges: Double, brightness: Double, variance: Double)] = candidates.enumerated().compactMap { (index, candidate) in
            guard let histogram = computeHistogram(candidate.image),
                  let edges = computeEdgeDensity(candidate.image),
                  let brightness = computeBrightness(candidate.image),
                  let variance = computeColorVariance(candidate.image) else {
                return nil
            }
            return (index: index, histogram: histogram, edges: edges, brightness: brightness, variance: variance)
        }
        
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
        
        // Calculate composite distinctness scores
        var scores: [(index: Int, score: Double)] = []
        
        for (i, metric) in framesToScore.enumerated() {
            var totalScore = 0.0
            var comparisons = 0
            
            // Compare with neighbors and distant frames
            let compareIndices = getComparisonIndices(for: i, total: framesToScore.count)
            
            for compareIdx in compareIndices {
                let other = framesToScore[compareIdx]
                
                // Histogram difference (color/tone changes)
                let histDiff = histogramDifference(metric.histogram, other.histogram)
                
                // Edge density difference (scene composition changes)
                let edgeDiff = abs(metric.edges - other.edges)
                
                // Brightness difference (lighting changes)
                let brightDiff = abs(metric.brightness - other.brightness)
                
                // Weighted composite score
                let compositeScore = (histDiff * 0.5) + (edgeDiff * 0.3) + (brightDiff * 0.2)
                
                totalScore += compositeScore
                comparisons += 1
            }
            
            let avgScore = comparisons > 0 ? totalScore / Double(comparisons) : 0
            scores.append((index: metric.index, score: avgScore))
        }
        
        // Sort by distinctness score (higher = more distinct)
        scores.sort { $0.score > $1.score }
        
        print("📊 Selected \(count) most distinct frames (avg score: \(String(format: "%.3f", scores.prefix(count).map { $0.score }.reduce(0, +) / Double(count))))")
        
        // Take top N distinct frames and sort by original time order
        let selectedIndices = scores.prefix(count).map { $0.index }.sorted()
        return selectedIndices.map { candidates[$0] }
    }
    
    // Get indices to compare against (neighbors + some distant frames)
    private func getComparisonIndices(for index: Int, total: Int) -> [Int] {
        var indices: [Int] = []
        
        // Add immediate neighbors only (reduced comparisons)
        if index > 0 { indices.append(index - 1) }
        if index < total - 1 { indices.append(index + 1) }
        
        // Add fewer distant frames (reduced from 8 to 4 total comparisons)
        let step = max(total / 8, 1)
        if index - step >= 0 { indices.append(index - step) }
        if index + step < total { indices.append(index + step) }
        
        return indices
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
