#!/usr/bin/env bash
# The safety rules of docs/BUILD_PLAN.md §3 as greps. CI runs this (ci.yml `checks` job); run it locally before pushing.
# GNU grep (Git Bash and Linux): the regexes use \b. Only Sources/ and App/ are searched (plus site/, README.md and
# CHANGELOG.md for the banned phrases), so tests and tools are exempt. Each check prints its hits and fails the script.
# Owner: architect until infra takes it over. Rule text lives in BUILD_PLAN §3; this file is exact and has mutation self-tests.
set -u
cd "$(dirname "$0")/.."
fail=0
check() { if [ -n "$2" ]; then echo "$2"; echo "::error::$1"; fail=1; fi; }
S='--include=*.swift'
# Whole-line // comments are exempt everywhere (a comment can't run); a trailing comment after code is not.
C='^[^:]+:[0-9]+:[[:space:]]*//'
# hits REGEX [EXEMPT] [DIRS]: matching lines "file:line:text", minus comment lines, minus lines matching EXEMPT
# (a grep -E pattern, normally a "file:" prefix such as '^Sources/AftertasteMac/Trasher\.swift:').
hits() { grep -rnsE $S "$1" ${3:-Sources App} | grep -vE "$C" | grep -vE "${2:-^$}" || true; }
# Self-tests: a regex that does not trip on its own bad example proves nothing. The examples are collected per regex and
# checked with two greps in selfcheck (spawning a process per example is minutes on Windows Git Bash).
#   selftest NAME REGEX 'bad line'   must match            cleantest NAME REGEX 'good line'   must NOT match
STD=$(mktemp -d)
trap 'rm -rf "$STD"' EXIT
selftest() { printf '%s\n' "$3" >> "$STD/$1.bad"; printf '%s' "$2" > "$STD/$1.re"; }
cleantest() { printf '%s\n' "$3" >> "$STD/$1.ok"; printf '%s' "$2" > "$STD/$1.re"; }
selfcheck() {
  local f name re m
  for f in "$STD"/*.re; do
    name=$(basename "$f" .re); re=$(cat "$f")
    if [ -f "$STD/$name.bad" ]; then
      m=$(grep -vE "$re" "$STD/$name.bad" || true)
      [ -z "$m" ] || check "safety_greps self-test: $name missed: $m" "self-test failed"
    fi
    if [ -f "$STD/$name.ok" ]; then
      m=$(grep -E "$re" "$STD/$name.ok" || true)
      [ -z "$m" ] || check "safety_greps self-test: $name flagged innocent code: $m" "self-test failed"
    fi
  done
}

M=Sources/AftertasteMac
# 1. Nothing is deleted, renamed, copied, linked, truncated or recycled. Ever. Deleting means FileManager.trashItem (1b).
R_DELETE='(^|[^[:alnum:]_.])(remove|unlink|unlinkat|rmdir|rename|renameat|renamex_np|renameatx_np|truncate|ftruncate|copyfile|fcopyfile|clonefile|clonefileat|fclonefileat|link|linkat|symlink|symlinkat|mkfifo|mknod|exchangedata|removefile|removefile_state_alloc)[[:space:]]*\(|\.(removeItem|removeItems|replaceItem|replaceItemAt|copyItem|linkItem|createSymbolicLink|setAttributes|recycle|setUbiquitous|removeFile|performFileOperation)[[:space:]]*\(|\bremoveItem\b|"/bin/(rm|mv|cp|ln)"|\bemptyTrash|F_PUNCHHOLE|\b(recycleOperation|destroyOperation|NSWorkspaceRecycleOperation|NSWorkspaceDestroyOperation)\b|\b(Darwin|Glibc)\.(remove|removefile|unlink|unlinkat|rmdir|rename|renameat|truncate|ftruncate|copyfile|link|symlink)\b'
selftest delete "$R_DELETE" 'try FileManager.default.removeItem(at: u)'
selftest delete "$R_DELETE" 'unlink(path)'
selftest delete "$R_DELETE" 'Darwin.rmdir(path)'
selftest delete "$R_DELETE" '_ = remove(path)'
selftest delete "$R_DELETE" 'rename(a, b)'
selftest delete "$R_DELETE" 'copyfile(a, b, nil, 0)'
selftest delete "$R_DELETE" 'try FileManager.default.copyItem(at: a, to: b)'
selftest delete "$R_DELETE" 'try FileManager.default.replaceItemAt(a, withItemAt: b)'
selftest delete "$R_DELETE" 'NSWorkspace.shared.recycle([u]) { _, _ in }'
selftest delete "$R_DELETE" 'let p = "/bin/rm"'
selftest delete "$R_DELETE" 'try FileManager.default.setAttributes([:], ofItemAtPath: p)'
selftest delete "$R_DELETE" 'ftruncate(fd, 0)'
selftest delete "$R_DELETE" 'removefile(path, nil, removefile_flags_t(REMOVEFILE_RECURSIVE))'
selftest delete "$R_DELETE" 'Darwin.removefile(path, nil, 0)'
selftest delete "$R_DELETE" 'let st = removefile_state_alloc()'
selftest delete "$R_DELETE" '_ = NSWorkspace.shared.performFileOperation(.recycleOperation, source: s, destination: "", files: f, tag: nil)'
selftest delete "$R_DELETE" 'let op = NSWorkspace.OperationName.destroyOperation'
selftest delete "$R_DELETE" 'let op = NSWorkspaceRecycleOperation'
cleantest delete "$R_DELETE" 'NSWorkspace.shared.open(url)'
cleantest delete "$R_DELETE" 'ticked.remove(id); items.remove(at: 0); dict.removeValue(forKey: k)'
check "Never delete, rename, copy, link, truncate, recycle or empty the Trash: deleting means FileManager.trashItem" "$(hits "$R_DELETE")"

# 1b/1c. The two verbs: trashItem( only in Trasher.swift, moveItem( only in UndoStore.swift (a move back out of the Trash).
R_TRASH='trashItem[[:space:]]*\('
R_MOVE='(^|[^[:alnum:]_])moveItem[[:space:]]*\('
selftest trashItem "$R_TRASH" 'try fm.trashItem(at: u, resultingItemURL: &r)'
selftest moveItem "$R_MOVE" 'try fm.moveItem(at: a, to: b)'
selftest moveItem "$R_MOVE" 'moveItem(at: a, to: b)'
cleantest moveItem "$R_MOVE" 'try fm.removeItem(at: u)'
check "trashItem( appears only in $M/Trasher.swift" "$(hits "$R_TRASH" "^$M/Trasher\.swift:")"
check "moveItem( appears only in $M/UndoStore.swift" "$(hits "$R_MOVE" "^$M/UndoStore\.swift:")"

# 1d. No permission, ownership, flag, xattr, ACL, timestamp or umask changes. Never clear a lock, never "fix" a permission.
R_PERM='(^|[^[:alnum:]_])(chmod|fchmod|lchmod|fchmodat|chown|fchown|lchown|fchownat|chflags|fchflags|lchflags|setxattr|fsetxattr|removexattr|fremovexattr|utimes|futimes|lutimes|utimensat|futimens|setattrlist|fsetattrlist|setattrlistat|acl_set_file|acl_set_fd|acl_delete_entry|umask)[[:space:]]*\('
selftest perm "$R_PERM" 'chflags(path, 0)'
selftest perm "$R_PERM" 'fchmod(fd, 0o600)'
selftest perm "$R_PERM" 'setxattr(p, "a", nil, 0, 0, 0)'
check "No chmod/chown/chflags/xattr/ACL/utimes/umask calls: modes are set by open(2) and createDirectory(attributes:) in the journal and inventory files only" "$(hits "$R_PERM")"
R_POSIXATTR='posixPermissions|\.immutable\b|\.ownerAccountID|\.groupOwnerAccountID'
selftest posixattr "$R_POSIXATTR" 'let a: [FileAttributeKey: Any] = [.posixPermissions: 0o700]'
check "posixPermissions only in $M/Journal.swift and $M/InventoryStore.swift (their own 0700 folder)" "$(hits "$R_POSIXATTR" "^$M/(Journal|InventoryStore)\.swift:")"

# 2. Writes. Two files create or append: Journal.swift (the append-only log, O_NOFOLLOW, 0600) and InventoryStore.swift
#    (one atomic JSON file); App/Export.swift writes what the user chose in a save panel. Nothing else writes a byte.
R_WRITE_SYS='\bO_(WRONLY|CREAT|APPEND)\b|(^|[^[:alnum:]_.])((Darwin|Glibc)\.)?(write|fsync|fdatasync)[[:space:]]*\(|\b(Darwin|Glibc)\.(write|fsync|fdatasync)\b'
selftest write-sys "$R_WRITE_SYS" 'let fd = open(p, O_WRONLY | O_APPEND | O_CREAT, 0o600)'
selftest write-sys "$R_WRITE_SYS" 'write(fd, ptr, n)'
selftest write-sys "$R_WRITE_SYS" 'Darwin.write(fd, ptr, n)'
selftest write-sys "$R_WRITE_SYS" 'fsync(fd)'
check "Raw write(2), fsync and O_WRONLY/O_CREAT/O_APPEND only in $M/Journal.swift" "$(hits "$R_WRITE_SYS" "^$M/Journal\.swift:")"
R_WRITE_FND='createFile[[:space:]]*\(|FileHandle[[:space:]]*\(forWriting|FileHandle[[:space:]]*\(forUpdating|createDirectory[[:space:]]*\(|\.write[[:space:]]*\((to|contentsOf):|write[[:space:]]*\(toFile:|OutputStream|\.seekToEnd|atomically:'
selftest write-fnd "$R_WRITE_FND" 'try data.write(to: url, options: .atomic)'
selftest write-fnd "$R_WRITE_FND" 'try fm.createDirectory(at: u, withIntermediateDirectories: true)'
selftest write-fnd "$R_WRITE_FND" 'fm.createFile(atPath: p, contents: nil)'
selftest write-fnd "$R_WRITE_FND" 'let h = try FileHandle(forWritingTo: u)'
check "File creation and writing only in $M/Journal.swift, $M/InventoryStore.swift and App/Export.swift" \
  "$(hits "$R_WRITE_FND" "^($M/(Journal|InventoryStore)|App/Export)\.swift:")"
# Reserved for the v1.1 Overwriter (APP4 §1.3, owner decision: not in v1). Nothing may open a file for in-place rewriting.
R_NEVER_RW='\bO_(RDWR|TRUNC|EXCL)\b|pwrite|writev|F_FULLFSYNC|F_NOCACHE|F_PUNCHHOLE'
selftest never-rw "$R_NEVER_RW" 'let fd = open(p, O_RDWR)'
selftest never-rw "$R_NEVER_RW" 'fcntl(fd, F_FULLFSYNC)'
check "No in-place rewriting (O_RDWR, O_TRUNC, pwrite, F_FULLFSYNC, F_NOCACHE): the overwrite feature is not in v1" "$(hits "$R_NEVER_RW")"

# 3. Never read file contents. The only reads: Journal.swift (the log), InventoryStore.swift (the inventory), Identity.swift
#    (Info.plist of .app bundles, launchd plists, container metadata plists: one file each, 1 MB cap, parsed in Core).
R_READ='(NS)?(Data|String)[[:space:]]*\(contentsOf(File)?:|NSData[[:space:]]*\(|NSString[[:space:]]*\(contentsOf|NS(Dictionary|Array)[[:space:]]*\(contentsOf|contentsOfFile|\.contents[[:space:]]*\(atPath|(^|[^[:alnum:]_.])(fopen|freopen|open|openat|read|pread)[[:space:]]*\(|\b(Darwin|Glibc)\.(open|openat|read|pread)\b|FileHandle[[:space:]]*\(forReading|InputStream[[:space:]]*\(|\bfread[[:space:]]*\(|\bmmap[[:space:]]*\(|NSImage[[:space:]]*\(contentsOf'
selftest read "$R_READ" 'let d = try Data(contentsOf: url)'
selftest read "$R_READ" 'let s = try String(contentsOf: url, encoding: .utf8)'
selftest read "$R_READ" 'let fd = open(path, O_RDONLY)'
selftest read "$R_READ" 'let n = read(fd, &buf, 10)'
selftest read "$R_READ" 'let h = try FileHandle(forReadingFrom: u)'
selftest read "$R_READ" 'let d = fm.contents(atPath: p)'
selftest read "$R_READ" 'let m = mmap(nil, n, PROT_READ, MAP_PRIVATE, fd, 0)'
check "No reading of file contents outside Journal.swift, InventoryStore.swift and Identity.swift" \
  "$(hits "$R_READ" "^$M/(Journal|InventoryStore|Identity)\.swift:")"
R_PLIST='PropertyListSerialization|PropertyListDecoder|PropertyListEncoder|NSKeyedUnarchiver|NSKeyedArchiver|\bplutil\b'
selftest plist "$R_PLIST" 'let o = try PropertyListSerialization.propertyList(from: d, options: [], format: nil)'
check "Property lists are parsed only in Sources/AftertasteCore/Parse/Parsers.swift (pure, tested on Linux)" "$(hits "$R_PLIST" '^Sources/AftertasteCore/Parse/Parsers\.swift:')"
R_BUNDLE='(^|[^[:alnum:]_])Bundle[[:space:]]*\((url|path)|NSBundle|CFBundleCreate|CFBundleCopy|CFBundleGetValueForInfoDictionaryKey'
selftest bundle "$R_BUNDLE" 'let b = Bundle(url: appURL)'
selftest bundle "$R_BUNDLE" 'let b = Foundation.Bundle(path: p)'
cleantest bundle "$R_BUNDLE" 'else if isUnusableBundle(path, now: now) { skipped.append(path) }'
check "Never open another app through Bundle(url:)/Bundle(path:): Identity reads Contents/Info.plist directly" "$(hits "$R_BUNDLE")"
check "infoDictionary (our own version string) only in App/AppModel.swift" "$(hits 'infoDictionary' '^App/AppModel\.swift:')"

# 4. Filesystem metadata and listing calls: the Mac layer only. Core takes snapshots, the app asks the backend.
R_META='fileExists[[:space:]]*\(|attributesOfItem[[:space:]]*\(|(^|[^[:alnum:]_])[lf]?stat[[:space:]]*\(|statfs|statvfs|getattrlist|contentsOfDirectory|subpathsOfDirectory|enumerator[[:space:]]*\(|opendir|readdir|realpath|resourceValues|getxattr|listxattr|isReadableFile|isWritableFile|isDeletableFile|isExecutableFile|destinationOfSymbolicLink|FileManager|NSFileManager|NSHomeDirectory|homeDirectoryForCurrentUser|getpwuid'
selftest meta "$R_META" 'if FileManager.default.fileExists(atPath: p) {}'
selftest meta "$R_META" 'var st = stat(); lstat(p, &st)'
selftest meta "$R_META" 'let u = FileManager.default.homeDirectoryForCurrentUser'
selftest meta "$R_META" 'let r = realpath(p, nil)'
check "Filesystem calls (FileManager, stat, directory listing, realpath, home lookup) only in Sources/AftertasteMac, plus the composition root App/AppModel.swift" \
  "$(hits "$R_META" '^App/AppModel\.swift:' 'Sources/AftertasteCore App')"

# 5. No shell, no child processes except the three read-only commands of ReadinessProbe.swift.
R_NOPROC='\bposix_spawn|\bexec[lv]p?e?[[:space:]]*\(|(^|[^.[:alnum:]_])(system|popen|fork|vfork)[[:space:]]*\(|"/bin/(ba|z)?sh"|"/usr/bin/env"|"-c"|NSAppleScript|NSUserAppleScriptTask|NSTask|osascript|\bsudo\b|launchctl|\bpkill\b|\bkillall\b|\blsof\b|"/(usr/)?bin/ps"|"/usr/bin/open"|"/usr/bin/(defaults|plutil|tccutil|sfltool|lsregister|pkgutil|mdfind|mdls|xattr|chflags|trash)"'
selftest noproc "$R_NOPROC" 'system("rm -rf /")'
selftest noproc "$R_NOPROC" 'p.arguments = ["-c", cmd]'
selftest noproc "$R_NOPROC" 'p.executableURL = URL(fileURLWithPath: "/bin/sh")'
selftest noproc "$R_NOPROC" 'let t = "launchctl bootout"'
selftest noproc "$R_NOPROC" 'run("/usr/bin/tccutil", ["reset", "All"])'
check "No shell, osascript, sudo, launchctl, pkill, killall, lsof, ps, open, defaults, tccutil, xattr or any command beyond ReadinessProbe's three" "$(hits "$R_NOPROC")"
R_PROCESS='\bProcess\b'
selftest process "$R_PROCESS" 'let p = Process()'
selftest process "$R_PROCESS" 'let p = Foundation.Process()'
cleantest process "$R_PROCESS" 'let v = ProcessInfo.processInfo.operatingSystemVersion'
check "Process only in $M/ReadinessProbe.swift (the allow-listed, read-only fdesetup/diskutil/tmutil runner)" "$(hits "$R_PROCESS" "^$M/ReadinessProbe\.swift:")"

# 6. Never signal, quit or kill anything. A running app blocks its items; Aftertaste does not stop it.
R_SIGNAL='(^|[^[:alnum:]_])(kill|killpg|pthread_kill|raise)[[:space:]]*\(|\bSIG[A-Z0-9]+\b|forceTerminate|\bproc_terminate|\btask_for_pid|\bdlsym|\bdlopen|@_silgen_name|@_cdecl'
selftest signal "$R_SIGNAL" 'kill(pid, SIGTERM)'
selftest signal "$R_SIGNAL" 'Darwin.kill(pid, 9)'
selftest signal "$R_SIGNAL" 'let s = SIGKILL'
selftest signal "$R_SIGNAL" 'app.forceTerminate()'
check "No kill, killpg, raise, SIG* names, forceTerminate, dlsym or private-symbol tricks anywhere" "$(hits "$R_SIGNAL")"
check "terminate() only as NSApp.terminate(nil) to quit Aftertaste itself" \
  "$(hits '\.terminate[[:space:]]*\(' '(NSApp|NSApplication\.shared)\.terminate[[:space:]]*\(')"
selftest terminate '\.terminate[[:space:]]*\(' 'process.terminate()'
R_RUNAPP='NSRunningApplication|runningApplications'
selftest runapp "$R_RUNAPP" 'NSWorkspace.shared.runningApplications.map(\.bundleIdentifier)'
check "NSRunningApplication/runningApplications only in $M/RunningApps.swift" "$(hits "$R_RUNAPP" "^$M/RunningApps\.swift:")"
R_NOTIF='didTerminateApplicationNotification|didLaunchApplicationNotification'
check "Workspace launch/terminate notifications only in $M/RunningApps.swift and App/AppModel.swift (re-evaluate, never poll)" "$(hits "$R_NOTIF" "^($M/RunningApps|App/AppModel)\.swift:")"
R_LIBPROC='proc_(listallpids|listpids|pidpath|pidinfo|name|regionfilename|set)|libproc'
selftest libproc "$R_LIBPROC" 'let n = proc_listallpids(nil, 0)'
selftest libproc "$R_LIBPROC" 'let n = proc_pidpath(pid, &buf, 4096)'
check "libproc (proc_listallpids, proc_pidpath: read-only executable paths) only in $M/Processes.swift" "$(hits "$R_LIBPROC" "^$M/Processes\.swift:")"

# 7. No privilege escalation, no helper, no login item.
R_ESC='SMAppService|SMJobBless|SMLoginItemSetEnabled|ServiceManagement|AuthorizationCreate|AuthorizationExecuteWithPrivileges|AuthorizationCopyRights|NSXPCConnection|NSXPCListener'
selftest escalate "$R_ESC" 'try SMAppService.daemon(plistName: "x").register()'
selftest escalate "$R_ESC" 'AuthorizationExecuteWithPrivileges(a, p, 0, nil, nil)'
check "No SMAppService, SMJobBless, Authorization*, ServiceManagement or XPC: no privileged helper in v1" "$(hits "$R_ESC")"

# 8. No privacy-database, keychain, accessibility, Apple-event or Launch Services tricks.
R_TCC='TCC\.db|\btccutil\b|kTCCService|AXIsProcessTrusted|AXUIElement|CGEvent|System Events|NSAppleEventDescriptor|\blsregister\b|\bsfltool\b|CGRequestScreenCaptureAccess|CGWindowListCreate|IOHIDRequestAccess'
selftest tcc "$R_TCC" 'let p = "~/Library/Application Support/com.apple.TCC/TCC.db"'
selftest tcc "$R_TCC" 'AXIsProcessTrusted()'
check "No TCC database, tccutil, Accessibility, Apple events, lsregister or sfltool" "$(hits "$R_TCC")"
R_KEYCHAIN='SecItem|SecKeychain|kSecClass|kSecAttr|kSecValue|kSecReturn|LAContext|LocalAuthentication'
selftest keychain "$R_KEYCHAIN" 'SecItemCopyMatching(q as CFDictionary, &r)'
check "No keychain access of any kind (an app cannot enumerate other apps' items without prompts)" "$(hits "$R_KEYCHAIN")"
R_SECCODE='SecStaticCode|SecCode|SecRequirement|SecCertificate|kSecCS|import Security'
selftest seccode "$R_SECCODE" 'SecStaticCodeCreateWithPath(u as CFURL, [], &code)'
check "Code-signature reading (Security.framework) only in $M/Identity.swift" "$(hits "$R_SECCODE" "^$M/Identity\.swift:")"
R_OPEN='NSWorkspace|LSOpen|openURL|\bLink[[:space:]]*\(|activateFileViewerSelecting|x-apple\.systempreferences'
selftest open "$R_OPEN" 'NSWorkspace.shared.open(url)'
selftest open "$R_OPEN" 'NSWorkspace.shared.activateFileViewerSelecting([u])'
check "NSWorkspace, openURL, Link and Finder reveal only in App/Links.swift, App/AppModel.swift, App/AftertasteApp.swift, App/AppIcons.swift (icons), $M/RunningApps.swift and $M/InstalledApps.swift" \
  "$(hits "$R_OPEN" "^(App/(Links|AppModel|AftertasteApp|AppIcons)|$M/(RunningApps|InstalledApps))\.swift:")"
check "System Settings deep links (x-apple.systempreferences) only in App/Links.swift" "$(hits 'x-apple\.systempreferences' '^App/Links\.swift:')"
R_DEFAULTS='UserDefaults|@AppStorage|@SceneStorage|NSUbiquitousKeyValueStore'
selftest defaults "$R_DEFAULTS" 'UserDefaults.standard.set(1, forKey: "a")'
check "UserDefaults, @AppStorage, @SceneStorage and iCloud key-value storage only in App/AppModel.swift" "$(hits "$R_DEFAULTS" '^App/AppModel\.swift:')"
R_PASTE='NSPasteboard|\.setString[[:space:]]*\(|\.setData[[:space:]]*\('
check "Pasteboard only in App/AppModel.swift and App/Export.swift" "$(hits "$R_PASTE" '^App/(AppModel|Export)\.swift:')"
check "Share services (NSSharingService, NSSharingServicePicker, ShareLink) nowhere: the card is copied or saved, never uploaded" "$(hits 'NSSharingService|ShareLink')"
check "No notifications in v1" "$(hits 'UserNotifications|UNUserNotificationCenter|UNMutableNotificationContent|NSUserNotification')"

# 9. Materialization is off for the whole process, pinned at the entry point (EDEADLK then means "dataless": record, don't retry).
MAT=$M/Materialization.swift
check "setiopolicy_np only in $MAT" "$(hits 'setiopolicy_np|getiopolicy_np|IOPOL_' "^$MAT:")"
matprobs() {
  local f=$1 s
  for s in 'typeMaterializeDatalessFiles: Int32 = 3' 'scopeProcess: Int32 = 0' 'materializeOff: Int32 = 1' \
           'setiopolicy_np(typeMaterializeDatalessFiles, scopeProcess, materializeOff) == 0'; do
    grep -qF -- "$s" "$f" || echo "$f: lost the line: $s"
  done
  grep -qE 'static func disableForProcess\(\)' "$f" || echo "$f: lost disableForProcess()"
  grep -E 'scopeThread|materializeOn|allowingOnThisThread' "$f" | grep -vE '^[[:space:]]*//' && echo "$f: Aftertaste never turns materialization back on"
}
if [ -f "$MAT" ]; then check "$MAT must disable dataless materialization process-wide and never re-enable it" "$(matprobs "$MAT")"; fi
if [ -f App/AftertasteApp.swift ]; then
  grep -qF 'Materialization.disableForProcess()' App/AftertasteApp.swift || check "App/AftertasteApp.swift must call Materialization.disableForProcess() at launch" "App/AftertasteApp.swift: missing call"
