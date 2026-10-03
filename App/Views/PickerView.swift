import AftertasteCore
import SwiftUI
import UniformTypeIdentifiers

/// The empty state and the way in (BUILD_PLAN §7.1 screen 1, DESIGN §6.5 "Welcome"). Over the afterglow: the drop zone is
/// the one lifted object, then "Find leftovers of apps that are gone" and "Erase readiness" as key-caps, and the list of
/// installed apps to pick from. Reads names and sizes only, and only once a scan starts; asks for no permission.
struct PickerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var targeted = false
    @State private var risen = false

    var body: some View {
        let _ = Self._printChanges()
        ZStack {
            Dawn()
            HStack(alignment: .top, spacing: Space.xl) {
                VStack(spacing: Space.m) {
                    dropZone
                    Text("Aftertaste reads names and sizes in your Library, plus the small property lists that name an app. It asks for no permission.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Space.s) {
                        Button { Task { await model.findOrphans() } } label: {
                            keyLabel("magnifyingglass", "Find leftovers", "of apps that are gone")
                        }
                        Button { model.show(.readiness) } label: {
                            keyLabel("lock.shield", "Erase readiness", "FileVault, disk, snapshots")
                        }
                    }
                    .buttonStyle(KeyCapStyle())
                    .disabled(model.isBusy)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minWidth: 320, idealWidth: 440, maxWidth: 460)
                installedList
                    .frame(minWidth: 260, maxWidth: .infinity)
            }
            .padding(Space.xxl)
        }
        .onAppear {
            // The tile rises 16pt and fades in once (MOTION §3.4); Reduce Motion gets a 150 ms fade.
            guard !risen else { return }
            if reduceMotion {
                withAnimation(Motion.standard(true)) { risen = true }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { withAnimation(Motion.hero) { risen = true } }
            }
        }
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        VStack(spacing: Space.s) {
            OnFloor(height: 96) {
                Image(systemName: "app.dashed")   // VERIFY app.dashed on macOS 13
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Brand.duskInk)
                    .well(Brand.dusk, size: 96)
            }
            .offset(y: risen || reduceMotion ? 0 : 16)
            .opacity(risen ? 1 : 0)
            Text(targeted ? "Release to look" : "Drop an app here")
                .font(.system(size: 22, weight: .semibold))
            HStack(spacing: Space.xs) {
                Text("or").foregroundStyle(.secondary)
                Button("Choose an app…") { Task { await model.chooseApp() } }
                    .buttonStyle(.bordered)
                    .disabled(model.isBusy)
            }
            if let message = model.dropMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity)
        // The dashed violet outline inside the surface: where the app will stand. Stronger while a file is over it.
        .overlay { DashedOutline(radius: Radius.tile, opacity: targeted ? 1 : 0.55).padding(Space.s) }
        .surface(Radius.plate)
        .modifier(HoverTilt(max: 6, glare: true))
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in drop(providers) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drop an app here")
    }

    /// Finder hands over file URLs. One app at a time; `AppModel.handleDrop` validates it (not an app, Apple's, ours, nested).
    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty, !model.isBusy else { return false }
        let model = self.model
        guard providers.count == 1 else {
            Task { @MainActor in model.dropMessage = "Drop one app at a time." }
            return true
        }
        providers[0].loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url = (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) } ?? (item as? URL)
            Task { @MainActor in await model.handleDrop(url.map { [$0] } ?? []) }
        }
        return true
    }

    // MARK: - Key-caps

    private func keyLabel(_ symbol: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Brand.duskInk)
                .well(Brand.dusk, size: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Installed list

    private var matches: [AppIdentity] {
        let all = model.pickable
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { $0.displayName.localizedCaseInsensitiveContains(q) || $0.bundleID.localizedCaseInsensitiveContains(q) }
    }

    private var installedList: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.plate, style: .continuous)
        return VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text("Installed").font(.caption.weight(.semibold).smallCaps()).foregroundStyle(.secondary)   // VERIFY small caps with SF
                Spacer()
                if model.installed != nil { Text("\(model.pickable.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            }
            .accessibilityElement(children: .combine)
            TextField("Search apps", text: $query)
                .textFieldStyle(.roundedBorder)
                .disabled(model.installed == nil)
            Group {
                if model.installed == nil {
                    placeholder(model.prefs.hasSeenFirstRun ? "Reading your Applications folders…" : "Your apps are listed after you continue.",
                                busy: model.prefs.hasSeenFirstRun)
                } else if model.pickable.isEmpty {
                    placeholder("No apps found in the usual folders.", busy: false)
                } else if matches.isEmpty {
                    placeholder("No installed app matches \"\(query)\".", busy: false)
                } else {
                    List(matches, id: \.bundlePath) { app in row(app) }
                        .listStyle(.inset)
                        .scrollContentBackground(.hidden)
                        .clipShape(shape)
                        .surface(Radius.plate)
                }
            }
            .frame(maxHeight: .infinity)
            if let snapshot = model.installed, !snapshot.unreadableLocations.isEmpty {
                Text("Some app folders could not be read, so this list may be missing apps.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func placeholder(_ text: String, busy: Bool) -> some View {
        VStack(spacing: Space.xs) {
            if busy { ProgressView().controlSize(.small) }
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Space.m)
        .surface(Radius.plate)
    }

    private func row(_ app: AppIdentity) -> some View {
        Button { Task { await model.choose(app) } } label: {
            HStack(spacing: Space.s) {
                AppIconView(path: app.bundlePath, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.displayName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if let detail = detail(app) { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
        .help(app.bundleID)
        .accessibilityLabel(app.displayName)
        .accessibilityValue(detail(app) ?? "")
        .accessibilityHint("Shows what Aftertaste would move to the Trash")
    }

    /// "Version 6.2 · Mac App Store"; an app only an administrator can move says so up front.
    private func detail(_ app: AppIdentity) -> String? {
        var parts: [String] = []
        if let version = app.version, !version.isEmpty { parts.append("Version \(version)") }
        switch app.installSource {
        case .appStore: parts.append("Mac App Store")
        case .brew: parts.append("Homebrew")
        case .setapp: parts.append("Setapp")
        case .pkg: parts.append("Installer")
        case .manual, .unknown: break
        }
        if app.bundleNeedsAdmin { parts.append("Needs your administrator") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
