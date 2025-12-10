import SwiftUI
import AVFoundation
import AppKit
import Combine

// MARK: - Models

struct VideoJob: Identifiable {
    let id: UUID = UUID()
    let url: URL
    var progress: Double = 0
    var status: String = "Queued"
    var outputPath: String? = nil
    var isComplete: Bool = false
    var isCancelled: Bool = false
    var hasSecurityAccess: Bool = false
}

enum AspectMode: String, CaseIterable {
    case fill = "Fill"
    case fit = "Fit"
    case source = "Source"
}

enum BackgroundTheme: String, CaseIterable {
    case black = "Black"
    case white = "White"
}

// MARK: - ViewModel

@MainActor
class GeneratorViewModel: ObservableObject {
    @Published var videoJobs: [UUID: VideoJob] = [:]
    @Published var jobOrder: [UUID] = []
    @Published var isProcessing = false
    @Published var completedCount = 0
    @Published var lastOutputPath: String? = nil
    @Published var outputFolderURL: URL?
    
    @AppStorage("rows") var rows: Int = 4
    @AppStorage("columns") var columns: Int = 4
    @AppStorage("maxConcurrent") var maxConcurrent: Int = 2
    @AppStorage("targetWidth") var targetWidth: Int = 1920
    @AppStorage("aspectMode") var aspectMode: String = AspectMode.fill.rawValue
    @AppStorage("backgroundTheme") var backgroundTheme: String = BackgroundTheme.black.rawValue
    @AppStorage("showTimestamps") var showTimestamps: Bool = true
    
    private var cancellationTokens: Set<UUID> = []
    private let frameExtractor = FrameExtractor()
    private let gridComposer = GridComposer()
    private var outputFolderAccess = false
    private var generationTask: Task<Void, Never>?
    
    // Debug logging flag
    private let debugLogging = false
    
    // MARK: - File Selection
    
    func handleDroppedURLs(_ urls: [URL]) {
        let videoURLs = collectVideoURLs(from: urls)
        addVideos(videoURLs)
    }
    
    func addVideos(_ urls: [URL]) {
        for url in urls {
            // Start accessing security-scoped resource (centralized)
            let hasAccess = url.startAccessingSecurityScopedResource()
            
            var job = VideoJob(url: url)
            job.hasSecurityAccess = hasAccess
            videoJobs[job.id] = job
            jobOrder.append(job.id)
            
            if debugLogging {
                print("📁 Added video: \(url.lastPathComponent), security access: \(hasAccess)")
            }
        }
    }
    
