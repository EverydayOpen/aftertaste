import Foundation

public enum FileVaultState: String, Codable, Sendable {
    case on, off
    /// Encryption or decryption in progress.
    case transitioning
    case unknown
}

public enum StorageKind: String, Codable, Sendable {
    case solidState, rotational, unknown
}

/// The read-only facts behind the "Erase readiness" panel (BUILD_PLAN §4.8). Each comes from one allow-listed command
/// (`fdesetup status`, `diskutil info -plist /`, `tmutil listlocalsnapshots /`) parsed by Core's `Parsers`; nothing is
/// written, nothing needs root (all VERIFY on 13, 15, 26). A fact that could not be read is nil/`unknown` and the panel says
/// so; it never guesses. `ReadinessText` turns this into the plain sentences of APP4 §1.2.
public struct ReadinessFacts: Codable, Hashable, Sendable {
    public var fileVault: FileVaultState
    public var storage: StorageKind
    /// "APFS", "HFS+" ... from `diskutil` (`FilesystemType`/`FilesystemName`, VERIFY).
    public var fileSystem: String?
    /// The volume is internal (`Internal` key, VERIFY).
    public var isInternal: Bool?
    /// `hw.optional.arm64` via the Mac layer, nil if unknown. Apple silicon encrypts internal storage with FileVault off too.
    public var isAppleSilicon: Bool?
    /// Count of local APFS snapshots on `/`; nil = could not be read.
    public var localSnapshotCount: Int?
    public var macOSVersion: String
    /// Names of the probes that failed or timed out ("fdesetup", "diskutil", "tmutil").
    public var failedProbes: [String]
    public var checkedAt: Date

    public init(fileVault: FileVaultState = .unknown, storage: StorageKind = .unknown, fileSystem: String? = nil,
                isInternal: Bool? = nil, isAppleSilicon: Bool? = nil, localSnapshotCount: Int? = nil, macOSVersion: String = "",
                failedProbes: [String] = [], checkedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.fileVault = fileVault
        self.storage = storage
        self.fileSystem = fileSystem
        self.isInternal = isInternal
        self.isAppleSilicon = isAppleSilicon
        self.localSnapshotCount = localSnapshotCount
        self.macOSVersion = macOSVersion
        self.failedProbes = failedProbes
        self.checkedAt = checkedAt
    }
}
