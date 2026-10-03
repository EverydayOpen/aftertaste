import Darwin
import Foundation
import AftertasteCore

/// Every app Aftertaste has seen installed (BUILD_PLAN §5): one JSON file next to the journal. When an app later vanishes,
/// matching its leftovers becomes exact because every ID it owned is known. An aid, never a requirement: every failure
/// here is silent and the scan simply has less to go on.
enum InventoryStore {
    private static let limit = 1000

    private static func path(_ home: String) -> String { Journal.directory(home: home) + "/inventory.json" }

    static func load(home: String) -> [InventoryRecord] {
        let file = path(home)
        var st = stat()
        guard lstat(file, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_uid == getuid(), st.st_size < 16 << 20,
              let data = try? Data(contentsOf: URL(fileURLWithPath: file)) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([InventoryRecord].self, from: data)) ?? []
    }

    /// Merges what is installed now into the stored records (first sighting kept, last sighting refreshed) and saves them.
    /// Records of apps that are gone stay, with their old `lastSeen`. Returns the merged list even if saving failed.
    @discardableResult
    static func update(with snapshot: InstalledSnapshot, home: String, now: Date) -> [InventoryRecord] {
        var byID = Dictionary(load(home: home).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for app in snapshot.apps {
            byID[app.bundleID] = InventoryRecord(identity: app, firstSeen: byID[app.bundleID]?.firstSeen ?? now, lastSeen: now)
        }
        let records = Array(byID.values.sorted { $0.lastSeen > $1.lastSeen }.prefix(limit))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        if Journal.prepare(home: home), let data = try? encoder.encode(records) {
            // Private like the log: the installed-app list is sensitive. VERIFY createFile replaces an existing file with this mode.
            FileManager.default.createFile(atPath: path(home), contents: data, attributes: [.posixPermissions: 0o600])
        }
        return records
    }
}
