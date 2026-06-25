import AppKit
import CoreData

/// Native macOS share sheet for sharing notes via Messages, Mail, AirDrop, etc.
struct ShareService {

    /// Presents the native macOS sharing picker for the given note, sharing the
    /// note's title and plain text content. Must be called on the main thread.
    @MainActor
    static func shareNote(_ note: Note) {
        let title = note.title ?? ""
        let content = note.plainText ?? ""
        let combined: String
        if title.isEmpty {
            combined = content
        } else {
            combined = "\(title)\n\n\(content)"
        }

        let items: [Any] = [combined]
        let sharingServicePicker = NSSharingServicePicker(items: items)

        guard let window = NSApp.keyWindow,
              let contentView = window.contentView else {
            return
        }
        sharingServicePicker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
    }
}
