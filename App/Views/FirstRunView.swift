import AftertasteCore
import AppKit
import SwiftUI

/// The first-run explainer (BUILD_PLAN §7.1 screen 1, docs/DESIGN.md §6.5): a sheet over the welcome screen, shown until
/// Continue. What Aftertaste reads and what it never does, in plain words. Nothing is read before it is passed (the model
/// does not list the installed apps or start a scan until `hasSeenFirstRun`). It cannot be dismissed any other way.
struct FirstRunView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var risen = false

    private let reads: [(symbol: String, text: String)] = [
        ("list.bullet.rectangle", "Names and sizes of items in your Library"),
        ("square.grid.2x2", "The apps you have installed"),
        ("doc.text.magnifyingglass", "Each app's Info.plist and signature"),
        ("terminal", "Three read-only commands for Erase readiness"),
    ]
    private let never: [(symbol: String, text: String)] = [
        ("lock.open", "Asks for no permissions"),
        ("wifi.slash", "Makes no network connections"),
        ("doc", "Reads no file contents, apart from small property lists that name an app"),
        ("trash", "Deletes nothing: items go to the Trash, with Undo"),
        ("person.badge.key", "Needs no helper or administrator"),
    ]

    var body: some View {
        VStack(spacing: Space.m) {
            OnFloor(height: 112) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 112, height: 112)
            }
            .modifier(HoverTilt(max: 8, glare: true))
            .offset(y: risen || reduceMotion ? 0 : 24)
            .opacity(risen ? 1 : 0)
            .accessibilityHidden(true)
            Text("What Aftertaste reads")
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.5)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: Space.xl) {
                column("Reads", reads)
                column("Never", never)
            }
            .padding(Space.l)
            .surface(16)
            Button("Continue") { model.prefs.hasSeenFirstRun = true }
                .buttonStyle(DuskButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(Space.xxl)
        .frame(width: 580)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            // The icon rises 24pt and fades in once (MOTION §3.4); Reduce Motion gets a 150 ms fade.
            guard !risen else { return }
            if reduceMotion {
                withAnimation(Motion.standard(true)) { risen = true }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { withAnimation(Motion.hero) { risen = true } }
            }
        }
    }

    private func column(_ title: String, _ rows: [(symbol: String, text: String)]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).font(.caption.weight(.semibold).smallCaps()).foregroundStyle(.secondary)   // VERIFY small caps with SF
                .accessibilityAddTraits(.isHeader)
            ForEach(rows, id: \.text) { row in
                HStack(alignment: .top, spacing: Space.xs) {
                    // VERIFY each symbol exists on macOS 13 (SF Symbols app); a missing one draws nothing.
                    Image(systemName: row.symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(Brand.duskInk)
                        .frame(width: 18).accessibilityHidden(true)
                    Text(row.text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
