import SwiftUI
import CoreData

struct NoteListView: View {
    @Binding var sidebarSelection: SidebarSelection?
    @Binding var selectedNote: Note?
    @Binding var searchText: String

    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.openWindow) private var openWindow

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "updatedAt", ascending: false)],
        animation: .default
    ) private var allNotes: FetchedResults<Note>

    @State private var searchToken: UUID?
    @State private var searchResults: Set<String> = Set()

    @AppStorage("notes.sortOption") private var sortOptionRaw: String = NoteSortOption.updatedDesc.rawValue

    // ── Multi-selection ──
    @State private var isSelectionMode: Bool = false
    @State private var selectedNoteIDs: Set<NSManagedObjectID> = []
    @State private var showBulkDeleteConfirm: Bool = false
    @State private var showEmptyTrashConfirm: Bool = false

    private var sortOption: NoteSortOption {
        NoteSortOption(rawValue: sortOptionRaw) ?? .updatedDesc
    }

    var body: some View {
        VStack(spacing: 0) {
            if sidebarSelection == .notebooksGrid {
                NotebookGridView { selection in
                    sidebarSelection = selection
                }
            } else {
                headerBar
                searchBar
                Divider()
                noteContent
                if isSelectionMode && !selectedNoteIDs.isEmpty {
                    selectionBar
                }
            }
        }
        .background(themeManager.backgroundColor)
        .frame(minWidth: 280)
        .confirmationDialog(
            sidebarSelection == .trash
                ? "\(selectedNoteIDs.count) notu kalıcı olarak silmek istediğinize emin misiniz? Bu işlem geri alınamaz."
                : "\(selectedNoteIDs.count) notu çöp kutusuna taşımak istediğinize emin misiniz?",
            isPresented: $showBulkDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(sidebarSelection == .trash ? "Kalıcı Sil" : "Çöpe Taşı", role: .destructive) {
                if sidebarSelection == .trash {
                    bulkDeleteSelected()
                } else {
                    bulkTrashSelected()
                }
            }
            Button("İptal", role: .cancel) {}
        }
        .confirmationDialog(
            "Çöp kutusundaki tüm notlar kalıcı olarak silinecek. Bu işlem geri alınamaz.",
            isPresented: $showEmptyTrashConfirm,
            titleVisibility: .visible
        ) {
            Button("Çöpü Boşalt", role: .destructive) {
                emptyTrash()
            }
            Button("İptal", role: .cancel) {}
        }
    }

    // MARK: - Selection Bar

    private var selectionBar: some View {
        HStack(spacing: 10) {
            Text("\(selectedNoteIDs.count) seçili")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(themeManager.textColor)
            Spacer()
            Button("Tümünü Seç") {
                selectedNoteIDs = Set(displayedNotes.map { $0.objectID })
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(themeManager.accentColor)

            Button("Hiçbiri") {
                selectedNoteIDs.removeAll()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(themeManager.secondaryText)

            Divider().frame(height: 16)

            // Geri Yükle (only in trash)
            if sidebarSelection == .trash {
                Button {
                    bulkRestoreSelected()
                } label: {
                    Label("Geri Yükle", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(themeManager.accentColor)

                Button {
                    showBulkDeleteConfirm = true
                } label: {
                    Label("Kalıcı Sil", systemImage: "trash.slash")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
            } else {
                Button {
                    showBulkDeleteConfirm = true
                } label: {
                    Label("Sil", systemImage: "trash")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(themeManager.secondaryText.opacity(0.08))
    }

    // MARK: - Header (title + count + view toggle)

    private var headerBar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(themeManager.textColor)
                    .lineLimit(1)
                Text("\(filteredNotes.count) not")
                    .font(.system(size: 10))
                    .foregroundColor(themeManager.secondaryText)
            }

            // Empty Trash button (only in trash view)
            if sidebarSelection == .trash && !filteredNotes.isEmpty {
                Button {
                    showEmptyTrashConfirm = true
                } label: {
                    Label("Çöpü Boşalt", systemImage: "trash.slash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Çöp kutusunu tamamen boşalt")
            }

            Spacer()

            // Sort menu
            Menu {
                ForEach(NoteSortOption.allCases, id: \.rawValue) { option in
                    Button {
                        sortOptionRaw = option.rawValue
                    } label: {
                        HStack {
                            Text(option.rawValue)
                            if sortOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 24)
                    .foregroundColor(themeManager.secondaryText)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(6)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Sırala: \(sortOption.rawValue)")
            .fixedSize()

            // List / Grid toggle
            HStack(spacing: 0) {
                toggleButton(mode: .list)
                toggleButton(mode: .grid)
            }
            .background(Color.secondary.opacity(0.12))
            .cornerRadius(7)
            .padding(.vertical, 1)

            // Selection mode toggle
            Button {
                isSelectionMode.toggle()
                if !isSelectionMode { selectedNoteIDs.removeAll() }
            } label: {
                Image(systemName: isSelectionMode ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 22)
                    .foregroundColor(isSelectionMode ? .white : themeManager.secondaryText)
                    .background(isSelectionMode ? themeManager.accentColor : Color.secondary.opacity(0.12))
                    .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help(isSelectionMode ? "Seçim modundan çık" : "Çoklu seçim modu")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(themeManager.backgroundColor)
    }

    private func toggleButton(mode: ViewMode) -> some View {
        let active = themeManager.viewMode == mode
        return Button {
            themeManager.viewMode = mode
        } label: {
            Image(systemName: mode.iconName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 22)
                .foregroundColor(active ? .white : themeManager.secondaryText)
                .background(active ? themeManager.accentColor : Color.clear)
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
        .help(mode.displayName)
    }

    private var headerTitle: String {
        switch sidebarSelection {
        case .allNotes, nil: return "Tüm Notlar"
        case .favorites: return "Favoriler"
        case .archived: return "Arşiv"
        case .trash: return "Çöp Kutusu"
        case .notebooksGrid: return "Defterler"
        case .notebook: return "Defter"
        case .tag: return "Etiket"
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(themeManager.secondaryText)
                .font(.system(size: 13))
            TextField("Ara...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onChange(of: searchText) { _, newValue in
                    if newValue.isEmpty {
                        searchResults = Set()
                        return
                    }
                    searchToken = UUID()
                    let token = searchToken!
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        guard self.searchToken == token else { return }
                        self.searchResults = FTS5Manager.shared.search(newValue)
                    }
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchResults = Set()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(themeManager.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.10))
        .cornerRadius(8)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Note content (list / grid)

    @ViewBuilder
    private var noteContent: some View {
        if filteredNotes.isEmpty {
            emptyState
        } else if themeManager.viewMode == .grid {
            gridView
        } else {
            listView
        }
    }

    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(displayedNotes, id: \.objectID) { note in
                    let isMultiSelected = selectedNoteIDs.contains(note.objectID)
                    HStack(spacing: 0) {
                        if isSelectionMode {
                            Button {
                                toggleNoteSelection(note)
                            } label: {
                                Image(systemName: isMultiSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 16))
                                    .foregroundColor(isMultiSelected ? themeManager.accentColor : themeManager.secondaryText)
                                    .padding(.leading, 10)
                            }
                            .buttonStyle(.plain)
                        }
                        ModernNoteCard(
                            note: note,
                            isSelected: isSelectionMode ? isMultiSelected : (selectedNote == note),
                            accentColor: themeManager.accentColor,
                            layout: .listRow,
                            density: themeManager.noteDensity,
                            searchQuery: searchText,
                            onClick: {
                                if isSelectionMode {
                                    toggleNoteSelection(note)
                                } else {
                                    selectedNote = note
                                }
                            }
                        )
                        .onTapGesture(count: 2) {
                            if !isSelectionMode, let uuid = note.uuid { openWindow(value: uuid) }
                        }
                        .onDrag {
                            let provider = NSItemProvider()
                            provider.suggestedName = note.displayTitle
                            if let uuid = note.uuid {
                                return NSItemProvider(object: uuid as NSString)
                            }
                            return provider
                        }
                        .contextMenu { noteContextMenu(for: note) }
                    }
                    Divider().opacity(0.4)
                }
            }
        }
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(displayedNotes, id: \.objectID) { note in
                    let isMultiSelected = selectedNoteIDs.contains(note.objectID)
                    ZStack(alignment: .topLeading) {
                        ModernNoteCard(
                            note: note,
                            isSelected: isSelectionMode ? isMultiSelected : (selectedNote == note),
                            accentColor: themeManager.accentColor,
                            layout: .gridTile,
                            density: themeManager.noteDensity,
                            searchQuery: searchText,
                            onClick: {
                                if isSelectionMode {
                                    toggleNoteSelection(note)
                                } else {
                                    selectedNote = note
                                }
                            }
                        )
                        .onTapGesture(count: 2) {
                            if !isSelectionMode, let uuid = note.uuid { openWindow(value: uuid) }
                        }
                        .onDrag {
                            let provider = NSItemProvider()
                            provider.suggestedName = note.displayTitle
                            if let uuid = note.uuid {
                                return NSItemProvider(object: uuid as NSString)
                            }
                            return provider
                        }
                        .contextMenu { noteContextMenu(for: note) }

                        if isSelectionMode && isMultiSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(themeManager.accentColor)
                                .background(Circle().fill(Color.white))
                                .padding(6)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: searchText.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(themeManager.secondaryText)
            Text(searchText.isEmpty ? "Not yok" : "Sonuç bulunamadı")
                .font(.caption)
                .foregroundColor(themeManager.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Filtered Notes

    private var filteredNotes: [Note] {
        allNotes.filter { note in
            // Sidebar filter
            let passesSidebar: Bool
            switch sidebarSelection {
            case .allNotes, nil:
                passesSidebar = !note.isTrashed && !note.isArchived
            case .favorites:
                passesSidebar = !note.isTrashed && note.isFavorite
            case .archived:
                passesSidebar = !note.isTrashed && note.isArchived
            case .trash:
                passesSidebar = note.isTrashed
            case .notebooksGrid:
                passesSidebar = !note.isTrashed && !note.isArchived
            case .notebook(let id):
                passesSidebar = !note.isTrashed && note.notebook?.objectID == id
            case .tag(let id):
                passesSidebar = !note.isTrashed && note.tagsArray.contains { $0.objectID == id }
            }
            guard passesSidebar else { return false }

            // Search filter — FTS5Manager returns UUID strings
            if !searchText.isEmpty {
                return note.uuid.map { searchResults.contains($0) } ?? false
            }
            return true
        }
    }

    /// Filtered notes sorted by the user-selected sort option.
    private var displayedNotes: [Note] {
        NoteSortOption.sort(filteredNotes, by: sortOption)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func noteContextMenu(for note: Note) -> some View {
        if note.isTrashed {
            Button("Geri Yükle") {
                note.isTrashed = false
                saveContext()
            }
            Divider()
            Button("Kalıcı Olarak Sil") {
                if let uuid = note.uuid {
                    FTS5Manager.shared.deleteNote(uuid: uuid)
                }
                viewContext.delete(note)
                saveContext()
            }
        } else {
            Button(note.isPinned ? "Sabitlemeyi Kaldır" : "Sabitle") {
                note.isPinned.toggle()
                saveContext()
            }
            Button(note.isFavorite ? "Favorilerden Çıkar" : "Favorilere Ekle") {
                note.isFavorite.toggle()
                saveContext()
            }
            Button(note.isArchived ? "Arşivden Çıkar" : "Arşivle") {
                note.isArchived.toggle()
                saveContext()
            }
            Divider()
            Button("Çöp Kutusuna Taşı") {
                note.isTrashed = true
                note.isPinned = false
                saveContext()
            }
        }
    }

    private func saveContext() {
        do {
            try viewContext.save()
        } catch {
            print("⚠️ Context save error: \(error)")
            viewContext.rollback()
        }
    }

    // MARK: - Multi-Selection Actions

    private func toggleNoteSelection(_ note: Note) {
        if selectedNoteIDs.contains(note.objectID) {
            selectedNoteIDs.remove(note.objectID)
        } else {
            selectedNoteIDs.insert(note.objectID)
        }
    }

    private func bulkDeleteSelected() {
        let ids = selectedNoteIDs
        var deleted = 0
        for id in ids {
            if let note = try? viewContext.existingObject(with: id) as? Note {
                if let uuid = note.uuid {
                    FTS5Manager.shared.deleteNote(uuid: uuid)
                }
                viewContext.delete(note)
                deleted += 1
            }
        }
        saveContext()
        selectedNoteIDs.removeAll()
        isSelectionMode = false
        if selectedNote.map({ $0.objectID }).flatMap({ ids.contains($0) }) == true {
            selectedNote = nil
        }
    }

    private func bulkRestoreSelected() {
        let ids = selectedNoteIDs
        for id in ids {
            if let note = try? viewContext.existingObject(with: id) as? Note {
                note.isTrashed = false
            }
        }
        saveContext()
        selectedNoteIDs.removeAll()
        isSelectionMode = false
    }

    private func bulkTrashSelected() {
        let ids = selectedNoteIDs
        for id in ids {
            if let note = try? viewContext.existingObject(with: id) as? Note {
                note.isTrashed = true
            }
        }
        saveContext()
        selectedNoteIDs.removeAll()
        isSelectionMode = false
        if selectedNote.map({ $0.objectID }).flatMap({ ids.contains($0) }) == true {
            selectedNote = nil
        }
    }

    /// Permanently deletes ALL trashed notes (Empty Trash action).
    private func emptyTrash() {
        let trashedNotes = allNotes.filter { $0.isTrashed }
        for note in trashedNotes {
            if let uuid = note.uuid {
                FTS5Manager.shared.deleteNote(uuid: uuid)
            }
            viewContext.delete(note)
        }
        saveContext()
        selectedNoteIDs.removeAll()
        isSelectionMode = false
        if selectedNote.map({ $0.isTrashed }) == true {
            selectedNote = nil
        }
    }
}

// MARK: - Count Badge (shared with sidebar)

/// Rounded count badge colored by a category color, e.g. "07".
struct CountBadge: View {
    let count: Int
    let color: Color

    var body: some View {
        if count <= 0 {
            EmptyView()
        } else {
            Text(formatted)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(color)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(color.opacity(0.16))
                .cornerRadius(7)
        }
    }

    private var formatted: String {
        count > 999 ? "999+" : String(format: "%02d", count)
    }
}
