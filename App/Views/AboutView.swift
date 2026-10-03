import AppKit
import AftertasteCore
import SwiftUI

/// About (BUILD_PLAN §7.1 screen 10, docs/DESIGN.md §6.5): icon, name, version, what it is, the honesty statement and the
/// "not affiliated" line. A centred column that scrolls rather than clips. Links go through the model, the only place that
/// opens URLs (safety_greps.sh check 8d); the version comes from the model too (check 3c).
struct AboutView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            column
                .frame(width: 400)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.xl)
        }
    }

    private var column: some View {
        VStack(spacing: Space.s) {
            OnFloor(height: 96) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
            }
            .accessibilityHidden(true)
            VStack(spacing: Space.xxs) {
                Text("Aftertaste").font(.system(size: 28, weight: .semibold)).tracking(-0.5)
                Text("Version \(model.appVersion)").font(.system(.callout, design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
            }
            Text("Finds what an uninstalled app left behind, shows why each item belongs to it, and moves the ones you pick to the Trash, with Undo. Free and open source (MIT License).")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            // The honesty statement: what it can see, what it does, and what it does not promise.
            VStack(spacing: Space.xs) {
                Text("It can only see what macOS lets an ordinary app see. When macOS protects a folder it says so and points you to it.")
                Text("It reads names and sizes, plus the small property-list files that say who an app or launch item is, and makes no network connections. Launch agents and helpers are listed, not removed.")
                Text("It moves files to the Trash and never overwrites anything, so it makes no promise about what could be read back from the disk. Erase readiness shows what applies on this Mac.")
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Not covered") {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(PlanText.notCovered(), id: \.self) { Text($0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Space.xxs)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            HStack(spacing: Space.s) {
                Button("Website") { model.openWebsite() }
                Button("Releases") { model.openReleases() }
                Button("Report a Problem") { model.openIssues() }
            }
            .buttonStyle(.borderless)   // not .link: that style keeps the system blue, and the app has one accent
            .foregroundStyle(Brand.duskInk)
            CopyButton(title: "Copy Diagnostics") { Task { await model.copyDiagnostics() } }
                .help("Copies a table of which places could be read, with no file names")
            VStack(spacing: Space.xxs) {
                Text("Aftertaste is not affiliated with or endorsed by any app it detects. Their names belong to their owners.")
                    .fixedSize(horizontal: false, vertical: true)
                Text(TraceCardView.address).textSelection(.enabled)
                Text("© 2026 EverydayOpen")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }
}
