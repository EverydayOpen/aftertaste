# Aftertaste: notes for coding agents

Aftertaste is a free, open-source (MIT), offline macOS app (Swift/SwiftUI, macOS 13+, Swift 5 language mode, not sandboxed,
no permissions, no network) that finds what an uninstalled app left behind, shows why each item belongs to it with a
confidence tier, moves the items you choose to the Trash with Undo, and produces a shareable Trace Report. It also has a
read-only "Erase readiness" panel. It never overwrites, never permanently deletes, never needs root.

Read [docs/BUILD_PLAN.md](docs/BUILD_PLAN.md) first. It is the contract: model and Core API (§4), Mac API (§5), safety rules
(§3), UI rules and copy (§8), demo mode (§9), file ownership (§10). Product background and evidence: the Whydunit repo's
`docs/next/APP4.md` and `docs/next/app4-research-*.md`. Going live: `docs/GO_LIVE.md`, `docs/RELEASING.md` (infra writes them).

## Be honest about what has run

- Only `AftertasteCore` is compiled and tested locally (Linux, in Docker). `AftertasteMac`, `App/` and the workflows have never
  been compiled or run until a CI run on macOS says so. **Never claim Mac or App code builds or works unless a CI run shows
  it.** Say "written, not compiled". Nothing has run on a real Mac: never claim runtime behaviour (container access, FDA,
  `trashItem`, Put Back, Time Machine, anything about erasing) until a tester has tried it.
- Don't invent APIs, flags or behaviour. Check Apple's docs and headers; mark anything you couldn't verify with `VERIFY`. If
  you're unsure an API exists on macOS 13, don't use it, or put it in `App/DesignSystem/Compat.swift` behind `if #available`.
- macOS 13 means `ObservableObject`, `@Published` and `@StateObject`; never `@Observable` or `@Bindable`.
- CI must build **Debug as well as Release** (the Release build skips `#if DEBUG`, where the demo code lives).

## Test

```sh
bash tools/test_core_docker.sh          # Core build + tests in Docker (Windows Git Bash too); must pass with no warnings
bash tools/safety_greps.sh              # the safety rules as greps + their self-tests; must print "safety greps: ok"
SAFETY_FAST=1 bash tools/safety_greps.sh   # same without the slow pinned-line mutation runs (about 25 s on Windows)
bash tools/repo_checks.sh               # home paths, empty Buttons, Edit menu, commit identity and credit lines (infra)
swift test                              # on a Mac: Core, Mac and real-filesystem tests
python tools/changelog.py --self-test   # changelog parser and markdown renderer (infra)
python tools/build_site.py --check      # website build (infra)
bash tools/doctor.sh                    # what's configured and what's left before go-live (infra)
```

Windows tip: Git Bash heredocs and `sed` mangle backslashes. Write regexes and Swift with an editor tool, not with `echo`.

## Safety rules (BUILD_PLAN §3; `tools/safety_greps.sh` enforces the mechanical ones)

This app moves other apps' files. A wrong deletion is the failure that kills the product. In short:

- `FileManager.trashItem` only in `Sources/AftertasteMac/Trasher.swift`; `moveItem` only in `UndoStore.swift`. No `removeItem`,
  `unlink`, `rmdir`, `rm`, rename, copy, truncate, chmod, chflags, xattr anywhere in `Sources/` or `App/`.
- `Process` only in `ReadinessProbe.swift`, only `/usr/bin/fdesetup status`, `/usr/sbin/diskutil info -plist /`,
  `/usr/bin/tmutil listlocalsnapshots /`. No shell, no `launchctl`, no signals (`kill`, `SIG*`, `terminate`), no `sudo`, no helper.
- Precision over recall. Default selection is the High tier only (`ItemSelection`). Medium needs "Include my data" plus an
  acknowledgement; Review runs one item at a time; Hands off and Needs admin have no checkbox. Launch agents, daemons and
  privileged helpers are **listed, not removed** in v1.
- Re-verify immediately before every item (`Guard.verify`: canonical parent, `lstat` never followed, same device, local volume,
  no lock flags, same `FileStamp`; running check read fresh) with **no `await` between verification and `trashItem`**. Write-ahead
  journal (`intent` before, `result` after); if the journal can't be written, nothing moves. Undo uses the recorded
  `resultingItemURL`, never overwrites.
- Never read file contents (names, sizes, `lstat` only; the sole exceptions are `Info.plist`, launchd plists, container metadata
  plists, our own journal and inventory). Materialisation is disabled at launch. iCloud, CloudStorage, Mail, Messages, Photos,
  Safari, Keychains, `com.apple.*`, `~/Library/Developer`, `~/.Trash`, our own data: hard-coded never-list.
- No network, no telemetry, no Sparkle in v1, no `print`/`NSLog`/`os_log` (paths reveal which apps a person has had).
- No overwrite and no free-space fill in v1 (owner decision). Never claim "secure", "unrecoverable", "forensic-proof", "all traces"
  or anything in `tools/banned_phrases.txt`; copy says what happened and what was looked at, never what it means.
- No `Button` with an empty action (a dialog's `role: .cancel` is the exception).

## Repo rules

- **Naming and attribution (owner decision).** Never write Claude, Anthropic or any AI-tool credit in commit messages, author
  fields, trailers, PR text or "built with" lines. Docs, hazard data and fixtures may name apps Aftertaste detects (Zoom, Slack,
  Adobe, Office, Firefox, JetBrains, VS Code ...) with the README line "Aftertaste is not affiliated with or endorsed by any app it
  detects." Demo and screenshot data use fictional apps (`com.example.*`). Git identity:
  `EverydayOpen <36332199+EverydayOpen@users.noreply.github.com>`. No `Co-Authored-By` trailers, ever.
- No personal home paths in committed files (Windows user folders, or `/Users/` followed by a real name). CI fails on them. Use
  `~`, `<scratchpad>`, a repo-relative path, or the example user `jane`. `/Users/Shared` is allowed.
- Every release needs a `## X.Y.Z — YYYY-MM-DD` section in `CHANGELOG.md`, written for users. Upcoming notes go under
  `## Unreleased` (never published).
- One base URL, `https://everydayopen.github.io/aftertaste`: `site/site.json` `baseURL` == `App/Links.swift` `Links.website`.
  `tools/doctor.sh --ci` fails when they disagree.
- GitHub push protection blocks key-shaped literals even in tests: build fake secrets/tokens from pieces at runtime.
- Python tools use the standard library only. Never commit key material (`.p12`, `.p8`) or real secrets.
- Code style is ponytail (BUILD_PLAN §1): the shortest correct code, no protocols with one implementation, no view model per
  screen, comments only where the why isn't obvious. Don't name functions `open`, `read`, `write`, `remove`, `rename`, `link`,
  `stat` or `truncate` (the greps flag those tokens).

## Ownership

When several agents work in parallel, each edits only its own files (BUILD_PLAN §10). `Model/*`, `Package.swift`,
`docs/BUILD_PLAN.md`, `tools/safety_greps.sh` and `tools/banned_phrases.txt` are frozen until infra takes the tools over: add
extensions in your own files, and propose any other change in your report.