fi

# 10. No network, no telemetry, no updater framework in v1 (Check for Updates opens the GitHub Releases page).
R_NET='URLSession|NSURLSession|NWConnection|NWPathMonitor|NWBrowser|NWListener|import Network|CFNetwork|CFStream|CFSocket|NSURLConnection|URLProtocol|WKWebView|import WebKit|SFSafariView|AsyncImage|MultipeerConnectivity|NetService|CloudKit|(^|[^[:alnum:]_.])socket[[:space:]]*\(|\b(Darwin|Glibc)\.(socket|connect|bind|listen|accept|sendto|getaddrinfo)\b|getaddrinfo|gethostbyname'
selftest net "$R_NET" 'let (d, _) = try await URLSession.shared.data(from: u)'
selftest net "$R_NET" 'import Network'
selftest net "$R_NET" 'let s = socket(AF_INET, SOCK_STREAM, 0)'
check "No network: no URLSession, Network framework, CFNetwork, sockets, web views, AsyncImage or CloudKit" "$(hits "$R_NET")"
check "No Sparkle and no other dependency in v1: the app never goes online by itself" \
  "$(grep -rnsE 'Sparkle|SUFeedURL|SUPublicEDKey|\.package[[:space:]]*\(' App Sources project.yml Package.swift | grep -vE "$C" || true)"

