import Foundation

/// The live-owner index: who is installed right now, so no item that an installed app could legitimately use is ever offered
/// (BUILD_PLAN §4.6). For uninstall-now the target is excluded, its siblings (another copy of the same app, another release
/// channel) are not. The inventory is history, not ownership: it never makes an app "live".
public struct InstalledIndex: Sendable {
    public let apps: [AppIdentity]
    private let inventory: [String: InventoryRecord]

    public init(installed: [AppIdentity], excluding target: AppIdentity?, inventory: [InventoryRecord]) {
        var kept = installed
        if let target {
            let path = Names.fold(GuardPolicy.normalize(target.bundlePath))
            if !path.isEmpty { kept.removeAll { Names.fold(GuardPolicy.normalize($0.bundlePath)) == path } }
        }
        self.apps = kept
        var records: [String: InventoryRecord] = [:]
        for record in inventory {
            let key = Names.fold(record.identity.bundleID)
            if let existing = records[key], existing.lastSeen >= record.lastSeen { continue }
            records[key] = record
        }
        self.inventory = records
    }

    /// Installed apps that own `id`: it is one of their IDs (bundle, nested helper, launchd label), or a dotted child of one.
    public func liveOwners(ofID id: String) -> [AppIdentity] {
        let f = Names.fold(id)
        return apps.filter { app in
            app.allIDs.contains { let a = Names.fold($0); return f == a || f.hasPrefix(a + ".") }
        }
    }

    /// Installed apps signed by the same developer team.
    public func liveOwners(ofTeam teamID: String) -> [AppIdentity] {
        let t = Names.fold(teamID)
        return apps.filter { $0.teamID.map(Names.fold) == t }
    }

    /// Same ID (another copy, another volume) or the same release-channel family (stable, Beta, Nightly, Insiders ...).
    public func isSibling(_ a: AppIdentity, of b: AppIdentity) -> Bool {
        if Names.fold(a.bundleID) == Names.fold(b.bundleID) { return true }
        return Hazards.channelFamily(ofID: a.bundleID) == Hazards.channelFamily(ofID: b.bundleID)
    }

    /// The inventory record for a bundle ID or any ID the recorded app owned (nested helper, launchd label).
    public func record(forID id: String) -> InventoryRecord? {
        let f = Names.fold(id)
        if let r = inventory[f] { return r }
        // ponytail: linear in the inventory (tens of apps); key it by nested ID if it ever holds thousands.
        return inventory.values.first { $0.identity.allIDs.contains { Names.fold($0) == f } }
    }

    var records: [InventoryRecord] { Array(inventory.values) }
}
