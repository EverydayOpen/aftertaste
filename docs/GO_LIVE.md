# Going live: from zero to the first public release

Aftertaste is free and open source: there are no payments, licences, accounts or updater to set up. Do the steps in order;
each one unblocks the next. `bash tools/doctor.sh` shows what's configured and what's still open. Signing and
notarization details live in [RELEASING.md](RELEASING.md); this file covers everything around them. Anything marked
**VERIFY** wasn't confirmed against the provider's docs, so check it there when you get to it.

The product decision, kill tests and launch plan are in the Whydunit repo's `docs/next/APP4.md` (sections 4 and 5) and the
`docs/next/app4-research-*.md` files; the build contract is [BUILD_PLAN.md](BUILD_PLAN.md). Nothing about runtime behaviour on a
real Mac has been verified yet (AGENTS.md): the first tester beta is where that starts.

## 1. Name check (before anything goes public)

On 2026-10-03 a search found 64 GitHub repositories named "aftertaste" (the top two with a handful of stars, one Swift repo at
0 stars), no Mac App Store result and no Homebrew cask. **Not searched:** trademark registers and domains. Run a knockout search
before any paid promotion. A knockout search is a quick screen for obvious conflicts, not a legal clearance.

- Search "Aftertaste" and close variants for software in Nice classes **9** (downloadable software) and **42** (software
  services):
  - USPTO: https://tmsearch.uspto.gov/
  - EUIPO: https://euipo.europa.eu/eSearch/ (**VERIFY** the address)
  - WIPO Global Brand Database: https://branddb.wipo.int/
  - India, IP India public search: https://tmrsearch.ipindia.gov.in/tmrpublicsearch/ (**VERIFY** the address)
  - The Mac App Store and a web search for "Aftertaste app" and "Aftertaste Mac".
- If a live mark or a shipping app uses the same or a confusingly similar name for software, switch to the fallback **Vestige**.
  The name appears in `project.yml`, `Package.swift`, `App/`, `Sources/`, `site/site.json`, the workflows' `APP`, the README and the
  site pages.
- Titles and the first line always read "Aftertaste for Mac" plus what it does.

## 2. GitHub: repo, Pages and the first CI runs

1. **Public repo, claimed on day 1.** On GitHub's free plan the repo must be public for the `release` environment, its secrets and
   its `v*` rule, for required reviewers, and for CodeQL. A public repo also runs standard GitHub-hosted runners, macOS included,
   for free (**VERIFY** current Actions pricing if you ever go private). Claim `https://everydayopen.github.io/aftertaste` early:
   a small app's search results can be poisoned by fake sites (the Pearcleaner case in the competitor research), and r/macapps
   removes posts from repos under 30 days old, so the repo should be public well before launch day.
2. **Push.** From this folder, with `gh` logged in as EverydayOpen:
   `git init -b main` (already done), confirm `git config user.email` is
   `36332199+EverydayOpen@users.noreply.github.com` (`bash tools/doctor.sh` checks), then
   `git add -A && git status --ignored`. Every file staged becomes public, so check that no key material or secrets are
   among them. Commit messages carry no `Co-Authored-By` trailer and name no AI tool or product (ci.yml's `checks` job
   fails the push otherwise). Then `gh repo create EverydayOpen/aftertaste --public --source . --push`. Keep `-b main`:
   `ci.yml` and `site.yml` run only on `main`.
3. **First CI run is the first compile.** Nothing in `AftertasteMac`, `AftertasteFixture` or `App/` has ever been compiled.
   Expect the `macos` job to fail on the first push; fix the compile errors from its log, in small commits, until it is
   green. The job builds the app **twice, Release and Debug**: the Release build skips `#if DEBUG` code, and the demo code lives
   there. Until both are green, every Mac and App file is "written, not compiled" (AGENTS.md).
4. **Pages.** The first push runs `site.yml`, which creates the `gh-pages` branch. Then open Settings › Pages › Build and
   deployment › Source: **Deploy from a branch**, branch `gh-pages`, folder `/ (root)`, and **Save**. The site is
   served at `https://everydayopen.github.io/aftertaste/`, which is `site/site.json`'s `baseURL` and `Links.website` in
   `App/Links.swift`; `bash tools/doctor.sh` checks that they agree. Leave **Issues** on: the site and the app's Help
   menu send people there. Create the label `wrong-match` for the issue form.