# 11. Paths reveal which apps a person has had installed: nothing prints or logs them.
R_LOG='(^|[^[:alnum:]_.])(print|debugPrint|dump|NSLog)[[:space:]]*\(|\bos_log\b|\bLogger[[:space:]]*\(|OSLog'
selftest log "$R_LOG" 'print(path)'
selftest log "$R_LOG" 'NSLog("%@", p)'
selftest log "$R_LOG" 'os_log("x")'
check "No print, debugPrint, dump, NSLog, os_log, Logger or OSLog" "$(hits "$R_LOG")"
check "Our own environment is read only in App/Demo.swift (-demoScreen / AFTERTASTE_DEMO)" \
  "$(hits 'ProcessInfo\.processInfo\.environment|getenv[[:space:]]*\(|\benviron\b|setenv[[:space:]]*\(' '^App/Demo\.swift:')"
check "No interpolation into fatalError, precondition or assert messages (a crash report must not carry names or paths)" \
  "$(hits '\b(fatalError|preconditionFailure|assertionFailure|precondition|assert)[[:space:]]*\(.*\\\(' '^App/Demo\.swift:')"

# 12. Layering. Core is Foundation-only and pure; Security/AppKit/Darwin live in the Mac layer; the app never touches them.
check "Sources/AftertasteCore imports only Foundation" \
  "$(hits '^[[:space:]]*(@testable )?import ' 'import Foundation[[:space:]]*$' Sources/AftertasteCore)"
