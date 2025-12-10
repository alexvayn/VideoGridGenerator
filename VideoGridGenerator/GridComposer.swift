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
    func composeGrid(frames: [ExtractedFrame], sourceURL: URL, config: GridConfig) async throws -> URL {
        let borderWidth = 2
        let framePadding = 8
        let titleHeight = 80
        let titleMargin = 20
        let bottomPadding = 20
        
        // Calculate thumbnail dimensions from target width
        let totalPadding = framePadding * (config.columns + 1) + (borderWidth * 2 * config.columns)
        let thumbnailWidth = (config.targetWidth - totalPadding) / config.columns
        let thumbnailHeight = Int(Double(thumbnailWidth) * 9.0 / 16.0) // Assume 16:9 for now
        
        let gridWidth = (thumbnailWidth + borderWidth * 2) * config.columns + framePadding * (config.columns + 1)
        let gridHeight = (thumbnailHeight + borderWidth * 2) * config.rows + framePadding * (config.rows + 1) + titleHeight + bottomPadding
        
        let gridImage = NSImage(size: NSSize(width: gridWidth, height: gridHeight))
        gridImage.lockFocus()
        
        // Background
        let bgColor = config.backgroundTheme == .black ? NSColor.black : NSColor.white
        bgColor.setFill()
        NSRect(x: 0, y: 0, width: gridWidth, height: gridHeight).fill()
        
        // Draw filename and metadata
        let videoFilename = sourceURL.lastPathComponent
        let asset = AVAsset(url: sourceURL)
        let duration = try? await asset.load(.duration)
        let durationString = duration != nil ? formatDuration(CMTimeGetSeconds(duration!)) : ""
        
        let titleText = "\(videoFilename)  •  \(config.rows)×\(config.columns)  •  \(durationString)"
        let titleRect = NSRect(x: titleMargin, y: gridHeight - titleHeight + 15, width: gridWidth - titleMargin * 2, height: titleHeight - 20)
        let titleColor = config.backgroundTheme == .black ? NSColor.white : NSColor.black
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .medium),
            .foregroundColor: titleColor
        ]
        titleText.draw(in: titleRect, withAttributes: titleAttrs)
        
        // Draw frames
        for (index, frame) in frames.enumerated() {
            let col = index % config.columns
            let row = index / config.columns
            
            let x = framePadding + col * (thumbnailWidth + borderWidth * 2 + framePadding)
            let y = gridHeight - titleHeight - framePadding - (row + 1) * (thumbnailHeight + borderWidth * 2 + framePadding)
            
            // Border
            let borderColor = config.backgroundTheme == .black ? NSColor.white : NSColor.black
            borderColor.setFill()
            let borderRect = NSRect(x: x, y: y, width: thumbnailWidth + borderWidth * 2, height: thumbnailHeight + borderWidth * 2)
            borderRect.fill()
            
            // Draw image based on aspect mode
            let destRect = NSRect(x: x + borderWidth, y: y + borderWidth, width: thumbnailWidth, height: thumbnailHeight)
            
            switch config.aspectMode {
            case .fill:
                frame.image.draw(in: destRect, from: .zero, operation: .copy, fraction: 1.0)
            case .fit:
                drawImageFit(frame.image, in: destRect, background: bgColor)
            case .source:
                drawImageFit(frame.image, in: destRect, background: bgColor)
            }
            
            // Timestamp
            if config.showTimestamps {
                let timestamp = formatTimestamp(CMTimeGetSeconds(frame.timestamp))
                let textRect = NSRect(x: x + borderWidth + 5, y: y + borderWidth + 5, width: thumbnailWidth - 10, height: 25)
                
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.9)
                shadow.shadowOffset = NSSize(width: 1, height: -1)
                shadow.shadowBlurRadius = 3
                
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                    .foregroundColor: NSColor.white,
                    .shadow: shadow
                ]
                timestamp.draw(in: textRect, withAttributes: attrs)
            }
        }
        
        gridImage.unlockFocus()
        
        // Save file
        let outputURL = try resolveOutputURL(for: sourceURL, config: config)
        
        if let tiffData = gridImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) {
            try jpegData.write(to: outputURL)
        }
        
        return outputURL
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
    
    private func resolveOutputURL(for videoURL: URL, config: GridConfig) throws -> URL {
        let videoDirectory = videoURL.deletingLastPathComponent()
        let baseFilename = videoURL.deletingPathExtension().lastPathComponent
        let outputFilename = "\(baseFilename)_\(config.rows)x\(config.columns).jpg"
        var outputURL = videoDirectory.appendingPathComponent(outputFilename)
        
        var counter = 1
        while FileManager.default.fileExists(atPath: outputURL.path) {
            let numberedFilename = "\(baseFilename)_\(config.rows)x\(config.columns)_\(counter).jpg"
            outputURL = videoDirectory.appendingPathComponent(numberedFilename)
            counter += 1
        }
        
        return outputURL
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
