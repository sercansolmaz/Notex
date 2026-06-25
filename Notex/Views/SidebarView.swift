import SwiftUI
import CoreData

struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var themeManager: ThemeManager

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)],
        predicate: NSPredicate(format: "parent == nil"),
        animation: .default
    ) private var rootNotebooks: FetchedResults<Notebook>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)],
        animation: .default
    ) private var tags: FetchedResults<Tag>

    @FetchRequest(
        sortDescriptors: [],
        animation: nil
    ) private var allNotes: FetchedResults<Note>

    @State private var showNewNotebook = false
    @State private var newNotebookName = ""
    @State private var showNewTag = false
    @State private var newTagName = ""
    @State private var newTagColor: Color_TagHelper = .blue
    @State private var collapsedNotebookIDs: Set<String> = []
    @State private var isTagSelectionMode: Bool = false
    @State private var selectedTagIDs: Set<NSManagedObjectID> = []
    @State private var showBulkTagDeleteConfirm: Bool = false
    @State private var showCleanUnusedTagsConfirm: Bool = false

    @AppStorage("sidebar.notebooksExpanded") private var notebooksExpanded: Bool = true
    @AppStorage("sidebar.tagsExpanded") private var tagsExpanded: Bool = true
    @AppStorage("sidebar.showCounts") private var showCounts: Bool = true
    @AppStorage("sidebar.showShortcuts") private var showShortcuts: Bool = true
    @AppStorage("sidebar.showArchive") private var showArchive: Bool = true
    @AppStorage("sidebar.showTrash") private var showTrash: Bool = true
    @AppStorage("sidebar.tagSort") private var tagSort: String = "alpha" // "alpha" or "count"

    var body: some View {
        VStack(spacing: 0) {
            // "Yeni Not" button + import icon
            HStack(spacing: 6) {
                Button {
                    NotificationCenter.default.post(name: .createNewNote, object: nil)
                } label: {
                    Label("Yeni Not", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(themeManager.accentColor)

                Button {
                    NotificationCenter.default.post(name: .openImportSheet, object: nil)
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .foregroundColor(themeManager.textColor)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("İçe Aktar")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            List(selection: $selection) {
                // Smart Folders
                Section {
                    if showShortcuts {
                        sidebarRow(
                            title: "Tüm Notlar",
                            systemImage: "tray.full",
                            color: themeManager.accentColor,
                            count: allCount,
                            selection: .allNotes
                        )
                        sidebarRow(
                            title: "Defterler",
                            systemImage: "square.grid.2x2",
                            color: .purple,
                            count: notebookCount,
                            selection: .notebooksGrid
                        )
                        sidebarRow(
                            title: "Favoriler",
                            systemImage: "star.fill",
                            color: .yellow,
                            count: favoritesCount,
                            selection: .favorites
                        )
                    }
                    if showArchive {
                        sidebarRow(
                            title: "Arşiv",
                            systemImage: "archivebox",
                            color: CategoryColor.orange.swiftUIColor,
                            count: archivedCount,
                            selection: .archived
                        )
                    }
                    if showTrash {
                        sidebarRow(
                            title: "Çöp Kutusu",
                            systemImage: "trash",
                            color: CategoryColor.red.swiftUIColor,
                            count: trashCount,
                            selection: .trash
                        )
                    }
                }

                // Notebooks
                Section {
                    if notebooksExpanded {
                        ForEach(flatNotebooks, id: \.notebook.objectID) { item in
                            notebookRow(item)
                        }

                        if showNewNotebook {
                            TextField("Defter adı", text: $newNotebookName, onCommit: createNotebook)
                                .textFieldStyle(.roundedBorder)
                        }

                        addButton(title: "Yeni Defter", systemImage: "folder.badge.plus") {
                            showNewNotebook.toggle()
                            if showNewNotebook { newNotebookName = "" }
                        }
                    }
                } header: {
                    collapsibleHeader(title: "Defterler", isExpanded: $notebooksExpanded)
                }

                // Tags
                Section {
                    if tagsExpanded {
                        // Sort + selection controls
                        HStack(spacing: 6) {
                            Button {
                                tagSort = (tagSort == "alpha") ? "count" : "alpha"
                            } label: {
                                Image(systemName: tagSort == "alpha" ? "arrow.down.circle" : "number.circle")
                                    .font(.system(size: 11))
                                    .foregroundColor(themeManager.secondaryText)
                            }
                            .buttonStyle(.plain)
                            .help(tagSort == "alpha" ? "Alfabetik (şu an)" : "Not sayısına göre (şu an)")

                            Spacer(minLength: 0)

                            // Selection mode toggle
                            Button {
                                isTagSelectionMode.toggle()
                                if !isTagSelectionMode { selectedTagIDs.removeAll() }
                            } label: {
                                Image(systemName: isTagSelectionMode ? "checkmark.circle.fill" : "checkmark.circle")
                                    .font(.system(size: 11))
                                    .foregroundColor(isTagSelectionMode ? themeManager.accentColor : themeManager.secondaryText)
                            }
                            .buttonStyle(.plain)
                            .help("Çoklu seçim")

                            // Clean unused tags
                            Button {
                                showCleanUnusedTagsConfirm = true
                            } label: {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11))
                                    .foregroundColor(themeManager.secondaryText)
                            }
                            .buttonStyle(.plain)
                            .help("İlişkisiz etiketleri temizle")
                        }

                        ForEach(sortedTags, id: \.objectID) { tag in
                            tagRow(tag)
                        }

                        // Bulk delete bar
                        if isTagSelectionMode && !selectedTagIDs.isEmpty {
                            HStack(spacing: 8) {
                                Text("\(selectedTagIDs.count) seçili")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(themeManager.textColor)
                                Spacer()
                                Button("Tümü") { selectedTagIDs = Set(tags.map { $0.objectID }) }
                                    .buttonStyle(.plain).font(.system(size: 10))
                                    .foregroundColor(themeManager.accentColor)
                                Button("Sil") { showBulkTagDeleteConfirm = true }
                                    .buttonStyle(.plain).font(.system(size: 10))
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(themeManager.secondaryText.opacity(0.08))
                            .cornerRadius(6)
                        }

                        if showNewTag {
                            HStack {
                                TextField("Etiket adı", text: $newTagName, onCommit: createTag)
                                    .textFieldStyle(.roundedBorder)
                                Menu {
                                    ForEach(Color_TagHelper.allCases, id: \.self) { color in
                                        Button(color.rawValue) { newTagColor = color }
                                    }
                                } label: {
                                    Circle()
                                        .fill(newTagColor.swiftUIColor)
                                        .frame(width: 14, height: 14)
                                }
                                .menuStyle(.borderlessButton)
                                .frame(width: 20)
                            }
                        }

                        addButton(title: "Yeni Etiket", systemImage: "tag") {
                            showNewTag.toggle()
                            if showNewTag { newTagName = "" }
                        }
                    }
                } header: {
                    HStack(spacing: 4) {
                        collapsibleHeaderInline(title: "Etiketler", isExpanded: $tagsExpanded)
                        Spacer(minLength: 0)
                        Text("(\(tags.count))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(themeManager.secondaryText)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(themeManager.sidebarBackground)
        }
        .navigationTitle("Notex")
        .onReceive(NotificationCenter.default.publisher(for: .createNewNotebookInternal)) { _ in
            showNewNotebook = true
            newNotebookName = ""
        }
        .confirmationDialog(
            "\(selectedTagIDs.count) etiketi silmek istediğinize emin misiniz?",
            isPresented: $showBulkTagDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Sil", role: .destructive) { bulkDeleteSelectedTags() }
            Button("İptal", role: .cancel) {}
        }
        .confirmationDialog(
            "Hiçbir notla ilişkisi olmayan etiketleri silmek istiyor musunuz?",
            isPresented: $showCleanUnusedTagsConfirm,
            titleVisibility: .visible
        ) {
            Button("İlişkisiz Etiketleri Sil", role: .destructive) { deleteUnusedTags() }
            Button("İptal", role: .cancel) {}
        } message: {
            let unused = tags.filter { $0.notesCount == 0 }.count
            Text("\(unused) ilişkisiz etiket bulundu.")
        }
    }

    // MARK: - Row Builders

    @ViewBuilder
    private func sidebarRow(
        title: String,
        systemImage: String,
        color: Color,
        count: Int,
        selection sel: SidebarSelection
    ) -> some View {
        let active = isSelectedRow(sel)
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(active ? color : themeManager.secondaryText)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 13, weight: active ? .semibold : .regular))
                .foregroundColor(themeManager.textColor)
            Spacer(minLength: 0)
            if showCounts {
                CountBadge(count: count, color: color)
            }
        }
        .padding(.vertical, 2)
        .tag(sel)
    }

    @ViewBuilder
    private func notebookRow(_ item: (notebook: Notebook, level: Int)) -> some View {
        let nb = item.notebook
        let active = isSelectedRow(.notebook(nb.objectID))
        let color = nb.notebookColor.swiftUIColor
        let hasChildren = nb.hasChildren
        let idStr = nb.objectID.uriRepresentation().absoluteString
        let isExpanded = !collapsedNotebookIDs.contains(idStr)

        HStack(spacing: 6) {
            // Chevron for expand/collapse (parents only)
            if hasChildren {
                Button {
                    toggleNotebookExpanded(nb)
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(themeManager.secondaryText)
                        .frame(width: 12, height: 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Daralt" : "Genişlet")
            } else {
                Spacer().frame(width: 12)
            }

            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .overlay(
                    Circle()
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
            Text(nb.displayName)
                .font(.system(size: 13, weight: active ? .semibold : .regular))
                .foregroundColor(themeManager.textColor)
                .lineLimit(1)
            Spacer(minLength: 0)
            if showCounts {
                // Parents show recursive total; leaves show direct count
                CountBadge(count: nb.allNotesCount, color: color)
            }
        }
        .padding(.leading, CGFloat(item.level) * 14)
        .padding(.vertical, 2)
        .tag(SidebarSelection.notebook(nb.objectID))
        .onDrag {
            let idString = "notebook:\(idStr)"
            return NSItemProvider(object: idString as NSString)
        }
        .onDrop(of: [.text], delegate: NotebookDropDelegate(notebook: nb, context: viewContext))
        .contextMenu {
            Button("Sil") { deleteNotebook(nb) }
        }
    }

    @ViewBuilder
    private func tagRow(_ tag: Tag) -> some View {
        let active = isSelectedRow(.tag(tag.objectID))
        let color = tag.categoryColor.swiftUIColor
        let count = tag.notesCount
        let isMultiSelected = selectedTagIDs.contains(tag.objectID)

        Button {
            if isTagSelectionMode {
                if selectedTagIDs.contains(tag.objectID) {
                    selectedTagIDs.remove(tag.objectID)
                } else {
                    selectedTagIDs.insert(tag.objectID)
                }
            } else {
                selection = .tag(tag.objectID)
            }
        } label: {
            HStack(spacing: 8) {
                if isTagSelectionMode {
                    Image(systemName: isMultiSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundColor(isMultiSelected ? themeManager.accentColor : themeManager.secondaryText)
                } else {
                    Circle()
                        .fill(color)
                        .frame(width: 9, height: 9)
                }
                Text(tag.displayName)
                    .font(.system(size: 13, weight: active ? .semibold : .regular))
                    .foregroundColor(themeManager.textColor)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("(\(count))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(active ? themeManager.accentColor : (count == 0 ? .red.opacity(0.5) : themeManager.secondaryText))
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isTagSelectionMode {
                Button(isMultiSelected ? "Seçimi Kaldır" : "Seç") {
                    if isMultiSelected {
                        selectedTagIDs.remove(tag.objectID)
                    } else {
                        selectedTagIDs.insert(tag.objectID)
                    }
                }
            }
            Button("Sil") { deleteTag(tag) }
            if tag.notesCount == 0 {
                Divider()
                Button("İlişkisiz etiketleri temizle") {
                    showCleanUnusedTagsConfirm = true
                }
            }
        }
    }

    /// Etiketleri sırala: alfabetik veya not sayısına göre
    private var sortedTags: [Tag] {
        let allTags = Array(tags)
        if tagSort == "count" {
            return allTags.sorted { $0.notesCount > $1.notesCount }
        }
        return allTags.sorted { ($0.displayName) < ($1.displayName) }
    }

    private func sectionHeader(title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.6)
            .foregroundColor(themeManager.secondaryText)
            .padding(.top, 4)
    }

    private func collapsibleHeader(title: String, isExpanded: Binding<Bool>) -> some View {
        collapsibleHeaderInline(title: title, isExpanded: isExpanded)
    }

    @ViewBuilder
    private func collapsibleHeaderInline(title: String, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(themeManager.secondaryText)
                    .frame(width: 10)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(themeManager.secondaryText)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.top, 4)
        }
        .buttonStyle(.plain)
    }

    private func addButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12))
                .foregroundColor(themeManager.secondaryText)
        }
        .buttonStyle(.plain)
    }

    private func isSelectedRow(_ sel: SidebarSelection) -> Bool {
        selection == sel
    }

    // MARK: - Counts

    private var allCount: Int {
        allNotes.filter { !$0.isTrashed && !$0.isArchived }.count
    }
    private var notebookCount: Int {
        flatNotebooks.count
    }
    private var favoritesCount: Int {
        allNotes.filter { !$0.isTrashed && $0.isFavorite }.count
    }
    private var archivedCount: Int {
        allNotes.filter { !$0.isTrashed && $0.isArchived }.count
    }
    private var trashCount: Int {
        allNotes.filter { $0.isTrashed }.count
    }

    // MARK: - Flat Notebooks

    private var flatNotebooks: [(notebook: Notebook, level: Int)] {
        var result: [(notebook: Notebook, level: Int)] = []
        func flatten(_ notebooks: [Notebook], level: Int) {
            for notebook in notebooks {
                result.append((notebook, level))
                let children = notebook.childrenArray
                if !children.isEmpty {
                    let idStr = notebook.objectID.uriRepresentation().absoluteString
                    if !collapsedNotebookIDs.contains(idStr) {
                        flatten(children, level: level + 1)
                    }
                }
            }
        }
        flatten(Array(rootNotebooks), level: 0)
        return result
    }

    private func toggleNotebookExpanded(_ notebook: Notebook) {
        let idStr = notebook.objectID.uriRepresentation().absoluteString
        withAnimation(.easeInOut(duration: 0.25)) {
            if collapsedNotebookIDs.contains(idStr) {
                collapsedNotebookIDs.remove(idStr)
            } else {
                collapsedNotebookIDs.insert(idStr)
            }
        }
    }

    // MARK: - Actions

    private func createNotebook() {
        let name = newNotebookName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            showNewNotebook = false
            return
        }
        let notebook = Notebook(context: viewContext)
        notebook.name = name
        notebook.createdAt = Date()
        notebook.updatedAt = Date()
        notebook.icon = "folder"
        do {
            try viewContext.save()
        } catch {
            print("⚠️ Create notebook error: \(error)")
        }
        newNotebookName = ""
        showNewNotebook = false
    }

    private func createTag() {
        let name = newTagName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            showNewTag = false
            return
        }
        let tag = Tag(context: viewContext)
        tag.name = name
        tag.color = newTagColor.rawValue
        tag.createdAt = Date()
        do {
            try viewContext.save()
        } catch {
            print("⚠️ Create tag error: \(error)")
        }
        newTagName = ""
        showNewTag = false
    }

    private func deleteTag(_ tag: Tag) {
        viewContext.delete(tag)
        do {
            try viewContext.save()
        } catch {
            print("⚠️ Delete tag error: \(error)")
        }
    }

    // MARK: - Bulk Tag Operations

    private func bulkDeleteSelectedTags() {
        let ids = selectedTagIDs
        for id in ids {
            if let tag = try? viewContext.existingObject(with: id) as? Tag {
                viewContext.delete(tag)
            }
        }
        do {
            try viewContext.save()
        } catch {
            print("⚠️ Bulk delete tags error: \(error)")
        }
        selectedTagIDs.removeAll()
        isTagSelectionMode = false
    }

    private func deleteUnusedTags() {
        let unused = tags.filter { $0.notesCount == 0 }
        for tag in unused {
            viewContext.delete(tag)
        }
        do {
            try viewContext.save()
        } catch {
            print("⚠️ Clean unused tags error: \(error)")
        }
    }

    private func deleteNotebook(_ notebook: Notebook) {
        viewContext.delete(notebook)
        do {
            try viewContext.save()
        } catch {
            print("⚠️ Delete notebook error: \(error)")
        }
    }
}

