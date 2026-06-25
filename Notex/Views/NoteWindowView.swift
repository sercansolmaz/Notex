import SwiftUI
import CoreData

/// Separate window for viewing/editing a single note, opened via double-click.
struct NoteWindowView: View {
    let noteUUID: String?

    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var note: Note?

    var body: some View {
        Group {
            if let note = note {
                NoteEditorView(note: note)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.questionmark")
                        .font(.system(size: 40))
                        .foregroundColor(themeManager.secondaryText)
                    Text("Not bulunamadı")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(themeManager.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(themeManager.editorBackground)
            }
        }
        .onAppear { fetchNote() }
        .onChange(of: noteUUID) { _, _ in fetchNote() }
    }

    private func fetchNote() {
        guard let uuid = noteUUID, !uuid.isEmpty else {
            note = nil
            return
        }
        let request: NSFetchRequest<Note> = Note.fetchRequest()
        request.predicate = NSPredicate(format: "uuid == %@", uuid)
        request.fetchLimit = 1
        do {
            note = try viewContext.fetch(request).first
        } catch {
            print("⚠️ NoteWindowView fetch error: \(error)")
            note = nil
        }
    }
}
