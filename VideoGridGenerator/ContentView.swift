import SwiftUI
import AVFoundation
import AppKit
import UniformTypeIdentifiers

struct VideoProgress: Identifiable {
    let id = UUID()
    let filename: String
    var progress: Double
    var status: String
}

struct ContentView: View {
    @State private var selectedVideoURLs: [URL] = []
    @State private var columns: String = "4"
    @State private var rows: String = "4"
    @State private var parallelProcessing: String = "5"
    @State private var isProcessing = false
    @State private var videoProgresses: [VideoProgress] = []
    @State private var statusMessage = "Ready"
    @State private var isDragOver = false
    @State private var completedCount = 0
    @State private var totalCount = 0
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Video Screenshot Grid Generator")
                .font(.title)
                .padding(.top)
            
            // File selection with drag & drop
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if selectedVideoURLs.isEmpty {
                            Text("No videos selected")
                        } else {
                            Text("\(selectedVideoURLs.count) video\(selectedVideoURLs.count == 1 ? "" : "s") selected")
                                .font(.headline)
                            ForEach(selectedVideoURLs.prefix(3), id: \.self) { url in
                                Text("• \(url.lastPathComponent)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if selectedVideoURLs.count > 3 {
                                Text("... and \(selectedVideoURLs.count - 3) more")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(5)
                    
                    Button("Choose Files") {
                        selectVideoFiles()
                    }
                }
                
                // Drag and drop zone
                Text("or drag & drop video files/folders here")
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
            
            // Grid dimensions and parallel processing
            HStack(spacing: 20) {
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
                
                Divider()
                    .frame(height: 30)
                
                HStack {
                    Text("Parallel:")
                    TextField("Files", text: $parallelProcessing)
                        .frame(width: 60)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Text("files")
                }
            }
            
            // Generate button
            Button("Generate Grids") {
                generateGrids()
            }
            .disabled(selectedVideoURLs.isEmpty || isProcessing)
            .padding()
            .background(selectedVideoURLs.isEmpty || isProcessing ? Color.gray : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            
            // Progress
            if isProcessing {
                VStack(spacing: 12) {
                    Text("Processing \(completedCount) of \(totalCount) completed")
                        .font(.headline)
                    
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(videoProgresses) { videoProgress in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(videoProgress.filename)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(Int(videoProgress.progress * 100))%")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    ProgressView(value: videoProgress.progress, total: 1.0)
                                        .progressViewStyle(LinearProgressViewStyle())
                                    
                                    Text(videoProgress.status)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(5)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .padding(.horizontal)
                }
            } else {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .frame(minWidth: 600, minHeight: 500)
        .padding()
    }
    
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        var newURLs: [URL] = []
        let group = DispatchGroup()
        
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                defer { group.leave() }
                guard let url = url else { return }
                
                // Check if it's a directory
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                    if isDirectory.boolValue {
                        // It's a folder - get all video files inside
                        let videos = self.getVideoFilesInDirectory(url)
                        newURLs.append(contentsOf: videos)
                    } else {
                        // It's a file - check if it's a video
                        let allowedExtensions = ["mp4", "m4v", "mov"]
                        let fileExtension = url.pathExtension.lowercased()
                        if allowedExtensions.contains(fileExtension) {
                            newURLs.append(url)
                        }
                    }
                }
            }
        }
        
        group.notify(queue: .main) {
            if !newURLs.isEmpty {
                self.selectedVideoURLs = newURLs
                self.statusMessage = "Selected \(newURLs.count) video\(newURLs.count == 1 ? "" : "s")"
            }
        }
        
        return true
    }
    
    func getVideoFilesInDirectory(_ directoryURL: URL) -> [URL] {
        var videoFiles: [URL] = []
        let allowedExtensions = ["mp4", "m4v", "mov"]
        
        if let enumerator = FileManager.default.enumerator(at: directoryURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                let fileExtension = fileURL.pathExtension.lowercased()
                if allowedExtensions.contains(fileExtension) {
                    videoFiles.append(fileURL)
                }
            }
        }
        
