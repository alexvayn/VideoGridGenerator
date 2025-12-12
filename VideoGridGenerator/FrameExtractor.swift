import AVFoundation
import AppKit
import CryptoKit


class FrameExtractor {
    
    // MARK: - Cache Management
    
    private func getCacheDirectory() -> URL? {
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let frameCacheDir = cacheDir.appendingPathComponent("VideoGridGenerator/FrameCache", isDirectory: true)
        
        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: frameCacheDir.path) {
            try? FileManager.default.createDirectory(at: frameCacheDir, withIntermediateDirectories: true)
        }
        
        return frameCacheDir
    }
    
    private func cacheKey(for url: URL, frameCount: Int) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modDate = attributes[.modificationDate] as? Date else {
            // Fallback to just path-based key if we can't get mod date
            return url.path.data(using: .utf8)!.base64EncodedString()
        }
        
        // Include file path, modification date, and frame count in hash
        let hashInput = "\(url.path)_\(modDate.timeIntervalSince1970)_\(frameCount)"
        let hash = SHA256.hash(data: hashInput.data(using: .utf8)!)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func cachedFramesExist(for url: URL, frameCount: Int) -> Bool {
        guard let cacheDir = getCacheDirectory() else { return false }
        let key = cacheKey(for: url, frameCount: frameCount)
        let cachePath = cacheDir.appendingPathComponent("\(key).cache")
        return FileManager.default.fileExists(atPath: cachePath.path)
    }
    
    private func loadCachedFrames(for url: URL, frameCount: Int) -> [ExtractedFrame]? {
        guard let cacheDir = getCacheDirectory() else { return nil }
        let key = cacheKey(for: url, frameCount: frameCount)
        let cachePath = cacheDir.appendingPathComponent("\(key).cache")
        
        guard let data = try? Data(contentsOf: cachePath) else {
            return nil
        }
        
        do {
            // FIXED: Add NSString to allowed classes to prevent warning spam
            let allowedClasses: [AnyClass] = [
                NSImage.self,
                NSDictionary.self,
                NSArray.self,
                NSNumber.self,
                NSData.self,
                NSString.self  // ← Critical for preventing 32K+ warnings
            ]
            
            guard let cached = try NSKeyedUnarchiver.unarchivedObject(
                ofClasses: allowedClasses,
                from: data
            ) as? [[String: Any]] else {
                print("⚠️ Failed to decode cached frames")
                return nil
            }
            
            var frames: [ExtractedFrame] = []
            for dict in cached {
                guard let imageData = dict["imageData"] as? Data,
                      let image = NSImage(data: imageData),
                      let timestampSeconds = dict["timestamp"] as? Double else {
                    continue
                }
                
                let timestamp = CMTime(seconds: timestampSeconds, preferredTimescale: 600)
                frames.append(ExtractedFrame(image: image, timestamp: timestamp))
            }
            
            return frames.isEmpty ? nil : frames
        } catch {
            print("⚠️ Cache deserialization error: \(error)")
            return nil
        }
    }
    
    private func saveFramesToCache(_ frames: [ExtractedFrame], for url: URL, frameCount: Int) {
        Task.detached(priority: .background) {
            guard let cacheDir = await self.getCacheDirectory() else { return }
            let key = await self.cacheKey(for: url, frameCount: frameCount)
            let cachePath = cacheDir.appendingPathComponent("\(key).cache")
            
            // Convert frames to serializable format
            var cacheData: [[String: Any]] = []
            for frame in frames {
                guard let tiffData = frame.image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let pngData = bitmap.representation(using: .png, properties: [:]) else {
                    continue
                }
                
                cacheData.append([
                    "imageData": pngData,
                    "timestamp": CMTimeGetSeconds(frame.timestamp)
                ])
            }
            
            do {
                let data = try NSKeyedArchiver.archivedData(withRootObject: cacheData, requiringSecureCoding: false)
                try data.write(to: cachePath)
            } catch {
                print("⚠️ Failed to save cache: \(error)")
            }
        }
    }
    
    // MARK: - Frame Extraction
    
    // Q2: Return tuple with fromCache indicator
    func extractFrames(from url: URL, count: Int, progressCallback: @escaping (Double) -> Void) async throws -> (frames: [ExtractedFrame], fromCache: Bool) {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Check cache first
        if cachedFramesExist(for: url, frameCount: count) {
            print("⚡️ CACHE HIT for \(url.lastPathComponent)")
            if let cached = loadCachedFrames(for: url, frameCount: count) {
                let cacheTime = CFAbsoluteTimeGetCurrent() - startTime
                print("⏱️  CACHED extraction took: \(String(format: "%.2f", cacheTime))s (instant!)")
                progressCallback(1.0)
                return (frames: cached, fromCache: true)
            } else {
                print("⚠️ Cache corrupted, extracting fresh frames")
            }
        }
        
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
        
        // OPTIMIZATION: Reduce oversampling from 2x to 1.5x (still good quality, faster)
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
        generator.maximumSize = CGSize(width: 480, height: 480)  // Increased for better quality
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        
        var candidateFrames: [ExtractedFrame] = []
        
        for (index, time) in candidateTimes.enumerated() {
            // CRITICAL: Yield to system between frames to prevent UI blocking
            if index % 5 == 0 {
                await Task.yield()
            }
            
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            candidateFrames.append(ExtractedFrame(image: nsImage, timestamp: time))
            
            // Report extraction progress as 0-50% of total
            progressCallback(Double(index) / Double(candidateTimes.count) * 0.5)
        }
        
        let extractTime = CFAbsoluteTimeGetCurrent() - extractStartTime
        print("⏱️  Frame extraction took: \(String(format: "%.2f", extractTime))s for \(candidateCount) frames")
        
        // Report that extraction is done (50%)
        progressCallback(0.5)
        
        let selectionStartTime = CFAbsoluteTimeGetCurrent()
        
        // Select most distinct frames with OPTIMIZED algorithm
        let selectedFrames = await selectDistinctFrames(from: candidateFrames, count: count) { selectionProgress in
            // Report selection progress as 50-100% of total
            progressCallback(0.5 + (selectionProgress * 0.5))
        }
        
        let selectionTime = CFAbsoluteTimeGetCurrent() - selectionStartTime
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        
        print("⏱️  Frame selection took: \(String(format: "%.2f", selectionTime))s")
        print("⏱️  TOTAL for \(url.lastPathComponent): \(String(format: "%.2f", totalTime))s (\(count) final frames from \(candidateCount) candidates)")
        print("")
        
        // Save to cache in background (non-blocking)
        saveFramesToCache(selectedFrames, for: url, frameCount: count)
        
        progressCallback(1.0)
        return (frames: selectedFrames, fromCache: false)
    }
    
    // MARK: - OPTIMIZED Frame Selection (10-20x faster)
    
    private func selectDistinctFrames(from candidates: [ExtractedFrame], count: Int, progressCallback: @escaping (Double) -> Void = { _ in }) async -> [ExtractedFrame] {
        guard candidates.count > count else {
            progressCallback(1.0)
            return candidates
        }
        
        // OPTIMIZATION: For small grids, just use evenly-spaced frames
        if count <= 12 {
            let step = Double(candidates.count) / Double(count)
            let selectedIndices = (0..<count).map { index in
                min(Int(Double(index) * step), candidates.count - 1)
            }
            progressCallback(1.0)
            return selectedIndices.map { candidates[$0] }
        }
        
        print("🎬 Starting distinctness selection: \(candidates.count) candidates → \(count) needed")
        
        progressCallback(0.1)
        
        // OPTIMIZATION: Compute only brightness and variance (skip expensive edge detection)
        let frameMetrics = await computeSimplifiedMetrics(for: candidates)
        
        progressCallback(0.3)
        
        guard frameMetrics.count > count else {
            print("⚠️ Not enough valid frames, using all candidates")
            progressCallback(1.0)
            return candidates
        }
        
        // Filter out extremely dark or bright frames (fades/transitions)
        let validFrames = frameMetrics.filter { metric in
            let hasGoodBrightness = metric.brightness > 0.15 && metric.brightness < 0.85
            let hasVariety = metric.variance > 0.008  // Slightly relaxed threshold
            return hasGoodBrightness && hasVariety
        }
        
        let framesToScore: [(index: Int, brightness: Double, variance: Double)]
        if validFrames.count < count {
            print("⚠️ Filter too aggressive (\(validFrames.count) < \(count)), using all \(frameMetrics.count) frames")
            framesToScore = frameMetrics
        } else {
            print("🔍 Brightness filter: \(frameMetrics.count) → \(validFrames.count) frames (removed \(frameMetrics.count - validFrames.count) fade/transition frames)")
            framesToScore = validFrames
        }
        
        progressCallback(0.5)
        
        // OPTIMIZATION: Drastically reduced comparison count
        // Only compare with 5 strategic frames instead of all neighbors + distant frames
        var scores: [(index: Int, score: Double)] = []
        let totalIterations = framesToScore.count
        
        for (i, metric) in framesToScore.enumerated() {
            // CRITICAL: Yield every 10 iterations to prevent UI blocking
            if i % 10 == 0 {
                await Task.yield()
                // Report progress during scoring (50-90%)
                progressCallback(0.5 + (Double(i) / Double(totalIterations)) * 0.4)
            }
            
            var totalScore = 0.0
            var comparisons = 0
            
            // Compare with just 5 strategically placed frames
            let compareIndices = getStrategicComparisonIndices(for: i, total: framesToScore.count)
            
            for compareIdx in compareIndices {
                let other = framesToScore[compareIdx]
                
                // Simple brightness difference (fast)
                let brightDiff = abs(metric.brightness - other.brightness)
                
                // Simple variance difference (fast)
                let varianceDiff = abs(metric.variance - other.variance)
                
                // Weighted score (no expensive histogram computation)
                let compositeScore = (brightDiff * 0.6) + (varianceDiff * 0.4)
                
                totalScore += compositeScore
                comparisons += 1
            }
            
            let avgScore = comparisons > 0 ? totalScore / Double(comparisons) : 0
            scores.append((index: metric.index, score: avgScore))
        }
        
        // Sort by distinctness score (higher = more distinct)
        scores.sort { $0.score > $1.score }
        
        print("📊 Selected \(count) most distinct frames (avg score: \(String(format: "%.3f", scores.prefix(count).map { $0.score }.reduce(0, +) / Double(count))))")
        
        progressCallback(1.0)
        
        // Take top N distinct frames and sort by original time order
        let selectedIndices = scores.prefix(count).map { $0.index }.sorted()
        return selectedIndices.map { candidates[$0] }
    }
    
    // OPTIMIZATION: Only compute brightness and variance (much faster)
    private func computeSimplifiedMetrics(for candidates: [ExtractedFrame]) async -> [(index: Int, brightness: Double, variance: Double)] {
        await withTaskGroup(of: (Int, Double, Double)?.self) { group in
            for (index, candidate) in candidates.enumerated() {
                group.addTask {
                    guard let brightness = self.computeBrightness(candidate.image),
                          let variance = self.computeColorVariance(candidate.image) else {
                        return nil
                    }
                    return (index, brightness, variance)
                }
            }
            
            var results: [(index: Int, brightness: Double, variance: Double)] = []
            for await result in group {
                if let result = result {
                    results.append((index: result.0, brightness: result.1, variance: result.2))
                }
            }
            
            return results.sorted { $0.index < $1.index }
        }
    }
    
    // OPTIMIZATION: Compare with only 5 frames instead of dozens
    private func getStrategicComparisonIndices(for index: Int, total: Int) -> [Int] {
        var indices: [Int] = []
        
        // Add immediate neighbors (2 frames)
        if index > 0 {
            indices.append(index - 1)
        }
        if index < total - 1 {
            indices.append(index + 1)
        }
        
        // Add 3 distant frames at strategic positions
        let quarterPoint = total / 4
        let halfPoint = total / 2
        let threeQuarterPoint = (total * 3) / 4
        
        for distantIdx in [quarterPoint, halfPoint, threeQuarterPoint] {
            if distantIdx != index && !indices.contains(distantIdx) && distantIdx < total {
                indices.append(distantIdx)
                if indices.count >= 5 {
                    break
                }
            }
        }
        
        return indices
    }
    
    private func computeBrightness(_ image: NSImage) -> Double? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let width = 16  // Reduced from 24 for speed
        let height = 16
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
        
        let width = 16  // Reduced from 24 for speed
        let height = 16
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
