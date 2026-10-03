# Changelog

Newest first. `tools/changelog.py` turns each section into the GitHub release notes and the website changelog, so
write for users. Headings must be `## X.Y.Z — YYYY-MM-DD` (em dash); the release workflow refuses a tag without one.
Write upcoming notes under `## Unreleased`, which is never published (the website deploys on every push to main). On
release day, rename it to `## X.Y.Z — <that day>`, commit, push only the tag, and push main once the release is
published (docs/RELEASING.md "Cutting a release"). Links must be full `https://` URLs: the GitHub release can't
resolve site-relative ones. Say what the app does, never what it means: findings, not promises (the phrases to avoid are in tools/banned_phrases.txt).

## Unreleased

First release. Aftertaste finds what an app you removed left behind on your Mac, shows why each item belongs to it, moves the
items you choose to the Trash, and lets you undo that. It also gives you a Trace Report you can save or share.

- **Two ways in**: drop an app onto the window to uninstall it and find its leftovers, or ask for the leftovers of apps that are
  already gone. You always see the list first; nothing moves until you press the button.
- **Shows why**: every row says why it belongs to the app, in one plain sentence, with a confidence tier. Only the items that
  rebuild themselves (caches, preferences, saved state, logs) are ticked for you. Anything that may hold your own data needs an
  extra switch and a tick, and shared or uncertain items are moved one at a time.
- **Moves to the Trash, with Undo**: items go to the Trash, never straight to deletion. History keeps every run and puts items back
  where they came from, without overwriting anything. Before each item moves, Aftertaste checks it again: that it is still the same
  item, that its app is not running and that nothing changed since the scan.
- **Says where it could not look**: "Looked in 25 of 26 places. 1 protected by macOS." Folders macOS protects are named, with a way
  to open them in Finder. It never says "nothing found" unless it could look everywhere.
- **Leaves some things alone**: Apple's own data, iCloud folders, Mail, Messages, Photos, Keychains and anything an installed app
  shares are never touched. Launch agents, launch daemons and privileged helpers are listed, not removed: removing the file would
  not stop a job that is already loaded, and the system-wide ones need an administrator.
- **Trace Report**: a card with measured numbers only (files, size, launch agents, helpers, how many places it looked in). Save it
  as an image, Markdown or JSON, or copy it. "Hide app names" swaps names for App 1, App 2.
- **Erase readiness**: a read-only page that says whether FileVault is on, what kind of storage this Mac has and how many local
  snapshots exist, and what no app can erase (snapshots, backups, iCloud copies, system logs). Moving a file to the Trash does not
  erase it; the page says so.
- Needs no permissions (it never requires Full Disk Access; when macOS blocks a folder it says so and offers an optional Settings shortcut), makes no network connections, reads no file contents and keeps a local activity log that never leaves the
  Mac. Requires macOS 13 or later, on Apple silicon or Intel. Free and open source under the MIT License. Aftertaste is not
  affiliated with or endorsed by any app it detects.
