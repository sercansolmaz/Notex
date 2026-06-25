import SwiftUI
import PDFKit

/// NSViewRepresentable wrapping PDFKit's PDFView for inline PDF preview
/// in the note editor. Configurable height, scrollable.
struct PDFPreviewView: NSViewRepresentable {
    let pdfURL: URL
    var height: CGFloat = 300

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = PDFDocument(url: pdfURL)
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.minScaleFactor = 0.3
        pdfView.maxScaleFactor = 3.0
        pdfView.backgroundColor = NSColor.controlBackgroundColor
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        // Update document if URL changed
        if nsView.document?.documentURL != pdfURL {
            nsView.document = PDFDocument(url: pdfURL)
        }
    }
}
