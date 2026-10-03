import Foundation

/// The one-line "why this belongs to the app" for each row, and the plain words for every refusal (BUILD_PLAN §4.2 step 6).
/// Built from the strongest evidence only; it never claims more than the evidence shows.
public enum WhyText {
    private static let priority: [EvidenceKind] = [
        .launchdProgramInBundle, .containerMetadata, .receipt, .launchdLabelIsID, .groupID, .exactID, .caskZap, .helperSuffix,
        .embeddedID, .teamPrefix, .launchdProgramGone, .executableName, .displayName,
    ]

    private static let knownExtensions = [".plist", ".savedstate", ".binarycookies", ".sfl2", ".sfl3", ".bom"]

    public static func line(for item: ResidueItem, owner: AppIdentity) -> String {
        var text: String
        let noOwner = item.evidence.contains { $0.kind == .noLiveOwner }
        if item.ruleID == "APP" {
            text = "The app you chose."
        } else if let e = priority.lazy.compactMap({ kind in item.evidence.first { $0.kind == kind } }).first {
            text = primary(e, item: item, owner: owner, noOwner: noOwner)
        } else {
            text = "Found by its name."
        }
        if noOwner, !text.contains("no installed app has this ID") { text += " No installed app has this ID." }
        if let seen = item.evidence.first(where: { $0.kind == .inventoryAbsent }) { text += " Last seen installed on \(seen.detail)." }
        if let stale = item.evidence.first(where: { $0.kind == .staleMtime }) { text += " Not changed for \(stale.detail)." }
        if let team = item.evidence.first(where: { $0.kind == .sameTeamInstalled }) {
            text += " Another app from the same developer (\(team.detail)) is still installed, so this is not preselected."
        }
        if let b = item.blocked {
            text += " " + (b == .listedOnly && item.kind == .yourData ? "May hold unsaved documents, so it is listed only." : reason(b))
        } else if item.irreplaceable {
            text += " May be your only copy."
        }
        return text
    }

    private static func primary(_ e: Evidence, item: ResidueItem, owner: AppIdentity, noOwner: Bool) -> String {
        let tail = noOwner ? "; no installed app has this ID." : "."
        switch e.kind {
        case .exactID:
            if isLiteral(item.name, id: e.detail) {
                if noOwner { return "Named exactly \(item.name)" + tail }
                let plain = Names.fold(item.name) == Names.fold(e.detail)
                return "Named exactly \(item.name)" + (plain ? ", the bundle ID of \(owner.displayName)." : ", after \(owner.displayName)'s bundle ID.")
            }
            return "Starts with the bundle ID \(e.detail)" + tail
        case .helperSuffix: return "Named after a \(e.detail) of \(owner.bundleID)."
        case .embeddedID: return "Named for a part of \(owner.displayName) (\(e.detail))."
        case .teamPrefix: return "Starts with the developer ID \(e.detail). Other apps from the same developer may use it."
        case .groupID: return "A group \(owner.displayName) shares data through (\(e.detail))."
        case .containerMetadata: return "macOS lists this container as belonging to \(e.detail)."
        case .launchdProgramInBundle: return "Starts a program inside \(owner.displayName)."
        case .launchdLabelIsID: return "Its label (\(e.detail)) starts with \(owner.displayName)'s bundle ID."
        case .launchdProgramGone: return "Starts a program that is no longer there."
        case .receipt: return "The installer receipt is named after \(e.detail)."
        case .caskZap: return "A known folder of \(owner.displayName) (\(item.name))."
        case .executableName: return "Named after the program \(e.detail); nothing else confirms it."
        case .displayName: return "Named like the app (\(e.detail)); nothing else confirms it."
        case .inventoryAbsent, .noLiveOwner, .sameTeamInstalled, .staleMtime, .vendorNesting: return "Found by its name."
        }
    }

    /// The name is the ID or the ID plus a documented extension.
    static func isLiteral(_ name: String, id: String) -> Bool {
        let n = Names.fold(name), i = Names.fold(id)
        return n == i || knownExtensions.contains { n == i + $0 }
    }

    public static func reason(_ b: BlockReason) -> String {
        switch b {
        case .appleOwned: return "Apple's own. Never touched."
        case .neverList: return "On the never-touch list."
        case .running: return "Running. Quit it first."
        case .runningUnknown: return "Could not tell whether it is running."
        case .protectedByMacOS: return "Protected by macOS. Reveal it in Finder to look."
        case .iCloud: return "Kept in iCloud. Manage it in System Settings."
        case .dataless: return "Stored in iCloud and not downloaded."
        case .locked: return "Locked. Aftertaste never unlocks anything."
        case .mountPoint: return "A drive is mounted here."
        case .linkEscapes: return "A link that leads somewhere else."
        case .otherVolume: return "On a different disk."
        case .notLocalVolume: return "Not on a local disk."
        case .sharedWithInstalled: return "Another installed app uses this."
        case .siblingInstalled: return "Another installed copy of this app uses this."
        case .listedOnly: return "Listed only. Removing the file would not stop a job that is already loaded."
        case .needsAdmin: return "Needs your administrator. Reveal in Finder or copy the path."
        case .ownerMayBeElsewhere: return "Its app may be on a drive that is not connected."
        case .otherUser: return "Belongs to another user."
        case .ownCopy: return "Aftertaste's own data."
        case .changed: return "Changed while Aftertaste was looking."
        }
    }

    /// One line per class group in the preview.
    public static func consequence(_ kind: ResidueKind) -> String {
        switch kind {
        case .app: return "The app itself."
        case .cache: return "Rebuilt automatically."
        case .settings: return "The app will start with default settings if you reinstall it."
        case .state: return "Window positions and recent items. Rebuilt automatically."
        case .logs: return "Old logs. Nothing depends on them."
        case .cookies: return "Sign-ins kept by the app's web views. You would sign in again."
        case .launchItem: return "Starts something at login. Listed only."
        case .yourData: return "Documents, sign-ins or history the app kept. Only tick if you will not reinstall or have a backup."
        case .shared: return "May be used by other apps from the same developer."
        case .system: return "Needs your administrator."
        }
    }
}
