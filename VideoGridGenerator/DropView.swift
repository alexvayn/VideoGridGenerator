import SwiftUI
import AppKit

// AppKit-based drop view that preserves security-scoped access
struct DropView: NSViewRepresentable {
    @Binding var isDragOver: Bool
    let onDrop: ([URL]) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = DropTargetView()
        view.onDragEntered = { isDragOver = true }
        view.onDragExited = { isDragOver = false }
        view.onDrop = { urls in
            isDragOver = false
            onDrop(urls)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

class DropTargetView: NSView {
    var onDragEntered: (() -> Void)?
    var onDragExited: (() -> Void)?
    var onDrop: (([URL]) -> Void)?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEntered?()
        return .copy
    }
    
    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExited?()
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return false
        }
        
        // Start accessing security-scoped resources immediately
        var accessibleURLs: [URL] = []
        for url in urls {
            let hasAccess = url.startAccessingSecurityScopedResource()
            print("🔐 Drag & Drop: \(url.lastPathComponent), security access: \(hasAccess)")
            accessibleURLs.append(url)
        }
        
        onDrop?(accessibleURLs)
        return true
    }
}
