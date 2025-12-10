import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = GeneratorViewModel()
    @State private var isDragOver = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Video Grid Generator")
                .font(.title)
                .padding(.top)
            
            // File selection
            fileSelectionView
            
            // Settings
            settingsView
            
            // Action buttons
            actionButtonsView
            
            // Last output
            if let lastOutput = viewModel.lastOutputPath {
                lastOutputView(lastOutput)
            }
            
            // Progress
            if viewModel.isProcessing {
                progressView
            }
            
            Spacer()
        }
        .frame(minWidth: 700, minHeight: 600)
        .padding()
    }
    
    // MARK: - Subviews
    
    private var fileSelectionView: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if viewModel.videoJobs.isEmpty {
                        Text("No videos selected")
                    } else {
                        Text("\(viewModel.videoJobs.count) video\(viewModel.videoJobs.count == 1 ? "" : "s") selected")
                            .font(.headline)
                        ForEach(Array(viewModel.jobOrder.prefix(3)), id: \.self) { jobId in
                            if let job = viewModel.videoJobs[jobId] {
                                Text("• \(job.url.lastPathComponent)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        if viewModel.videoJobs.count > 3 {
                            Text("... and \(viewModel.videoJobs.count - 3) more")
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
                .overlay(
                    DropView(isDragOver: $isDragOver) { urls in
                        viewModel.handleDroppedURLs(urls)
                    }
                )
        }
        .padding(.horizontal)
    }
    
    private var settingsView: some View {
        VStack(spacing: 16) {
            // Output folder selection
            HStack(spacing: 20) {
                Text("Output Folder:")
                    .frame(width: 100, alignment: .trailing)
                
                if let folder = viewModel.outputFolderURL {
                    Text(folder.path)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(5)
                    
                    Button("Change") {
                        viewModel.selectOutputFolder()
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    
                    Button("Clear") {
                        viewModel.clearOutputFolder()
                    }
                    .buttonStyle(BorderlessButtonStyle())
                } else {
                    Text("Same as video (or Downloads if no permission)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Button("Set Output Folder") {
                        viewModel.selectOutputFolder()
                    }
                }
            }
            
            Divider()
            
            // Grid size
            HStack(spacing: 20) {
                Text("Grid Size:")
                    .frame(width: 100, alignment: .trailing)
                
                Stepper("\(viewModel.columns) columns", value: $viewModel.columns, in: 1...10)
                    .frame(width: 150)
                
                Stepper("\(viewModel.rows) rows", value: $viewModel.rows, in: 1...10)
                    .frame(width: 150)
            }
            
            // Target width
            HStack(spacing: 20) {
                Text("Output Width:")
                    .frame(width: 100, alignment: .trailing)
                
                Picker("", selection: $viewModel.targetWidth) {
                    Text("1920px").tag(1920)
                    Text("2560px").tag(2560)
                    Text("3000px").tag(3000)
                    Text("3840px (4K)").tag(3840)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 400)
            }
            
            // Aspect mode
            HStack(spacing: 20) {
                Text("Aspect Mode:")
                    .frame(width: 100, alignment: .trailing)
                
                Picker("", selection: $viewModel.aspectMode) {
                    ForEach(AspectMode.allCases, id: \.rawValue) { mode in
                        Text(mode.rawValue).tag(mode.rawValue)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 300)
            }
            
            // Background theme
            HStack(spacing: 20) {
                Text("Background:")
                    .frame(width: 100, alignment: .trailing)
                
                Picker("", selection: $viewModel.backgroundTheme) {
                    ForEach(BackgroundTheme.allCases, id: \.rawValue) { theme in
                        Text(theme.rawValue).tag(theme.rawValue)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 200)
            }
            
            // Options
            HStack(spacing: 20) {
                Text("Options:")
                    .frame(width: 100, alignment: .trailing)
                
                Toggle("Show Timestamps", isOn: $viewModel.showTimestamps)
                
                Spacer()
                
                Stepper("Process \(viewModel.maxConcurrent) at once", value: $viewModel.maxConcurrent, in: 1...10)
                    .frame(width: 200)
            }
        }
        .padding(.horizontal)
    }
    
    private var actionButtonsView: some View {
        HStack(spacing: 16) {
            Button("Generate Grids") {
                viewModel.generateGrids()
            }
            .disabled(viewModel.videoJobs.isEmpty || viewModel.isProcessing)
            .padding()
            .background(viewModel.videoJobs.isEmpty || viewModel.isProcessing ? Color.gray : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            
            if viewModel.isProcessing {
                Button("Cancel") {
                    viewModel.cancelGeneration()
                }
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            
            if !viewModel.videoJobs.isEmpty && !viewModel.isProcessing {
                Button("Clear Completed") {
                    viewModel.clearCompleted()
                }
                .padding()
                .background(Color.secondary)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
    }
    
    private func lastOutputView(_ path: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last Output:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Text(path)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Button("Reveal") {
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                }
                .buttonStyle(BorderlessButtonStyle())
                .font(.caption)
            }
        }
        .padding(8)
        .background(Color.green.opacity(0.1))
        .cornerRadius(5)
        .padding(.horizontal)
    }
    
    private var progressView: some View {
        VStack(spacing: 12) {
            Text("Processing: \(viewModel.completedCount) of \(viewModel.videoJobs.count) completed")
                .font(.headline)
            
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(viewModel.jobOrder, id: \.self) { jobId in
                        if let job = viewModel.videoJobs[jobId], !job.isComplete {
                            jobProgressView(job)
                        }
                    }
                    
                    // Completed jobs with output paths
                    ForEach(viewModel.jobOrder, id: \.self) { jobId in
                        if let job = viewModel.videoJobs[jobId], job.isComplete {
                            completedJobView(job)
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
            .padding(.horizontal)
        }
    }
    
    private func jobProgressView(_ job: VideoJob) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(job.url.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Text("\(Int(job.progress * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: job.progress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle())
            
            Text(job.status)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(5)
    }
    
    private func completedJobView(_ job: VideoJob) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(job.url.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                if job.isCancelled {
                    Text("Cancelled")
                        .font(.caption2)
                        .foregroundColor(.orange)
                } else {
                    Text("✓ Complete")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            
            if let outputPath = job.outputPath {
                HStack {
                    Text(outputPath)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Button("Reveal") {
                        NSWorkspace.shared.selectFile(outputPath, inFileViewerRootedAtPath: "")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .font(.caption2)
                }
            }
        }
        .padding(8)
        .background(Color.green.opacity(0.05))
        .cornerRadius(5)
    }
    
    // MARK: - Actions
    
    private func selectVideoFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.message = "Select video files or folders"
        
        // Request read/write access
        panel.canCreateDirectories = false
        
        if panel.runModal() == .OK {
            // Store security-scoped bookmarks for write access
            var urlsWithAccess: [URL] = []
            
            for url in panel.urls {
                // For files, we need the parent directory bookmark
                let bookmarkURL = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
                
                do {
                    // Create security-scoped bookmark
                    let bookmarkData = try bookmarkURL.bookmarkData(
                        options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    
                    // Resolve bookmark to maintain access
                    var isStale = false
                    let resolvedURL = try URL(
                        resolvingBookmarkData: bookmarkData,
                        options: .withSecurityScope,
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )
                    
                    _ = resolvedURL.startAccessingSecurityScopedResource()
                    urlsWithAccess.append(url)
                } catch {
                    print("⚠️ Could not create bookmark for \(bookmarkURL.path): \(error)")
                    urlsWithAccess.append(url)
                }
            }
            
            viewModel.handleDroppedURLs(urlsWithAccess)
        }
    }
}