// MARK: - Notebook Drag & Drop Delegate

/// Accepts both dragged notes (UUID string) and dragged notebooks
/// (prefixed "notebook:" + objectID URI string) and handles them accordingly:
/// - Note drop: moves the note into the target notebook.
/// - Notebook drop: nests the dropped notebook under the target (sets parent).
struct NotebookDropDelegate: DropDelegate {
    let notebook: Notebook
    let context: NSManagedObjectContext

    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [.text]).first else { return false }
        let ctx = context
        let targetID = notebook.objectID
        item.loadObject(ofClass: NSString.self) { reading, _ in
            guard let str = reading as? String, !str.isEmpty else { return }

            if str.hasPrefix("notebook:") {
                // Notebook being nested under target
                let uriString = String(str.dropFirst("notebook:".count))
                guard let url = URL(string: uriString),
                      let coordinator = ctx.persistentStoreCoordinator,
                      let droppedID = coordinator.managedObjectID(forURIRepresentation: url) else { return }

                DispatchQueue.main.async {
                    guard let droppedNotebook = try? ctx.existingObject(with: droppedID) as? Notebook,
                          let targetNotebook = try? ctx.existingObject(with: targetID) as? Notebook else {
                        return
                    }
                    // Prevent dropping on self
                    if droppedNotebook == targetNotebook { return }
                    // Prevent creating a cycle (dropping ancestor onto descendant)
                    if Self.isDescendant(targetNotebook, of: droppedNotebook) { return }

                    droppedNotebook.parent = targetNotebook
                    targetNotebook.updatedAt = Date()
                    do {
                        try ctx.save()
                    } catch {
                        print("⚠️ Drop nest notebook error: \(error)")
                        ctx.rollback()
                    }
                }
            } else {
                // Note being moved into notebook (existing behavior)
                let uuidString = str
                DispatchQueue.main.async {
                    let req = NSFetchRequest<Note>(entityName: "Note")
                    req.predicate = NSPredicate(format: "uuid == %@", uuidString)
                    req.fetchLimit = 1
                    guard let note = try? ctx.fetch(req).first,
                          let targetNotebook = try? ctx.existingObject(with: targetID) as? Notebook else {
                        return
                    }
                    note.notebook = targetNotebook
                    note.updatedAt = Date()
                    do {
                        try ctx.save()
                        if let uuid = note.uuid {
                            FTS5Manager.shared.indexNote(uuid: uuid, title: note.title ?? "", content: note.plainText ?? "")
                        }
                    } catch {
                        print("⚠️ Drop move note error: \(error)")
                        ctx.rollback()
                    }
                }
            }
        }
        return true
    }

    /// Returns true if `target` is a descendant of `ancestor` (prevents cycles).
    private static func isDescendant(_ target: Notebook, of ancestor: Notebook) -> Bool {
        var current: Notebook? = target.parent
        while let parent = current {
            if parent == ancestor { return true }
            current = parent.parent
        }
        return false
    }
}
