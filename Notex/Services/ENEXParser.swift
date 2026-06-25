import CoreData
import Foundation

/// SAX XML parser for Evernote .enex export files.
final class ENEXParser: NSObject, XMLParserDelegate {
    private var notes: [Note] = []
    private var context: NSManagedObjectContext!
    private var notebook: Notebook?

    private var currentElement = ""
    private var currentText = ""
    private var currentTitle = ""
    private var currentContent = ""
    private var currentCreated = Date()
    private var currentUpdated = Date()
    private var currentTags: [String] = []

    func parse(data: Data, context: NSManagedObjectContext, notebook: Notebook? = nil) -> [Note] {
        self.context = context
        self.notebook = notebook
        self.notes = []

        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        parser.parse()

        return notes
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        if elementName == "note" {
            currentTitle = ""
            currentContent = ""
            currentCreated = Date()
            currentUpdated = Date()
            currentTags = []
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if currentElement == "content" {
            if let text = String(data: CDATABlock, encoding: .utf8) {
                currentContent += text
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "title":
            currentTitle = value
        case "created":
            currentCreated = parseEvernoteDate(value) ?? Date()
        case "updated":
            currentUpdated = parseEvernoteDate(value) ?? Date()
        case "tag":
            if !value.isEmpty { currentTags.append(value) }
        case "note":
            createNote()
        default:
            break
        }
        currentText = ""
        currentElement = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        print("⚠️ ENEX parse error: \(parseError)")
    }

    // MARK: - Private

    private func createNote() {
        let note = Note(context: context)
        note.uuid = UUID().uuidString
        note.title = currentTitle
        note.createdAt = currentCreated
        note.updatedAt = currentUpdated
        note.notebook = notebook

        let attrString = ENMLConverter.shared.convert(enml: currentContent)
        note.plainText = attrString.string
        note.content = Note.encodeAttributedString(attrString)

        // Create tags
        for tagName in currentTags {
            let tag = getOrCreateTag(name: tagName)
            let noteTag = NoteTag(context: context)
            noteTag.note = note
            noteTag.tag = tag
        }

        notes.append(note)
    }

    private func getOrCreateTag(name: String) -> Tag {
        let request: NSFetchRequest<Tag> = Tag.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[c] %@", name)
        request.fetchLimit = 1
        if let existing = try? context.fetch(request).first {
            return existing
        }
        let tag = Tag(context: context)
        tag.name = name
        tag.color = "blue"
        tag.createdAt = Date()
        return tag
    }

    private func parseEvernoteDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: string)
    }
}