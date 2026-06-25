import CoreData
import Foundation

/// Parses [[wiki-link]] syntax from note text and maintains NoteLink relationships.
final class BacklinkService: @unchecked Sendable {
    static let shared = BacklinkService()

    private let wikiLinkRegex: NSRegularExpression?

    private init() {
        wikiLinkRegex = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#, options: [])
    }

    func extractWikiLinks(from text: String) -> [String] {
        guard let regex = wikiLinkRegex else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range]).trimmingCharacters(in: .whitespaces)
        }
    }

    /// Updates outgoing NoteLinks for the given note based on [[wiki-links]] in its text.
    func updateBacklinks(for note: Note, in context: NSManagedObjectContext) {
        // Remove existing outgoing links
        if let existing = note.outgoingLinks as? Set<NoteLink> {
            for link in existing {
                context.delete(link)
            }
        }

        // Extract wiki links from note content
        let text = note.plainText ?? ""
        let linkTexts = extractWikiLinks(from: text)
        guard !linkTexts.isEmpty else {
            do {
                try context.save()
            } catch {
                print("⚠️ Backlink save error: \(error)")
            }
            return
        }

        // Find matching notes by title (case-insensitive)
        for linkText in linkTexts {
            let request: NSFetchRequest<Note> = Note.fetchRequest()
            request.predicate = NSPredicate(format: "title ==[c] %@", linkText)

            do {
                let matchingNotes = try context.fetch(request)
                for dstNote in matchingNotes where dstNote != note {
                    let link = NoteLink(context: context)
                    link.linkText = linkText
                    link.createdAt = Date()
                    link.srcNote = note
                    link.dstNote = dstNote
                }
            } catch {
                print("⚠️ Backlink fetch error: \(error)")
            }
        }

        do {
            try context.save()
        } catch {
            print("⚠️ Backlink save error: \(error)")
        }
    }
}
