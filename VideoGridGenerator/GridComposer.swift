import AppKit
import AVFoundation

struct GridConfig {
    let rows: Int
    let columns: Int
    let targetWidth: Int
    let aspectMode: AspectMode
    let backgroundTheme: BackgroundTheme
    let showTimestamps: Bool
}

class GridComposer {
    func composeGrid(frames: [ExtractedFrame], sourceURL: URL, config: GridConfig, outputFolder: URL? = nil) async throws -> URL {
        let borderWidth = 2
        let framePadding = 8
        let titleHeight = 90  // C4: Increased from 80 for better spacing
        let titleMargin = 20
        let bottomPadding = 20
        
        // C1: Determine source aspect ratio for .source mode
        let sourceAspectRatio = try await determineAspectRatio(sourceURL: sourceURL, frames: frames, config: config)
        
        // Calculate thumbnail dimensions from target width
        let totalPadding = framePadding * (config.columns + 1) + (borderWidth * 2 * config.columns)
        let thumbnailWidth = (config.targetWidth - totalPadding) / config.columns
        
        // C1: Calculate height based on aspect mode
        let thumbnailHeight: Int
        if config.aspectMode == .source {
            thumbnailHeight = Int(Double(thumbnailWidth) / sourceAspectRatio)
        } else {
            thumbnailHeight = Int(Double(thumbnailWidth) * 9.0 / 16.0) // Default 16:9
        }
        
        let gridWidth = (thumbnailWidth + borderWidth * 2) * config.columns + framePadding * (config.columns + 1)
        let gridHeight = (thumbnailHeight + borderWidth * 2) * config.rows + framePadding * (config.rows + 1) + titleHeight + bottomPadding
        
        let gridImage = NSImage(size: NSSize(width: gridWidth, height: gridHeight))
        gridImage.lockFocus()
        
        // Background
        let bgColor = config.backgroundTheme == .black ? NSColor.black : NSColor.white
        bgColor.setFill()
        NSRect(x: 0, y: 0, width: gridWidth, height: gridHeight).fill()
        
        // Draw filename and metadata with background strip
        let videoFilename = sourceURL.lastPathComponent
        let asset = AVAsset(url: sourceURL)
        let duration = try? await asset.load(.duration)
        let durationString = duration != nil ? formatDuration(CMTimeGetSeconds(duration!)) : ""
        
        let titleText = "\(videoFilename)  •  \(config.rows)×\(config.columns)  •  \(durationString)"
        
        // Draw semi-transparent background strip for title
        let titleBgRect = NSRect(x: 0, y: gridHeight - titleHeight, width: gridWidth, height: titleHeight)
        let titleBgColor = config.backgroundTheme == .black
            ? NSColor.black.withAlphaComponent(0.3)
            : NSColor.white.withAlphaComponent(0.3)
        titleBgColor.setFill()
        titleBgRect.fill()
        
        // C4: Adjusted positioning for better spacing
        let titleRect = NSRect(x: titleMargin, y: gridHeight - titleHeight + 20, width: gridWidth - titleMargin * 2, height: titleHeight - 25)
        let titleColor = config.backgroundTheme == .black ? NSColor.white : NSColor.black
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .medium),
            .foregroundColor: titleColor
        ]
        titleText.draw(in: titleRect, withAttributes: titleAttrs)
        
        // C2: Small corner radius for softer edges
        let cornerRadius: CGFloat = 3
        
        // Draw frames
        for (index, frame) in frames.enumerated() {
            let col = index % config.columns
            let row = index / config.columns  // Fixed: was incorrectly dividing by rows
            
            let x = framePadding + col * (thumbnailWidth + borderWidth * 2 + framePadding)
            let y = gridHeight - titleHeight - framePadding - (row + 1) * (thumbnailHeight + borderWidth * 2 + framePadding)
            
            // C2: Border with rounded corners
            let borderColor = config.backgroundTheme == .black ? NSColor.white : NSColor.black
            borderColor.setFill()
            let borderRect = NSRect(x: x, y: y, width: thumbnailWidth + borderWidth * 2, height: thumbnailHeight + borderWidth * 2)
            let borderPath = NSBezierPath(roundedRect: borderRect, xRadius: cornerRadius, yRadius: cornerRadius)
            borderPath.fill()
            
            // Save graphics state for clipping
            NSGraphicsContext.current?.saveGraphicsState()
            
            // C2: Clip to rounded rect for image
            let destRect = NSRect(x: x + borderWidth, y: y + borderWidth, width: thumbnailWidth, height: thumbnailHeight)
            let destPath = NSBezierPath(roundedRect: destRect, xRadius: cornerRadius - 1, yRadius: cornerRadius - 1)
            destPath.setClip()
            
            // Draw image based on aspect mode
            switch config.aspectMode {
            case .fill:
                frame.image.draw(in: destRect, from: .zero, operation: .copy, fraction: 1.0)
            case .fit:
                drawImageFit(frame.image, in: destRect, background: bgColor)
            case .source:
                drawImageFit(frame.image, in: destRect, background: bgColor)
            }
            
            // Restore clipping state
            NSGraphicsContext.current?.restoreGraphicsState()
            
            // C3: Timestamp with theme-appropriate colors and better padding
            if config.showTimestamps {
                let timestamp = formatTimestamp(CMTimeGetSeconds(frame.timestamp))
                // Increased padding from 8 to 10px for better spacing
                let textRect = NSRect(x: x + borderWidth + 10, y: y + borderWidth + 10, width: thumbnailWidth - 20, height: 30)
                
                // Adjust colors based on background theme
                let timestampColor: NSColor
                let shadowColor: NSColor
                
                if config.backgroundTheme == .white {
                    timestampColor = NSColor.black
                    shadowColor = NSColor.white.withAlphaComponent(0.9)
                } else {
                    timestampColor = NSColor.white
                    shadowColor = NSColor.black.withAlphaComponent(0.9)
                }
                
                let shadow = NSShadow()
                shadow.shadowColor = shadowColor
                shadow.shadowOffset = NSSize(width: 1, height: -1)
                shadow.shadowBlurRadius = 4
                
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 18, weight: .bold),
                    .foregroundColor: timestampColor,
                    .shadow: shadow
                ]
                timestamp.draw(in: textRect, withAttributes: attrs)
            }
        }
        
        gridImage.unlockFocus()
        
        // Save file
        let outputURL = try resolveOutputURL(for: sourceURL, config: config, outputFolder: outputFolder)
        
        print("🎨 Grid image composed, size: \(gridWidth)×\(gridHeight)")
        
        if let tiffData = gridImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) {
            
            print("📦 JPEG data generated, size: \(jpegData.count) bytes")
            
            do {
                try jpegData.write(to: outputURL)
                print("✅ Successfully wrote file to: \(outputURL.path)")
                
                // Verify file exists
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    print("✅ Verified: File exists at \(outputURL.path)")
                } else {
                    print("❌ ERROR: File does not exist after writing!")
                }
            } catch {
                print("❌ ERROR writing file: \(error)")
                throw error
            }
        } else {
            print("❌ ERROR: Failed to generate JPEG data")
            throw NSError(domain: "GridComposer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to generate JPEG"])
        }
        
        return outputURL
    }
    
    // C1: Determine aspect ratio from video track or fallback to frame
    private func determineAspectRatio(sourceURL: URL, frames: [ExtractedFrame], config: GridConfig) async throws -> Double {
        if config.aspectMode != .source {
            return 16.0 / 9.0  // Default for non-source modes
        }
        
        // Try to get aspect ratio from video track
        let asset = AVAsset(url: sourceURL)
        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            let naturalSize = try? await track.load(.naturalSize)
            let preferredTransform = try? await track.load(.preferredTransform)
            
            if let size = naturalSize, let transform = preferredTransform {
                // Apply transform to get display size (handles rotation)
                let transformedSize = size.applying(transform)
                let width = abs(transformedSize.width)
                let height = abs(transformedSize.height)
                
                if height > 0 {
                    return width / height
                }
            }
        }
        
        // Fallback: use first frame's dimensions
        if let firstFrame = frames.first {
            let size = firstFrame.image.size
            if size.height > 0 {
                return size.width / size.height
            }
        }
        
        // Final fallback to 16:9
        return 16.0 / 9.0
    }
    
    private func drawImageFit(_ image: NSImage, in rect: NSRect, background: NSColor) {
        let imageSize = image.size
        let imageAspect = imageSize.width / imageSize.height
        let rectAspect = rect.width / rect.height
        
        var drawRect = rect
        if imageAspect > rectAspect {
            // Image wider than rect
            let newHeight = rect.width / imageAspect
            drawRect.origin.y += (rect.height - newHeight) / 2
            drawRect.size.height = newHeight
        } else {
            // Image taller than rect
            let newWidth = rect.height * imageAspect
            drawRect.origin.x += (rect.width - newWidth) / 2
            drawRect.size.width = newWidth
        }
        
        background.setFill()
        rect.fill()
        image.draw(in: drawRect, from: .zero, operation: .copy, fraction: 1.0)
    }
    
    private func resolveOutputURL(for videoURL: URL, config: GridConfig, outputFolder: URL? = nil) throws -> URL {
        let baseFilename = videoURL.deletingPathExtension().lastPathComponent
        let outputFilename = "\(baseFilename)_\(config.rows)x\(config.columns).jpg"
        
        // If user selected an output folder, use that
        if let customFolder = outputFolder {
            var outputURL = customFolder.appendingPathComponent(outputFilename)
            
            var counter = 1
            while FileManager.default.fileExists(atPath: outputURL.path) {
                let numberedFilename = "\(baseFilename)_\(config.rows)x\(config.columns)_\(counter).jpg"
                outputURL = customFolder.appendingPathComponent(numberedFilename)
                counter += 1
            }
            
            print("✅ Will write to custom folder: \(outputURL.path)")
            return outputURL
        }
        
        // Try to write to same directory as video
        let videoDirectory = videoURL.deletingLastPathComponent()
        var outputURL = videoDirectory.appendingPathComponent(outputFilename)
        
        // Test if we can write to this directory
        let testURL = videoDirectory.appendingPathComponent(".test_write_\(UUID().uuidString)")
        do {
            try "test".write(to: testURL, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(at: testURL)
            
            // We can write here, proceed with collision checking
            var counter = 1
            while FileManager.default.fileExists(atPath: outputURL.path) {
                let numberedFilename = "\(baseFilename)_\(config.rows)x\(config.columns)_\(counter).jpg"
                outputURL = videoDirectory.appendingPathComponent(numberedFilename)
                counter += 1
            }
            
            print("✅ Will write to: \(outputURL.path)")
            return outputURL
            
        } catch {
            // Can't write to video directory, use user's actual Downloads folder
            print("⚠️ Cannot write to video directory: \(error)")
            print("💡 Tip: Click 'Set Output Folder' to choose where to save files")
            
            // Get the real Downloads folder (not sandboxed)
            let homeURL = FileManager.default.homeDirectoryForCurrentUser
            let downloadsURL = homeURL.appendingPathComponent("Downloads")
            
            // Verify Downloads exists and is accessible
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: downloadsURL.path, isDirectory: &isDir) || !isDir.boolValue {
                print("⚠️ Downloads folder not accessible, using fallback")
                let fallbackURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                outputURL = fallbackURL.appendingPathComponent(outputFilename)
            } else {
                outputURL = downloadsURL.appendingPathComponent(outputFilename)
            }
            
            var counter = 1
            while FileManager.default.fileExists(atPath: outputURL.path) {
                let numberedFilename = "\(baseFilename)_\(config.rows)x\(config.columns)_\(counter).jpg"
                if outputURL.path.contains("/Downloads/") {
                    outputURL = downloadsURL.appendingPathComponent(numberedFilename)
                } else {
                    outputURL = outputURL.deletingLastPathComponent().appendingPathComponent(numberedFilename)
                }
                counter += 1
            }
            
            print("✅ Will write to Downloads: \(outputURL.path)")
            return outputURL
        }
    }
    
    private func formatTimestamp(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, secs)
        } else {
            return String(format: "%ds", secs)
        }
    }
}
