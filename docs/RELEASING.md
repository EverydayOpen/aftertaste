# Releasing Aftertaste

There are two kinds of tag, and until a Developer ID exists only the first is used:

- `vX.Y.Z-beta.N` runs [beta.yml](../.github/workflows/beta.yml): an ad-hoc signed universal zip as a GitHub
  pre-release, with its SHA-256 in the notes and as a `.sha256` asset, and the Gatekeeper steps for testers. Pre-releases never become
  `releases/latest`, so the site's download link is unaffected.
- `vX.Y.Z` (digits only) runs [.github/workflows/release.yml](../.github/workflows/release.yml) in three jobs:
  1. **build** first runs a preflight that fails before any build time: the tag's version must have a `CHANGELOG.md`
     section; `site/site.json`'s `baseURL` and `Links.website` in `App/Links.swift` must be real and agree
     (`bash tools/doctor.sh --ci`); the safety greps must pass; `releasesRepo` must be this repository and `dmgName` must
     be `Aftertaste.dmg`; and `notarytool` must accept the App Store Connect key. It then runs `swift test` (the
     real-filesystem tests scan a fake home and really move files to the Trash and back), archives a universal (arm64 + x86_64) Developer ID build
     with the hardened runtime, checks the bundle (both architectures, hardened runtime, **no entitlements, no usage
     strings**, no demo-mode code, which exists only in Debug builds) and launches it on the arm64 runner (it must stay up for 10 seconds). Only then does it notarize and
     staple the app, and build, sign, notarize and staple the DMG.
  2. **smoke-intel** launches the same signed app on GitHub's Intel runner (`macos-15-intel`).
  3. **publish** runs only when both launch tests passed. It creates the GitHub Release with the changelog section
     plus the DMG's SHA-256 as its notes, and uploads the DMG twice: `Aftertaste-X.Y.Z.dmg`, and the fixed-name `Aftertaste.dmg`, which
     gives a stable `releases/latest/download/Aftertaste.dmg` link (the site's `/download/` page does not use it yet; once a
     signed release exists, point its button at `{{downloadURL}}`), plus a `SHA256SUMS` asset covering both.
     Notes, checksums and both DMGs are made in **build**, so **publish** has no checkout and runs no repo code.
     **build** also attests the DMGs' build provenance ([actions/attest-build-provenance](https://github.com/actions/attest-build-provenance),
     pinned by SHA; the job holds `id-token: write` and `attestations: write`), and beta.yml does the same for the zip.