R_SYSIMPORT='import (Darwin|Glibc|MachO|IOKit|Security|libproc)|getuid[[:space:]]*\(|geteuid[[:space:]]*\(|getpid[[:space:]]*\(|getppid[[:space:]]*\(|sysctl|rusage'
selftest sysimport "$R_SYSIMPORT" 'import Darwin'
check "Darwin, Security, sysctl and uid/pid calls only in Sources/AftertasteMac (Core and App never touch them)" "$(hits "$R_SYSIMPORT" '' 'Sources/AftertasteCore App')"
check "SwiftUI/Combine never in Sources/ (UI is App/ only); AppKit/Cocoa only in $M/RunningApps.swift and $M/InstalledApps.swift" \
  "$(hits 'import (SwiftUI|Combine|AppKit|Cocoa|UIKit)' "^$M/(RunningApps|InstalledApps)\.swift:" Sources)"

# 13. iCloud and sync folders are hands-off: their names appear in one place (the never-list), nowhere else.
R_ICLOUD='Mobile Documents|CloudStorage|CloudDocs|FileProvider|iCloud~|com~apple~CloudDocs'
selftest icloud "$R_ICLOUD" 'let p = home + "/Library/Mobile Documents"'
selftest icloud "$R_ICLOUD" 'let p = home + "/Library/CloudStorage/Dropbox"'
check "iCloud/CloudDocs/FileProvider/CloudStorage names only in Sources/AftertasteCore/Rules/NeverList.swift" "$(hits "$R_ICLOUD" '^Sources/AftertasteCore/Rules/NeverList\.swift:')"

