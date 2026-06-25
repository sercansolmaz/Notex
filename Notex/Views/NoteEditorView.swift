import SwiftUI
import CoreData
import AppKit
import UniformTypeIdentifiers

extension Notification.Name {
    static let navigateToNote = Notification.Name("NotexNavigateToNote")
}

struct NoteEditorView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var themeManager: ThemeManager

    @ObservedObject var note: Note
    var isFocusMode: Bool = false

    @StateObject private var editorController = EditorController()

    // Editor state
    @State private var editorText: NSAttributedString = NSAttributedString()
    @State private var titleText: String = ""

    // Content save debounce (UUID token pattern — no Timer, crash-safe)
    @State private var saveToken: UUID?
    @State private var pendingText: NSAttributedString?

    // Title save debounce
    @State private var titleSaveToken: UUID?
    @State private var pendingTitle: String?

    @State private var isLoaded = false
    @State private var showTagAssignment = false
    @State private var showBacklinks = false
    @State private var showVersionHistory = false

    // PDF attachment
    @State private var pdfPath: String?
    @State private var isProcessingOCR = false

    var body: some View {
        VStack(spacing: 0) {
            if !isFocusMode {
                contextChipsBar
            }

            // Title
            TextField("Başlık", text: $titleText)
                .textFieldStyle(.plain)
                .font(themeManager.fontFamily.swiftUIFont(size: 28, weight: .bold))
                .foregroundColor(themeManager.textColor)
                .padding(.horizontal, isFocusMode ? 48 : 24)
                .padding(.top, isFocusMode ? 24 : 16)
                .padding(.bottom, 8)
                .onChange(of: titleText) { _, _ in saveTitle() }

            if !isFocusMode {
                FormattingToolbar(controller: editorController)
                Divider().opacity(0.4)
            }

            // Editor
            RichTextEditor(
                attributedString: $editorText,
                fontSize: themeManager.fontSize,
                lineSpacing: themeManager.lineSpacing,
                fontFamily: themeManager.fontFamily,
                controller: editorController,
                onTextChange: { newText in saveContent(newText) }
            )
            .padding(.horizontal, isFocusMode ? 48 : 24)
            .padding(.bottom, 8)

            // PDF attachment preview
            if !isFocusMode {
                pdfAttachmentSection
            }

            // Status bar
            if isFocusMode {
                minimalStatusBar
            } else {
                statusBar
                backlinksPanel
            }
        }
        .background(themeManager.editorBackground)
        .onAppear { loadNoteContent() }
        .onChange(of: note.objectID) { _, _ in loadNoteContent() }
        .sheet(isPresented: $showTagAssignment) {
            TagAssignmentView(note: note)
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(isPresented: $showVersionHistory) {
            VersionHistoryView(
                noteUUID: note.displayUUID,
                noteTitle: note.displayTitle,
                onRestore: { loadNoteContent() }
            )
            .environment(\.managedObjectContext, viewContext)
            .environmentObject(themeManager)
        }
    }

    // MARK: - Context Chips

    private var contextChipsBar: some View {
        HStack(spacing: 8) {
            if let notebook = note.notebook {
                let color = notebook.notebookColor.swiftUIColor
                HStack(spacing: 4) {
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                    Text(notebook.displayName)
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color.opacity(0.15))
                .cornerRadius(6)
            }

            ForEach(note.tagsArray, id: \.objectID) { tag in
                HStack(spacing: 3) {
                    Circle()
                        .fill(tag.categoryColor.swiftUIColor)
                        .frame(width: 6, height: 6)
                    Text(tag.displayName)
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(tag.categoryColor.swiftUIColor.opacity(0.15))
                .cornerRadius(6)
            }

            Button {
                showTagAssignment = true
            } label: {
                Label("Etiket Ekle", systemImage: "tag")
                    .font(.system(size: 11))
                    .foregroundColor(themeManager.secondaryText)
            }
            .buttonStyle(.plain)

            Button {
                addFile()
            } label: {
                Label("Dosya Ekle", systemImage: "paperclip")
                    .font(.system(size: 11))
                    .foregroundColor(themeManager.secondaryText)
            }
            .buttonStyle(.plain)

            Button {
                ShareService.shareNote(note)
            } label: {
                Label("Paylaş", systemImage: "square.and.arrow.up")
                    .font(.system(size: 11))
                    .foregroundColor(themeManager.secondaryText)
            }
            .buttonStyle(.plain)

            Button {
                showVersionHistory = true
            } label: {
                Label("Sürüm Geçmişi", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 11))
                    .foregroundColor(themeManager.secondaryText)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 16) {
            Label("\(note.wordCount) kelime", systemImage: "text.alignleft")
            Label("\(note.characterCount) karakter", systemImage: "character")
            Label(note.readingTimeText, systemImage: "clock")
            Spacer()
            Text("Düzenlendi: \(note.fullDateText)")
            Text("·")
            Text("#\(note.displayUUID)")
        }
        .font(.system(size: 10))
        .foregroundColor(themeManager.secondaryText)
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08))
    }

    private var minimalStatusBar: some View {
        HStack(spacing: 16) {
            Text("\(note.wordCount) kelime")
            Text(note.readingTimeText)
            Spacer()
        }
        .font(.system(size: 10))
        .foregroundColor(themeManager.secondaryText)
        .padding(.horizontal, 48)
        .padding(.vertical, 6)
    }

    // MARK: - Backlinks Panel

    @ViewBuilder
    private var backlinksPanel: some View {
        if !note.backlinkNotes.isEmpty {
            Divider().opacity(0.4)
            DisclosureGroup("Geri Bağlantılar (\(note.backlinkNotes.count))", isExpanded: $showBacklinks) {
                ForEach(note.backlinkNotes, id: \.objectID) { backlinkNote in
                    Button {
                        NotificationCenter.default.post(name: .navigateToNote, object: backlinkNote.objectID)
                    } label: {
                        HStack {
                            Image(systemName: "arrowshape.turn.up.left")
                                .font(.system(size: 10))
                            Text(backlinkNote.displayTitle)
                                .font(.system(size: 12))
                        }
                        .foregroundColor(themeManager.textColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.system(size: 11))
            .foregroundColor(themeManager.textColor)
            .padding(.horizontal, 24)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.05))
        }
    }

    // MARK: - PDF Attachment Section

    @ViewBuilder
    private var pdfAttachmentSection: some View {
        if isProcessingOCR {
            Divider().opacity(0.4)
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("PDF işleniyor (OCR)...")
                    .font(.system(size: 11))
                    .foregroundColor(themeManager.secondaryText)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.05))
        } else if let path = pdfPath, FileManager.default.fileExists(atPath: path) {
            Divider().opacity(0.4)
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 11))
                        .foregroundColor(themeManager.accentColor)
                    Text("PDF Ek")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(themeManager.secondaryText)
                    Spacer()
                    Button {
                        pdfPath = nil
                        if let uuid = note.uuid {
                            UserDefaults.standard.removeObject(forKey: "pdfAttachment.\(uuid)")
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(themeManager.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help("PDF Eki Kaldır")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 6)

                PDFPreviewView(pdfURL: URL(fileURLWithPath: path))
                    .frame(height: 300)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
            .background(Color.secondary.opacity(0.05))
        }
    }

    // MARK: - Add File (images / PDF / any file)

    private func addFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf, .png, .jpeg, .gif, .plainText, .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsOtherFileTypes = true
        panel.prompt = "Ekle"
        panel.title = "Dosya Seçin"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Copy file into app attachments folder
        guard let destURL = AttachmentService.copyFileToAttachments(from: url) else { return }

        let noteUUID = note.displayUUID
        let currentFontSize = themeManager.fontSize
        let currentFontFamily = themeManager.fontFamily

        if AttachmentService.isImage(at: destURL) {
            // Insert image inline immediately
            if let inline = AttachmentService.inlineImageAttachment(from: destURL, maxWidth: 400) {
                let mutable = NSMutableAttributedString(attributedString: editorText)
                let separator = NSAttributedString(
                    string: "\n\n",
                    attributes: [.font: currentFontFamily.nsFont(size: CGFloat(currentFontSize))]
                )
                mutable.append(separator)
                mutable.append(inline)
                let newContent = NSAttributedString(attributedString: mutable)
                editorText = newContent
                saveContent(newContent)
            }

            // Queue OCR after a delay
            isProcessingOCR = true
            AttachmentService.scheduleIdleOCR(on: destURL, delay: 30) { ocrText in
                guard !note.isDeleted,
                      note.managedObjectContext != nil,
                      note.uuid == noteUUID else {
                    isProcessingOCR = false
                    return
                }
                isProcessingOCR = false
                appendOCRText(ocrText, label: "🖼️ Görsel İçeriği")
            }
        } else if AttachmentService.isPDF(at: destURL) {
            // Show PDF preview immediately
            pdfPath = destURL.path
            UserDefaults.standard.set(destURL.path, forKey: "pdfAttachment.\(noteUUID)")

            // Queue OCR after a delay
            isProcessingOCR = true
            AttachmentService.scheduleIdleOCR(on: destURL, delay: 30) { ocrText in
                guard !note.isDeleted,
                      note.managedObjectContext != nil,
                      note.uuid == noteUUID else {
                    isProcessingOCR = false
                    return
                }
                isProcessingOCR = false
                appendOCRText(ocrText, label: "📄 PDF İçeriği")
            }
        } else {
            // Other file types: insert a reference marker
            let mutable = NSMutableAttributedString(attributedString: editorText)
            let separator = NSAttributedString(
                string: "\n\n",
                attributes: [.font: currentFontFamily.nsFont(size: CGFloat(currentFontSize))]
            )
            let refString = NSAttributedString(
                string: "📎 \(destURL.lastPathComponent)\n",
                attributes: [.font: currentFontFamily.nsFont(size: CGFloat(currentFontSize))]
            )
            mutable.append(separator)
            mutable.append(refString)
            let newContent = NSAttributedString(attributedString: mutable)
            editorText = newContent
            saveContent(newContent)
        }
    }

    /// Appends extracted OCR text to the editor content (preserves rich text).
    @MainActor
    private func appendOCRText(_ ocrText: String, label: String) {
        let trimmed = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let mutable = NSMutableAttributedString(attributedString: editorText)
        let separator = NSAttributedString(
            string: "\n\n---\n\(label):\n\n",
            attributes: [.font: themeManager.fontFamily.nsFont(size: CGFloat(themeManager.fontSize))]
        )
        let ocrAttr = NSAttributedString(
            string: trimmed,
            attributes: [.font: themeManager.fontFamily.nsFont(size: CGFloat(themeManager.fontSize))]
        )
        mutable.append(separator)
        mutable.append(ocrAttr)
        let newContent = NSAttributedString(attributedString: mutable)
        editorText = newContent
        saveContent(newContent)
    }

    // MARK: - Load

    private func loadNoteContent() {
        titleText = note.title ?? ""
        if let data = note.content {
            editorText = Note.decodeAttributedString(from: data)
        } else {
            editorText = NSAttributedString(string: note.plainText ?? "")
        }
        // Load PDF attachment path from UserDefaults
        if let uuid = note.uuid {
            pdfPath = UserDefaults.standard.string(forKey: "pdfAttachment.\(uuid)")
        } else {
            pdfPath = nil
        }
        isLoaded = true
    }

    // MARK: - Title Save (debounced)

    private func saveTitle() {
        guard isLoaded else { return }
        pendingTitle = titleText
        titleSaveToken = UUID()
        let token = titleSaveToken!
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard self.titleSaveToken == token else { return }
            self.performTitleSave()
        }
    }

    private func performTitleSave() {
        guard let pendingTitle = pendingTitle else { return }
        guard !note.isDeleted else { return }
        guard note.managedObjectContext != nil else { return }
        guard note.title != pendingTitle else { return }

        note.title = pendingTitle
        note.updatedAt = Date()

        do {
            try viewContext.save()
            if let uuid = note.uuid {
                FTS5Manager.shared.indexNote(uuid: uuid, title: pendingTitle, content: note.plainText ?? "")
            }
        } catch {
            print("⚠️ Title save error: \(error)")
            viewContext.rollback()
        }
    }

    // MARK: - Content Save (debounced — UUID token pattern, no Timer)

    private func saveContent(_ attrString: NSAttributedString) {
        pendingText = attrString
        saveToken = UUID()
        let token = saveToken!
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard self.saveToken == token else { return }
            self.performSave()
        }
    }

    private func performSave() {
        guard let pendingText = pendingText else { return }
        guard !note.isDeleted else { return }
        guard note.managedObjectContext != nil else { return }

        let plainText = pendingText.string

        note.content = Note.encodeAttributedString(pendingText)
        note.plainText = plainText

        // Auto-generate title if empty
        if titleText.trimmingCharacters(in: .whitespaces).isEmpty {
            let firstLine = plainText.components(separatedBy: .newlines).first ?? ""
            let newTitle = firstLine.trimmingCharacters(in: .whitespaces)
            let finalTitle = newTitle.isEmpty ? "Başlıksız" : newTitle
            note.title = finalTitle
            titleText = finalTitle
        }

        note.updatedAt = Date()

        do {
            try viewContext.save()
            if let uuid = note.uuid {
                FTS5Manager.shared.indexNote(uuid: uuid, title: note.title ?? "", content: plainText)
            }
            BacklinkService.shared.updateBacklinks(for: note, in: viewContext)
            // Auto-snapshot for version history
            VersionHistoryService.shared.saveSnapshot(note: note)
        } catch {
            print("⚠️ Content save error: \(error)")
            viewContext.rollback()
        }
    }
}
