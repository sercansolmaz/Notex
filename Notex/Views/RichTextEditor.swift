import SwiftUI
import AppKit

// MARK: - EditorTextView

/// Custom NSTextView with suppressNextChange flag to prevent infinite save loops
/// and checkbox toggle support.
final class EditorTextView: NSTextView {
    var suppressNextChange = false

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndex(for: point)
        if charIndex != NSNotFound {
            let nsString = string as NSString
            let lineRange = nsString.lineRange(for: NSRange(location: charIndex, length: 0))
            let line = nsString.substring(with: lineRange)

            if line.contains("- [ ]") {
                let markerRange = nsString.range(of: "- [ ]", options: [], range: lineRange)
                if markerRange.location != NSNotFound {
                    textStorage?.replaceCharacters(in: markerRange, with: "- [x]")
                    didChangeText()
                    return
                }
            } else if line.contains("- [x]") {
                let markerRange = nsString.range(of: "- [x]", options: [], range: lineRange)
                if markerRange.location != NSNotFound {
                    textStorage?.replaceCharacters(in: markerRange, with: "- [ ]")
                    didChangeText()
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }

    // MARK: - Table Insertion

    /// Inserts an editable text table at the current cursor position using
    /// NSTextTable + NSTextTableBlock. Cells are navigable with Tab.
    func insertTable(rows: Int, columns: Int) {
        guard let storage = textStorage else { return }

        let table = NSTextTable()
        table.numberOfColumns = columns
        table.collapsesBorders = true

        let font = self.font ?? NSFont.systemFont(ofSize: 14)
        let mutable = NSMutableAttributedString()

        for row in 0..<rows {
            for col in 0..<columns {
                let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: col, columnSpan: 1)

                let paraStyle = NSMutableParagraphStyle()
                paraStyle.textBlocks = [block]

                let placeholder = NSAttributedString(
                    string: " ",
                    attributes: [.font: font, .paragraphStyle: paraStyle]
                )
                mutable.append(placeholder)

                // Tab between columns
                if col < columns - 1 {
                    mutable.append(NSAttributedString(string: "\t"))
                }
            }
            // Newline between rows
            if row < rows - 1 {
                mutable.append(NSAttributedString(string: "\n"))
            }
        }

        let insertLocation = selectedRange.location
        storage.insert(mutable, at: insertLocation)
        didChangeText()
    }
}

// MARK: - EditorController

/// Bridges formatting commands from SwiftUI toolbar to the NSTextView.
final class EditorController: ObservableObject {
    weak var textView: EditorTextView?

    func toggleBold() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange
        let baseSize = tv.font?.pointSize ?? 14