Checking a download. `SHA256SUMS` (or the beta's `.sha256`) is made by the same job that uploads the file, so it only
catches a corrupted download. The attestation is the stronger check: it is signed through Sigstore and names the repository,
workflow and commit that built the file. With the [GitHub CLI](https://cli.github.com/) (run next to the download):

```sh
gh attestation verify Aftertaste-X.Y.Z.dmg -R EverydayOpen/aftertaste   # or the beta's Aftertaste-X.Y.Z-beta.N.zip
```

There is no updater framework (Sparkle) and no appcast: the app never goes online, so the website's download link and the Releases page are
the update path (the app's "Check for Updates" just opens Releases). Everything around the release (GitHub Pages, the
name check, the kill tests) is in [GO_LIVE.md](GO_LIVE.md).

Everything below works from Windows (Git Bash has `openssl` and `base64`). You only need a Mac to check the result.

## One-time setup (before the first signed release)

Do all of this **outside the repo folder**. `.gitignore` blocks `*.p12`, `*.p8`, `*.key` and `*.pem`, but key material
should never be in the working tree at all. Keep an offline backup of `devid.key`, `devid.p12` and the `.p8` file (a
password manager works). The same Developer ID certificate signs every EverydayOpen app.

### 1. Apple Developer Program

- Enroll as an **Individual** ($99/year). In India, enrollment only works through the **Apple Developer app** on an
  iPhone or iPad. Approval isn't instant, so start early.
- Write down your **Team ID** (developer.apple.com › Account › Membership details). It becomes the `DEVELOPMENT_TEAM`
  secret.

### 2. Developer ID Application certificate (no Mac needed)

```sh
openssl genrsa -out devid.key 2048
# MSYS_NO_PATHCONV=1: Git Bash rewrites arguments starting with '/' into Windows paths, which breaks -subj
MSYS_NO_PATHCONV=1 openssl req -new -key devid.key -out devid.csr -subj "/emailAddress=you@example.com/CN=Your Name/C=IN"
```

Go to developer.apple.com › Certificates, IDs & Profiles › Certificates › **+** › **Developer ID Application** (G2
Sub-CA), upload `devid.csr` and download `developerID_application.cer`. Then:

```sh
openssl x509 -inform DER -in developerID_application.cer -out devid.pem
# Legacy PKCS#12 algorithms so `security import` on the runner accepts the file
openssl pkcs12 -export -inkey devid.key -in devid.pem -out devid.p12 \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 -passout pass:CHOOSE_A_PASSWORD
base64 -w0 devid.p12 > devid.p12.b64
```

Only the Account Holder can create Developer ID certificates, and each account can have at most 5.

### 3. App Store Connect API key (for notarytool)

Go to App Store Connect › Users and Access › Integrations › **Team Keys**, generate a key with the Developer role, and
download `AuthKey_XXXXXXXXXX.p8`. You can download it only once. Write down the **Key ID** and the **Issuer ID** shown
above the table, then run:

```sh
base64 -w0 AuthKey_XXXXXXXXXX.p8 > authkey.p8.b64
```

Use a Team key: `--issuer` is required for Team keys and is rejected for Individual keys.

### 4. GitHub environment, secrets and repository settings

Environment secrets, the `v*` rule and required reviewers need a public repo, or GitHub Pro for a private one
([GO_LIVE.md](GO_LIVE.md) step 2).

In the repo, go to Settings › Environments › **New environment** `release`, then:

- Under Deployment branches and tags, choose *Selected* and add the tag rule `v*`.
- Add yourself as a required reviewer so every signing run waits for your approval.

Add these as **environment secrets** of `release`. With the GitHub CLI you can pipe files, for example
`gh secret set DEVELOPER_ID_P12_BASE64 --env release < devid.p12.b64`.

| Secret | Value |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | contents of `devid.p12.b64` |
| `DEVELOPER_ID_P12_PASSWORD` | the `.p12` password from step 2 |
| `KEYCHAIN_PASSWORD` | any random string |
| `DEVELOPMENT_TEAM` | your 10-character Team ID |
| `ASC_KEY_P8_BASE64` | contents of `authkey.p8.b64` |
| `ASC_KEY_ID` | Key ID from step 3 |
| `ASC_ISSUER_ID` | Issuer ID from step 3 |

The release and the website both publish with the workflow's own `github.token`, so there is no personal access token to
create or renew. `ExportOptions.plist` keeps `REPLACE_WITH_TEAM_ID`; the workflow fills in the real Team ID from the
secret.

Also set, because `bash tools/doctor.sh` checks them:

- A branch ruleset on `main` that blocks force pushes and deletion.
- A **tag ruleset** so only an admin can create `v*` tags: without it any collaborator with write access can push a
  `v*-beta.N` tag and publish a pre-release with no review (the `release` environment guards only signed releases). Settings
  › Rules › New tag ruleset, target `v*`, enforcement Active, rules Restrict creations, updates and deletions; leave only
  the repository admin role in the bypass list. From a terminal (`target` and `enforcement` are the rulesets API's field names, VERIFY):
  `gh api repos/EverydayOpen/aftertaste/rulesets -X POST --input -` with `{"name":"v-tags","target":"tag","enforcement":"active","conditions":{"ref_name":{"include":["refs/tags/v*"],"exclude":[]}},"rules":[{"type":"creation"},{"type":"update"},{"type":"deletion"}],"bypass_actors":[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"always"}]}`
  (`actor_id` 5 is the Admin role, VERIFY).
- **Immutable releases** on, and **private vulnerability reporting** on (SECURITY.md sends reports there).
- CodeQL runs from `.github/workflows/codeql.yml`, so leave the repository's CodeQL **default setup off**; the two conflict.
- Create the issue label `wrong-match` (the wrong-match form applies it).

## Tester betas

Tag `vX.Y.Z-beta.N` and push the tag. [beta.yml](../.github/workflows/beta.yml) builds an ad-hoc signed universal app
(hardened runtime off), launches it once, and publishes a GitHub pre-release with install steps, the zip's SHA-256 and a `.sha256` asset.
The pre-release's `--prerelease` flag keeps it off `releases/latest`.

Before sending a beta to testers, a person (not CI) runs `swift test` on a real Mac and says so in the release notes
("tested by N testers on macOS X"). Until then the notes must not claim any runtime behaviour (AGENTS.md).

## Cutting a release

1. Make sure `main` is green in the **ci** workflow, `bash tools/doctor.sh` shows no `ERROR`, and the go/no-go list in
   [GO_LIVE.md](GO_LIVE.md) step 7 is satisfied.
2. Rename `## Unreleased` in `CHANGELOG.md` to `## X.Y.Z — YYYY-MM-DD` (em dash, today's ISO date), check that the notes
   are written for users, and commit it, but don't push `main` yet. The section becomes the GitHub release notes and the
   site's changelog (`## Unreleased` is never published). Check it with
   `python tools/changelog.py notes X.Y.Z --format html`.
3. Tag that commit and push only the tag. The tag sets the version (`MARKETING_VERSION`), and the workflow run number
   sets the build number (`CURRENT_PROJECT_VERSION`). Don't edit the versions in `project.yml`.
   ```sh
   git tag v1.0.0
   git push origin v1.0.0
   ```
4. Open Actions › **release**, approve the environment, and wait about 20 minutes. The **build** and **publish** jobs
   both use the `release` environment, so a reviewer approves twice: once to build and once to publish after both launch
   tests have passed. If a launch test fails, the job prints the newest crash report. If notarization fails, it prints
   Apple's notary log.
5. **Push `main` once publish has succeeded** (`git push origin main`). That push deploys the site with the new changelog
   entry; pushed earlier, the site would list a release that doesn't exist yet. Before 1.0 has a released section on
   `main`, `/download/` shows the no-release-yet status line and the Releases button. If `main` moved meanwhile, `git pull --no-rebase` first: a rebase would
   leave the tagged commit off `main`.
6. **Verify on a Mac.** Download `Aftertaste-1.0.0.dmg` from Releases, download `SHA256SUMS` next to it and run `grep Aftertaste-1.0.0.dmg SHA256SUMS | shasum -a 256 -c` (the release notes carry the same hash, but they are editable; `SHA256SUMS` is the asset) and `gh attestation verify Aftertaste-1.0.0.dmg -R EverydayOpen/aftertaste`, then:
   ```sh
   xcrun stapler validate Aftertaste-1.0.0.dmg
   spctl -a -vvv -t open --context context:primary-signature Aftertaste-1.0.0.dmg   # accepted, source=Notarized Developer ID
   ```
   Open the DMG, drag the app to Applications and launch it. There should be no Gatekeeper warning. Then check:
   ```sh
   spctl -a -vvv /Applications/Aftertaste.app
   codesign -dvv /Applications/Aftertaste.app      # Authority=Developer ID Application, Timestamp=, flags=0x10000(runtime)
   lipo -archs /Applications/Aftertaste.app/Contents/MacOS/Aftertaste   # x86_64 arm64
   ```
   Then run it for real: install a throwaway app (one you do not need), use it once, drag it onto Aftertaste, read the preview, move the High items to the Trash, check the Trash and `~/Library/Application Support/Aftertaste/`, and Undo from History.
7. Check that `https://github.com/EverydayOpen/aftertaste/releases/latest/download/Aftertaste.dmg` downloads this version.

**Before the first public release,** tag a throwaway `v0.0.1` from a throwaway branch (with its own `CHANGELOG.md`
section, so the website never lists it), install it on a Mac, and check steps 6 and 7. This proves the certificate and
notarization work end to end. Delete the release afterwards (`gh release delete v0.0.1 --cleanup-tag`).

If a release is broken, don't reuse its version. Delete it (`gh release delete vX.Y.Z --cleanup-tag`), fix the problem and
tag the next patch version.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `security import` fails with `-25264 MAC verification failed` | Re-export the `.p12` with the legacy flags in step 2. |
| codesign: "unable to build chain to self-signed root" | Import Apple's Developer ID G2 intermediate (`https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer`) into the CI keychain in the import step. |
| Notary log: "not signed with a valid Developer ID certificate" or "no secure timestamp" | Check that the identity is *Developer ID Application*, not Apple Development, and that `OTHER_CODE_SIGN_FLAGS=--timestamp` is set. |
| notarytool returns 401 | A Team key needs `--issuer`. Check `ASC_ISSUER_ID` and that the key wasn't revoked. |
| Preflight: "CHANGELOG.md needs a '## X.Y.Z — …' section" | Add the section (em dash, ISO date, at least one line of notes), commit, delete the tag and push it again. |
| Preflight: the safety greps fail | Run `bash tools/safety_greps.sh` and fix the lines it prints. Never loosen a grep to get a release out. |
| "is not universal" | Check that the archive ran with `ARCHS="arm64 x86_64"`. |
| "must ship with no entitlements" | `App/Aftertaste.entitlements` must stay an empty dictionary; Aftertaste needs none. |
| `swift test` fails in the release job on the real-filesystem tests | Read the failure first. If `trashItem` is unavailable in the runner's session the Trash tests skip with the reason (BUILD_PLAN section 12) and the `fixtures` workflow's `probe-trash.txt` is the evidence; any other failure is a real bug in the scan, the guard or the move path. |
| Launch smoke test: "quit within 10 s of launch" | Read the crash report printed below the error. Crashes only on the Intel job usually mean an arm64-only binary, or an API newer than the runner's macOS used without `if #available`. |