        return videoFiles
    }
    
    func selectVideoFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.message = "Select video files or folders"
        
        if panel.runModal() == .OK {
            var allVideos: [URL] = []
            
            for url in panel.urls {
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                    if isDirectory.boolValue {
                        allVideos.append(contentsOf: getVideoFilesInDirectory(url))
                    } else {
                        allVideos.append(url)
                    }
                }
            }
            
            selectedVideoURLs = allVideos
            statusMessage = "Selected \(allVideos.count) video\(allVideos.count == 1 ? "" : "s")"
        }
    }
    
    func generateGrids() {
        guard !selectedVideoURLs.isEmpty,
              let cols = Int(columns), cols > 0,
              let rws = Int(rows), rws > 0,
              let maxParallel = Int(parallelProcessing), maxParallel > 0 else {
            statusMessage = "Please select videos and enter valid settings"
            return
        }
        
        isProcessing = true
        completedCount = 0
        totalCount = selectedVideoURLs.count
        videoProgresses = []
        
        Task {
            await processVideosInParallel(
                urls: selectedVideoURLs,
                columns: cols,
                rows: rws,
                maxConcurrent: maxParallel
            )
            
            await MainActor.run {
                isProcessing = false
                statusMessage = "Complete! Processed \(completedCount) of \(totalCount) video\(totalCount == 1 ? "" : "s")"
                videoProgresses = []
                
                // Open the folder containing the first video
                if let firstVideoURL = selectedVideoURLs.first {
                    let folderURL = firstVideoURL.deletingLastPathComponent()
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
                }
            }
        }
    }
    
    func processVideosInParallel(urls: [URL], columns: Int, rows: Int, maxConcurrent: Int) async {
        await withTaskGroup(of: Void.self) { group in
            var activeCount = 0
            var index = 0
            
            while index < urls.count {
                // Add tasks up to max concurrent
                while activeCount < maxConcurrent && index < urls.count {
                    let videoURL = urls[index]
                    let videoIndex = index
                    
                    // Create progress tracker
                    await MainActor.run {
                        videoProgresses.append(VideoProgress(
                            filename: videoURL.lastPathComponent,
                            progress: 0,
                            status: "Starting..."
                        ))
                    }
                    
                    group.addTask {
                        await self.processVideo(
                            videoURL: videoURL,
                            columns: columns,
                            rows: rows,
                            progressIndex: videoIndex
                        )
                    }
                    
                    activeCount += 1
                    index += 1
                }
                
                // Wait for at least one task to complete
                await group.next()
                activeCount -= 1
            }
            
            // Wait for remaining tasks
            await group.waitForAll()
        }
    }
    
    func processVideo(videoURL: URL, columns: Int, rows: Int, progressIndex: Int) async {
        do {
            _ = try await createScreenshotGrid(
                videoURL: videoURL,
                columns: columns,
                rows: rows,
                progressIndex: progressIndex
            )
            
            await MainActor.run {
                completedCount += 1
                // Remove from progress list when done
                videoProgresses.removeAll { $0.filename == videoURL.lastPathComponent }
            }
        } catch {
            await MainActor.run {
                if let index = videoProgresses.firstIndex(where: { $0.filename == videoURL.lastPathComponent }) {
                    videoProgresses[index].status = "Error: \(error.localizedDescription)"
                    videoProgresses[index].progress = 0
                }
                completedCount += 1
            }
        }
    }
    
    func updateProgress(index: Int, progress: Double, status: String) async {
        await MainActor.run {
            if index < videoProgresses.count {
                videoProgresses[index].progress = progress
                videoProgresses[index].status = status
            }
        }
    }
    
    func createScreenshotGrid(videoURL: URL, columns: Int, rows: Int, progressIndex: Int) async throws -> URL {
        let asset = AVAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)
        let totalFrames = columns * rows
        
        await updateProgress(index: progressIndex, progress: 0.1, status: "Loading video...")
        
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
            let frameProgress = 0.1 + (Double(index) / Double(totalFrames)) * 0.7
            await updateProgress(
                index: progressIndex,
                progress: frameProgress,
                status: "Capturing frame \(index + 1) of \(totalFrames)..."
            )
            
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
        
        await updateProgress(index: progressIndex, progress: 0.85, status: "Compositing grid...")
        
        // Create grid image with borders and title
        let thumbnailWidth = 400
        let thumbnailHeight = 225
        let borderWidth = 2  // White border around each frame
        let framePadding = 8  // Space between frames
        let titleHeight = 80
        let titleMargin = 20
        let bottomPadding = 20  // Padding at the bottom
        
        let gridWidth = (thumbnailWidth + borderWidth * 2) * columns + framePadding * (columns + 1)
        let gridHeight = (thumbnailHeight + borderWidth * 2) * rows + framePadding * (rows + 1) + titleHeight + bottomPadding
        
        let gridImage = NSImage(size: NSSize(width: gridWidth, height: gridHeight))
        gridImage.lockFocus()
        
        // Black background
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: gridWidth, height: gridHeight).fill()
        
        // Draw filename at top with more vertical space
        let videoFilename = videoURL.lastPathComponent
        let titleRect = NSRect(x: titleMargin, y: gridHeight - titleHeight + 15, width: gridWidth - titleMargin * 2, height: titleHeight - 20)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        videoFilename.draw(in: titleRect, withAttributes: titleAttrs)
        
        // Draw thumbnails with white borders and padding
        for (index, (image, timestamp)) in images.enumerated() {
            let col = index % columns
            let row = index / columns
            
            // Calculate position with padding
            let x = framePadding + col * (thumbnailWidth + borderWidth * 2 + framePadding)
            let y = gridHeight - titleHeight - framePadding - (row + 1) * (thumbnailHeight + borderWidth * 2 + framePadding)
            
            // Draw white border
            NSColor.white.setFill()
            let borderRect = NSRect(x: x, y: y, width: thumbnailWidth + borderWidth * 2, height: thumbnailHeight + borderWidth * 2)
            borderRect.fill()
            
            // Draw thumbnail
            let destRect = NSRect(x: x + borderWidth, y: y + borderWidth, width: thumbnailWidth, height: thumbnailHeight)
            image.draw(in: destRect)
            
            // Draw timestamp with shadow
            let textRect = NSRect(x: x + borderWidth + 5, y: y + borderWidth + 5, width: thumbnailWidth - 10, height: 25)
            
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
        
        await updateProgress(index: progressIndex, progress: 0.95, status: "Saving file...")
        
        // Save to same folder as video file with clean filename
        let videoDirectory = videoURL.deletingLastPathComponent()
        let baseFilename = videoURL.deletingPathExtension().lastPathComponent
        let outputFilename = "\(baseFilename).jpg"
        var outputURL = videoDirectory.appendingPathComponent(outputFilename)
        
        // Handle duplicate filenames
        var counter = 1
        while FileManager.default.fileExists(atPath: outputURL.path) {
            let numberedFilename = "\(baseFilename)_\(counter).jpg"
            outputURL = videoDirectory.appendingPathComponent(numberedFilename)
            counter += 1
        }
        
        if let tiffData = gridImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) {
            try jpegData.write(to: outputURL)
        }
        
        await updateProgress(index: progressIndex, progress: 1.0, status: "Complete!")
        
        return outputURL
    }
}
