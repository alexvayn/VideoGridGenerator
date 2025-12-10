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
        
        // Oversample 3x for distinctness selection
        let candidateCount = count * 3
        var candidateTimes: [CMTime] = []
        
        for i in 0..<candidateCount {
            let timeInSeconds = skipStart + (usableDuration / Double(candidateCount + 1)) * Double(i + 1)
            let time = CMTime(seconds: timeInSeconds, preferredTimescale: 600)
            candidateTimes.append(time)
        }
        
        // Extract candidate frames
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 800, height: 800) // 2x typical thumbnail
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
        
        // Calculate distinctness scores between sequential frames
        var scores: [(index: Int, score: Double)] = []
        
        for i in 0..<candidates.count {
            let score: Double
            if i == 0 {
                score = compareFrames(candidates[i].image, candidates[min(i + 1, candidates.count - 1)].image)
            } else if i == candidates.count - 1 {
                score = compareFrames(candidates[i].image, candidates[i - 1].image)
            } else {
                let scorePrev = compareFrames(candidates[i].image, candidates[i - 1].image)
                let scoreNext = compareFrames(candidates[i].image, candidates[i + 1].image)
                score = (scorePrev + scoreNext) / 2.0
            }
            scores.append((index: i, score: score))
        }
        
        // Sort by distinctness score (higher = more distinct)
        scores.sort { $0.score > $1.score }
        
        // Take top N distinct frames and sort by original time order
        let selectedIndices = scores.prefix(count).map { $0.index }.sorted()
        return selectedIndices.map { candidates[$0] }
    }
    
    private func compareFrames(_ img1: NSImage, _ img2: NSImage) -> Double {
        guard let hist1 = computeHistogram(img1),
              let hist2 = computeHistogram(img2) else {
            return 0.0
        }
        
        // Calculate histogram difference (simple sum of absolute differences)
        var diff = 0.0
        for i in 0..<hist1.count {
            diff += abs(hist1[i] - hist2[i])
        }
        
        return diff
    }
    
    private func computeHistogram(_ image: NSImage) -> [Double]? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let width = 32
        let height = 32
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
}
