import Foundation
import PDFKit
import Vision
import CoreData
import AppKit

/// Handles PDF attachment copying and Vision-based OCR text extraction.
struct PDFService {

    /// Directory where PDF attachments are stored.
    static var attachmentsFolder: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("Notex/attachments", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    // MARK: - Copy PDF

    /// Copies a PDF from the given source URL into the app's attachments folder.
    /// Handles name collisions by appending a counter. Returns the destination URL.
    static func copyPDFToAttachments(from sourceURL: URL) -> URL? {
        let folder = attachmentsFolder
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        var destURL = folder.appendingPathComponent("\(baseName).pdf")
        var counter = 1
        while FileManager.default.fileExists(atPath: destURL.path) {
            destURL = folder.appendingPathComponent("\(baseName)_\(counter).pdf")
            counter += 1
        }
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            return destURL
        } catch {
            print("⚠️ PDF copy error: \(error)")
            return nil
        }
    }

    // MARK: - OCR

    /// Performs OCR on all pages of a PDF using the Vision framework.
    /// Renders each page to an image at 2x resolution, then runs text recognition.
    /// Runs on a background priority — call from an async context.
    static func performOCR(on pdfURL: URL) async -> String {
        guard let pdfDoc = PDFDocument(url: pdfURL) else { return "" }
        var fullText = ""

        for i in 0..<pdfDoc.pageCount {
            guard let page = pdfDoc.page(at: i) else { continue }
            let pageRect = page.bounds(for: .mediaBox)

            // Render page to a high-resolution NSImage for better OCR accuracy
            let scale: CGFloat = 2.0
            let renderSize = NSSize(width: pageRect.width * scale, height: pageRect.height * scale)
            let thumbnail = page.thumbnail(of: renderSize, for: .mediaBox)

            guard let cgImage = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                continue
            }

            // Run Vision text recognition
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // Try Turkish + English; falls back gracefully if unsupported
            request.recognitionLanguages = ["tr-TR", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                // Retry with default languages only
                request.recognitionLanguages = []
                do {
                    try handler.perform([request])
                } catch {
                    print("⚠️ Vision OCR error on page \(i): \(error)")
                    continue
                }
            }

            let observations = request.results ?? []
            var pageText = ""
            for observation in observations {
                if let candidate = observation.topCandidates(1).first {
                    pageText += candidate.string + "\n"
                }
            }
            if !pageText.isEmpty {
                fullText += "--- Sayfa \(i + 1) ---\n\(pageText)\n"
            }
        }

        return fullText
    }
}
