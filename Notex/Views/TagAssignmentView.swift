import SwiftUI
import CoreData

/// Popover view for assigning tags to a note.
struct TagAssignmentView: View {
    @ObservedObject var note: Note
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)],
        animation: .default
    ) private var allTags: FetchedResults<Tag>

    @State private var newTagName = ""
    @State private var selectedColor: Color_TagHelper = .blue

    private var noteTagIDs: Set<NSManagedObjectID> {
        Set(note.tagsArray.map { $0.objectID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Etiketler")
                .font(.headline)

            // New tag creation
            HStack {
                TextField("Yeni etiket", text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { createTag() }

                ForEach(Color_TagHelper.allCases, id: \.self) { color in
                    Circle()
                        .fill(color.swiftUIColor)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle()
                                .stroke(selectedColor == color ? Color.primary : Color.clear, lineWidth: 2)
                        )
                        .onTapGesture { selectedColor = color }
                }

                Button {
                    createTag()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .disabled(newTagName.isEmpty)
            }

            Divider()

            // Tag list
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if allTags.isEmpty {
                        Text("Henüz etiket yok")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    }

                    ForEach(allTags, id: \.objectID) { tag in
                        Toggle(isOn: Binding(
                            get: { noteTagIDs.contains(tag.objectID) },
                            set: { isOn in toggleTag(tag, isOn: isOn) }
                        )) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(tag.tagColor.swiftUIColor)
                                    .frame(width: 10, height: 10)
                                Text(tag.displayName)
                                    .font(.system(size: 13))
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Tamam") { dismiss() }
                    .keyboardShortcut(.return)
            }
        }
        .padding(16)
        .frame(width: 320, height: 360)
    }

    private func createTag() {
        let name = newTagName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let tag = Tag(context: viewContext)
        tag.name = name
        tag.color = selectedColor.rawValue
        tag.createdAt = Date()

        let noteTag = NoteTag(context: viewContext)
        noteTag.note = note
        noteTag.tag = tag

        do {
            try viewContext.save()
            newTagName = ""
        } catch {
            print("⚠️ Create tag error: \(error)")
            viewContext.rollback()
        }
    }

    private func toggleTag(_ tag: Tag, isOn: Bool) {
        if isOn {
            let noteTag = NoteTag(context: viewContext)
            noteTag.note = note
            noteTag.tag = tag
        } else {
            if let existing = (note.noteTags as? Set<NoteTag>)?.first(where: { $0.tag == tag }) {
                viewContext.delete(existing)
            }
        }

        do {
            try viewContext.save()
        } catch {
            print("⚠️ Toggle tag error: \(error)")
            viewContext.rollback()
        }
    }
}
