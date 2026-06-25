import Foundation

/// Sort options for the note list, persisted via @AppStorage("notes.sortOption").
enum NoteSortOption: String, CaseIterable {
    case updatedDesc = "Değiştirilme (Yeni)"
    case updatedAsc = "Değiştirilme (Eski)"
    case createdDesc = "Oluşturulma (Yeni)"
    case createdAsc = "Oluşturulma (Eski)"
    case titleAsc = "Alfabetik (A-Z)"
    case titleDesc = "Alfabetik (Z-A)"
    case sizeDesc = "Boyut (Büyük)"
    case sizeAsc = "Boyut (Küçük)"

    /// SF Symbol icon for the menu row.
    var iconName: String {
        switch self {
        case .updatedDesc: return "arrow.down.circle"
        case .updatedAsc: return "arrow.up.circle"
        case .createdDesc: return "arrow.down.doc"
        case .createdAsc: return "arrow.up.doc"
        case .titleAsc: return "textformat.abc"
        case .titleDesc: return "textformat.abc.diacritical"
        case .sizeDesc: return "arrow.down.square"
        case .sizeAsc: return "arrow.up.square"
        }
    }

    /// Applies the sort to an array of notes and returns the sorted result.
    /// Pinned notes ALWAYS appear first (regardless of sort option); within
    /// each group (pinned / non-pinned) the selected option is applied.
    static func sort(_ notes: [Note], by option: NoteSortOption) -> [Note] {
        let pinned = notes.filter { $0.isPinned }
        let nonPinned = notes.filter { !$0.isPinned }
        // If nothing is pinned, skip the extra work.
        guard !pinned.isEmpty else {
            return applyOption(notes, by: option)
        }
        return applyOption(pinned, by: option) + applyOption(nonPinned, by: option)
    }

    /// Sorts an array purely by the selected option (no pin grouping).
    private static func applyOption(_ notes: [Note], by option: NoteSortOption) -> [Note] {
        switch option {
        case .updatedDesc:
            return notes.sorted { ($0.updatedAt ?? Date.distantPast) > ($1.updatedAt ?? Date.distantPast) }
        case .updatedAsc:
            return notes.sorted { ($0.updatedAt ?? Date.distantPast) < ($1.updatedAt ?? Date.distantPast) }
        case .createdDesc:
            return notes.sorted { ($0.createdAt ?? Date.distantPast) > ($1.createdAt ?? Date.distantPast) }
        case .createdAsc:
            return notes.sorted { ($0.createdAt ?? Date.distantPast) < ($1.createdAt ?? Date.distantPast) }
        case .titleAsc:
            return notes.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        case .titleDesc:
            return notes.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedDescending }
        case .sizeDesc:
            return notes.sorted { ($0.plainText?.count ?? 0) > ($1.plainText?.count ?? 0) }
        case .sizeAsc:
            return notes.sorted { ($0.plainText?.count ?? 0) < ($1.plainText?.count ?? 0) }
        }
    }
}
