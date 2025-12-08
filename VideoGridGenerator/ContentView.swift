import SwiftUI
import AVFoundation
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selectedVideoURL: URL?
    @State private var columns: String = "4"
    @State private var rows: String = "4"
    @State private var isProcessing = false
    @State private var progress: Double = 0
    @State private var statusMessage = "Ready"
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isDragOver = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Video Screenshot Grid Generator")
                .font(.title)
                .padding(.top)
            
            // File selection with drag & drop
            VStack {
                HStack {
                    Text(selectedVideoURL?.lastPathComponent ?? "No video selected")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(5)
                    
                    Button("Choose Video") {
                        selectVideoFile()
                    }
                }
                
                // Drag and drop zone
                Text("or drag & drop video file here")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5]))
                            .foregroundColor(isDragOver ? .blue : .gray.opacity(0.5))
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isDragOver ? Color.blue.opacity(0.1) : Color.clear)
                    )
                    .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                        handleDrop(providers: providers)
                    }
            }
            .padding(.horizontal)
            
            // Grid dimensions
            HStack {
                Text("Grid Size:")
                TextField("Columns", text: $columns)
                    .frame(width: 60)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Text("×")
                TextField("Rows", text: $rows)
                    .frame(width: 60)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            // Generate button
            Button("Generate Grid") {
                generateGrid()
            }
            .disabled(selectedVideoURL == nil || isProcessing)
            .padding()
            .background(selectedVideoURL == nil || isProcessing ? Color.gray : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            
            // Progress
            if isProcessing {
                ProgressView(value: progress, total: 1.0)
                    .padding(.horizontal)
                Text(statusMessage)
                    .font(.caption)
            } else {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .frame(minWidth: 500, minHeight: 400)
        .padding()
        .alert("Result", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
    
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        _ = provider.loadObject(ofClass: URL.self) { url, error in
            guard let url = url else { return }
            
            // Check if it's a video file
            let allowedExtensions = ["mp4", "m4v", "mov"]
            let fileExtension = url.pathExtension.lowercased()
            
            if allowedExtensions.contains(fileExtension) {
                DispatchQueue.main.async {
                    self.selectedVideoURL = url
                    self.statusMessage = "Video selected: \(url.lastPathComponent)"
                }
            }
        }
        
        return true
    }
    
    func selectVideoFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.message = "Select a video file"
        
        if panel.runModal() == .OK {
            selectedVideoURL = panel.url
            statusMessage = "Video selected: \(panel.url?.lastPathComponent ?? "")"
        }
    }
    
    func generateGrid() {
        guard let videoURL = selectedVideoURL,
              let cols = Int(columns), cols > 0,
              let rws = Int(rows), rws > 0 else {
            alertMessage = "Please select a video and enter valid grid dimensions"
            showingAlert = true
            return
        }
        
        isProcessing = true
        progress = 0
        statusMessage = "Loading video..."
        
        Task {
            do {
                let outputURL = try await createScreenshotGrid(
                    videoURL: videoURL,
                    columns: cols,
                    rows: rws
                )
                
                await MainActor.run {
                    isProcessing = false
                    statusMessage = "Complete!"
                    alertMessage = "Grid saved to:\n\(outputURL.path)"
                    showingAlert = true
                    
                    // Open the file in Finder
                    NSWorkspace.shared.selectFile(outputURL.path, inFileViewerRootedAtPath: "")
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    statusMessage = "Error occurred"
                    alertMessage = "Error: \(error.localizedDescription)"
                    showingAlert = true
                }
            }
        }
    }
    
    func createScreenshotGrid(videoURL: URL, columns: Int, rows: Int) async throws -> URL {
        let asset = AVAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)
        let totalFrames = columns * rows
        
        // Generate timestamps evenly distributed
        var timestamps: [CMTime] = []
        for i in 0..<totalFrames {
            let timeInSeconds = (totalSeconds / Double(totalFrames + 1)) * Double(i + 1)
            let time = CMTime(seconds: timeInSeconds, preferredTimescale: 600)
            timestamps.append(time)
        }
        
        // Generate thumbnails
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        var images: [(NSImage, String)] = []
        
        for (index, time) in timestamps.enumerated() {
            await MainActor.run {
                progress = Double(index) / Double(totalFrames)
                statusMessage = "Capturing frame \(index + 1) of \(totalFrames)..."
            }
            
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            
            // Format timestamp
            let seconds = CMTimeGetSeconds(time)
            let hours = Int(seconds) / 3600
            let minutes = (Int(seconds) % 3600) / 60
            let secs = Int(seconds) % 60
            let timestamp = String(format: "%02d:%02d:%02d", hours, minutes, secs)
            
            images.append((nsImage, timestamp))
        }
        
        await MainActor.run {
            statusMessage = "Compositing grid..."
        }
        
        // Create grid image with borders and title
        let thumbnailWidth = 400
        let thumbnailHeight = 225
        let borderWidth = 5
        let titleHeight = 60
        let titleMargin = 20
        
        let gridWidth = (thumbnailWidth + borderWidth) * columns + borderWidth
        let gridHeight = (thumbnailHeight + borderWidth) * rows + borderWidth + titleHeight
        
        let gridImage = NSImage(size: NSSize(width: gridWidth, height: gridHeight))
        gridImage.lockFocus()
        
        // Black background
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: gridWidth, height: gridHeight).fill()
        
        // Draw filename at top
        let videoFilename = videoURL.lastPathComponent
        let titleRect = NSRect(x: titleMargin, y: gridHeight - titleHeight + 10, width: gridWidth - titleMargin * 2, height: titleHeight)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        videoFilename.draw(in: titleRect, withAttributes: titleAttrs)
        
        // Draw thumbnails with borders
        for (index, (image, timestamp)) in images.enumerated() {
            let col = index % columns
            let row = index / columns
            let x = borderWidth + col * (thumbnailWidth + borderWidth)
            let y = gridHeight - titleHeight - borderWidth - (row + 1) * (thumbnailHeight + borderWidth)
            
            let destRect = NSRect(x: x, y: y, width: thumbnailWidth, height: thumbnailHeight)
            image.draw(in: destRect)
            
            // Draw timestamp with shadow
            let textRect = NSRect(x: x + 5, y: y + 5, width: thumbnailWidth - 10, height: 25)
            
            // Create shadow
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.9)
            shadow.shadowOffset = NSSize(width: 1, height: -1)
            shadow.shadowBlurRadius = 3
            
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: NSColor.white,
                .shadow: shadow
            ]
            timestamp.draw(in: textRect, withAttributes: attrs)
        }
        
        gridImage.unlockFocus()
        
        // Save to Downloads folder
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let filename = "grid_\(videoURL.deletingPathExtension().lastPathComponent)_\(Date().timeIntervalSince1970).jpg"
        let outputURL = downloadsURL.appendingPathComponent(filename)
        
        if let tiffData = gridImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) {
            try jpegData.write(to: outputURL)
        }
        
        return outputURL
    }
}
