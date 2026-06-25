import SwiftUI
import CoreData

/// Grid of notebooks shown as colorful cards (görsel 3 inspiration).
/// Clicking a card navigates into that notebook.
struct NotebookGridView: View {
    var onSelect: (SidebarSelection) -> Void

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)],
        predicate: NSPredicate(format: "parent == nil"),
        animation: .default
    ) private var rootNotebooks: FetchedResults<Notebook>

    @EnvironmentObject private var themeManager: ThemeManager

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Defterler")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(themeManager.textColor)
                Text("\(rootNotebooks.count)")
                    .font(.system(size: 13))
                    .foregroundColor(themeManager.secondaryText)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            if allNotebooks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(allNotebooks, id: \.objectID) { notebook in
                            notebookCard(notebook)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(themeManager.backgroundColor)
    }

    // MARK: - Card

    private func notebookCard(_ notebook: Notebook) -> some View {
        let color = notebook.notebookColor.swiftUIColor
        let initial = String(notebook.displayName.prefix(1)).uppercased()
        let count = notebook.activeNotesCount

        return Button {
            onSelect(.notebook(notebook.objectID))
        } label: {
            VStack(spacing: 0) {
                // Cover area with big initial
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.85), color.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text(initial)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    // Note count badge
                    VStack {
                        HStack {
                            Spacer()
                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(color)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.white.opacity(0.9))
                                    .clipShape(Capsule())
                            }
                        }
                        Spacer()
                    }
                    .padding(8)
                }
                .frame(height: 90)

                // Name
                Text(notebook.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(themeManager.textColor)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("\(notebook.displayName) Defterini Aç") {
                onSelect(.notebook(notebook.objectID))
            }
        }
    }

    // MARK: - Helpers

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 40))
                .foregroundColor(themeManager.secondaryText)
            Text("Henüz defter yok")
                .font(.system(size: 13))
                .foregroundColor(themeManager.secondaryText)
            Text("Yeni bir defter oluşturmak için kenar çubuğundaki \"Yeni Defter\" düğmesini kullanın.")
                .font(.system(size: 11))
                .foregroundColor(themeManager.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Flatten all notebooks (root + children) for a richer grid.
    private var allNotebooks: [Notebook] {
        var result: [Notebook] = []
        func flatten(_ notebooks: [Notebook]) {
            for nb in notebooks {
                result.append(nb)
                flatten(nb.childrenArray)
            }
        }
        flatten(Array(rootNotebooks))
        return result
    }
}
