import Foundation

/// A local SwiftData file a host can opt into.
///
/// ``AskConfiguration`` still defaults to ``AskPersistence/memory``. Private CloudKit stays
/// ``AskPersistence/privateCloud(containerIdentifier:storeURL:)``. This helper does not turn either of those on.
/// The sample app calls ``applicationSupportPersistence()``. A test passes its own directory.
public enum AskLocalStore {
    public static let folderName = "AskKitSample"
    public static let fileName = "conversations.store"

    /// `root/AskKitSample`. The sample app's root is Application Support.
    public static func directory(in root: URL) -> URL {
        root.appendingPathComponent(folderName, isDirectory: true)
    }

    public static func storeURL(in directory: URL) -> URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
    }

    /// Creates `directory` if needed and returns `.swiftData` for the file inside it. CloudKit is off.
    public static func persistence(directory: URL) throws -> AskPersistence {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return .swiftData(storeURL: storeURL(in: directory))
    }

    /// The running sample app's file, under Application Support. Tests should not call this.
    public static func applicationSupportPersistence() throws -> AskPersistence {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return try persistence(directory: directory(in: root))
    }
}