        if range.length == 0 {
            let current = tv.typingAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: baseSize)
            let isBold = current.fontDescriptor.symbolicTraits.contains(.bold)
            let newFont = isBold
                ? NSFontManager.shared.convert(current, toNotHaveTrait: .boldFontMask)
                : NSFontManager.shared.convert(current, toHaveTrait: .boldFontMask)
            tv.typingAttributes[.font] = newFont
        } else {
            storage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
                let current = (value as? NSFont) ?? NSFont.systemFont(ofSize: baseSize)
                let isBold = current.fontDescriptor.symbolicTraits.contains(.bold)
                let newFont = isBold
                    ? NSFontManager.shared.convert(current, toNotHaveTrait: .boldFontMask)
                    : NSFontManager.shared.convert(current, toHaveTrait: .boldFontMask)
                storage.addAttribute(.font, value: newFont, range: attrRange)
            }
        }
        tv.didChangeText()
    }

    func toggleItalic() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange
        let baseSize = tv.font?.pointSize ?? 14

        if range.length == 0 {
            let current = tv.typingAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: baseSize)
            let isItalic = current.fontDescriptor.symbolicTraits.contains(.italic)
            let newFont = isItalic
                ? NSFontManager.shared.convert(current, toNotHaveTrait: .italicFontMask)
                : NSFontManager.shared.convert(current, toHaveTrait: .italicFontMask)
            tv.typingAttributes[.font] = newFont
        } else {
            storage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
                let current = (value as? NSFont) ?? NSFont.systemFont(ofSize: baseSize)
                let isItalic = current.fontDescriptor.symbolicTraits.contains(.italic)
                let newFont = isItalic
                    ? NSFontManager.shared.convert(current, toNotHaveTrait: .italicFontMask)
                    : NSFontManager.shared.convert(current, toHaveTrait: .italicFontMask)
                storage.addAttribute(.font, value: newFont, range: attrRange)
            }
        }
        tv.didChangeText()
    }

    func toggleUnderline() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange
        guard range.length > 0 else { return }
        let attrs = storage.attributes(at: range.location, longestEffectiveRange: nil, in: range)
        let current = (attrs[.underlineStyle] as? Int) ?? 0
        let newStyle: Int = current == 0 ? NSUnderlineStyle.single.rawValue : 0
        storage.addAttribute(.underlineStyle, value: newStyle, range: range)
        tv.didChangeText()
    }

    func toggleStrikethrough() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange
        guard range.length > 0 else { return }
        let attrs = storage.attributes(at: range.location, longestEffectiveRange: nil, in: range)
        let current = (attrs[.strikethroughStyle] as? Int) ?? 0
        let newStyle: Int = current == 0 ? NSUnderlineStyle.single.rawValue : 0
        storage.addAttribute(.strikethroughStyle, value: newStyle, range: range)
        tv.didChangeText()
    }

    func toggleBulletList() {
        guard let tv = textView else { return }
        let range = tv.selectedRange
        let nsString = tv.string as NSString
        let lineRange = nsString.lineRange(for: range)
        let line = nsString.substring(with: lineRange)
        if line.hasPrefix("- ") {
            tv.textStorage?.replaceCharacters(in: lineRange, with: String(line.dropFirst(2)))
        } else {
            tv.textStorage?.replaceCharacters(in: lineRange, with: "- " + line)
        }
        tv.didChangeText()
    }

    func toggleCheckbox() {
        guard let tv = textView else { return }
        let range = tv.selectedRange
        let nsString = tv.string as NSString
        let lineRange = nsString.lineRange(for: range)
        let line = nsString.substring(with: lineRange)
        if line.hasPrefix("- [ ] ") {
            tv.textStorage?.replaceCharacters(in: lineRange, with: "- [x] " + String(line.dropFirst(6)))
        } else if line.hasPrefix("- [x] ") {
            tv.textStorage?.replaceCharacters(in: lineRange, with: "- [ ] " + String(line.dropFirst(6)))
        } else if line.hasPrefix("- ") {
            tv.textStorage?.replaceCharacters(in: lineRange, with: "- [ ] " + String(line.dropFirst(2)))
        } else {
            tv.textStorage?.replaceCharacters(in: lineRange, with: "- [ ] " + line)
        }
        tv.didChangeText()
    }

    func insertWikiLink() {
        guard let tv = textView else { return }
        let range = tv.selectedRange
        if range.length > 0 {
            let selectedText = (tv.string as NSString).substring(with: range)
            tv.textStorage?.replaceCharacters(in: range, with: "[[\(selectedText)]]")
        } else {
            tv.textStorage?.replaceCharacters(in: range, with: "[[]]")
            tv.selectedRange = NSRange(location: range.location + 2, length: 0)
        }
        tv.didChangeText()
    }

    func insertTable(rows: Int, columns: Int) {
        guard let tv = textView else { return }
        tv.insertTable(rows: rows, columns: columns)
    }

    // MARK: - Highlight

    /// Applies (or removes) a background color highlight on the selected range.
    /// If the selection is empty, it toggles the typing-attribute so the next
    /// typed characters are highlighted.
    func toggleHighlight(color: NSColor) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange

        if range.length == 0 {
            // Toggle typing attribute
            if let current = tv.typingAttributes[.backgroundColor] as? NSColor,
               current.isEqual(to: color) {
                tv.typingAttributes.removeValue(forKey: .backgroundColor)
            } else {
                tv.typingAttributes[.backgroundColor] = color
            }
        } else {
            storage.addAttribute(.backgroundColor, value: color, range: range)
        }
        tv.didChangeText()
    }

    /// Clears any background highlight on the selected range (or typing attribute).
    func removeHighlight() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange
        if range.length == 0 {
            tv.typingAttributes.removeValue(forKey: .backgroundColor)
        } else {
            storage.removeAttribute(.backgroundColor, range: range)
        }
        tv.didChangeText()
    }

    // MARK: - Quote Block

    /// Toggles a "quote block" style on the selected paragraph(s):
    /// light gray background + 20pt left indent + italic font.
    func toggleQuoteBlock() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let nsString = tv.string as NSString
        let selectedRange = tv.selectedRange
        let paraRange = nsString.paragraphRange(for: selectedRange)
        let baseSize = tv.font?.pointSize ?? 14

        // Determine current state by checking if already has the quote indent
        let currentPara = storage.attribute(.paragraphStyle, at: paraRange.location,
                                            longestEffectiveRange: nil, in: paraRange) as? NSParagraphStyle
        let isQuote = (currentPara?.headIndent ?? 0) >= 20

        storage.beginEditing()
        if isQuote {
            // Remove quote styling
            storage.removeAttribute(.backgroundColor, range: paraRange)
            // Restore default paragraph style (remove indent)
            storage.enumerateAttribute(.paragraphStyle, in: paraRange, options: []) { value, attrRange, _ in
                let mutable = NSMutableParagraphStyle()
                if let existing = value as? NSParagraphStyle {
                    mutable.setParagraphStyle(existing)
                }
                mutable.headIndent = 0
                mutable.firstLineHeadIndent = 0
                storage.addAttribute(.paragraphStyle, value: mutable, range: attrRange)
            }
            // Restore non-italic font
            storage.enumerateAttribute(.font, in: paraRange, options: []) { value, attrRange, _ in
                let current = (value as? NSFont) ?? NSFont.systemFont(ofSize: baseSize)
                if current.fontDescriptor.symbolicTraits.contains(.italic) {
                    let newFont = NSFontManager.shared.convert(current, toNotHaveTrait: .italicFontMask)
                    storage.addAttribute(.font, value: newFont, range: attrRange)
                }
            }
        } else {
            // Apply quote styling
            storage.addAttribute(.backgroundColor,
                                 value: NSColor.controlBackgroundColor,
                                 range: paraRange)
            storage.enumerateAttribute(.paragraphStyle, in: paraRange, options: []) { value, attrRange, _ in
                let mutable = NSMutableParagraphStyle()
                if let existing = value as? NSParagraphStyle {
                    mutable.setParagraphStyle(existing)
                }
                mutable.headIndent = 20
                mutable.firstLineHeadIndent = 20
                storage.addAttribute(.paragraphStyle, value: mutable, range: attrRange)
            }
            storage.enumerateAttribute(.font, in: paraRange, options: []) { value, attrRange, _ in
                let current = (value as? NSFont) ?? NSFont.systemFont(ofSize: baseSize)
                if !current.fontDescriptor.symbolicTraits.contains(.italic) {
                    let newFont = NSFontManager.shared.convert(current, toHaveTrait: .italicFontMask)
                    storage.addAttribute(.font, value: newFont, range: attrRange)
                }
            }
        }
        storage.endEditing()
        tv.didChangeText()
    }

    // MARK: - Code Block

    /// Toggles a "code block" style on the selected paragraph(s):
    /// monospace font + gray background + slightly smaller size.
    func toggleCodeBlock() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let nsString = tv.string as NSString
        let selectedRange = tv.selectedRange
        let paraRange = nsString.paragraphRange(for: selectedRange)

        // Check current state by examining the font at paragraph start
        let currentFont = storage.attribute(.font, at: paraRange.location,
                                            longestEffectiveRange: nil, in: paraRange) as? NSFont
        let isMono = currentFont?.fontName.contains("Menlo") == true ||
                     currentFont?.fontName.contains("Monaco") == true ||
                     currentFont?.fontName.contains("Courier") == true

        let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        storage.beginEditing()
        if isMono {
            // Revert to system font
            storage.removeAttribute(.backgroundColor, range: paraRange)
            storage.addAttribute(.font,
                                 value: NSFont.systemFont(ofSize: 14),
                                 range: paraRange)
        } else {
            storage.addAttribute(.backgroundColor,
                                 value: NSColor(white: 0.92, alpha: 1.0),
                                 range: paraRange)
            storage.addAttribute(.font, value: monoFont, range: paraRange)
        }
        storage.endEditing()
        tv.didChangeText()
    }
}

