import AftertasteCore
import SwiftUI

/// Erase readiness (docs/DESIGN.md §6.5): FileVault, the kind of storage, local snapshots, who could read old data, and what
/// this app cannot reach, in the fixed sentences of `ReadinessText`. Read-only: three system commands, nothing changed, no
/// switch, no number bigger than a row's. A fact that could not be read says so; nothing here is a guess and nothing
/// promises an outcome. Written, not compiled.
struct ReadinessView: View {
    @EnvironmentObject private var model: AppModel

    /// Shown as parts of their own below the rows, not as rows.
    private static let apart: Set<String> = ["notReachable", "needToBeSure"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                header
                if let facts = model.readiness {
                    content(ReadinessText.lines(facts), facts: facts)
                } else {
                    HStack(spacing: Space.s) {
                        ProgressView().controlSize(.small)
                        Text("Checking this Mac…").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Dawn())
        // Three read-only commands, run when the panel opens (unless the model already holds fresh facts) and again on
        // "Check Again"; nothing is read before.
        .task { if model.readiness == nil { await model.loadReadiness() } }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("Erase readiness").font(.system(size: 28, weight: .semibold)).tracking(-0.5)
                Text("Read-only. Three system commands, no changes.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.s)
            if model.isDemo { Tag(text: TraceReportText.sampleWatermark, tint: .secondary) }
            Button("Check Again") { Task { await model.loadReadiness() } }
                .buttonStyle(.bordered)
                .disabled(model.readiness == nil)
        }
    }

    private func content(_ lines: [ReadinessText.Line], facts: ReadinessFacts) -> some View {
        let rows = lines.filter { !Self.apart.contains($0.id) }
        let sure = lines.first { $0.id == "needToBeSure" }
        return VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, line in
                    if index > 0 { Divider().opacity(0.5) }
                    ReadinessRow(line: line)
                }
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(16)
            if !facts.failedProbes.isEmpty {
                Text("These checks did not finish: \(facts.failedProbes.joined(separator: ", ")). Their lines above say they could not be read.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Who could read old data").font(.system(size: 15, weight: .semibold))
                ForEach(Array(ReadinessText.threats().enumerated()), id: \.offset) { index, threat in
                    if index > 0 { Divider().opacity(0.5) }
                    HStack(alignment: .top, spacing: Space.m) {
                        Text(threat.who).font(.system(size: 13, weight: .semibold))
                            .frame(width: 200, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(threat.answer).font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(16)
            Text(ReadinessText.notReachable).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let sure {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(sure.title).font(.system(size: 13, weight: .semibold))
                    Text(sure.body).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button { model.openEraseGuide() } label: {
                        HStack(spacing: 4) {
                            Text("How to Erase This Mac")
                            Image(systemName: "arrow.up.right").imageScale(.small).accessibilityHidden(true)
                        }
                    }
                        .buttonStyle(.bordered)
                        .help("Opens Apple's page about Erase All Content and Settings in your browser")
                }
            }
        }
    }
}

/// A dot in the line's tone, the title, the sentence. A line that says "could not be read" is set exactly like the others.
private struct ReadinessRow: View {
    let line: ReadinessText.Line

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Circle().fill(line.tone.tint).frame(width: 6, height: 6).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title).font(.system(size: 13, weight: .semibold))
                Text(line.body).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
