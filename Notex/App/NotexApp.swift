import SwiftUI
import CoreData

@main
struct NotexApp: App {
    @StateObject private var persistenceController = PersistenceController.shared
    @StateObject private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(persistenceController)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.colorScheme)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    // Trigger auto-backup check on launch (runs silently if not due)
                    BackupService.autoBackupIfNeeded(context: persistenceController.container.viewContext)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Yeni Not") {
                    NotificationCenter.default.post(name: .createNewNote, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("Yeni Defter") {
                    NotificationCenter.default.post(name: .createNewNotebook, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("Tema Değiştir") {
                    themeManager.cycleTheme()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("Odak Modu") {
                    NotificationCenter.default.post(name: .toggleFocusMode, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
            // Find & Replace — routes to the focused NSTextView's built-in find panel.
            CommandGroup(after: .textEditing) {
                Button("Bul") {
                    NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Bul ve Değiştir") {
                    // Action tag 3 = "Find and Replace" in NSTextFinder
                    NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .option])
            }
        }

        WindowGroup("NoteWindow", for: String.self) { $noteUUID in
            NoteWindowView(noteUUID: noteUUID)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.colorScheme)
        }
        .defaultSize(width: 700, height: 600)

        Settings {
            SettingsView()
                .environmentObject(themeManager)
                .environmentObject(persistenceController)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let createNewNote = Notification.Name("NotexCreateNewNote")
    static let createNewNotebook = Notification.Name("NotexCreateNewNotebook")
    static let toggleFocusMode = Notification.Name("NotexToggleFocusMode")
}
