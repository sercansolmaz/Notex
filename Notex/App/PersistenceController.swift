import CoreData
import Foundation

/// Error-tolerant persistence controller.
/// Uses NSPersistentContainer for local-first storage.
/// CloudKit sync can be added later with proper entitlements.
final class PersistenceController: ObservableObject, @unchecked Sendable {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    private init() {
        container = PersistenceController.createContainer()
    }

    // MARK: - Container Creation

    private static func createContainer() -> NSPersistentContainer {
        // Load model from the app bundle
        let model = PersistenceController.loadModel()
        let container = NSPersistentContainer(name: "NotexModel", managedObjectModel: model)

        let storeURL = PersistenceController.storeURL()
        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                print("⚠️ Core Data store failed: \(error.userInfo)")
                PersistenceController.recreateStore(container: container)
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        return container
    }

    private static func loadModel() -> NSManagedObjectModel {
        // Try loading from main bundle (compiled .momd)
        if let url = Bundle.main.url(forResource: "NotexModel", withExtension: "momd"),
           let model = NSManagedObjectModel(contentsOf: url) {
            return model
        }
        // Fallback: try .mom
        if let url = Bundle.main.url(forResource: "NotexModel", withExtension: "mom"),
           let model = NSManagedObjectModel(contentsOf: url) {
            return model
        }
        // Last resort: merged model
        if let model = NSManagedObjectModel.mergedModel(from: [.main]) {
            return model
        }
        print("⚠️ Failed to load Core Data model — using empty model")
        return NSManagedObjectModel()
    }

    private static func recreateStore(container: NSPersistentContainer) {
        let storeURL = PersistenceController.storeURL()
        try? FileManager.default.removeItem(at: storeURL)
        try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
        try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))

        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores { _, error in
            if let error = error {
                print("⚠️ Fresh store also failed: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    }

    // MARK: - Save

    func save() {
        let context = container.viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("⚠️ Save error: \(error)")
            context.rollback()
        }
    }

    // MARK: - Store URL

    private static func storeURL() -> URL {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = supportDir.appendingPathComponent("Notex", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("NotexModel.sqlite")
    }
}