// MARK: - RichTextEditor (NSViewRepresentable)

struct RichTextEditor: NSViewRepresentable {
    @Binding var attributedString: NSAttributedString
    var fontSize: Double
    var lineSpacing: Double
    var fontFamily: FontFamilyOption = .system
    var controller: EditorController
    var onTextChange: (NSAttributedString) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = EditorTextView()
        textView.delegate = context.coordinator
        textView.font = fontFamily.nsFont(size: CGFloat(fontSize))
        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesFontPanel = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 0
        textView.autoresizingMask = [.width]

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CGFloat(lineSpacing)
        textView.defaultParagraphStyle = paragraphStyle

        // Set initial text with suppress to avoid triggering save
        textView.suppressNextChange = true
        textView.textStorage?.setAttributedString(attributedString)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        controller.textView = textView
        context.coordinator.parent = self
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? EditorTextView else { return }
        controller.textView = textView

        // Update font size / family
        let currentSize = textView.font?.pointSize ?? 0
        let currentFamily = textView.font?.fontName ?? ""
        let targetFont = fontFamily.nsFont(size: CGFloat(fontSize))
        if currentSize != CGFloat(fontSize) || currentFamily != targetFont.fontName {
            textView.font = targetFont
        }

        // Update line spacing
        let currentSpacing = textView.defaultParagraphStyle?.lineSpacing ?? 0
        if currentSpacing != CGFloat(lineSpacing) {
            let newStyle = NSMutableParagraphStyle()
            newStyle.lineSpacing = CGFloat(lineSpacing)
            textView.defaultParagraphStyle = newStyle
        }

