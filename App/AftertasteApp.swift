import AftertasteMac
import AppKit
import SwiftUI

/// A regular window app (Dock icon): drag an app onto the window, pick one from the list, or look for leftovers of apps
/// that are gone. The menu bar item is optional (off by default) and only reopens the window. Closing the window quits the
/// app unless the item is on. There is no login item and no helper (BUILD_PLAN §1).
@main
struct AftertasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Created lazily by SwiftUI after `init()` below has run, so materialization is already off when the model exists.
    @StateObject private var model = AppModel()

    // First thing at launch: a dataless iCloud file then fails with EDEADLK instead of being downloaded by a scan
    // (BUILD_PLAN §3 S11; safety_greps.sh pins this call).
    init() { _ = Materialization.disableForProcess() }

    var body: some Scene {
        // The window first, so a demo launch always shows it (Overstay lesson e).
        Window("Aftertaste", id: "main") {
            RootView().environmentObject(model)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 980, height: 660)
        .commands { AftertasteCommands(model: model) }

        // Only inserted while the preference is on. A thin "Open Aftertaste": the window is the app.
        MenuBarExtra(isInserted: $model.prefs.showMenuBarItem) {
            OpenAftertasteMenu()
        } label: {
            Image(nsImage: MenuBarIcon.glyph).accessibilityLabel("Aftertaste")
        }
    }
}

private struct OpenAftertasteMenu: View {
    // VERIFY on macOS 13: openWindow(id:) reopens a closed Window scene from a MenuBarExtra menu.
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Aftertaste") {
            openWindow(id: "main")
            activateApp()
        }
        Divider()
        Button("Quit Aftertaste") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Menus. The Edit menu stays whole (never replace `.pasteboard` or `.textEditing`: tools/repo_checks.sh). Preferences is
/// a sheet in the main window, so the commands open the window first. Every item that moves nothing is a read or a view
/// change; Move to Trash is only ever the button in the window, behind its confirm sheet.
@MainActor private struct AftertasteCommands: Commands {
    @ObservedObject var model: AppModel
    // VERIFY on macOS 13: the environment reaches Commands, so openWindow works from a menu item.
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Choose App…") {
                show()
                Task { await model.chooseApp() }
            }
            .keyboardShortcut("o")
            .disabled(model.isBusy || model.sheetOpen)
            Button("Find Leftovers of Removed Apps") {
                show()
                Task { await model.findOrphans() }
            }
            .keyboardShortcut("l")
            .disabled(model.isBusy || model.sheetOpen)
        }
        CommandGroup(replacing: .appInfo) {
            Button("About Aftertaste") {
                show()
                model.show(.about)
            }
            Button("Check for Updates…") { model.openReleases() }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Preferences…") {
                show()
                model.showPreferences = true
            }
            .keyboardShortcut(",")
            .disabled(model.isBusy || model.showReport)
        }
        CommandGroup(after: .toolbar) {
            // The only keyboard route back; Escape stays with the sheets. These wait while the report or Preferences is open.
            Button("Back") { model.goBack() }
                .keyboardShortcut("[")
                .disabled(model.screen == .welcome || model.isBusy || model.sheetOpen)
            Button("Rescan") { Task { await model.rescan() } }
                .keyboardShortcut("r")
                .disabled(model.isBusy || model.sheetOpen || model.request == nil)
            Divider()
            Button("History") {
                show()
                model.show(.history)
            }
            .keyboardShortcut("y")
            .disabled(model.sheetOpen)
            Button("Erase Readiness") {
                show()
                model.show(.readiness)
            }
            .keyboardShortcut("e", modifiers: [.command, .option])
            .disabled(model.sheetOpen)
        }
        // No help book (its default item only says "Help isn't available"): the website instead.
        CommandGroup(replacing: .help) {
            Button("Aftertaste Help") { model.openWebsite() }
            Button("Report a Problem…") { model.openIssues() }
            Divider()
            // For testers: an errno matrix per place, no file names.
            Button("Copy Diagnostics") { Task { await model.copyDiagnostics() } }
        }
    }

    private func show() {
        openWindow(id: "main")
        activateApp()
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Mirrors `Preferences.showMenuBarItem` (set by `AppModel`): with the menu bar item on, closing the window keeps the
    /// app alive so the item can reopen it.
    static var keepRunning = false
    /// Set by `AppModel` while a Move or Undo runs: Command-Q and a closed window wait for it (the user can quit again after).
    static var busy = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Before SwiftUI creates the window; didFinish would be too late to drop the Tab menu items.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard Self.busy else { return .terminateNow }
        NSSound.beep()
        return .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !Self.keepRunning }
}
