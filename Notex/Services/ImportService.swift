import CoreData
import Foundation
import UniformTypeIdentifiers

/// Imports notes from MD, TXT, and ENEX files.
final class ImportService: @unchecked Sendable {
    static let shared = ImportService()

    private init() {}

    func importFile(at url: URL, into context: NSManagedObjectContext, notebook: Notebook? = nil) -> [Note] {
        guard let data = try? Data(contentsOf: url) else {
            print("⚠️ Import: Could not read file at \(url.path)")
            return []
        }

        let ext = url.pathExtension.lowercased()
        switch ext {
        case "txt":
            if let note = importText(data: data, fileName: url.deletingPathExtension().lastPathComponent, context: context, notebook: notebook) {
                return [note]
            }
        case "md", "markdown":
            if let note = importMarkdown(data: data, fileName: url.deletingPathExtension().lastPathComponent, context: context, notebook: notebook) {
                return [note]
            }
        case "enex":
            let parser = ENEXParser()
            return parser.parse(data: data, context: context, notebook: notebook)
        default:
            print("⚠️ Import: Unsupported file type .\(ext)")
        }

        return []
    }

    // MARK: - TXT

    private func importText(data: Data, fileName: String, context: NSManagedObjectContext, notebook: Notebook?) -> Note? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let note = Note(context: context)
        note.uuid = UUID().uuidString
        note.title = fileName
        note.plainText = text
        note.content = Note.encodeAttributedString(NSAttributedString(string: text))
        note.createdAt = Date()
        note.updatedAt = Date()
        note.notebook = notebook

        if let uuid = note.uuid {
            FTS5Manager.shared.indexNote(uuid: uuid, title: fileName, content: text)
        }
        return note
    }

    // MARK: - Markdown

    private func importMarkdown(data: Data, fileName: String, context: NSManagedObjectContext, notebook: Notebook?) -> Note? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let note = Note(context: context)
        note.uuid = UUID().uuidString

        var title = fileName
        var content = text
        let lines = text.components(separatedBy: .newlines)
        if let firstLine = lines.first, firstLine.hasPrefix("# ") {
            title = String(firstLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            content = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let attrString = NSAttributedString(string: content)
        note.title = title
        note.plainText = content
        note.content = Note.encodeAttributedString(attrString)
        note.createdAt = Date()
        note.updatedAt = Date()
        note.notebook = notebook

        if let uuid = note.uuid {
            FTS5Manager.shared.indexNote(uuid: uuid, title: title, content: content)
        }
        return note
    }
}