import AppKit
import AftertasteCore
import SwiftUI

/// The Trace Report sheet (BUILD_PLAN §7.1 screen 7, docs/DESIGN.md §6.5): the 1200x630 card preview, "Hide app names", and
/// Copy / Save PNG / Markdown / JSON. Reached from Preview ("Export report") and Result. `scan` is the scan the user is looking
/// at; the caller passes the one from before any move, because the card is the "before" screen.
struct TraceReportView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let scan: ScanResult
    /// nil until the user touches the toggle: then the model's default (pre-ticked for several apps or by Preferences, since an
    /// installed-app list is sensitive). Not set in `onAppear`, so the first frame already has the right names.
    @State private var hideChoice: Bool?

    private var hide: Bool { hideChoice ?? model.hideNamesDefault }

    /// Rebuilt when the toggle changes, so the preview, the PNG, the Markdown and the JSON always agree.
    private var report: TraceReport {
        TraceReportText.report(from: scan, options: .init(hideNames: hide, includeRows: true, appVersion: model.appVersion, isSample: model.isDemo),
                               now: scan.scannedAt)
    }

    var body: some View {
        let report = self.report
        VStack(spacing: Space.m) {
            VStack(spacing: Space.xxs) {
                Text("Trace Report").font(.system(size: 22, weight: .semibold))
                Text("A list of what was found in the places listed. Every number was measured on this Mac during this scan.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TraceCardView(card: TraceReportText.card(from: report))
                .modifier(HoverTilt(max: 4, glare: true))
                .lifted()
                .padding(.vertical, Space.xs)
            Toggle("Hide app names", isOn: Binding(get: { hide }, set: { hideChoice = $0 }))
                .help("Replaces app names and bundle IDs with App 1, App 2 in the card and in every file you save.")
            bar
        }
        .padding(Space.xxl)
        .frame(width: 600 + 2 * Space.xxl)
        .background(Dawn())
    }

    private var bar: some View {
        HStack(spacing: Space.xs) {
            CopyCardButton(title: "Copy as image") { report }
            .buttonStyle(DuskButtonStyle())
            .keyboardShortcut(.defaultAction)
            .help("Copies the card as a PNG image")
            Button("Save PNG…") { Export.run(.png, report: report) }.help("Saves the card as a 1200 by 630 pixel PNG")
            Button("Save Markdown…") { Export.run(.markdown, report: report) }.help("Saves every item with its reason, and what is not covered")
            Button("Save JSON…") { Export.run(.json, report: report) }.help("Saves the same report as data")
            Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.xs)
        .barSurface()
    }
}

/// The share card as a 600x315pt view: 1200x630 px at 2x. The on-screen preview and the exported PNG are this same view
/// (`Export` renders it). An object, not a screen: the night sky in every scheme, front-facing and flat, pure fills only (no
/// material, blur, shadow or AppKit control), so every saved PNG looks the same (docs/DESIGN.md §6.6). Content comes only from
/// `ShareCard`: measured numbers, no paths, no claims about recovery or erasure, no line with a zero count.
struct TraceCardView: View {
    static let size = CGSize(width: 600, height: 315)
    /// The site address without the scheme, e.g. "everydayopen.github.io/aftertaste" (Core has no URL).
    static let address = Links.website.absoluteString.replacingOccurrences(of: "https://", with: "")

    let card: ShareCard
    /// On-screen width. The art is always drawn at 600pt and scaled, so the PNG never depends on this.
    var width = TraceCardView.size.width

    /// Fixed, not the design system's adaptive colours: the card looks the same in light and dark.
    private enum Palette {
        static let skyTop = Color(red: 0.055, green: 0.043, blue: 0.122)        // #0E0B1F
        static let skyBottom = Color(red: 0.078, green: 0.094, blue: 0.153)     // #141827
        static let horizon = Color(red: 0.498, green: 0.890, blue: 0.839)       // #7FE3D6
        static let text = Color(red: 0.933, green: 0.941, blue: 0.969)          // #EEF0F7
        static let muted = Color(red: 0.639, green: 0.659, blue: 0.729)         // #A3A8BA
        static let violet = Color(red: 0.718, green: 0.659, blue: 1.0)          // #B7A8FF
    }
    private static let inset: CGFloat = 36
    /// The horizon line: 82% down the card.
    private static let horizonY: CGFloat = 258

    var body: some View {
        let scale = width / Self.size.width
        art
            .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
            .background { backdrop }
            .clipped()
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: width, height: Self.size.height * scale, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }

    private var label: String {
        var parts = ["Trace Report card.", TraceReportText.headline(card) + ".", TraceReportText.figures(card) + ".", TraceReportText.coverage(card)]
        if let note = TraceReportText.listedNote(card) { parts.append(note) }
        if card.isSample { parts.append(TraceReportText.sampleWatermark + ".") }
        return parts.joined(separator: " ")
    }

    /// The sky, the horizon and the faint pool under it. Offsets only, so nothing here takes part in the layout.
    private var backdrop: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Palette.skyTop, Palette.skyBottom], startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [Palette.horizon.opacity(0.16), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 40)
                .offset(y: Self.horizonY + 1)
            Palette.horizon.opacity(0.7)
                .frame(height: 1)
                .offset(y: Self.horizonY)
        }
    }

    private var art: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
            Spacer(minLength: 6)
            hero
            Spacer(minLength: 4)
            footer
        }
        .padding(.horizontal, Self.inset)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    // MARK: - Top row

    /// The mark and wordmark on the left, the "Sample data" watermark on the right.
    private var topRow: some View {
        HStack(spacing: 8) {
            Mark()
            Text("AFTERTASTE").font(.system(size: 12, weight: .semibold)).tracking(2.2).foregroundColor(Palette.muted)
            Spacer(minLength: 12)
            if card.isSample {
                HStack(spacing: 6) {
                    Circle().fill(Palette.violet).frame(width: 7, height: 7)
                    Text(TraceReportText.sampleWatermark).font(.system(size: 13, weight: .semibold)).tracking(0.3).foregroundColor(Palette.violet)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(Palette.violet.opacity(0.16)))
                .overlay(Capsule().strokeBorder(Palette.violet.opacity(0.55), lineWidth: 1))
            }
        }
        .lineLimit(1)
        .frame(height: 24)
    }

    /// The app's outline with a tile lifted out of it: the product's mark, drawn (no image, so it renders the same everywhere).
    private struct Mark: View {
        var body: some View {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Palette.violet, style: StrokeStyle(lineWidth: 1.4, dash: [3, 2.5]))
                    .frame(width: 17, height: 17)
                    .offset(x: 0, y: 5)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Palette.violet)
                    .frame(width: 11, height: 11)
                    .offset(x: 9, y: 0)
            }
            .frame(width: 22, height: 22, alignment: .topLeading)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Hero

    /// "Orbit Meet 6.2 left behind" with the app name in violet, the figures, then where it looked. Shrinks (never clips) for
    /// a long name: a smaller size past 20 characters, then at most two lines.
    private var hero: some View {
        let line = TraceReportText.headline(card)
        let figures = TraceReportText.figures(card), coverage = TraceReportText.coverage(card), note = TraceReportText.listedNote(card)
        return VStack(alignment: .leading, spacing: 12) {
            headline(line)
                .font(.system(size: line.count > 20 ? 36 : 44, weight: .semibold))
                .tracking(-0.8)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            Text(figures)
                .font(.system(size: Self.fit(figures.count, [(44, 22), (75, 18)], smallest: 15), weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(Palette.text.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(coverage)
                if let note { Text(note) }
            }
            .font(.system(size: Self.fit(coverage.count + (note?.count ?? 0), [(120, 17), (190, 14), (280, 12)], smallest: 11)))
            .foregroundColor(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The card is a fixed 600x315 and its caveats (the "at least" floor, what was not measured, what could not be read) must all
    /// show, so longer text is set smaller and wraps; it is never cut. `steps` are (longest text, size) pairs.
    private static func fit(_ length: Int, _ steps: [(upTo: Int, size: CGFloat)], smallest: CGFloat) -> CGFloat {
        steps.first { length <= $0.upTo }?.size ?? smallest
    }

    /// The subject (the app name, or "3 removed apps") in violet, the rest in the card's text colour.
    private func headline(_ line: String) -> Text {
        var out = AttributedString(line)
        if let r = out.range(of: card.subject) { out[r].foregroundColor = Palette.violet }   // VERIFY on macOS 13: colour runs inside ImageRenderer
        return Text(out).foregroundColor(Palette.text)
    }

    // MARK: - Footer

    /// Provenance on one line, the address under it, both below the horizon.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(TraceReportText.provenance(card)).font(.system(size: 11, design: .monospaced))
            Text(Self.address).font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(Palette.muted)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}