# 14. Selection. Only High is ever preselected, and the one place a set of ticks is built is Core/Selection/ItemSelection.swift.
R_SELECT='isSelected[[:space:]]*=[[:space:]]*true|\b(ticked|selected|selection)[A-Za-z]*\.(insert|formUnion|update)[[:space:]]*\('
selftest select "$R_SELECT" 'item.isSelected = true'
selftest select "$R_SELECT" 'ticked.insert(item.id)'
selftest select "$R_SELECT" 'selectedIDs.formUnion(all)'
# AppModel assigns `ticked` only from ItemSelection (or clears it): direct assignment, union and += could preselect Medium or Review.
R_TICKED='\bticked[[:space:]]*(=|\+=)|\bticked\.(union|subtracting|formUnion|insert|remove)'
selftest ticked "$R_TICKED" 'ticked = Set(scan.items.map(\.id))'
selftest ticked "$R_TICKED" 'ticked += [id]'
selftest ticked "$R_TICKED" 'ticked.formUnion(all)'
selftest ticked "$R_TICKED" 'ticked = ticked.union(all)'
cleantest ticked "$R_TICKED" 'if ticked.contains(id) {'
cleantest ticked "$R_TICKED" '@Published private(set) var ticked: Set<String> = []'
check "Ticking happens only in Sources/AftertasteCore/Selection/ItemSelection.swift (a unit test proves tier != .high is never preselected)" \
  "$(hits "$R_SELECT" '^Sources/AftertasteCore/Selection/ItemSelection\.swift:')"
