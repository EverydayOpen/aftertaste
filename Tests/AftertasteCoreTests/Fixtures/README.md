# Core test fixtures

JSON and text fixtures read through `#filePath` (never bundled, so Linux builds stay warning-free).

- `library/*.json`: the hazard fixtures of BUILD_PLAN §6.1 (gate K2). `HazardFixtureTests` loads every file, builds a
  `ScanInput`, runs `Scan.analyze`, and checks the expectations. It then ticks **everything**, acknowledges everything, builds a
  plan, and asserts that nothing listed under `installedOwned` is preselected or planned.
- `commands/*.txt`, `commands/*.plist`: stdout of `fdesetup status`, `diskutil info -plist /` and `tmutil listlocalsnapshots /`
  captured on CI runners by the probe workflow (BUILD_PLAN §6.4). Hand-written until the first probe run, marked `# handwritten`
  (the test loader drops `#` lines from the text files).

Fake names only: the example user is `jane`, apps are `com.example.*`. The few real app names that exist in hazard data
(Zoom, Slack, Adobe, Firefox...) are listed in `Sources/AftertasteCore/Rules/Hazards.swift` and the README's
"not affiliated" note covers them. Fake Team IDs are ten upper-case letters and digits (`VENDORTEAM`).

## `library/*.json` schema

```
name, note             free text
kind                   "app" (uninstall-now) or "orphans"
target                 bundle ID of the app being removed (first app with that ID); "app" only
apps[]                 id, name, exec?, team?, path? (default /Applications/<name>.app), version?, groups[]?, embedded[]?, helpers[]?,
                       installed? (default true; the target is normally installed too)
library                { "<LibraryRoot.relativePath>": [ entry, ... ] }   user roots like "Library/Caches", system roots absolute
                       entry = "name" or { name, type: file|directory|symlink, container: <metadata ID>, label, program, programExists }
sizes                  { "<path relative to home>": bytes }   measured sizes; a Containers or Group Containers entry without one is "protected"
volumeMayBeMissing     true to simulate an unmounted drive
expect.tiers           { "<path>": "high|medium|low|handsOff|needsAdmin" }     paths are relative to ~ unless they start with /
expect.blocked         { "<path>": "<BlockReason>" }
expect.absent          paths that must not appear in the result at all
expect.installedOwned  paths an installed app uses: never preselected, never planned
expect.preselected     the exact set of preselected paths
expect.emptyResult     true when the scan must produce no group
```

Add a fixture by adding a file; the loader picks up everything in `library/`.
