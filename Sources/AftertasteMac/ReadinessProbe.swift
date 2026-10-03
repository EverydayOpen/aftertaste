import Darwin
import Foundation
import os
import AftertasteCore

/// The facts behind the "Erase readiness" panel (BUILD_PLAN §5.8): three read-only commands and nothing else. A closed enum
/// with absolute paths and fixed arguments; no shell, no input, no environment from outside. A probe that takes too long is
/// abandoned: the caller gets `timedOut`, and the child is never signalled (Aftertaste has no signal API anywhere, S6).
enum ReadinessProbe {
    enum Command: CaseIterable {
        case fileVault, disk, snapshots

        var path: String {
            switch self {
            case .fileVault: return "/usr/bin/fdesetup"
            case .disk: return "/usr/sbin/diskutil"
            case .snapshots: return "/usr/bin/tmutil"
            }
        }

        var arguments: [String] {
            switch self {
            case .fileVault: return ["status"]
            case .disk: return ["info", "-plist", "/"]
            case .snapshots: return ["listlocalsnapshots", "/"]
            }
        }

        var name: String { URL(fileURLWithPath: path).lastPathComponent }
    }

    struct Output: Sendable {
        var status: Int32
        var stdout: Data
        var timedOut: Bool
        var ok: Bool { !timedOut && status == 0 }
        var text: String { String(decoding: stdout, as: UTF8.self) }
    }

    private static let timeout: TimeInterval = 10
    private static let outputCap = 1 << 20

    /// Absolute executable, argument array, stdin and stderr on /dev/null, stdout drained concurrently (no 64 KB pipe
    /// deadlock) and capped at 1 MB. ponytail: a stuck child keeps its drain thread until it exits; that is the price of
    /// never signalling.
    static func run(_ command: Command) async -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.path)
        process.arguments = command.arguments
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe

        return await withCheckedContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let finish: @Sendable (Output) -> Void = { output in
                if resumed.withLock({ was in let first = !was; was = true; return first }) { continuation.resume(returning: output) }
            }
            do { try process.run() } catch {
                finish(Output(status: -1, stdout: Data(), timedOut: false))
                return
            }
            DispatchQueue.global().async {
                var collected = Data()
                // Keep draining past the cap so the child never blocks on a full pipe.
                while let chunk = try? pipe.fileHandleForReading.read(upToCount: 1 << 16), !chunk.isEmpty {
                    if collected.count < outputCap { collected.append(chunk.prefix(outputCap - collected.count)) }
                }
                process.waitUntilExit()
                finish(Output(status: process.terminationStatus, stdout: collected, timedOut: false))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(Output(status: -1, stdout: Data(), timedOut: true))
            }
        }
    }

    /// Runs the three probes and parses them with Core. A probe that failed, timed out or printed something unreadable is
    /// named in `failedProbes` and its fact stays unknown (the panel says "could not be read", never a guess).
    static func facts(now: Date, macOSVersion: String) async -> ReadinessFacts {
        async let vault = run(.fileVault)
        async let disk = run(.disk)
        async let snapshots = run(.snapshots)
        let (v, d, s) = await (vault, disk, snapshots)

        var facts = ReadinessFacts(macOSVersion: macOSVersion, checkedAt: now)
        var failed: [String] = []
        if v.ok { facts.fileVault = Parsers.fdesetup(v.text) }
        if !v.ok || facts.fileVault == .unknown { failed.append(Command.fileVault.name) }
        if d.ok {
            let parsed = Parsers.diskutilInfo(d.stdout)
            facts.storage = parsed.storage
            facts.fileSystem = parsed.fileSystem
            facts.isInternal = parsed.isInternal
        }
        if !d.ok || facts.storage == .unknown { failed.append(Command.disk.name) }
        if s.ok { facts.localSnapshotCount = Parsers.tmutilSnapshots(s.text) }
        if !s.ok || facts.localSnapshotCount == nil { failed.append(Command.snapshots.name) }
        facts.isAppleSilicon = appleSilicon()
        facts.failedProbes = failed
        return facts
    }

    /// `hw.optional.arm64` is 1 on Apple silicon and absent on Intel (VERIFY, also under Rosetta). nil if it cannot be told.
    private static func appleSilicon() -> Bool? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 { return value == 1 }
        return errno == ENOENT ? false : nil
    }
}
