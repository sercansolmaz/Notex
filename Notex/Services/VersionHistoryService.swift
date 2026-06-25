import Foundation
import CoreData

/// Stores version snapshots of notes as JSON files under
/// `~/Library/Application Support/Notex/versions/<noteUUID>/`.
/// Keeps at most 20 snapshots per note, oldest pruned first.
final class VersionHistoryService: @unchecked Sendable {
    static let shared = VersionHistoryService()

    private let maxSnapshots = 20
    /// Minimum characters of plain-text change before a new snapshot is recorded.
    private let minChangeThreshold = 20

    private let fm = FileManager.default

    private init() {}

    // MARK: - Directory

    private var baseDir: URL {
        let home = NSHomeDirectory()
        let appSupport = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/Notex/versions")
        if !fm.fileExists(atPath: appSupport.path) {
            try? fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
        return appSupport
    }

    private func dir(for uuid: String) -> URL {
        let d = baseDir.appendingPathComponent(uuid)
        if !fm.fileExists(atPath: d.path) {
            try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
        return d
    }

    // MARK: - Snapshot model

    struct Snapshot: Identifiable, Codable, Hashable {
        var id: String { timestamp }
        let timestamp: String          // ISO8601 string (also filename)
        let date: Date
        let title: String
        let plainText: String
        let contentBase64: String
    }

    // MARK: - Save

    /// Records a snapshot of the note if content changed significantly since the last one.
    func saveSnapshot(note: Note) {
        guard let uuid = note.uuid, !uuid.isEmpty else { return }
        let plain = note.plainText ?? ""
        let title = note.title ?? ""

        // Throttle: compare with most recent snapshot
        let existing = loadSnapshots(for: uuid)
        if let last = existing.last {
            let diff = abs(last.plainText.count - plain.count)
            if diff < minChangeThreshold && last.title == title {
                return
            }
        }

        let data = note.content ?? Data()
        let snapshot = Snapshot(
            timestamp: Self.isoStamp(from: Date()),
            date: Date(),
            title: title,
            plainText: plain,
            contentBase64: data.base64EncodedString()
        )

        let fileURL = dir(for: uuid).appendingPathComponent("\(snapshot.timestamp).json")
        do {
            let encoded = try JSONEncoder().encode(snapshot)
            try encoded.write(to: fileURL, options: .atomic)
        } catch {
            print("⚠️ VersionHistory: failed to write snapshot: \(error)")
        }

        pruneOldSnapshots(for: uuid)
    }

    // MARK: - Read

    /// Returns all snapshots for a note, ordered oldest → newest.
    func loadSnapshots(for uuid: String) -> [Snapshot] {
        let d = dir(for: uuid)
        guard let urls = try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)
                .filter({ $0.pathExtension == "json" }) else { return [] }

        var snapshots: [Snapshot] = []
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { continue }
            snapshots.append(snap)
        }
        return snapshots.sorted { $0.date < $1.date }
    }

    /// Lightweight preview list for the UI.
    func getSnapshots(for uuid: String) -> [(date: Date, title: String, preview: String)] {
        loadSnapshots(for: uuid).map {
            let preview = $0.plainText.prefix(200)
            return ($0.date, $0.title, String(preview))
        }
    }

    // MARK: - Restore

    /// Restores a snapshot's content onto the given note, saving the context.
    func restoreSnapshot(uuid: String, timestamp: String, context: NSManagedObjectContext) -> Bool {
        let snaps = loadSnapshots(for: uuid)
        guard let snap = snaps.first(where: { $0.timestamp == timestamp }) else { return false }

        let request: NSFetchRequest<Note> = Note.fetchRequest()
        request.predicate = NSPredicate(format: "uuid == %@", uuid)
        request.fetchLimit = 1

        guard let note = try? context.fetch(request).first else { return false }

        // Decode content
        if let data = Data(base64Encoded: snap.contentBase64) {
            note.content = data
        }
        note.plainText = snap.plainText
        note.title = snap.title
        note.updatedAt = Date()

        do {
            try context.save()
            if let u = note.uuid {
                FTS5Manager.shared.indexNote(uuid: u, title: snap.title, content: snap.plainText)
            }
            return true
        } catch {
            print("⚠️ VersionHistory: restore save failed: \(error)")
            context.rollback()
            return false
        }
    }

    // MARK: - Prune

    private func pruneOldSnapshots(for uuid: String) {
        var snaps = loadSnapshots(for: uuid)
        guard snaps.count > maxSnapshots else { return }
        let toDelete = snaps.count - maxSnapshots
        // oldest first
        snaps.sort { $0.date < $1.date }
        for i in 0..<toDelete {
            let url = dir(for: uuid).appendingPathComponent("\(snaps[i].timestamp).json")
            try? fm.removeItem(at: url)
        }
    }

    // MARK: - Helpers

    private static func isoStamp(from date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "_")
    }
}
