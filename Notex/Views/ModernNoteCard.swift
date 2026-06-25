import SwiftUI

/// Modern note card with colored category indicator.
/// Supports list layout (full width, horizontal) and grid layout (2-column tile).
/// Density (comfortable / compact) adjusts spacing.
struct ModernNoteCard: View {
    @ObservedObject var note: Note
    let isSelected: Bool
    let accentColor: Color
    let layout: CardLayout
    let density: NoteDensity
    var searchQuery: String = ""
    let onClick: () -> Void

    @EnvironmentObject private var themeManager: ThemeManager

    enum CardLayout {
        case listRow
        case gridTile
    }

    var body: some View {
        switch layout {
        case .listRow:
            listRowCard
        case .gridTile:
            gridTileCard
        }
    }

    // MARK: - List Row

    private var listRowCard: some View {
        Button(action: onClick) {
            HStack(spacing: 10) {
                // Colored category indicator bar (left accent)
                RoundedRectangle(cornerRadius: 2)
                    .fill(note.categoryColor.swiftUIColor)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: vSpacing) {
                    HStack(spacing: 4) {
                        if note.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9))
                                .rotationEffect(.degrees(30))
                                .foregroundColor(isSelected ? Color.white.opacity(0.9) : themeManager.accentColor)
                        }
                        if note.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundColor(isSelected ? Color.white.opacity(0.9) : .yellow)
                        }

                        Text(highlightedTitle)
                            .font(.system(size: density == .comfortable ? 14 : 13, weight: .semibold))
                            .lineLimit(1)
                            .foregroundColor(isSelected ? .white : .primary)

                        Spacer(minLength: 0)
                    }

                    if density == .comfortable && !note.displayPreview.isEmpty {
                        Text(highlightedPreview)
                            .font(.system(size: 11))
                            .lineLimit(2)
                            .foregroundColor(isSelected ? Color.white.opacity(0.72) : noteSecondary)
                    }

                    // Footer: category dot + label · date
                    HStack(spacing: 5) {
                        categoryChip(inline: true)
                        Spacer(minLength: 0)
                        Text(note.shortDateLabel)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(isSelected ? Color.white.opacity(0.65) : noteSecondary)
                    }
                }
                .padding(.trailing, 6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, density == .comfortable ? 10 : 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grid Tile

    private var gridTileCard: some View {
        Button(action: onClick) {
            VStack(alignment: .leading, spacing: vSpacing) {
                // Top row: category dot + date
                HStack(spacing: 6) {
                    Circle()
                        .fill(note.categoryColor.swiftUIColor)
                        .frame(width: 7, height: 7)
                    Text(note.categoryLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(note.categoryColor.swiftUIColor)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .rotationEffect(.degrees(30))
                            .foregroundColor(isSelected ? Color.white.opacity(0.65) : noteSecondary)
                    }
                    Text(note.shortDateLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(isSelected ? Color.white.opacity(0.65) : noteSecondary)
                }

                // Title
                Text(highlightedTitle)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(2)
                    .foregroundColor(isSelected ? .white : .primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                // Preview
                if !note.displayPreview.isEmpty {
                    Text(highlightedPreview)
                        .font(.system(size: 11))
                        .lineLimit(3)
                        .foregroundColor(isSelected ? Color.white.opacity(0.72) : noteSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }

                // Tag dots footer
                if !note.tagsArray.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(note.tagsArray.prefix(4), id: \.objectID) { tag in
                            Circle()
                                .fill(tag.categoryColor.swiftUIColor)
                                .frame(width: 5, height: 5)
                        }
                        if note.tagsArray.count > 4 {
                            Text("+\(note.tagsArray.count - 4)")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(noteSecondary)
                        }
                        Spacer(minLength: 0)
                        if note.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8))
                                .rotationEffect(.degrees(30))
                                .foregroundColor(isSelected ? Color.white.opacity(0.8) : themeManager.accentColor)
                        }
                        if note.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundColor(isSelected ? Color.white.opacity(0.8) : .yellow)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: density == .comfortable ? 132 : 108)
            .background(tileBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? accentColor.opacity(0.0) : borderColor, lineWidth: 1)
            )
            .cornerRadius(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func categoryChip(inline: Bool) -> some View {
        if inline {
            HStack(spacing: 4) {
                Circle()
                    .fill(note.categoryColor.swiftUIColor)
                    .frame(width: 6, height: 6)
                Text(note.categoryLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(isSelected ? Color.white.opacity(0.7) : noteSecondary)
                    .lineLimit(1)
            }
        }
    }

    private var vSpacing: CGFloat {
        density == .comfortable ? 5 : 3
    }

    private var noteSecondary: Color {
        themeManager.secondaryText
    }

    private var rowBackground: Color {
        if isSelected { return accentColor }
        return Color.clear
    }

    private var tileBackground: Color {
        if isSelected { return accentColor.opacity(0.12) }
        return themeManager.cardBackground
    }

    private var borderColor: Color {
        Color.secondary.opacity(0.12)
    }

    // MARK: - Search Highlighting

    private var highlightedTitle: AttributedString {
        highlightSearch(note.displayTitle, query: searchQuery)
    }

    private var highlightedPreview: AttributedString {
        highlightSearch(note.displayPreview, query: searchQuery)
    }
}

// MARK: - Search Highlight Helper

/// Highlights all case-insensitive occurrences of `query` in `text` with a yellow
/// background and black foreground. Returns a plain `AttributedString` when the
/// query is empty (so no highlighting is applied during normal browsing).
func highlightSearch(_ text: String, query: String) -> AttributedString {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return AttributedString(text) }

    var attr = AttributedString(text)
    let lower = text.lowercased()
    let q = trimmed.lowercased()

    var searchStart = lower.startIndex
    while let range = lower.range(of: q, range: searchStart..<lower.endIndex) {
        if let attrRange = attr.range(of: String(text[range]), options: .caseInsensitive) {
            attr[attrRange].backgroundColor = .yellow
            attr[attrRange].foregroundColor = .black
        }
        searchStart = range.upperBound
    }
    return attr
}