        // Only update text if the string content is different from what's displayed.
        // This prevents the textDidChange → saveContent → updateNSView → textDidChange loop.
        let currentString = textView.textStorage?.string ?? ""
        if currentString != attributedString.string {
            textView.suppressNextChange = true
            textView.textStorage?.setAttributedString(attributedString)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        /// Re-entry guard while applying markdown shortcut formatting.
        private var isApplyingMarkdown = false

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? EditorTextView else { return }

            // Suppress changes caused by programmatic text updates (from updateNSView)
            if textView.suppressNextChange {
                textView.suppressNextChange = false
                return
            }

            // Markdown shortcut detection — only on space, guarded against re-entry.
            if !isApplyingMarkdown {
                if applyMarkdownShortcuts(in: textView) {
                    // Formatting was applied; didChangeText() already propagated
                    // the change to the parent in the re-entrant call.
                    return
                }
            }

            guard let storage = textView.textStorage else { return }
            let attrString = NSAttributedString(attributedString: storage)
            parent.attributedString = attrString
            parent.onTextChange(attrString)
        }

        // MARK: - Markdown Shortcuts

        /// Detects markdown patterns at the start of the current line and
        /// converts them to rich formatting. Only runs when the character
        /// just typed was a space. Returns `true` if a conversion was applied.
        @discardableResult
        private func applyMarkdownShortcuts(in textView: EditorTextView) -> Bool {
            guard let storage = textView.textStorage else { return false }
            let cursor = textView.selectedRange()
            // Only on a caret (no selection) with a preceding character.
            guard cursor.length == 0, cursor.location > 0 else { return false }

            let nsString = storage.string as NSString
            guard cursor.location <= nsString.length else { return false }

            // The character just typed must be a space.
            let prevChar = nsString.substring(with: NSRange(location: cursor.location - 1, length: 1))
            guard prevChar == " " else { return false }

            // Current line range (includes trailing newline).
            let lineRange = nsString.lineRange(for: NSRange(location: cursor.location, length: 0))
            let line = nsString.substring(with: lineRange)

            // Match patterns. `prefixLen` = chars to drop from the start.
            // `newPrefix` = replacement visual prefix (e.g. "☐ "). `font` = heading font.
            var prefixLen = 0
            var newPrefix = ""
            var newText = ""
            var font: NSFont?

            if line.hasPrefix("# ") {
                prefixLen = 2; newPrefix = ""
                newText = String(line.dropFirst(2))
                font = .systemFont(ofSize: 22, weight: .bold)
            } else if line.hasPrefix("## ") {
                prefixLen = 3; newPrefix = ""
                newText = String(line.dropFirst(3))
                font = .systemFont(ofSize: 18, weight: .bold)
            } else if line.hasPrefix("### ") {
                prefixLen = 4; newPrefix = ""
                newText = String(line.dropFirst(4))
                font = .systemFont(ofSize: 16, weight: .bold)
            } else if line.hasPrefix("- [ ] ") {
                prefixLen = 6; newPrefix = "☐ "
                newText = "☐ " + String(line.dropFirst(6))
            } else if line.hasPrefix("- [x] ") {
                prefixLen = 6; newPrefix = "☑ "
                newText = "☑ " + String(line.dropFirst(6))
            } else if line.hasPrefix("> ") {
                prefixLen = 2; newPrefix = ""
                newText = String(line.dropFirst(2))
                font = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 14), toHaveTrait: .italicFontMask)
            } else if line.hasPrefix("- ") {
                prefixLen = 2; newPrefix = "• "
                newText = "• " + String(line.dropFirst(2))
            } else {
                return false // no match
            }

            isApplyingMarkdown = true
            defer { isApplyingMarkdown = false }

            // Base attributes on existing storage attributes at line start,
            // then override the font if the pattern requires it.
            var attrs = storage.attributes(at: lineRange.location,
                                           longestEffectiveRange: nil, in: lineRange)
            if let font = font {
                attrs[.font] = font
            }
            let replacement = NSAttributedString(string: newText, attributes: attrs)

            // Cursor math: the removed prefix was before the cursor; the new
            // prefix replaces it. Net cursor delta = newPrefix.length − prefixLen.
            let newPrefixLen = (newPrefix as NSString).length
            let cursorDelta = newPrefixLen - prefixLen
            let newCursor = max(lineRange.location, cursor.location + cursorDelta)

            storage.replaceCharacters(in: lineRange, with: replacement)
            textView.setSelectedRange(NSRange(location: newCursor, length: 0))
            textView.didChangeText() // re-enters textDidChange (isApplyingMarkdown=true)
            return true
        }
    }
}

