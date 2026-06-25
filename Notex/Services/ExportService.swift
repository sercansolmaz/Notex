import AppKit
import Foundation

/// Exports notes to PDF, RTF, HTML, and Markdown formats.
@MainActor
final class ExportService {
    static let shared = ExportService()

    enum ExportFormat: String, CaseIterable, Identifiable {
        case markdown = "Markdown (.md)"
        case html = "HTML (.html)"
        case pdf = "PDF (.pdf)"
        case rtf = "RTF (.rtf)"

        var id: String { rawValue }
        var fileExtension: String {
            switch self {
            case .markdown: return "md"
            case .html: return "html"
            case .pdf: return "pdf"
            case .rtf: return "rtf"
            }
        }
    }

    private init() {}

    func exportNote(_ note: Note, as format: ExportFormat, to url: URL) -> Bool {
        switch format {
        case .markdown: return exportAsMarkdown(note, to: url)
        case .html: return exportAsHTML(note, to: url)
        case .pdf: return exportAsPDF(note, to: url)
        case .rtf: return exportAsRTF(note, to: url)
        }
    }

    // MARK: - Helpers

    private func getAttributedString(_ note: Note) -> NSAttributedString {
        if let data = note.content {
            return Note.decodeAttributedString(from: data)
        }
        return NSAttributedString(string: note.plainText ?? "")
    }

    // MARK: - Markdown

    private func exportAsMarkdown(_ note: Note, to url: URL) -> Bool {
        let title = note.displayTitle
        let content = note.plainText ?? ""
        let markdown = "# \(title)\n\n\(content)"
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            print("⚠️ Markdown export error: \(error)")
            return false
        }
    }

    // MARK: - HTML

    private func exportAsHTML(_ note: Note, to url: URL) -> Bool {
        let attrString = getAttributedString(note)
        do {
            let htmlData = try attrString.data(
                from: NSRange(location: 0, length: attrString.length),
                documentAttributes: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ]
            )
            try htmlData.write(to: url)
            return true
        } catch {
            print("⚠️ HTML export error: \(error)")
            return false
        }
    }

    // MARK: - RTF

    private func exportAsRTF(_ note: Note, to url: URL) -> Bool {
        let attrString = getAttributedString(note)
        do {
            let rtfData = try attrString.data(
                from: NSRange(location: 0, length: attrString.length),
                documentAttributes: [
                    .documentType: NSAttributedString.DocumentType.rtf
                ]
            )
            try rtfData.write(to: url)
            return true
        } catch {
            print("⚠️ RTF export error: \(error)")
            return false
        }
    }

    // MARK: - PDF

    private func exportAsPDF(_ note: Note, to url: URL) -> Bool {
        let attrString = getAttributedString(note)

        let pageWidth: CGFloat = 612
        let margin: CGFloat = 50
        let contentWidth = pageWidth - 2 * margin

        let textStorage = NSTextStorage(attributedString: attrString)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(containerSize: NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)

        let totalHeight = max(792, usedRect.height + 2 * margin)

        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: totalHeight))
        let textView = NSTextView(frame: NSRect(x: margin, y: totalHeight - usedRect.height - margin, width: contentWidth, height: usedRect.height + margin), textContainer: textContainer)
        textView.drawsBackground = false
        textView.isEditable = false
        containerView.addSubview(textView)

        let pdfData = containerView.dataWithPDF(inside: containerView.bounds)
        do {
            try pdfData.write(to: url)
            return true
        } catch {
            print("⚠️ PDF export error: \(error)")
            return false
        }
    }
}