check "App assigns ticked only through ItemSelection. (or = [])" \
  "$(hits "$R_TICKED" 'ItemSelection\.|ticked[[:space:]]*=[[:space:]]*\[\]' App)"

# 15. macOS 13 deployment target: newer APIs only in App/DesignSystem/Compat.swift, behind if #available.
check "macOS 14+ APIs only in App/DesignSystem/Compat.swift" \
  "$(hits 'ContentUnavailableView|\.onKeyPress|\.symbolEffect|Animation\.smooth|\.smooth[[:space:]]*\(|@Observable|@Bindable|\.inspector[[:space:]]*\(|\.contentMargins|Button[[:space:]]*\([^)]*systemImage:|initial:|AccessibilityNotification|backgroundProminence|SettingsLink|containerRelativeFrame|\.scrollPosition[[:space:]]*\(|\.phaseAnimator|\.keyframeAnimator|\.scrollTargetBehavior|\.sensoryFeedback|\.containerBackground|\.presentationBackground|\.focusEffectDisabled|\.defaultScrollAnchor|\.windowResizeBehavior|\.windowToolbarStyle|\.activate[[:space:]]*\(\)|buttonBorderShape[[:space:]]*\(\.capsule\)|onChange[[:space:]]*\(of:[^{]*\)[[:space:]]*\{[[:space:]]*[A-Za-z_]+[[:space:]]*,[[:space:]]*[A-Za-z_]+[[:space:]]+in|glassEffect|\.fileDropDestination' '^App/DesignSystem/Compat\.swift:')"

# 16. Only Swift is compiled: a C/ObjC file or a build-phase script would escape every grep above.
check "Sources/ and App/ hold no non-Swift source files; project.yml has no build scripts; Package.swift no plugins" \
  "$(find Sources App -type f \( -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o -name '*.m' -o -name '*.mm' -o -name '*.h' -o -name '*.hpp' -o -name '*.s' -o -name '*.S' -o -name '*.sh' -o -name '*.py' -o -name '*.js' -o -name '*.pl' -o -name '*.rb' \) 2>/dev/null; grep -nE 'preBuildScripts|postBuildScripts|postCompileScripts|buildToolPlugins|runOnlyWhenInstalling|^[[:space:]]*-?[[:space:]]*script:' project.yml 2>/dev/null || true; grep -nE '\.plugin\(|plugins:|unsafeFlags|linkerSettings|cSettings' Package.swift || true)"

# 17. Honest copy: tools/banned_phrases.txt is matched against everything the user can read (App/, Sources/ strings, site/, .github/,
#     README.md, CHANGELOG.md). Whole-line // comments in Swift are exempt; any other line may carry the marker
#     `no-claim-ok` when it names a banned phrase only to say we do not make that claim.
BP=tools/banned_phrases.txt
BP_RE=$(grep -vE '^[[:space:]]*(#|$)' "$BP" | paste -sd'|' -)
bp_hits() {   # bp_hits FILE_OR_DIR...: banned phrase hits, minus marker lines and Swift comment lines
  grep -rnsIiE --exclude-dir=_dist --exclude='BannedPhrases.swift' "$BP_RE" "$@" | grep -vF 'no-claim-ok' | grep -vE '^[^:]+\.swift:[0-9]+:[[:space:]]*//' || true
}
if [ -f "$BP" ]; then
  T=$(mktemp -d)
  cat > "$T/p.txt" <<'PHRASES'
This app will securely erase your files
Use Secure Delete for sensitive data
Your data is permanently deleted
The files are permanently gone
It leaves unrecoverable gaps
irrecoverable
data cannot be recovered
a forensic-proof cleaner
anti-forensic mode
military grade
meets DoD standards
the NSA cannot read it
Gutmann 35 pass
a file shredder
Wipe the leftovers
100% gone
We guarantee it
a certified eraser
certificate of destruction
NIST compliant
GDPR ready
HIPAA safe
clean your Mac in one click
remove junk files
PHRASES
  want=$(grep -c . "$T/p.txt"); got=$(grep -ciE "$BP_RE" "$T/p.txt")
  [ "$got" -eq "$want" ] || check "safety_greps self-test: banned phrases missed ($got of $want matched)" "$(grep -viE "$BP_RE" "$T/p.txt")"
  sed 's/$/  no-claim-ok/' "$T/p.txt" > "$T/m.txt"
  [ -z "$(bp_hits "$T/m.txt")" ] || check "safety_greps self-test: the no-claim-ok marker did not exempt" "$(bp_hits "$T/m.txt")"
  printf 'Moved 3 items to the Trash. Undo from History. Erase readiness: FileVault is on.\n' > "$T/p.txt"
  [ -z "$(bp_hits "$T/p.txt")" ] || check "safety_greps self-test: banned-phrase regex flagged honest copy" "self-test failed"
  rm -rf "$T"
  check "Banned phrases (tools/banned_phrases.txt) in App/, Sources/, site/, .github/, README.md or CHANGELOG.md; mark an intentional mention 'no-claim-ok' and say why" \
    "$(bp_hits App Sources site README.md CHANGELOG.md .github)"
else
  check "tools/banned_phrases.txt is missing" "missing"
fi