    private func collectVideoURLs(from urls: [URL]) -> [URL] {
        var result: [URL] = []
        let allowedExtensions = ["mp4", "m4v", "mov"]
        
        for url in urls {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    // Directory: start access, enumerate, then stop
                    let dirHasAccess = url.startAccessingSecurityScopedResource()
                    result.append(contentsOf: getVideoFilesInDirectory(url))
                    if dirHasAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                } else if allowedExtensions.contains(url.pathExtension.lowercased()) {
                    result.append(url)
                }
            }
        }
        
        return result
    }
    
    private func getVideoFilesInDirectory(_ directoryURL: URL) -> [URL] {
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
    
    // MARK: - Output Folder Management
    
    func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select where to save grid images"
        panel.prompt = "Select Folder"
        
        if panel.runModal() == .OK, let url = panel.url {
            // Stop accessing previous folder if any
            if outputFolderAccess, let oldURL = outputFolderURL {
                oldURL.stopAccessingSecurityScopedResource()
            }
            
            // Start accessing new folder
            outputFolderAccess = url.startAccessingSecurityScopedResource()
            outputFolderURL = url
            
            if debugLogging {
                print("📂 Output folder set to: \(url.path)")
                print("🔐 Security access granted: \(outputFolderAccess)")
            }
        }
    }
    
    func clearOutputFolder() {
        if outputFolderAccess, let url = outputFolderURL {
            url.stopAccessingSecurityScopedResource()
        }
        outputFolderURL = nil
        outputFolderAccess = false
    }
    
    // MARK: - Generation
    
    func generateGrids() {
        guard !videoJobs.isEmpty else { return }
        
        // Cancel any existing generation task
        generationTask?.cancel()
        
        isProcessing = true
        completedCount = 0
        cancellationTokens.removeAll()
        
        generationTask = Task {
            await processVideosWithSemaphore()
            
            guard !Task.isCancelled else {
                await MainActor.run {
                    isProcessing = false
                }
                return
            }
            
            await MainActor.run {
                isProcessing = false
                if let firstJobId = jobOrder.first,
                   let firstJob = videoJobs[firstJobId] {
                    let folderURL = firstJob.url.deletingLastPathComponent()
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
                }
            }
        }
    }
    
    func cancelGeneration() {
        // Cancel the task
        generationTask?.cancel()
        
        // Mark all incomplete jobs as cancelled
        for jobId in jobOrder {
            cancellationTokens.insert(jobId)
            if var job = videoJobs[jobId], !job.isComplete {
                job.isCancelled = true
                job.status = "Cancelled"
                job.isComplete = true
                videoJobs[jobId] = job
            }
        }
        
        isProcessing = false
    }
    
    private func processVideosWithSemaphore() async {
        await withTaskGroup(of: Void.self) { group in
            let semaphore = AsyncSemaphore(value: maxConcurrent)
            
            for jobId in jobOrder {
                // Check if task is cancelled before adding new work
                guard !Task.isCancelled else {
                    break
                }
                
                guard let job = videoJobs[jobId] else { continue }
                
                group.addTask {
                    await semaphore.wait()
                    
                    // Check cancellation after acquiring semaphore
                    if Task.isCancelled {
                        await semaphore.signal()
                        return
                    }
                    
                    await self.processVideo(jobId: jobId, url: job.url)
                    
                    await semaphore.signal()
                }
            }
            
            await group.waitForAll()
        }
    }
    
    private func processVideo(jobId: UUID, url: URL) async {
        // Early exit if cancelled
        guard !Task.isCancelled && !cancellationTokens.contains(jobId) else {
            await updateJob(jobId: jobId) { job in
                job.isCancelled = true
                job.status = "Cancelled"
                job.isComplete = true
            }
            await releaseSecurityAccess(for: jobId)
            return
        }
        
        await updateJob(jobId: jobId) { job in
            job.status = "Loading..."
            job.progress = 0.1
        }
        
        do {
            let config = GridConfig(
                rows: rows,
                columns: columns,
                targetWidth: targetWidth,
                aspectMode: AspectMode(rawValue: aspectMode) ?? .fill,
                backgroundTheme: BackgroundTheme(rawValue: backgroundTheme) ?? .black,
                showTimestamps: showTimestamps
            )
            
            let frames = try await frameExtractor.extractFrames(
                from: url,
                count: rows * columns,
                progressCallback: { progress in
                    Task { @MainActor in
                        self.updateJob(jobId: jobId) { job in
                            job.progress = 0.1 + (progress * 0.7)
                            job.status = "Extracting frames..."
                        }
                    }
                }
            )
            
            guard !Task.isCancelled && !cancellationTokens.contains(jobId) else {
                await updateJob(jobId: jobId) { job in
                    job.isCancelled = true
                    job.status = "Cancelled"
                    job.isComplete = true
                }
                await releaseSecurityAccess(for: jobId)
                return
            }
            
            await updateJob(jobId: jobId) { job in
                job.status = "Compositing..."
                job.progress = 0.85
            }
            
            let outputURL = try await gridComposer.composeGrid(
                frames: frames,
                sourceURL: url,
                config: config,
                outputFolder: self.outputFolderURL
            )
            
            await updateJob(jobId: jobId) { job in
                job.progress = 1.0
                job.status = "Complete"
                job.outputPath = outputURL.path
                job.isComplete = true
            }
            
            await MainActor.run {
                completedCount += 1
                lastOutputPath = outputURL.path
            }
            
        } catch {
            await updateJob(jobId: jobId) { job in
                job.status = "Error: \(error.localizedDescription)"
                job.isComplete = true
            }
            print("❌ Error processing \(url.lastPathComponent): \(error)")
        }
        
        // Always release security access when done
        await releaseSecurityAccess(for: jobId)
    }
    
    private func releaseSecurityAccess(for jobId: UUID) async {
        await MainActor.run {
            if let job = videoJobs[jobId], job.hasSecurityAccess {
                job.url.stopAccessingSecurityScopedResource()
                if debugLogging {
                    print("🔓 Released security access for: \(job.url.lastPathComponent)")
                }
            }
        }
    }
    
    private func updateJob(jobId: UUID, update: (inout VideoJob) -> Void) {
        guard var job = videoJobs[jobId] else { return }
        update(&job)
        videoJobs[jobId] = job
    }
    
    func clearCompleted() {
        let completedIds = videoJobs.filter { $0.value.isComplete }.map { $0.key }
        for id in completedIds {
            videoJobs.removeValue(forKey: id)
        }
        jobOrder.removeAll { completedIds.contains($0) }
        completedCount = 0
        lastOutputPath = nil
    }
    
    func clearAll() {
        // Release security access for all jobs
        for (_, job) in videoJobs {
            if job.hasSecurityAccess {
                job.url.stopAccessingSecurityScopedResource()
            }
        }
        
        videoJobs.removeAll()
        jobOrder.removeAll()
        completedCount = 0
        lastOutputPath = nil
    }
}

// MARK: - AsyncSemaphore (Cancellation-aware)

actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    
    init(value: Int) {
        self.value = value
    }
    
    func wait() async {
        value -= 1
        if value >= 0 { return }
        
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
    
    func signal() {
        value += 1
        if value <= 0, !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume()
        }
    }
    
    // Allow cancelling all waiters (prevents deadlock on task cancellation)
    func cancelAll() {
        while !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume()
        }
        value = 0
    }
}