5. **Repository settings** listed in RELEASING.md step 4 (branch ruleset, immutable releases, private vulnerability
   reporting). **Leave the CodeQL default setup off**: `codeql.yml` is the setup. Its Swift build mode has never run
   (**VERIFY** the first run traces the build; the file's header says what to check).
6. **Screens.** Run Actions › **screens** once the Debug build is green and open the PNG artifacts: every frame must be a real
   window capture (the workflow checks size and non-blank, but look at them). The README hero and the site screenshots are picked
   from those frames and stay labelled "Sample data".
7. **The probe workflow (day 1).** Open Actions › **fixtures** › Run workflow. It runs the real-filesystem tests and a set of
   read-only probes on the arm64 and Intel runners and uploads `probe-*` artifacts. Read, in this order:
   - `probe-trash.txt`: does `FileManager.trashItem` work in the runner's session, what happens to a symlink (the link must
     move, the target must stay), does moving an item back work. If `trashItem` fails headless, the Trash tests skip and the
     tester beta is where it gets checked (BUILD_PLAN section 12).
   - `fdesetup`, `diskutil-info`, `tmutil-snapshots` `.stdout/.stderr/.exit`: do the three Erase-readiness commands work for an
     ordinary user on macOS 26 and on the Intel image? Their output becomes parser fixtures under
     `Tests/AftertasteCoreTests/Fixtures/commands/`.
   - `root-*` and `containers-listing`: which listings an ordinary process may read.
   Then update the VERIFY marks in BUILD_PLAN section 12. The runners are fresh virtual machines (no third-party containers, no
   Time Machine, no FileVault, no iCloud), so they cannot answer the Containers question: that is the testers' job (section 3).

## 3. Kill tests and testers (APP4 section 5)

The owner runs the gates, not an agent. Aftertaste is being built before K0 and K1 are answered (owner decision); the tester beta is
where they happen, and a failed gate stops the launch, not the repository.

- **K0 Demand probe.** Post a small, read-only script that lists the `~/Library` folders whose bundle-ID-shaped name matches no
  installed app, and ask for the count and size. Fewer than about 10 real pastes in 7 days: demand is quiet; reconsider.
- **K1 The card is interesting.** On at least 5 testers' Macs, at least 3 common apps leave a non-boring number (100 or more
  files, or 500 MB or more, after normal use). If typical results are "12 files, 40 MB", the card is not shareable.
- **K2 Zero wrong matches.** The hazard fixtures (Firefox and Thunderbird, Office, Adobe, JetBrains, VS Code, a same-named CLI
  folder, Xcode and Xcode-beta) must pre-select 0 items that belong to an installed app. This runs in CI (Core and the real
  filesystem); any failure is fixed before a beta goes out.
- **Buffer week, on macOS 15, 26 and 27:** read the testers' **Help › Copy Diagnostics**. The make-or-break question is
  whether the owning-app protection on `Containers` and `Group Containers` still applies once the app is gone, and what error a
  denied move returns (BUILD_PLAN section 12). If most container leftovers turn out unreadable even for removed apps, drop
  containers from the headline and market Preferences, Caches, Saved State and the rest; if that leaves a median under about
  200 MB per tester (a guess, not a measurement), shelve it. Also check `trashItem` on a symlink, Cookies protection, Finder's
  Put Back, and whether Full Disk Access changes anything (decides whether that button stays).
- **Any report of a wrong move** (something an installed app still needed, or something the user did not tick): stop the beta, add
  the case to the never-list and the fixtures, and publish the fix before anything else. One confirmed report not fixed within
  48 hours: pull the release.

## 4. Optional: a custom domain

Skip this unless you want your own domain; `everydayopen.github.io/aftertaste` works as is.

1. Verify the domain for the EverydayOpen organization first (organization Settings › Pages › **Add a domain**; GitHub
   shows a TXT record to add). This stops anyone else from taking the domain over on GitHub Pages.
2. Add these records at your DNS host:

   | Type | Name | Value |
   |---|---|---|
   | A | `@` | `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153` (four records) |
   | AAAA | `@` | `2606:50c0:8000::153`, `2606:50c0:8001::153`, `2606:50c0:8002::153`, `2606:50c0:8003::153` |
   | CNAME | `www` | `everydayopen.github.io` |

3. In the repo, open Settings › Pages › Custom domain, enter the domain and save. GitHub commits a `CNAME` file to
   `gh-pages`, which `site.yml` never overwrites. Tick **Enforce HTTPS** when it becomes available.
4. Change `site/site.json` `baseURL` and `Links.website` to `https://<domain>` (no path) and run
   `bash tools/doctor.sh`. The app has no update feed, so older copies only lose their Help link's address; GitHub
   redirects the old one.

## 5. Apple Developer Program and signing

Public betas can ship unsigned (`beta.yml`, with the Gatekeeper steps in the release notes and a SHA-256). A first
**public** launch is much better signed and notarized: follow RELEASING.md steps 1 to 4 (enrollment, the Developer ID
Application certificate, the App Store Connect Team API key, and the `release` environment with its seven secrets). With
`gh` logged in, `bash tools/doctor.sh` lists any secret that's still missing. Aftertaste is a file-moving app from a new
developer, so the trust cost of an unsigned build is real: decide before launch week, not on it. If Gatekeeper or Full Disk
Access trouble is more than 30% of the first 20 issues, signing is the blocker; ship no further unsigned betas. Unsigned casks
cannot enter the main Homebrew tap, so until a Developer ID exists the download is direct only.

## 6. Website and privacy review