# 18. Pinned-line checks (Overstay's Signal.swift pattern). The two files that move things must keep their guard order, and the
#     read-only command runner must keep its three commands. `ordered FILE LINES...` prints a problem per missing or
#     out-of-order line; the self-tests build a synthetic file from the required lines and mutate it.
ordered() {
  local f=$1; shift
  local c prev=0 n s
  c=$(grep -nvE '^[[:space:]]*//' "$f")
  for s in "$@"; do
    n=$(printf '%s\n' "$c" | grep -F -m1 -- "$s" | cut -d: -f1)
    if [ -z "$n" ]; then echo "$f: lost the line: $s"; continue; fi
    if [ "$n" -le "$prev" ]; then echo "$f: out of order (must come after the previous pinned line): $s"; fi
    prev=$n
  done
}
# Trasher.swift: the whole action is the planner-mirror refusal, verify (only .ok proceeds), the installed-owner refusal, running check, write-ahead intent, move, result, with no suspension point between
# the verification and the move, exactly one trashItem, and its error never swallowed.
TRASH_PINS=('Journal.begin(' 'notAllowed(item, in: plan)' 'Guard.verify(' 'case .ok: break' 'isInstalled(owner)' 'RunningApps.snapshot(' 'RunningCheck.state(' 'Journal.intent(' 'trashItem(at: url, resultingItemURL: &resulting)' 'Journal.result(')
trashprobs() {
  local f=$1 c n a b
  ordered "$f" "${TRASH_PINS[@]}"
  c=$(grep -nvE '^[[:space:]]*//' "$f")
  n=$(printf '%s\n' "$c" | grep -cE 'trashItem[[:space:]]*\(')
  [ "$n" -eq 1 ] || echo "$f: expected exactly one trashItem(, found $n"
  printf '%s\n' "$c" | grep -E 'trashItem' | grep -E 'try[?!]' || true
  a=$(printf '%s\n' "$c" | grep -F -m1 'Guard.verify(' | cut -d: -f1)
  b=$(printf '%s\n' "$c" | grep -F -m1 'trashItem(' | cut -d: -f1)
  if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then
    printf '%s\n' "$c" | awk -F: -v a="$a" -v b="$b" '$1>=a && $1<=b' | grep -E '\bawait\b|Task\.sleep|DispatchQueue|withCheckedContinuation|withTaskGroup' | sed "s|^|$f: suspension point between Guard.verify and trashItem: |" || true
  fi
  printf '%s\n' "$c" | grep -E '\.(removeItem|moveItem|copyItem)|NSWorkspace' || true
}
# UndoStore.swift: verify the Trash entry against the journal stamp, refuse an occupied destination, write-ahead intent, move
# back out of the Trash to the recorded original, result. One moveItem; destination never overwritten.
UNDO_PINS=('Journal.begin(' 'Guard.verifyRestore(' 'Journal.intent(' 'moveItem(at: trashed, to: original)' 'Journal.result(')
undoprobs() {
  local f=$1 c n
  ordered "$f" "${UNDO_PINS[@]}"
  c=$(grep -nvE '^[[:space:]]*//' "$f")
  n=$(printf '%s\n' "$c" | grep -cE '(^|[^[:alnum:]_])moveItem[[:space:]]*\(')
  [ "$n" -eq 1 ] || echo "$f: expected exactly one moveItem(, found $n"
  printf '%s\n' "$c" | grep -E '(^|[^[:alnum:]_])moveItem' | grep -E 'try[?!]' || true
  printf '%s\n' "$c" | grep -E 'trashItem|replaceItem|\.removeItem|copyItem' || true
}
# Guard.swift: canonicalise the parent, never follow the leaf, same device, local volume, flags, owner, the pure Core policy,
# and verifyRestore's Trash-entry identity and occupied-destination checks. Whole expressions, not bare tokens: a bare token
# (an enum case, a second mention) can be satisfied by another line after the real check is deleted.
GUARD_PINS=('GuardPolicy.check(' 'realpath(' 'lstat(' 'st_dev' 'MNT_LOCAL' 'st_flags' 'Stamps.same(' 'st.st_uid == getuid()' 'Fs.dataVaultFlag' 'Fs.datalessFlag' 'Fs.lockedFlags' 'record.stamp.device' 'record.stamp.inode' 'return .destinationExists')
guardprobs() {
  local f=$1 s
  for s in "${GUARD_PINS[@]}"; do
    grep -vE '^[[:space:]]*//' "$f" | grep -qF -- "$s" || echo "$f: lost the check: $s"
  done
}
# Journal.swift: append-only, never follows a symlink, private file and folder, durable, fail closed.
journalprobs() {
  local f=$1 s
  for s in 'O_APPEND' 'O_NOFOLLOW' 'O_NONBLOCK' '0o600' '0o700' 'fsync(' 'static func begin(' 'static func intent(' 'static func result('; do
    grep -vE '^[[:space:]]*//' "$f" | grep -qF -- "$s" || echo "$f: lost: $s"
  done
  grep -E 'O_TRUNC|ftruncate|\.removeItem' "$f" | grep -vE '^[[:space:]]*//' || true
}
# ReadinessProbe.swift: a closed enum of three commands; the only absolute paths in the file are theirs; no other arguments.
PROBE_PINS=('return "/usr/bin/fdesetup"' 'return "/usr/sbin/diskutil"' 'return "/usr/bin/tmutil"' 'return ["status"]' 'return ["info", "-plist", "/"]' 'return ["listlocalsnapshots", "/"]' 'process.executableURL = URL(fileURLWithPath: command.path)' 'process.arguments = command.arguments')
probeprobs() {
  local f=$1 c n
  c=$(grep -vE '^[[:space:]]*//' "$f")
  ordered "$f" "${PROBE_PINS[@]}" | grep -v 'out of order' || true
  printf '%s\n' "$c" | grep -oE '"/(usr|bin|sbin|opt|System|Library|private)[^"]*"' | grep -vxE '"/usr/bin/fdesetup"|"/usr/sbin/diskutil"|"/usr/bin/tmutil"' | sed "s|^|$f: unexpected absolute path literal: |" || true
  printf '%s\n' "$c" | grep -E '\b(deletelocalsnapshots|thinlocalsnapshots|localsnapshot|secureErase|eraseVolume|eraseDisk|disable|enable|startbackup|restore|apfs|mount|unmount|repair|destinationinfo|sudo)\b' | sed "s|^|$f: forbidden word: |" || true
  n=$(printf '%s\n' "$c" | grep -cE '\.arguments[[:space:]]*=')
  [ "$n" -eq 1 ] || echo "$f: expected exactly one .arguments assignment, found $n"
  n=$(printf '%s\n' "$c" | grep -cE '\.executableURL[[:space:]]*=')
  [ "$n" -eq 1 ] || echo "$f: expected exactly one .executableURL assignment, found $n"
  printf '%s\n' "$c" | grep -E 'terminate\(|interrupt\(|kill|launchPath|\.launch\(\)' | sed "s|^|$f: a timed-out probe is abandoned, never signalled: |" || true
}

selfcheck

