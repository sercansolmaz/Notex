import CoreData
import AppKit
import SwiftUI
import Foundation

// MARK: - Encoding / Decoding Helpers

extension Note {
    static func encodeAttributedString(_ attrString: NSAttributedString) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: attrString, requiringSecureCoding: false)
    }

    static func decodeAttributedString(from data: Data) -> NSAttributedString {
        if let result = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data) {
            return result
        }
        if let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) {
            unarchiver.requiresSecureCoding = false
            let result = unarchiver.decodeObject() as? NSAttributedString
            unarchiver.finishDecoding()
            return result ?? NSAttributedString()
        }
        return NSAttributedString()
    }
}

// MARK: - Category Color Palette (used for notebook + tag dots/badges)

/// Stable 9-color palette matching the design references.
enum CategoryColor: String, CaseIterable, Identifiable {
    case green, orange, blue, purple, pink, teal, yellow, red, indigo

    var id: String { rawValue }

    var swiftUIColor: SwiftUI.Color {
        switch self {
        case .green:   return SwiftUI.Color(red: 0.30, green: 0.74, blue: 0.44)
        case .orange:  return SwiftUI.Color(red: 0.95, green: 0.55, blue: 0.20)
        case .blue:    return SwiftUI.Color(red: 0.21, green: 0.48, blue: 0.91)
        case .purple:  return SwiftUI.Color(red: 0.58, green: 0.35, blue: 0.82)
        case .pink:    return SwiftUI.Color(red: 0.95, green: 0.38, blue: 0.62)
        case .teal:    return SwiftUI.Color(red: 0.20, green: 0.70, blue: 0.68)
        case .yellow:  return SwiftUI.Color(red: 0.92, green: 0.76, blue: 0.22)
        case .red:     return SwiftUI.Color(red: 0.90, green: 0.27, blue: 0.27)
        case .indigo:  return SwiftUI.Color(red: 0.31, green: 0.33, blue: 0.74)
        }
    }

    var displayName: String {
        switch self {
        case .green:   return "Yeşil"
        case .orange:  return "Turuncu"
        case .blue:    return "Mavi"
        case .purple:  return "Mor"
        case .pink:    return "Pembe"
        case .teal:    return "Turkuaz"
        case .yellow:  return "Sarı"
        case .red:     return "Kırmızı"
        case .indigo:  return "Çivit"
        }
    }

    /// Deterministic color from an arbitrary string (djb2 hash).
    static func from(_ text: String?) -> CategoryColor {
        let palette = CategoryColor.allCases
        guard let name = text, !name.isEmpty else { return .blue }
        var hash: UInt64 = 5381
        for byte in name.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return palette[Int(hash % UInt64(palette.count))]
    }
}

// MARK: - Note Computed Properties

extension Note {
    var displayTitle: String {
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? "Başlıksız" : t
    }

    var displayPreview: String {
        let text = plainText ?? ""
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if lines.count > 1 {
            return lines.dropFirst().joined(separator: " ").prefix(140).description
        }
        return text.prefix(140).description
    }

