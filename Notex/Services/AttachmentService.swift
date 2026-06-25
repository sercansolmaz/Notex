import Foundation
import AppKit
import UniformTypeIdentifiers
import Vision
import PDFKit

/// Handles arbitrary file attachments (images, PDFs, and other files):
/// copies them into the app's attachments folder, builds inline previews for
/// images, and runs deferred OCR for text extraction.
struct AttachmentService {

    /// Directory where all attachments are stored.
    static var attachmentsFolder: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("Notex/attachments", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    // MARK: - Type detection

    static func isImage(at url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "tiff", "bmp"]
        return imageExts.contains(ext)
    }

    static func isPDF(at url: URL) -> Bool {
        url.pathExtension.lowercased() == "pdf"
    }

    // MARK: - Copy

    /// Copies an arbitrary file into the attachments folder, handling name
    /// collisions by appending a counter. Returns the destination URL.
    static func copyFileToAttachments(from sourceURL: URL) -> URL? {
        // If the file already lives in the attachments folder, return it as-is.
        let folder = attachmentsFolder
        if sourceURL.deletingLastPathComponent().path == folder.path {
            return sourceURL
        }

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        var destURL = ext.isEmpty
            ? folder.appendingPathComponent(baseName)
            : folder.appendingPathComponent("\(baseName).\(ext)")
        var counter = 1
        while FileManager.default.fileExists(atPath: destURL.path) {
            let name = ext.isEmpty
                ? "\(baseName)_\(counter)"
                : "\(baseName)_\(counter).\(ext)"
            destURL = folder.appendingPathComponent(name)
            counter += 1
        }
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            return destURL
        } catch {
            print("⚠️ Attachment copy error: \(error)")
            return nil
        }
    }

    // MARK: - Inline image attachment

    /// Builds an inline `NSAttributedString` containing the image scaled to fit
    /// `maxWidth`, suitable for appending to the editor's attributed string.
    static func inlineImageAttachment(from url: URL, maxWidth: CGFloat = 400) -> NSAttributedString? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        return inlineImageAttachment(image: image, maxWidth: maxWidth, fileName: url.lastPathComponent)
    }

    /// Builds an inline `NSAttributedString` for a given `NSImage`.
    static func inlineImageAttachment(image: NSImage, maxWidth: CGFloat = 400, fileName: String? = nil) -> NSAttributedString {
        let scale = min(1.0, maxWidth / max(image.size.width, 1))
        let displayWidth = image.size.width * scale
        let displayHeight = image.size.height * scale

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: 0, width: displayWidth, height: displayHeight)

        let para = NSMutableParagraphStyle()
        para.alignment = .left

        let attrString = NSMutableAttributedString(attachment: attachment)
        attrString.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: attrString.length))
        return attrString
    }

    // MARK: - OCR (deferred)

    /// Runs Vision OCR on an image file and returns the recognized text.
    static func performImageOCR(on url: URL) async -> String {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["tr-TR", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            request.recognitionLanguages = []
            do {
                try handler.perform([request])
            } catch {
                print("⚠️ Image OCR error: \(error)")
                return ""
            }
        }

        let observations = request.results ?? []
        var text = ""
        for observation in observations {
            if let candidate = observation.topCandidates(1).first {
                text += candidate.string + "\n"
            }
        }
        return text
    }

    /// Queues OCR to run after a delay (simulating idle), invoking the
    /// completion handler on the main actor when finished. Uses a simple
    /// delay-based approach so it doesn't fight the typing debounce.
    static func scheduleIdleOCR(on url: URL, delay: TimeInterval = 30, completion: @escaping @MainActor (String) -> Void) {
        Task {
            // Wait (simulate "idle") before doing heavy OCR work.
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            let ocrText: String
            if isPDF(at: url) {
                ocrText = await PDFService.performOCR(on: url)
            } else if isImage(at: url) {
                ocrText = await performImageOCR(on: url)
            } else {
                ocrText = ""
            }

            await MainActor.run { completion(ocrText) }
        }
    }
}