# --- real files, when they exist --------------------------------------------------------------------------------------
[ -f "$M/Trasher.swift" ] && check "$M/Trasher.swift must keep the verify, running check, intent, trashItem, result order with no await between" "$(trashprobs "$M/Trasher.swift")"
[ -f "$M/UndoStore.swift" ] && check "$M/UndoStore.swift must keep verifyRestore, intent, one moveItem, result" "$(undoprobs "$M/UndoStore.swift")"
[ -f "$M/Guard.swift" ] && check "$M/Guard.swift must keep its canonicalisation, same-device, local-volume, flag and policy checks" "$(guardprobs "$M/Guard.swift")"
[ -f "$M/Journal.swift" ] && check "$M/Journal.swift must stay append-only, no-follow, 0600/0700, fsync'd" "$(journalprobs "$M/Journal.swift")"
[ -f "$M/ReadinessProbe.swift" ] && check "$M/ReadinessProbe.swift must run exactly fdesetup status, diskutil info -plist / and tmutil listlocalsnapshots /" "$(probeprobs "$M/ReadinessProbe.swift")"

# --- self-tests of the probes: a synthetic file made of the pinned lines is clean, and every mutation is flagged ----------
synth() { local out=$1; shift; : > "$out"; printf '%s\n' "$@" >> "$out"; }
probe_selftest() {   # probe_selftest NAME PROBEFN SYNTHFILE
  local name=$1 fn=$2 f=$3 T m
  T=$(mktemp -d)
  [ -z "$($fn "$f")" ] || check "safety_greps self-test: $name flagged its own pinned lines" "$($fn "$f")"
  shift 3
  for m in "$@"; do
    sed "$m" "$f" > "$T/m.swift"
    [ -n "$($fn "$T/m.swift")" ] || check "safety_greps self-test: the $name check missed the mutation $m" "self-test failed"
  done
  rm -rf "$T"
}
if [ -z "${SAFETY_FAST:-}" ]; then   # SAFETY_FAST=1 skips the ~80 mutation runs (slow on Windows Git Bash); CI never sets it
T=$(mktemp -d)
synth "$T/Trasher.swift" "${TRASH_PINS[@]}"
probe_selftest trasher trashprobs "$T/Trasher.swift" \
  's/Journal.begin(/Journal.start(/' 's/notAllowed(item, in: plan)/allowed(item, in: plan)/' 's/case .ok: break/case .ok: continue/' 's/isInstalled(owner)/isGone(owner)/' 's/Guard.verify(/Guard.skip(/' 's/RunningApps.snapshot(/RunningApps.skip(/' 's/RunningCheck.state(/RunningCheck.skip(/' \
  's/Journal.intent(/Journal.skip(/' 's/Journal.result(/Journal.skip(/' 's/trashItem(at: url, resultingItemURL: &resulting)/trashItem(at: url, resultingItemURL: nil)/' \
  's/trashItem(at: url, resultingItemURL: &resulting)/try? trashItem(at: url, resultingItemURL: \&resulting)/' \
  '$a try fm.trashItem(at: url, resultingItemURL: &resulting)' '$a try fm.removeItem(at: url)' '$a try fm.moveItem(at: a, to: b)' \
  '/Guard.verify(/{n;s/^/await Task.yield()\n/}' '/RunningCheck.state(/{n;s/^/let x = await foo()\n/}' \
  '1{h;d};/Journal.intent(/{G}' '$a NSWorkspace.shared.recycle([u]) { _, _ in }'
synth "$T/UndoStore.swift" "${UNDO_PINS[@]}"
probe_selftest undo undoprobs "$T/UndoStore.swift" \
  's/Guard.verifyRestore(/Guard.skip(/' 's/Journal.intent(/Journal.skip(/' 's/moveItem(at: trashed, to: original)/moveItem(at: trashed, to: other)/' \
  's/moveItem(at: trashed, to: original)/try? fm.moveItem(at: trashed, to: original)/' 's/Journal.result(/Journal.skip(/' \
  '$a try fm.moveItem(at: a, to: b)' '$a try fm.replaceItemAt(a, withItemAt: b)' '$a try fm.trashItem(at: u, resultingItemURL: nil)'
synth "$T/Guard.swift" "${GUARD_PINS[@]}"
probe_selftest guard guardprobs "$T/Guard.swift" 's/realpath(/path(/' 's/MNT_LOCAL/MNT_X/' 's/GuardPolicy.check(/GuardPolicy.skip(/' 's/st_flags/st_x/' 's/Stamps.same(/Stamps.skip(/' 's/lstat(/stat(/' \
  's/st_dev/st_x/' 's/st.st_uid == getuid()/st.st_uid == 0/' 's/Fs.dataVaultFlag/Fs.noFlag/' 's/Fs.datalessFlag/Fs.noFlag/' 's/Fs.lockedFlags/Fs.noFlag/' \
  's/record.stamp.device/record.stamp.dev/' 's/record.stamp.inode/record.stamp.ino/' 's/return .destinationExists/return .ok/'
synth "$T/Journal.swift" 'O_APPEND' 'O_NOFOLLOW' 'O_NONBLOCK' '0o600' '0o700' 'fsync(' 'static func begin(' 'static func intent(' 'static func result('
probe_selftest journal journalprobs "$T/Journal.swift" 's/O_NOFOLLOW/O_X/' 's/O_APPEND/O_X/' 's/0o600/0o644/' 's/fsync(/flush(/' 's/static func intent(/static func note(/' '$a let f = O_TRUNC' '$a try fm.removeItem(at: u)'
synth "$T/ReadinessProbe.swift" "${PROBE_PINS[@]}"
probe_selftest probe probeprobs "$T/ReadinessProbe.swift" \
  's|"/usr/bin/fdesetup"|"/usr/bin/fdesetup2"|' 's|return \["status"\]|return ["status", "-x"]|' 's|"/usr/sbin/diskutil"|"/usr/sbin/diskutil2"|' \
  '$a let p = "/bin/rm"' '$a let q = "/usr/sbin/softwareupdate"' '$a let a = ["deletelocalsnapshots", "/"]' '$a let s = ["secureErase", "freespace"]' \
  '$a process.arguments = ["x"]' '$a process.executableURL = URL(fileURLWithPath: "/usr/bin/open")' '$a process.terminate()' '$a kill(pid, 9)'
rm -rf "$T"
fi

[ "$fail" -eq 0 ] && echo "safety greps: ok"
exit $fail
