import Darwin

/// Executable paths of the running processes, read-only (libproc). No argv, no environment, no working directory.
/// nil means the process list itself could not be read; the running check then fails closed (S6).
enum Processes {
    private static let pathBufferSize = 4096 // PROC_PIDPATHINFO_MAXSIZE (4 * MAXPATHLEN), spelled out

    static func executablePaths() -> [String]? {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return nil }
        // Slack for processes that start between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return nil }
        var seen = Set<String>()
        var buffer = [CChar](repeating: 0, count: pathBufferSize)
        for pid in pids.prefix(Int(count)) where pid > 0 {
            // Other users' processes fail here; that is fine, only ours can run from our files.
            let n = proc_pidpath(pid, &buffer, UInt32(pathBufferSize))
            if n > 0 { seen.insert(String(decoding: buffer.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self)) }
        }
        return Array(seen)
    }
}
