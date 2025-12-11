import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = GeneratorViewModel()
    @State private var isDragOver = false
    
    var body: some View {
        HSplitView {
            // Left side: Main controls (75%)
            VStack(spacing: 20) {
                Text("Video Grid Generator")
                    .font(.title)
                    .padding(.top)
                
                // INPUT SECTION
                VStack(alignment: .leading, spacing: 12) {
                    Text("Input")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    fileSelectionView
                }
                
                Divider()
                
                // OUTPUT SECTION
                VStack(alignment: .leading, spacing: 12) {
                    Text("Output")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    outputFolderView
                }
                
                Divider()
                
                // GRID SECTION
                VStack(alignment: .leading, spacing: 12) {
                    Text("Grid")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    gridSettingsView
                }
                
                Divider()
                
                // OPTIONS SECTION
                VStack(alignment: .leading, spacing: 12) {
                    Text("Options")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    optionsView
                }
                
                Divider()
                
                // Action buttons
                actionButtonsView
                
                // Last output - only show when not processing and has output
                if !viewModel.isProcessing, let lastOutput = viewModel.lastOutputPath {
                    lastOutputView(lastOutput)
                }
                
                Spacer()
            }
            .frame(minWidth: 500)
            .padding()
            
            // Right side: Progress view (25%)
            VStack(spacing: 12) {
                HStack {
                    Text("Processing Queue")
                        .font(.headline)
                    Spacer()
                    if !viewModel.videoJobs.isEmpty && !viewModel.isProcessing {
                        Button("Clear Completed") {
                            viewModel.clearCompleted()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
                .padding(.horizontal)
                .padding(.top)
                
                if viewModel.isProcessing {
                    Text("\(viewModel.completedCount) of \(viewModel.videoJobs.count) completed")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                if viewModel.videoJobs.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 48))
                            .foregroundColor(.accentColor.opacity(0.5))
                        Text("No videos selected")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            // Active jobs
                            ForEach(viewModel.jobOrder, id: \.self) { jobId in
                                if let job = viewModel.videoJobs[jobId], !job.isComplete {
                                    jobProgressView(job)
                                }
                            }
                            
                            // Completed jobs
                            ForEach(viewModel.jobOrder, id: \.self) { jobId in
                                if let job = viewModel.videoJobs[jobId], job.isComplete {
                                    completedJobView(job)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                Spacer()
            }
            .frame(minWidth: 250, maxWidth: 400)
            .background(Color.gray.opacity(0.05))
        }
        .frame(minWidth: 900, minHeight: 600)
    }
    
    // MARK: - Subviews
    
    private var fileSelectionView: some View {
        VStack(spacing: 8) {
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
                
                VStack(spacing: 8) {
                    Button("Choose Files") {
                        selectVideoFiles()
                    }
                    .buttonStyle(.bordered)
                    
                    if !viewModel.videoJobs.isEmpty {
                        Button("Clear All") {
                            viewModel.clearAll()
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.secondary)
                    }
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
                        .foregroundColor(isDragOver ? .accentColor : .gray.opacity(0.5))
                )
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isDragOver ? Color.accentColor.opacity(0.1) : Color.clear)
                )
                .overlay(
                    DropView(isDragOver: $isDragOver) { urls in
                        viewModel.handleDroppedURLs(urls)
                    }
                )
        }
    }
    
    private var outputFolderView: some View {
        HStack(spacing: 12) {
            if let folder = viewModel.outputFolderURL {
                VStack(alignment: .leading, spacing: 4) {
                    Text(folder.lastPathComponent)
                        .font(.subheadline)
                    Text(folder.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(5)
                
                Button("Change") {
                    viewModel.selectOutputFolder()
                }
                .buttonStyle(.bordered)
                
                Button("Clear") {
                    viewModel.clearOutputFolder()
                }
                .buttonStyle(.borderless)
            } else {
                Text("Same as video (or Downloads if no permission)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Button("Set Output Folder") {
                    viewModel.selectOutputFolder()
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
    private var gridSettingsView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                Stepper("\(viewModel.columns) columns", value: $viewModel.columns, in: 1...10)
                    .frame(width: 150)
                
                Stepper("\(viewModel.rows) rows", value: $viewModel.rows, in: 1...10)
                    .frame(width: 150)
            }
            
            Picker("Output Width", selection: $viewModel.targetWidth) {
                Text("1920px").tag(1920)
                Text("2560px").tag(2560)
                Text("3000px").tag(3000)
                Text("3840px (4K)").tag(3840)
            }
            .pickerStyle(SegmentedPickerStyle())
        }
    }
    
    private var optionsView: some View {
        VStack(spacing: 12) {
            Picker("Aspect", selection: $viewModel.aspectMode) {
                ForEach(AspectMode.allCases, id: \.rawValue) { mode in
                    Text(mode.rawValue).tag(mode.rawValue)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            
            Picker("Background", selection: $viewModel.backgroundTheme) {
                ForEach(BackgroundTheme.allCases, id: \.rawValue) { theme in
                    Text(theme.rawValue).tag(theme.rawValue)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            
            HStack {
                Toggle("Show Timestamps", isOn: $viewModel.showTimestamps)
                
                Spacer()
                
                Stepper("Process \(viewModel.maxConcurrent) at once", value: $viewModel.maxConcurrent, in: 1...10)
                    .frame(width: 220)
            }
        }
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
            .buttonStyle(.borderedProminent)
            
            if viewModel.isProcessing {
                Button("Cancel") {
                    viewModel.cancelGeneration()
                }
                .buttonStyle(.bordered)
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
    
    private func jobProgressView(_ job: VideoJob) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(truncateFilename(job.url.lastPathComponent, maxLength: 45))
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
                Text(truncateFilename(job.url.lastPathComponent, maxLength: 45))
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
                    Text(truncatePath(outputPath))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
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
    
    // Helper function to truncate filenames intelligently
    private func truncateFilename(_ filename: String, maxLength: Int) -> String {
        if filename.count <= maxLength {
            return filename
        }
        
        // Try to preserve extension
        let components = filename.split(separator: ".")
        if components.count > 1, let ext = components.last {
            let nameWithoutExt = components.dropLast().joined(separator: ".")
            let truncated = String(nameWithoutExt.prefix(maxLength - Int(ext.count) - 4)) + "..."
            return truncated + ".\(ext)"
        }
        
        return String(filename.prefix(maxLength - 3)) + "..."
    }
    
    // Helper function to truncate paths to ~/folder/file format
    private func truncatePath(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let filename = url.lastPathComponent
        let parentFolder = url.deletingLastPathComponent().lastPathComponent
        
        // Show as ~/ParentFolder/filename.jpg
        return "~/\(parentFolder)/\(filename)"
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
