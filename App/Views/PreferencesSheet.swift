import AftertasteCore
import SwiftUI
import UniformTypeIdentifiers

/// Preferences (BUILD_PLAN §7.1 screen 9): a stock grouped Form in a sheet, as tall as its content (no dead space), and
/// scrolling only once a long keep-list passes the cap. Everything is `model.prefs`, which the model stores. The keep-list only
/// ever adds protection (Core's `NeverList` reads it); nothing here can make Aftertaste touch more.
struct PreferencesSheet: View {
    @EnvironmentObject private var model: AppModel
    @State private var entry = ""
    @State private var problem: String?
    @State private var targeted = false

    var body: some View {
        // The first layout is the form at its own height; when that is taller than the cap, the second scrolls it.
        // VERIFY on a Mac that a grouped Form with scrolling off reports its content height on macOS 13.
        ViewThatFits(in: .vertical) {
            VStack(spacing: 0) {
                form.scrollDisabled(true).fixedSize(horizontal: false, vertical: true)
                bar
            }
            VStack(spacing: 0) {
                form
                bar
            }
        }
        .frame(width: 480)
        .frame(maxHeight: 560)
    }

    private var form: some View {
        Form {
            Section {
                Toggle("Hide app names in exports", isOn: $model.prefs.hideAppNamesInExports)
                Toggle("Show menu bar item", isOn: $model.prefs.showMenuBarItem)
                LabeledContent("Updates") { Button("Check for Updates…") { model.openReleases() } }
            } footer: {
                Text("The menu bar item only reopens this window. Closing the window quits Aftertaste unless it is on. Checking for updates opens the releases page in your browser.")
            }
            Section {
                ForEach(model.prefs.keepList, id: \.self) { item in
                    HStack {
                        Text(item).font(.system(.callout, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: Space.xs)
                        Button { model.prefs.keepList.removeAll { $0 == item } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("Stop keeping this")
                            .accessibilityLabel("Remove \(item)")
                    }
                }
                HStack {
                    TextField("Bundle ID or folder path", text: $entry).onSubmit(add)
                    Button("Add", action: add).disabled(entry.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let problem { Text(problem).font(.caption).foregroundStyle(.secondary) }
            } header: {
                Text("Never touch")
            } footer: {
                Text("Drop an app on this list, or type a bundle ID such as com.example.app or a folder path. What is listed is never offered or moved.")
            }
        }
        .formStyle(.grouped)
        .overlay { if targeted { DashedOutline(radius: Radius.chip).padding(Space.xs) } }
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in drop(providers) }
    }

    private var bar: some View {
        HStack {
            Spacer()
            Button("Done") { model.showPreferences = false }
                .buttonStyle(DuskButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(Space.m)
    }

    /// A bundle ID that passes Core's strict check, or an absolute path with no wildcard or `..`.
    private func add() {
        let text = entry.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let isPath = text.hasPrefix("/") && !text.contains("..") && !text.contains("*") && !text.contains("?")
        guard StrictBundleID.isValid(text) || isPath else {
            problem = "Enter a bundle ID like com.example.app, or a folder path that starts with /."
            return
        }
        keep(text)
        entry = ""
    }

    private func keep(_ text: String) {
        if !model.prefs.keepList.contains(text) { model.prefs.keepList.append(text) }
        problem = nil
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url = (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) } ?? (item as? URL)
            guard let path = url?.path else { return }
            Task { @MainActor in await keepApp(at: path) }
        }
        return true
    }

    /// The same checks as a dropped app on the welcome screen (it must be an app that can be a target).
    private func keepApp(at path: String) async {
        let found = await model.backend.identify(path)
        if let id = found.identity?.bundleID { keep(id) } else { problem = found.rejection ?? "That is not an app." }
    }
}
