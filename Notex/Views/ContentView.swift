import SwiftUI
import CoreData
import AppKit

// MARK: - SidebarSelection

enum SidebarSelection: Hashable {
    case allNotes
    case favorites
    case archived
    case trash
    case notebooksGrid
    case notebook(NSManagedObjectID)
    case tag(NSManagedObjectID)
}

// MARK: - ContentView

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var selectedNote: Note?
    @State private var sidebarSelection: SidebarSelection? = .allNotes
    @State private var focusMode = false
    @State private var searchText = ""
    @State private var showSplash: Bool = true
    @State private var showTemplatePicker: Bool = false

    var body: some View {
        Group {
            if focusMode {
                FocusModeContainer(
                    note: selectedNote,
                    onExit: { focusMode = false }
                )
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(themeManager)
            } else {
                NavigationSplitView {
                    SidebarView(selection: $sidebarSelection)
                        .environment(\.managedObjectContext, viewContext)
                        .environmentObject(themeManager)
                } content: {
                    NoteListView(
                        sidebarSelection: $sidebarSelection,
                        selectedNote: $selectedNote,
                        searchText: $searchText
                    )
                    .environment(\.managedObjectContext, viewContext)
                    .environmentObject(themeManager)
                } detail: {
                    if let note = selectedNote, !note.isDeleted {
                        NoteEditorView(note: note)
                            .environment(\.managedObjectContext, viewContext)
                            .environmentObject(themeManager)
                    } else {
                        EmptyEditorView()
                            .environmentObject(themeManager)
                            .background(themeManager.editorBackground)
                    }
                }
                .tint(themeManager.accentColor)
            }
        }
        .background(themeManager.backgroundColor)
        .overlay(alignment: .center) {
            if showSplash {
                SplashView {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showSplash = false
                    }
                }
                .zIndex(1000)
                .transition(.opacity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleFocusMode)) { _ in
            focusMode.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .createNewNote)) { _ in
            showTemplatePicker = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .createNewNotebook)) { _ in
            NotificationCenter.default.post(name: .createNewNotebookInternal, object: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToNote)) { notification in
            if let id = notification.object as? NSManagedObjectID {
                selectedNote = try? viewContext.existingObject(with: id) as? Note
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openImportSheet)) { _ in
            // Open the Settings window (focused on Import tab)
            if #available(macOS 14.0, *) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } else {
                NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            }
        }
        .sheet(isPresented: $showTemplatePicker) {
            TemplatePickerView(
                onSelect: { template in
                    showTemplatePicker = false
                    createNewNote(with: template)
                },
                onCancel: {
                    showTemplatePicker = false
                }
            )
            .environmentObject(themeManager)
        }
        .onAppear {
            autoCleanOldTrash()
        }
    }

    private func createNewNote(with template: NoteTemplate = .empty) {
        let note = Note(context: viewContext)
        note.uuid = UUID().uuidString
        note.title = ""
        note.createdAt = Date()
        note.updatedAt = Date()

        // Apply template content (plain text → attributed string)
        let body = template.content
        note.plainText = body
        note.content = Note.encodeAttributedString(NSAttributedString(string: body))

        // Determine target notebook: explicit default notebook setting takes
        // priority, otherwise fall back to the currently selected notebook.
        let defaultNotebookURI = UserDefaults.standard.string(forKey: "sidebar.defaultNotebook") ?? ""
        if !defaultNotebookURI.isEmpty,
           let url = URL(string: defaultNotebookURI),
           let coordinator = viewContext.persistentStoreCoordinator,
           let objectID = coordinator.managedObjectID(forURIRepresentation: url) {
            note.notebook = try? viewContext.existingObject(with: objectID) as? Notebook
        } else if case .notebook(let id) = sidebarSelection {
            note.notebook = try? viewContext.existingObject(with: id) as? Notebook
        }

        do {
            try viewContext.save()
            selectedNote = note
            if let uuid = note.uuid {
                FTS5Manager.shared.indexNote(uuid: uuid, title: "", content: body)
            }
        } catch {
            print("⚠️ Create note error: \(error)")
            viewContext.rollback()
        }
    }

    /// Permanently deletes trashed notes older than 30 days (auto-cleanup on launch).
    private func autoCleanOldTrash() {
        let request = NSFetchRequest<Note>(entityName: "Note")
        request.predicate = NSPredicate(format: "isTrashed == YES")
        let trashedNotes = (try? viewContext.fetch(request)) ?? []
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        var deletedAny = false
        for note in trashedNotes {
            if let updated = note.updatedAt, updated < cutoff {
                if let uuid = note.uuid { FTS5Manager.shared.deleteNote(uuid: uuid) }
                viewContext.delete(note)
                deletedAny = true
            }
        }
        if deletedAny {
            try? viewContext.save()
        }
    }
}

// MARK: - EmptyEditorView

struct EmptyEditorView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundColor(Color.secondary.opacity(0.6))
            Text("Bir not seçin")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("veya ⌘N ile yeni bir not oluşturun")
                .font(.caption)
                .foregroundColor(Color.secondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - FocusModeContainer

struct FocusModeContainer: View {
    let note: Note?
    let onExit: () -> Void
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let note = note, !note.isDeleted {
                NoteEditorView(note: note, isFocusMode: true)
                    .environment(\.managedObjectContext, viewContext)
                    .environmentObject(themeManager)
            } else {
                Text("Odak modu için bir not seçin")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Button(action: onExit) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(12)
        }
    }
}

// MARK: - Internal Notification Names

extension Notification.Name {
    static let createNewNotebookInternal = Notification.Name("NotexCreateNewNotebookInternal")
    static let openImportSheet = Notification.Name("NotexOpenImportSheet")
}