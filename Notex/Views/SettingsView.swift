import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettingsView()
                .tabItem { Label("Görünüm", systemImage: "paintbrush") }
            EditorSettingsView()
                .tabItem { Label("Düzenleyici", systemImage: "textformat") }
            ViewSettingsView()
                .tabItem { Label("Görünüm Ayarları", systemImage: "rectangle.grid.2x2") }
            SidebarSettingsView()
                .tabItem { Label("Kenar Çubuğu", systemImage: "sidebar.left") }
            ImportSettingsView()
                .tabItem { Label("İçe Aktarma", systemImage: "square.and.arrow.down") }
            BackupSettingsView()
                .tabItem { Label("Yedekleme", systemImage: "externaldrive.badge.plus") }
            DataSettingsView()
                .tabItem { Label("Veri", systemImage: "externaldrive") }
        }
        .frame(width: 520, height: 480)
    }
}

// MARK: - Appearance

struct AppearanceSettingsView: View {
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        Form {
            Section("Tema Modu") {
                Picker("Tema", selection: Binding(
                    get: { themeManager.theme },
                    set: { themeManager.theme = $0 }
                )) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.shortLabel).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack(spacing: 8) {
                    ForEach(AppTheme.allCases) { theme in
                        VStack(spacing: 4) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(theme == themeManager.theme ? themeManager.accentColor.opacity(0.18) : Color.secondary.opacity(0.10))
                                    .frame(height: 40)
                                Image(systemName: theme.iconName)
                                    .font(.system(size: 15))
                                    .foregroundColor(theme == themeManager.theme ? themeManager.accentColor : themeManager.secondaryText)
                            }
                            Text(theme.shortLabel)
                                .font(.system(size: 10))
                                .foregroundColor(themeManager.secondaryText)
                        }
                    }
                }
                .padding(.top, 2)
            }

            Section("Vurgu Rengi") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                    ForEach(AccentColorOption.allCases) { option in
                        ZStack {
                            Circle()
                                .fill(option.color)
                                .frame(width: 28, height: 28)
                            if themeManager.accentColorOption == option {
                                Circle()
                                    .stroke(Color.primary.opacity(0.8), lineWidth: 3)
                                    .frame(width: 34, height: 34)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .onTapGesture { themeManager.setAccentColor(option) }
                        .help(option.displayName)
                    }
                }
                .padding(.vertical, 2)
            }

            Section("Kategori Renkleri") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                    ForEach(CategoryColor.allCases) { color in
                        VStack(spacing: 3) {
                            Circle()
                                .fill(color.swiftUIColor)
                                .frame(width: 20, height: 20)
                            Text(color.displayName)
                                .font(.system(size: 9))
                                .foregroundColor(themeManager.secondaryText)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Editor

struct EditorSettingsView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("defaultExportFormat") private var defaultExportFormat: String = "Markdown (.md)"

    var body: some View {
        Form {
            Section("Yazı Tipi Ailesi") {
                Picker("Font", selection: Binding(
                    get: { themeManager.fontFamily },
                    set: { themeManager.setFontFamily($0) }
                )) {
                    ForEach(FontFamilyOption.allCases) { family in
                        Text(family.displayName).tag(family)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                // Preview
                Text("Yazı tipi önizlemesi")
                    .font(themeManager.fontFamily.swiftUIFont(size: CGFloat(themeManager.fontSize)))
                    .foregroundColor(themeManager.textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(6)
            }

            Section("Yazı Boyutu") {
                HStack {
                    Text("Boyut")
                    Spacer()
                    Text("\(Int(themeManager.fontSize)) pt")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(themeManager.accentColor)
                }
                Slider(value: $themeManager.fontSize, in: 12...24, step: 1)
                    .tint(themeManager.accentColor)
            }

            Section("Satır Aralığı") {
                HStack {
                    Text("Aralık")
                    Spacer()
                    Text(String(format: "%.1f", themeManager.lineSpacing))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(themeManager.accentColor)
                }
                Slider(value: $themeManager.lineSpacing, in: 1.0...3.0, step: 0.1)
                    .tint(themeManager.accentColor)
            }

            Section("Dışa Aktarma") {
                Picker("Varsayılan Format", selection: $defaultExportFormat) {
                    ForEach(ExportService.ExportFormat.allCases) { format in
                        Text(format.rawValue).tag(format.rawValue)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - View settings

struct ViewSettingsView: View {
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        Form {
            Section("Varsayılan Görünüm Modu") {
                Picker("Mod", selection: Binding(
                    get: { themeManager.defaultViewMode },
                    set: { themeManager.setDefaultViewMode($0) }
                )) {
                    ForEach(ViewMode.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.iconName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("Liste Yoğunluğu") {
                Picker("Yoğunluk", selection: Binding(
                    get: { themeManager.noteDensity },
                    set: { themeManager.setNoteDensity($0) }
                )) {
                    ForEach(NoteDensity.allCases) { density in
                        Label(density.displayName, systemImage: density.iconName).tag(density)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Sidebar Settings

struct SidebarSettingsView: View {
    @EnvironmentObject private var themeManager: ThemeManager

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)],
        animation: nil
    ) private var notebooks: FetchedResults<Notebook>

    @AppStorage("sidebar.showCounts") private var showCounts: Bool = true
    @AppStorage("sidebar.showShortcuts") private var showShortcuts: Bool = true
    @AppStorage("sidebar.showArchive") private var showArchive: Bool = true
    @AppStorage("sidebar.showTrash") private var showTrash: Bool = true
    @AppStorage("sidebar.defaultNotebook") private var defaultNotebook: String = ""

    var body: some View {
        Form {
            Section("Görünürlük") {
                Toggle("Sayım rozetlerini göster", isOn: $showCounts)
                Toggle("Kısayolları göster", isOn: $showShortcuts)
                Toggle("Arşivi göster", isOn: $showArchive)
                Toggle("Çöp Kutusunu göster", isOn: $showTrash)
            }

            Section("Varsayılan Defter") {
                Picker("Yeni notların ekleneceği defter", selection: $defaultNotebook) {
                    Text("Seçili defter (otomatik)").tag("")
                    ForEach(notebooks, id: \.objectID) { notebook in
                        Text(notebook.displayName).tag(notebook.objectID.uriRepresentation().absoluteString)
                    }
                }
                Text("Boş bırakılırsa, yeni notlar o an seçili olan deftere eklenir.")
                    .font(.system(size: 11))
                    .foregroundColor(themeManager.secondaryText)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Data

struct DataSettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        Form {
            Section("iCloud Senkronizasyonu") {
                HStack {
                    Image(systemName: "icloud")
                        .foregroundColor(themeManager.accentColor)
                    Text("iCloud ile senkronizasyon aktif")
                        .font(.system(size: 13))
                }
                Text("Notlarınız iCloud hesabınız ile otomatik olarak senkronize edilir. iCloud giriş yapmadıysanız, notlar yerel olarak saklanır.")
                    .font(.system(size: 11))
                    .foregroundColor(themeManager.secondaryText)
            }

            Section("Arama Dizini") {
                Button("Arama Dizinini Yeniden Oluştur") {
                    reindexSearch()
                }
            }

            Section("Dışa / İçe Aktarma") {
                Text("Dışa aktarma biçimi Düzenleyici sekmesinden ayarlanır. Notları dışa aktarmak için not listesinde sağ tıklayın.")
                    .font(.system(size: 11))
                    .foregroundColor(themeManager.secondaryText)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func reindexSearch() {
        let request: NSFetchRequest<Note> = Note.fetchRequest()
        let notes = (try? viewContext.fetch(request)) ?? []
        let indexData = notes.compactMap { note -> (uuid: String, title: String, content: String)? in
            guard let uuid = note.uuid else { return nil }
            return (uuid, note.title ?? "", note.plainText ?? "")
        }
        FTS5Manager.shared.reindexAll(notes: indexData)
    }
}

// MARK: - Import Settings

struct ImportSettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var statusMessage: String = ""
    @State private var isImporting: Bool = false
    @State private var isDropTargeted: Bool = false
    @State private var progressTotal: Int = 0
    @State private var progressCurrent: Int = 0
    @State private var currentFileName: String = ""
    @State private var importPhase: String = ""

    var body: some View {
        Form {
            // ── Sürükle Bırak ──
            Section("Sürükle Bırak Bölgesi") {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .foregroundColor(isDropTargeted ? themeManager.accentColor : themeManager.secondaryText)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isDropTargeted ? themeManager.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
                    )
                    .frame(height: 100)
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "tray.and.arrow.down")
                                .font(.system(size: 24))
                                .foregroundColor(themeManager.secondaryText)
                            Text("Dosyalarınızı buraya sürükleyip bırakın")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(themeManager.textColor)
                            Text(".enex · .md · .txt · .html · .jpg · .png · .pdf")
                                .font(.system(size: 10))
                                .foregroundColor(themeManager.secondaryText)
                        }
                    )
                    .onDrop(of: [.fileURL], delegate: ImportDropDelegate(
                        isTargeted: $isDropTargeted,
                        handle: { url in handleDroppedFile(url) }
                    ))
                    .padding(.vertical, 4)
            }

            // ── İçe Aktarma Seçenekleri ──
            Section("Kaynaklardan İçe Aktar") {
                Button {
                    importFromAppleNotes()
                } label: {
                    Label("Apple Notes'tan İçe Aktar", systemImage: "app")
                }
                .disabled(isImporting)
                Text("Apple Notes uygulamasındaki tüm notlarınızı içe aktarır. İlerleme canlı gösterilir.")
                    .font(.system(size: 11))
                    .foregroundColor(themeManager.secondaryText)

                Divider()

                Button {
                    importENEX()
                } label: {
                    Label("Evernote (ENEX) Dosyası", systemImage: "doc.text")
                }
                .disabled(isImporting)
                Text("Evernote'dan dışa aktardığınız .enex dosyasını seçin. Notlar, etiketler ve ekler korunur.")
                    .font(.system(size: 11))
                    .foregroundColor(themeManager.secondaryText)

                Divider()

                Button {
                    importENEXMultiple()
                } label: {
                    Label("Birden Fazla ENEX (Defter Seçimi)", systemImage: "doc.text.below.ecg")
                }
                .disabled(isImporting)
                Text("Evernote'dan defter bazında export ettiğiniz birden fazla .enex dosyasını seçin. Her dosya ayrı bir defter olarak içe aktarılır.")
                    .font(.system(size: 11))
                    .foregroundColor(themeManager.secondaryText)

                Divider()

                Button {
                    importMarkdownFolder()
                } label: {
                    Label("Markdown Klasörü", systemImage: "folder")
                }
                .disabled(isImporting)
                Text("Bir klasör seçin; içindeki tüm .md dosyaları ayrı notlar olarak içe aktarılır.")
                    .font(.system(size: 11))
                    .foregroundColor(themeManager.secondaryText)

                Divider()

                Button {
                    importTextFile()
                } label: {
                    Label("Düz Metin (.txt)", systemImage: "doc.plaintext")
                }
                .disabled(isImporting)
                Text("Bir veya birden fazla .txt dosyasını içe aktarın.")
                    .font(.system(size: 11))
                    .foregroundColor(themeManager.secondaryText)
            }

            // ── İlerleme Paneli ──
            Section("İçe Aktarma Durumu") {
                if isImporting {
                    VStack(alignment: .leading, spacing: 8) {
                        // Phase
                        if !importPhase.isEmpty {
                            Text(importPhase)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(themeManager.accentColor)
                        }

                        // Progress bar
                        if progressTotal > 0 {
                            ProgressView(
                                value: Double(progressCurrent),
                                total: Double(progressTotal)
                            )
                            .progressViewStyle(.linear)
                            .tint(themeManager.accentColor)

                            HStack {
                                Text("\(progressCurrent) / \(progressTotal)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(themeManager.textColor)
                                Spacer()
                                Text("%\(Int(Double(progressCurrent) / Double(max(progressTotal, 1)) * 100))")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(themeManager.accentColor)
                            }
                        }

                        // Current file
                        if !currentFileName.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "doc")
                                    .font(.system(size: 10))
                                    .foregroundColor(themeManager.secondaryText)
                                Text(currentFileName)
                                    .font(.system(size: 11))
                                    .foregroundColor(themeManager.secondaryText)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }

                        // Spinner for indeterminate
                        if progressTotal == 0 {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Hazırlanıyor...")
                                    .font(.system(size: 12))
                                    .foregroundColor(themeManager.secondaryText)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } else if !statusMessage.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: statusMessage.contains("Hata") ? "exclamationmark.triangle" : "checkmark.circle.fill")
                            .foregroundColor(statusMessage.contains("Hata") ? .red : .green)
                            .font(.system(size: 13))
                        Text(statusMessage)
                            .font(.system(size: 12))
                            .foregroundColor(themeManager.textColor)
                    }
                    .padding(.vertical, 2)
                } else {
                    Text("Henüz içe aktarma yapılmadı.")
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.secondaryText)
                }
            }

            // ── Evernote Bağlantı Bilgisi ──
            Section("Evernote Hesabı") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .foregroundColor(themeManager.accentColor)
                            .font(.system(size: 12))
                        Text("Evernote'a doğrudan bağlanmak")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text("Evernote hesabınıza doğrudan bağlanarak defter seçmek için Evernote API erişimi gerekir. Şu an için en pratik yol:\n\n1. Evernote'da Defterler → Dışa Aktar (.enex)\n2. Her defteri ayrı .enex olarak kaydedin\n3. Yukarıdaki 'Birden Fazla ENEX' butonu ile içe aktarın")
                        .font(.system(size: 11))
                        .foregroundColor(themeManager.secondaryText)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Apple Notes (with progress)

    private func importFromAppleNotes() {
        isImporting = true
        progressTotal = 0
        progressCurrent = 0
        currentFileName = ""
        importPhase = "Apple Notes notları sayılıyor..."
        statusMessage = ""

        DispatchQueue.global(qos: .userInitiated).async {
            // Count notes first
            let countScript = "Application('Notes').notes.length;"
            var totalNotes = 0
            let countTask = Process()
            countTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            countTask.arguments = ["-l", "JavaScript", "-e", countScript]
            let countPipe = Pipe()
            countTask.standardOutput = countPipe
            try? countTask.run()
            countTask.waitUntilExit()
            let countData = countPipe.fileHandleForReading.readDataToEndOfFile()
            if let str = String(data: countData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                totalNotes = Int(str) ?? 0
            }

            DispatchQueue.main.async {
                self.progressTotal = totalNotes
                self.importPhase = "Apple Notes: \(totalNotes) not içe aktarılıyor"
            }

            // Read in batches
            let batchSize = 50
            let ctx = self.viewContext
            var importedTotal = 0

            for offset in stride(from: 0, to: totalNotes, by: batchSize) {
                let end = min(offset + batchSize, totalNotes)

                // Update progress
                DispatchQueue.main.async {
                    self.progressCurrent = offset
                    self.currentFileName = "Notlar \(offset + 1)-\(end)"
                }

                // Read batch via JXA
                let script = """
                const Notes = Application('Notes');
                const notes = Notes.notes;
                const start = \(offset);
                const end = Math.min(start + \(batchSize), \(totalNotes));
                const result = [];
                for (let i = start; i < end; i++) {
                    try {
                        const n = notes[i];
                        let plaintext = '';
                        try { plaintext = n.plaintext(); } catch(e) {}
                        let cd = null;
                        try { cd = n.creationDate().toISOString(); } catch(e) {}
                        let md = null;
                        try { md = n.modificationDate().toISOString(); } catch(e) {}
                        let container = '';
                        try { container = n.container().name(); } catch(e) {}
                        result.push({ name: n.name(), plaintext: plaintext, creationDate: cd, modificationDate: md, container: container });
                    } catch(e) {}
                }
                JSON.stringify(result);
                """

                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                task.arguments = ["-l", "JavaScript", "-e", script]
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = Pipe()
                try? task.run()
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()

                guard let jsonStr = String(data: data, encoding: .utf8),
                      let notesData = parseJSONBackground(jsonStr) else { continue }

                // Save to Core Data
                ctx.performAndWait {
                    for noteData in notesData {
                        let note = Note(context: ctx)
                        note.uuid = UUID().uuidString
                        note.title = (noteData["name"] as? String) ?? "Başlıksız"
                        note.plainText = noteData["plaintext"] as? String
                        note.createdAt = self.parseDate(noteData["creationDate"] as? String)
                        note.updatedAt = self.parseDate(noteData["modificationDate"] as? String) ?? Date()
                        note.isFavorite = false
                        note.isTrashed = false
                        note.isArchived = false

                        // Find or create notebook
                        if let container = noteData["container"] as? String, !container.isEmpty {
                            let req: NSFetchRequest<Notebook> = Notebook.fetchRequest()
                            req.predicate = NSPredicate(format: "name ==[c] %@", container)
                            req.fetchLimit = 1
                            if let nb = try? ctx.fetch(req).first {
                                note.notebook = nb
                            } else {
                                let nb = Notebook(context: ctx)
                                nb.name = container
                                nb.createdAt = Date()
                                nb.updatedAt = Date()
                                note.notebook = nb
                            }
                        }

                        // Index
                        if let uuid = note.uuid {
                            FTS5Manager.shared.indexNote(uuid: uuid, title: note.title ?? "", content: note.plainText ?? "")
                        }

                        importedTotal += 1
                    }
                    try? ctx.save()
                }

                DispatchQueue.main.async {
                    self.progressCurrent = end
                }
            }

            DispatchQueue.main.async {
                self.isImporting = false
                self.importPhase = ""
                self.currentFileName = ""
                self.statusMessage = "\(importedTotal) not Apple Notes'tan içe aktarıldı."
            }
        }
    }

    // MARK: - ENEX (with progress)

    private func importENEX() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.xml]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "İçe Aktar"
        panel.title = "ENEX Dosyası Seçin"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isImporting = true
        progressTotal = 0
        progressCurrent = 0
        currentFileName = url.lastPathComponent
        importPhase = "ENEX dosyası okunuyor..."
        statusMessage = ""

        // Notebook name = filename without .enex extension
        let notebookName = url.deletingPathExtension().lastPathComponent

        let ctx = viewContext
        DispatchQueue.global(qos: .userInitiated).async {
            // Phase 1: Create notebook + Parse
            DispatchQueue.main.async { self.importPhase = "ENEX parse ediliyor..." }
            var noteCount = 0
            var indexData: [(uuid: String, title: String, content: String)] = []
            let ctx = viewContext

            ctx.performAndWait {
                // Create a notebook with the same name as the file
                let nb = Notebook(context: ctx)
                nb.name = notebookName
                nb.createdAt = Date()
                nb.updatedAt = Date()
                nb.icon = "folder"

                // Import all notes into this notebook (dates preserved by ENEXParser)
                let notes = ImportService.shared.importFile(at: url, into: ctx, notebook: nb)
                noteCount = notes.count

                // Set notebook timestamps to earliest note creation if available
                let earliest = notes.compactMap { $0.createdAt }.min()
                if let earliest = earliest {
                    nb.createdAt = earliest
                }

                for note in notes {
                    if let uuid = note.uuid {
                        indexData.append((uuid: uuid, title: note.title ?? "", content: note.plainText ?? ""))
                    }
                }
            }

            // Phase 2: Index with progress
            let finalCount = noteCount
            DispatchQueue.main.async {
                self.progressTotal = finalCount
                self.importPhase = "\(finalCount) not kaydediliyor ve indeksleniyor..."
            }

            for (i, data) in indexData.enumerated() {
                DispatchQueue.main.async {
                    self.progressCurrent = i + 1
                    self.currentFileName = data.title.prefix(40).description
                }
                FTS5Manager.shared.indexNote(uuid: data.uuid, title: data.title, content: data.content)
            }

            DispatchQueue.main.async {
                do {
                    try ctx.save()
                    self.isImporting = false
                    self.importPhase = ""
                    self.currentFileName = ""
                    self.statusMessage = "\(noteCount) not «\(notebookName)» defterine içe aktarıldı."
                } catch {
                    self.isImporting = false
                    self.statusMessage = "Kaydetme hatası: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Multiple ENEX (defter bazında)

    private func importENEXMultiple() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.xml]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "İçe Aktar"
        panel.title = "Birden Fazla ENEX Dosyası Seçin (Her biri bir defter)"

        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        let urls = panel.urls
        isImporting = true
        progressTotal = urls.count
        progressCurrent = 0
        importPhase = "\(urls.count) ENEX dosyası işlenecek"
        statusMessage = ""

        let ctx = viewContext
        DispatchQueue.global(qos: .userInitiated).async {
            var totalImported = 0

            for (i, url) in urls.enumerated() {
                let notebookName = url.deletingPathExtension().lastPathComponent

                DispatchQueue.main.async {
                    self.progressCurrent = i
                    self.currentFileName = notebookName
                    self.importPhase = "Defter: \(notebookName) işleniyor..."
                }

                // Create notebook
                var notebook: Notebook?
                ctx.performAndWait {
                    let nb = Notebook(context: ctx)
                    nb.name = notebookName
                    nb.createdAt = Date()
                    nb.updatedAt = Date()
                    notebook = nb
                    try? ctx.save()
                }

                // Import into this notebook
                let notes = ImportService.shared.importFile(at: url, into: ctx, notebook: notebook)
                totalImported += notes.count

                // Index
                for note in notes {
                    if let uuid = note.uuid {
                        FTS5Manager.shared.indexNote(uuid: uuid, title: note.title ?? "", content: note.plainText ?? "")
                    }
                }

                DispatchQueue.main.async {
                    self.progressCurrent = i + 1
                }
            }

            DispatchQueue.main.async {
                do {
                    try ctx.save()
                    self.isImporting = false
                    self.importPhase = ""
                    self.currentFileName = ""
                    self.statusMessage = "\(urls.count) defter, \(totalImported) not içe aktarıldı."
                } catch {
                    self.isImporting = false
                    self.statusMessage = "Kaydetme hatası: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Markdown folder (with progress)

    private func importMarkdownFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Seç"
        panel.title = "Markdown Klasörü Seçin"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isImporting = true
        progressTotal = 0
        progressCurrent = 0
        importPhase = "Dosyalar taranıyor..."
        statusMessage = ""

        let ctx = viewContext
        let dirURL = url
        DispatchQueue.global(qos: .userInitiated).async {
            let files = self.collectFiles(in: dirURL, extensions: ["md", "markdown"])

            DispatchQueue.main.async {
                self.progressTotal = files.count
                self.importPhase = "\(files.count) Markdown dosyası içe aktarılıyor..."
            }

            var total = 0
            for (i, fileURL) in files.enumerated() {
                DispatchQueue.main.async {
                    self.progressCurrent = i + 1
                    self.currentFileName = fileURL.lastPathComponent
                }
                let created = ImportService.shared.importFile(at: fileURL, into: ctx, notebook: nil)
                for note in created {
                    if let uuid = note.uuid {
                        FTS5Manager.shared.indexNote(uuid: uuid, title: note.title ?? "", content: note.plainText ?? "")
                    }
                }
                total += created.count
            }

            DispatchQueue.main.async {
                do {
                    try ctx.save()
                    self.isImporting = false
                    self.importPhase = ""
                    self.currentFileName = ""
                    self.statusMessage = "\(files.count) dosya tarandı, \(total) not içe aktarıldı."
                } catch {
                    self.isImporting = false
                    self.statusMessage = "Kaydetme hatası: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Plain text (with progress)

    private func importTextFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "İçe Aktar"
        panel.title = "Metin Dosyaları Seçin"

        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        let urls = panel.urls
        isImporting = true
        progressTotal = urls.count
        progressCurrent = 0
        importPhase = "\(urls.count) dosya içe aktarılıyor..."
        statusMessage = ""

        let ctx = viewContext
        DispatchQueue.global(qos: .userInitiated).async {
            var total = 0
            for (i, fileURL) in urls.enumerated() {
                DispatchQueue.main.async {
                    self.progressCurrent = i + 1
                    self.currentFileName = fileURL.lastPathComponent
                }
                let created = ImportService.shared.importFile(at: fileURL, into: ctx, notebook: nil)
                for note in created {
                    if let uuid = note.uuid {
                        FTS5Manager.shared.indexNote(uuid: uuid, title: note.title ?? "", content: note.plainText ?? "")
                    }
                }
                total += created.count
            }

            DispatchQueue.main.async {
                do {
                    try ctx.save()
                    self.isImporting = false
                    self.importPhase = ""
                    self.currentFileName = ""
                    self.statusMessage = "\(total) not içe aktarıldı."
                } catch {
                    self.isImporting = false
                    self.statusMessage = "Kaydetme hatası: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Drag & Drop

    private func handleDroppedFile(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        let noteExts: Set<String> = ["enex", "md", "markdown", "txt", "html", "htm"]
        guard noteExts.contains(ext) else {
            statusMessage = "Bu dosya türü (.\(ext)) sürükle-bırak ile içe aktarılamıyor."
            return
        }

        isImporting = true
        progressTotal = 1
        progressCurrent = 0
        currentFileName = url.lastPathComponent
        importPhase = "\(url.lastPathComponent) işleniyor..."
        statusMessage = ""

        let ctx = viewContext
        DispatchQueue.global(qos: .userInitiated).async {
            let created = ImportService.shared.importFile(at: url, into: ctx, notebook: nil)

            DispatchQueue.main.async { self.progressCurrent = 1 }

            for note in created {
                if let uuid = note.uuid {
                    FTS5Manager.shared.indexNote(uuid: uuid, title: note.title ?? "", content: note.plainText ?? "")
                }
            }

            DispatchQueue.main.async {
                do {
                    try ctx.save()
                    self.isImporting = false
                    self.importPhase = ""
                    self.currentFileName = ""
                    self.statusMessage = "\(created.count) not içe aktarıldı."
                } catch {
                    self.isImporting = false
                    self.statusMessage = "Kaydetme hatası: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Helpers

    private func collectFiles(in directory: URL, extensions: [String]) -> [URL] {
        var results: [URL] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: nil) else { return [] }
        for case let url as URL in enumerator where extensions.contains(url.pathExtension.lowercased()) {
            results.append(url)
        }
        return results
    }

    private func parseJSON(_ str: String) -> [[String: Any]]? {
        guard let data = str.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    }

    private func parseDate(_ str: String?) -> Date? {
        guard let str = str, !str.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        return f.date(from: str)
    }
}

// Top-level parse for background queue
private func parseJSONBackground(_ str: String) -> [[String: Any]]? {
    guard let data = str.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
}

// MARK: - Import Drag & Drop Delegate

/// Drop delegate for the import zone. Reads the dropped file URL and forwards
/// it to the supplied handler closure (which updates the view's state).
struct ImportDropDelegate: DropDelegate {
    var isTargeted: Binding<Bool>
    let handle: @Sendable (URL) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        isTargeted.wrappedValue = true
    }

    func dropExited(info: DropInfo) {
        isTargeted.wrappedValue = false
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        let handler = handle
        for item in providers {
            item.loadItem(forTypeIdentifier: "public.file-url", options: nil) { reading, _ in
                var url: URL?
                if let data = reading as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let str = reading as? String {
                    url = URL(string: str)
                } else if let droppedURL = reading as? URL {
                    url = droppedURL
                }
                guard let finalURL = url else { return }
                DispatchQueue.main.async {
                    handler(finalURL)
                }
            }
        }
        return true
    }
}

// MARK: - Backup Settings

struct BackupSettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var themeManager: ThemeManager

    @AppStorage("backup.autoEnabled") private var autoEnabled: Bool = false
    @AppStorage("backup.folderPath") private var folderPath: String = ""
    @AppStorage("backup.frequency") private var frequencyRaw: String = BackupService.Frequency.weekly.rawValue

    @State private var backupStatus: String = ""
    @State private var isBackingUp: Bool = false

    private var frequency: Binding<BackupService.Frequency> {
        Binding(
            get: { BackupService.Frequency(rawValue: frequencyRaw) ?? .weekly },
            set: { frequencyRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Otomatik Yedekleme") {
                Toggle("Otomatik yedeklemeyi etkinleştir", isOn: $autoEnabled)

                if autoEnabled {
                    Picker("Sıklık", selection: frequency) {
                        ForEach(BackupService.Frequency.allCases) { freq in
                            Text(freq.displayName).tag(freq)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text("Yedekler, uygulama açıldığında seçilen sıklığa göre otomatik olarak oluşturulur.")
                        .font(.system(size: 11))
                        .foregroundColor(themeManager.secondaryText)
                }
            }

            Section("Yedekleme Klasörü") {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .foregroundColor(themeManager.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        if folderPath.isEmpty {
                            Text("Klasör seçilmedi")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(themeManager.secondaryText)
                        } else {
                            Text(displayPath)
                                .font(.system(size: 11))
                                .foregroundColor(themeManager.textColor)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer()
                    Button("Seç...") {
                        pickFolder()
                    }
                }
                Text("İCloud Drive, Dropbox veya Google Drive klasörlerini seçebilirsiniz. Senkronizasyon uygulamaları dosyaları otomatik yükler.")
                    .font(.system(size: 11))
                    .foregroundColor(themeManager.secondaryText)
            }

            Section("Yedekleme") {
                Button {
                    backupNow()
                } label: {
                    HStack {
                        if isBackingUp {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Şimdi Yedekle")
                    }
                }
                .disabled(isBackingUp)

                if !backupStatus.isEmpty {
                    Text(backupStatus)
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.secondaryText)
                }
            }

            Section("Son Yedekleme") {
                if let lastDate = BackupService.lastBackupDate {
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                        Text("Son yedekleme: \(formatDate(lastDate))")
                            .font(.system(size: 12))
                    }
                } else {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(themeManager.secondaryText)
                        Text("Henüz yedekleme yapılmadı")
                            .font(.system(size: 12))
                            .foregroundColor(themeManager.secondaryText)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var displayPath: String {
        let expanded = (folderPath as NSString).expandingTildeInPath
        if expanded.hasPrefix(NSHomeDirectory()) {
            return "~" + expanded.dropFirst(NSHomeDirectory().count)
        }
        return expanded
    }

    private func pickFolder() {
        if let url = BackupService.pickBackupFolder() {
            folderPath = url.path
        }
    }

    private func backupNow() {
        guard !isBackingUp else { return }
        isBackingUp = true
        backupStatus = "Yedekleniyor..."

        // If no folder configured, prompt first (NSOpenPanel needs main thread)
        if folderPath.isEmpty {
            if let url = BackupService.pickBackupFolder() {
                folderPath = url.path
            } else {
                isBackingUp = false
                backupStatus = "İptal edildi"
                return
            }
        }

        let dest = URL(fileURLWithPath: folderPath)
        let ctx = viewContext

        DispatchQueue.global(qos: .userInitiated).async {
            let result = BackupService.performBackup(context: ctx, destination: dest)
            DispatchQueue.main.async {
                self.isBackingUp = false
                if result.success {
                    self.backupStatus = result.message
                } else {
                    self.backupStatus = "Hata: \(result.message)"
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
