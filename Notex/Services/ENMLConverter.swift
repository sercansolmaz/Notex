import AppKit
import Foundation

/// Converts Evernote EN-ML (XML) content to NSAttributedString.
/// Uses a regex-based approach for robustness — strips tags and decodes entities.
final class ENMLConverter: @unchecked Sendable {
    static let shared = ENMLConverter()

    private init() {}

    func convert(enml: String) -> NSAttributedString {
        var text = enml

        // Replace block elements with newlines
        let blockReplacements: [(String, String)] = [
            ("</div>", "\n"),
            ("</p>", "\n"),
            ("<br>", "\n"),
            ("<br/>", "\n"),
            ("<br />", "\n"),
            ("</li>", "\n"),
            ("<li>", "\n• "),
        ]
        for (tag, replacement) in blockReplacements {
            text = text.replacingOccurrences(of: tag, with: replacement, options: .caseInsensitive)
        }

        // Replace opening div/p tags with nothing (their closing tags already added newlines)
        text = text.replacingOccurrences(of: "<div[^>]*>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<p[^>]*>", with: "", options: .regularExpression)

        // Apply basic formatting via regex
        // Bold: <b>...</b> or <strong>...</strong>
        let boldFont = NSFont.boldSystemFont(ofSize: 14)
        let regularFont = NSFont.systemFont(ofSize: 14)
        let italicFont = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 14), toHaveTrait: .italicFontMask)

        // Build attributed string with basic formatting
        let result = NSMutableAttributedString()

        // First, strip all remaining tags but track bold/italic
        var remaining = text
        while !remaining.isEmpty {
            if let openRange = remaining.range(of: "<") {
                // Text before the tag
                let beforeTag = String(remaining[remaining.startIndex..<openRange.lowerBound])
                if !beforeTag.isEmpty {
                    result.append(NSAttributedString(string: beforeTag, attributes: [.font: regularFont]))
                }

                // Find closing >
                guard let closeRange = remaining.range(of: ">", range: openRange.upperBound..<remaining.endIndex) else {
                    // No closing >, append rest as text
                    result.append(NSAttributedString(string: String(remaining[openRange.lowerBound...]), attributes: [.font: regularFont]))
                    break
                }

                let tagName = String(remaining[openRange.upperBound..<closeRange.lowerBound]).lowercased()
                remaining = String(remaining[closeRange.upperBound...])

                // Handle specific tags
                if tagName.hasPrefix("b") || tagName.hasPrefix("strong") {
                    // Find closing tag
                    if let closeTag = findClosingTag(remaining, tagName: tagName.hasPrefix("b") ? "b" : "strong") {
                        let inner = String(remaining[remaining.startIndex..<closeTag.lowerBound])
                        result.append(NSAttributedString(string: stripTags(inner), attributes: [.font: boldFont]))
                        remaining = String(remaining[closeTag.upperBound...])
                    }
                } else if tagName.hasPrefix("i") || tagName.hasPrefix("em") {
                    if let closeTag = findClosingTag(remaining, tagName: tagName.hasPrefix("i") ? "i" : "em") {
                        let inner = String(remaining[remaining.startIndex..<closeTag.lowerBound])
                        result.append(NSAttributedString(string: stripTags(inner), attributes: [.font: italicFont]))
                        remaining = String(remaining[closeTag.upperBound...])
                    }
                }
                // Other tags: just skip (already stripped)
            } else {
                // No more tags
                result.append(NSAttributedString(string: remaining, attributes: [.font: regularFont]))
                break
            }
        }

        // Decode HTML entities
        let decoded = decodeHTMLEntities(result.string)
        return NSAttributedString(string: decoded, attributes: [.font: regularFont])
    }

    private func findClosingTag(_ text: String, tagName: String) -> Range<String.Index>? {
        let closeTag = "</\(tagName)>"
        return text.range(of: closeTag, options: .caseInsensitive)
    }

    private func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    private func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&nbsp;", " "),
            ("&#39;", "'"),
            ("&apos;", "'"),
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }
}