    var tagsArray: [Tag] {
        let set = noteTags as? Set<NoteTag> ?? []
        return set.compactMap { $0.tag }.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    /// Primary category color for a note: notebook's color first, else first tag's color.
    var categoryColor: CategoryColor {
        if let notebook = notebook {
            return notebook.notebookColor
        }
        if let firstTag = tagsArray.first {
            return CategoryColor(rawValue: firstTag.color ?? "blue") ?? .blue
        }
        return .blue
    }

    /// Short category label shown on cards (notebook name or first tag name).
    var categoryLabel: String {
        if let notebook = notebook {
            return notebook.displayName
        }
        if let firstTag = tagsArray.first {
            return firstTag.displayName
        }
        return "Genel"
    }

    var dateLabel: String {
        guard let date = updatedAt else { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "BUGÜN" }
        if calendar.isDateInYesterday(date) { return "DÜN" }
        let daysAgo = calendar.dateComponents([.day], from: date, to: Date()).day ?? 0
        if daysAgo < 7 { return "\(daysAgo) GÜN ÖNCE" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date).uppercased()
    }

    var shortDateLabel: String {
        guard let date = updatedAt else { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "tr_TR")
            f.dateFormat = "HH:mm"
            return f.string(from: date)
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }

    var fullDateText: String {
        guard let date = updatedAt else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var wordCount: Int {
        let text = plainText ?? ""
        return text.split { $0.isWhitespace }.count
    }

    var characterCount: Int {
        plainText?.count ?? 0
    }

    var readingTimeText: String {
        let words = wordCount
        let minutes = max(1, Int(ceil(Double(words) / 200.0)))
        return "\(minutes) dk okuma"
    }

    var displayUUID: String {
        if let u = uuid, !u.isEmpty { return u }
        let newUUID = UUID().uuidString
        uuid = newUUID
        return newUUID
    }

    var backlinkNotes: [Note] {
        let links = incomingLinks as? Set<NoteLink> ?? []
        return links.compactMap { $0.srcNote }
            .sorted { ($0.updatedAt ?? Date.distantPast) > ($1.updatedAt ?? Date.distantPast) }
    }

    var outgoingNotes: [Note] {
        let links = outgoingLinks as? Set<NoteLink> ?? []
        return links.compactMap { $0.dstNote }
            .sorted { $0.displayTitle < $1.displayTitle }
    }

    var thumbnailImage: NSImage? {
        nil
    }
}

// MARK: - Notebook Computed Properties

extension Notebook {
    var childrenArray: [Notebook] {
        let set = children as? Set<Notebook> ?? []
        return set.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    var notesArray: [Note] {
        let set = notes as? Set<Note> ?? []
        return set.sorted { ($0.updatedAt ?? Date.distantPast) > ($1.updatedAt ?? Date.distantPast) }
    }

    var displayName: String {
        name?.isEmpty == false ? name! : "İsimsiz Defter"
    }

    /// Deterministic category color derived from the notebook's name (hash-based).
    var notebookColor: CategoryColor {
        CategoryColor.from(name)
    }

    /// Count of notes that are NOT trashed and NOT archived, directly in this notebook.
    var activeNotesCount: Int {
        notesArray.filter { !$0.isTrashed && !$0.isArchived }.count
    }

    /// Recursive count of all active (non-trashed, non-archived) notes including
    /// child notebooks' notes.
    var allNotesCount: Int {
        var total = activeNotesCount
        for child in childrenArray {
            total += child.allNotesCount
        }
        return total
    }

    /// Recursive count of all notes including children (synonym for allNotesCount).
    var totalNotesCount: Int {
        allNotesCount
    }

    /// Recursive count of direct + children notes regardless of trashed/archived state.
    var totalAllNotesCount: Int {
        var total = notesArray.count
        for child in childrenArray {
            total += child.totalAllNotesCount
        }
        return total
    }

    /// True if this notebook has child notebooks.
    var hasChildren: Bool {
        !(childrenArray.isEmpty)
    }
}

// MARK: - Tag Computed Properties

extension Tag {
    var displayName: String {
        name?.isEmpty == false ? name! : "İsimsiz Etiket"
    }

    var tagColor: Color_TagHelper {
        Color_TagHelper(rawValue: color ?? "blue") ?? .blue
    }

    /// Maps the legacy stored color string into the modern CategoryColor palette.
    var categoryColor: CategoryColor {
        CategoryColor(rawValue: color ?? "blue") ?? .blue
    }

    var notesCount: Int {
        let set = noteTags as? Set<NoteTag> ?? []
        return set.count
    }
}

enum Color_TagHelper: String, CaseIterable {
    case blue, purple, pink, red, orange, yellow, green, teal, gray

    var nsColor: NSColor {
        switch self {
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .pink: return .systemPink
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .teal: return .systemTeal
        case .gray: return .systemGray
        }
    }

    var swiftUIColor: SwiftUI.Color {
        SwiftUI.Color(nsColor)
    }
}
