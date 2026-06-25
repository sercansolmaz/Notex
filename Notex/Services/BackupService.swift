import Foundation
import CoreData
import AppKit

/// Folder-based backup system. Exports all notes as Markdown + a JSON manifest
/// into a timestamped subfolder of the user-selected (or auto-configured) folder.
/// Works with any folder — iCloud Drive, Dropbox, Google Drive, or local — because
/// it just uses FileManager; the sync apps handle propagation.
struct BackupService {

    /// Backup frequency options.
    enum Frequency: String, CaseIterable, Identifiable {
        case daily = "daily"
        case weekly = "weekly"
        case monthly = "monthly"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .daily: return "Günlük"
            case .weekly: return "Haftalık"
            case .monthly: return "Aylık"
            }
        }

        var seconds: TimeInterval {
            switch self {
            case .daily: return 86_400
            case .weekly: return 604_800
            case .monthly: return 2_592_000
            }
        }
    }

    /// Plain data extracted from a Note — safe to use on any thread.
    struct BackupNoteData {
        let title: String
        let uuid: String
        let plainText: String
        let createdAt: Date
        let updatedAt: Date
        let notebookName: String
        let tagNames: [String]
        let isFavorite: Bool
        let isArchived: Bool
    }

    struct BackupResult {
        let success: Bool
        let folderURL: URL?
        let noteCount: Int
        let message: String
    }

    // MARK: - Manual Backup (with picker)

    /// Presents a folder picker (NSOpenPanel) and performs a backup into the
    /// chosen directory. Must be called from the main thread (NSOpenPanel).
    @MainActor
    static func performBackupWithPicker(context: NSManagedObjectContext) -> BackupResult {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Yedekle"
        panel.title = "Yedekleme Klasörü Seçin"
        panel.message = "Notlar bu klasörün içine zaman damgalı bir alt klasör olarak yedeklenecek."

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            return BackupResult(success: false, folderURL: nil, noteCount: 0, message: "İptal edildi")
        }

        UserDefaults.standard.set(url.path, forKey: "backup.folderPath")
        return performBackup(context: context, destination: url)
    }

    // MARK: - Core Backup Logic (thread-safe)

    /// Performs a backup into the given destination directory, creating a
    /// timestamped subfolder. Safe to call from any thread — Core Data access
    /// is wrapped in `context.performAndWait`.
    static func performBackup(context: NSManagedObjectContext, destination: URL) -> BackupResult {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())

        let backupFolderName = "notex_backup_\(timestamp)"
        let backupFolderURL = destination.appendingPathComponent(backupFolderName)

        do {
            try FileManager.default.createDirectory(at: backupFolderURL, withIntermediateDirectories: true)
        } catch {
            return BackupResult(success: false, folderURL: nil, noteCount: 0,
                                message: "Klasör oluşturulamadı: \(error.localizedDescription)")
        }

        // Extract note data on the context's queue (thread-safe)
        let noteData = extractNoteData(context: context)

        // Write files — safe on any thread
        var manifestEntries: [[String: Any]] = []
        var successCount = 0
        let isoFormatter = ISO8601DateFormatter()

        for item in noteData {
            let markdown = "# \(item.title)\n\n\(item.plainText)\n"
            let safeTitle = sanitizeFileName(item.title)
            let fileName = "\(safeTitle)_\(String(item.uuid.prefix(8))).md"
            let fileURL = backupFolderURL.appendingPathComponent(fileName)

            do {
                try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
                successCount += 1

                manifestEntries.append([
                    "file": fileName,
                    "title": item.title,
                    "uuid": item.uuid,
                    "createdAt": isoFormatter.string(from: item.createdAt),
                    "updatedAt": isoFormatter.string(from: item.updatedAt),
                    "notebook": item.notebookName,
                    "tags": item.tagNames,
                    "isFavorite": item.isFavorite,
                    "isArchived": item.isArchived
                ])
            } catch {
                print("⚠️ Backup: failed to write \(fileName): \(error)")
            }
        }

        // Write manifest
        let manifest: [String: Any] = [
            "app": "Notex",
            "version": 1,
            "backupDate": isoFormatter.string(from: Date()),
            "noteCount": successCount,
            "notes": manifestEntries
        ]

        let manifestURL = backupFolderURL.appendingPathComponent("notex_backup.json")
        do {
            let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: manifestURL, options: .atomic)
        } catch {
            print("⚠️ Backup: manifest write error: \(error)")
        }

        UserDefaults.standard.set(Date(), forKey: "backup.lastDate")

        return BackupResult(success: true, folderURL: backupFolderURL,
                            noteCount: successCount,
                            message: "\(successCount) not başarıyla yedeklendi")
    }

    // MARK: - Data Extraction (thread-safe via performAndWait)

    private static func extractNoteData(context: NSManagedObjectContext) -> [BackupNoteData] {
        var result: [BackupNoteData] = []
        context.performAndWait {
            let request: NSFetchRequest<Note> = Note.fetchRequest()
            request.predicate = NSPredicate(format: "isTrashed == NO")
            request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

            guard let notes = try? context.fetch(request) else { return }
            for note in notes {
                result.append(BackupNoteData(
                    title: note.displayTitle,
                    uuid: note.uuid ?? UUID().uuidString,
                    plainText: note.plainText ?? "",
                    createdAt: note.createdAt ?? Date(),
                    updatedAt: note.updatedAt ?? Date(),
                    notebookName: note.notebook?.displayName ?? "",
                    tagNames: note.tagsArray.map { $0.displayName },
                    isFavorite: note.isFavorite,
                    isArchived: note.isArchived
                ))
            }
        }
        return result
    }

    // MARK: - Auto Backup

    /// Checks whether an automatic backup is due based on the configured frequency
    /// and folder path. If due, performs the backup. Can be called from any thread.
    static func autoBackupIfNeeded(context: NSManagedObjectContext) {
        let autoEnabled = UserDefaults.standard.bool(forKey: "backup.autoEnabled")
        guard autoEnabled else { return }

        let folderPath = UserDefaults.standard.string(forKey: "backup.folderPath") ?? ""
        guard !folderPath.isEmpty else { return }

        let folderURL = URL(fileURLWithPath: folderPath)
        guard FileManager.default.fileExists(atPath: folderURL.path) else { return }

        let frequencyRaw = UserDefaults.standard.string(forKey: "backup.frequency") ?? Frequency.weekly.rawValue
        let frequency = Frequency(rawValue: frequencyRaw) ?? .weekly

        let lastBackup = UserDefaults.standard.object(forKey: "backup.lastDate") as? Date ?? .distantPast
        let elapsed = Date().timeIntervalSince(lastBackup)
        guard elapsed >= frequency.seconds else { return }

        let result = performBackup(context: context, destination: folderURL)
        if result.success {
            print("✅ Auto-backup: \(result.message) → \(result.folderURL?.path ?? "")")
        } else {
            print("⚠️ Auto-backup failed: \(result.message)")
        }
    }

    // MARK: - Folder Picker

    /// Presents a folder picker. Must be called from the main thread.
    @MainActor
    static func pickBackupFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Seç"
        panel.title = "Yedekleme Klasörü Seçin"

        let response = panel.runModal()
        guard response == .OK else { return nil }
        return panel.url
    }

    // MARK: - Helpers

    static var lastBackupDate: Date? {
        UserDefaults.standard.object(forKey: "backup.lastDate") as? Date
    }

    private static func sanitizeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name
            .components(separatedBy: invalid)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "not" : cleaned
    }
}