// MARK: - FormattingToolbar

struct FormattingToolbar: View {
    @ObservedObject var controller: EditorController

    @State private var showTablePopover = false
    @State private var tableRows: Int = 3
    @State private var tableColumns: Int = 3
    @State private var showHighlightPopover = false

    /// Highlight palette (görsel 2 inspiration).
    private let highlightColors: [(name: String, color: NSColor)] = [
        ("Turuncu", NSColor(srgbRed: 1.0, green: 0.647, blue: 0.0, alpha: 0.45)),
        ("Kırmızı", NSColor(srgbRed: 1.0, green: 0.42, blue: 0.42, alpha: 0.45)),
        ("Mavi",    NSColor(srgbRed: 0.529, green: 0.808, blue: 0.922, alpha: 0.55)),
        ("Sarı",    NSColor(srgbRed: 1.0, green: 1.0, blue: 0.6, alpha: 0.6)),
        ("Yeşil",   NSColor(srgbRed: 0.565, green: 0.933, blue: 0.565, alpha: 0.5)),
        ("Mor",     NSColor(srgbRed: 0.867, green: 0.627, blue: 0.867, alpha: 0.5))
    ]

    var body: some View {
        HStack(spacing: 2) {
            ToolbarButton(icon: "bold", action: { controller.toggleBold() })
            ToolbarButton(icon: "italic", action: { controller.toggleItalic() })
            ToolbarButton(icon: "underline", action: { controller.toggleUnderline() })
            ToolbarButton(icon: "strikethrough", action: { controller.toggleStrikethrough() })

            Divider().frame(height: 16).padding(.horizontal, 4)

            ToolbarButton(icon: "list.bullet", action: { controller.toggleBulletList() })
            ToolbarButton(icon: "checkmark.square", action: { controller.toggleCheckbox() })

            Divider().frame(height: 16).padding(.horizontal, 4)

            // Highlight button with color popover
            Button {
                showHighlightPopover = true
            } label: {
                Image(systemName: "highlighter")
                    .font(.system(size: 13))
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Vurgu Rengi")
            .popover(isPresented: $showHighlightPopover) {
                VStack(spacing: 10) {
                    Text("Vurgu Rengi")
                        .font(.system(size: 13, weight: .semibold))

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                        ForEach(highlightColors, id: \.name) { item in
                            Button {
                                controller.toggleHighlight(color: item.color)
                                showHighlightPopover = false
                            } label: {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: item.color))
                                    .frame(width: 36, height: 28)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(item.name)
                        }
                    }

                    Divider()

                    Button {
                        controller.removeHighlight()
                        showHighlightPopover = false
                    } label: {
                        Label("Vurguyu Kaldır", systemImage: "xmark.circle")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .frame(width: 180)
            }

            // Quote block
            ToolbarButton(icon: "quote.opening", action: { controller.toggleQuoteBlock() })
                .help("Alıntı Bloğu")
            // Code block
            ToolbarButton(icon: "chevron.left.forwardslash.chevron.right",
                          action: { controller.toggleCodeBlock() })
                .help("Kod Bloğu")

            ToolbarButton(icon: "link", action: { controller.insertWikiLink() })

            Divider().frame(height: 16).padding(.horizontal, 4)

            // Table button with popover
            Button {
                showTablePopover = true
            } label: {
                Image(systemName: "tablecells")
                    .font(.system(size: 13))
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Tablo Ekle")
            .popover(isPresented: $showTablePopover) {
                VStack(spacing: 12) {
                    Text("Tablo Ekle")
                        .font(.system(size: 13, weight: .semibold))

                    HStack {
                        Text("Satır:")
                            .font(.system(size: 12))
                        Spacer()
                        Stepper("\(tableRows)", value: $tableRows, in: 1...20)
                            .frame(width: 80)
                    }

                    HStack {
                        Text("Sütun:")
                            .font(.system(size: 12))
                        Spacer()
                        Stepper("\(tableColumns)", value: $tableColumns, in: 1...10)
                            .frame(width: 80)
                    }

                    Button("Ekle") {
                        controller.insertTable(rows: tableRows, columns: tableColumns)
                        showTablePopover = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(width: 200)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
    }
}

private struct ToolbarButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(icon)
    }
}