1. `site/site.json` names the owner (EverydayOpen), shown in the site footer. Run
   `python tools/build_site.py --check` and push `main`: `site.yml` publishes the site. `/download/` shows the
   no-release-yet status line and the Releases button until `CHANGELOG.md` on `main` has a released section (step 9).
2. **Privacy review.** The site has no separate terms or privacy pages; the privacy text is the README "Privacy" section,
   the home page `#privacy` section and `/what-it-reads/#privacy`. Have a lawyer check it against: free, open-source software under the MIT License, provided as is; an app that
   **moves files other apps wrote** (to the Trash, with Undo; "findings, not guarantees" and the wording of the confirm sheet);
   what the app actually does (no network, no telemetry, no account, one local activity log of home-relative paths, a small
   inventory of installed apps and one preferences blob; reads folder names and sizes and a few property-list files, never
   other file contents); GitHub as host of the site and the downloads (it sees visitors' IP addresses; **VERIFY** what it logs for
   Pages and release downloads); and the contact route for privacy requests.
3. **Honest-copy review.** Read the site, the README, the app's strings and a screenshot of every screen against the list in
   `tools/banned_phrases.txt` and against APP4 section 1.2 ("will say" / "will never say"). The CI check only catches the phrases
   it knows; look for the meaning, not just the words (BUILD_PLAN section 12, last item).
4. The site and README use real tester numbers once they exist, with permission. Until then every number is labelled
   "Sample data".

## 7. Go / no-go

Publish only when all of these hold:

- CI is green on the exact commit being tagged, both Release and Debug builds, including the real-filesystem tests on arm64 and
  Intel.
- K2 passed (it runs in CI) and K1 did not fail; the buffer-week container question is answered or the Containers rows are
  documented as best effort.
- The first-run explainer, the preview, the confirm sheet ("Items go to the Trash. You can undo from History until you empty
  it.") and the result sheet were read by a person on a real Mac, and Undo was used at least once on a real Mac.
- The release notes state what was tested ("tested by N testers on macOS X"), nothing more.
- `bash tools/doctor.sh` has no `ERROR` and no `todo` you have not decided to accept; `tools/safety_greps.sh` and
  `tools/repo_checks.sh` are green.

## 8. Before the first public release

**Rehearse** as RELEASING.md describes under "Before the first public release".

## 9. First release

1. On release day, rename `## Unreleased` in `CHANGELOG.md` to `## 1.0.0 — <that day>` and commit it, then tag and push
   only `v1.0.0`. Push `main` once the release is published (RELEASING.md "Cutting a release"): that push deploys the
   site, and `/download/` stops showing the no-release-yet status line.
2. **Homebrew** (optional, **VERIFY**): an own tap `EverydayOpen/homebrew-tap` with a cask pointing at
   `releases/download/v1.0.0/Aftertaste-1.0.0.dmg` and its SHA-256. Homebrew's stance on casks in its official tap is
   unverified; an own tap avoids the question.

## 10. Launch and after

APP4 section 4.2 has the order. **Trust first:** the canonical URL everywhere, SHA-256 checksums in each release, `SECURITY.md`, a
"never paste a Terminal command to install this" line, and the banned-phrase CI check visible in the README (the honesty is the
pitch). The repo is public from day 1 so it is over 30 days old by launch. The owner writes the posts, not an agent, and posts
nothing automatically.

- **Launch day L** (after the buffer week): the GitHub release (unsigned beta, with checksums); the site; an r/macapps post that
  leads with a real tester's Trace Report card for a named app and a measured number, not the tool. Show HN only with the
  measurement angle ("what uninstalling X left behind, measured"): tool posts score low there, grievance posts score high.
  Post Tuesday to Thursday, about 8 to 10 am US Eastern, and avoid Black Friday week.
- **Weeks 2 to 4:** collect tester cards into a `RESIDUE.md` table (app versions, macOS, sample size stated); answer every issue
  within 48 hours; a second post only when there is new measured data.

Post-release checks:

- The stable link downloads the new DMG
  (`https://github.com/EverydayOpen/aftertaste/releases/latest/download/Aftertaste.dmg`; `<baseURL>/download/` does not use it
  yet, so check the page's own link too). It opens and the app launches without a Gatekeeper warning. The release workflow
  already launched it on Apple silicon and Intel.
- `/changelog/` and `/feed.xml` show the release.
- In the app, the Help menu opens the website and the wrong-match form, and everything works with Wi-Fi off.
- Watch Issues (every wrong match becomes a Core fixture and a test) and the Actions runs. The weekly **ci** and **fixtures**
  runs show whether the current macOS image still behaves as the tests assume.
- Kill criteria (APP4 section 5): by day 14, under 150 stars and under 500 downloads: stop feature work and keep the site; 150 to
  500: maintenance only; over 500: continue (v1.1 candidates: a gated file-level overwrite on non-flash volumes only, removal of
  orphaned launch agents, a public Residue Index page). By day 60, under 400 stars and fewer than 5 external issues or pull
  requests: archive with a clear README. At any time: a competitor ships a before-delete shareable report, or Pearcleaner resumes
  development: re-run the comparison before spending more.
