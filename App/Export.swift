import AppKit
import AftertasteCore
import SwiftUI
import UniformTypeIdentifiers

/// What the Trace Report sheet, the Result screen's "Copy card" and `AppModel.exportReport(format:)` ask for.
enum ExportFormat: Hashable {
    case markdown, json, png, copyCard
}

/// The only code in App/ that writes a file, and only where the user picks in the save panel (BUILD_PLAN §3.1 checks 2b, 8g).
/// It is also one of the two files allowed to touch the pasteboard. The DEBUG demo's `-demoCardOut` goes through `writePNG`.
@MainActor enum Export {
    /// Everything exported is made from the report as the user last saw it: names already hidden if they ticked the box.
    /// False when the card could not be drawn: for `.copyCard` the text version was copied instead; for `.png` nothing was saved.
    @discardableResult static func run(_ format: ExportFormat, report: TraceReport) -> Bool {
        let card = TraceReportText.card(from: report)
        switch format {
        case .copyCard: return copyImage(card)
        case .png:
            guard let data = pngData(card) else {
                NSSound.beep()
                return false
            }
            save(data, as: .png, name: "Aftertaste Trace Report.png")
        case .markdown: save(Data(TraceReportText.markdown(report).utf8), as: UTType(filenameExtension: "md") ?? .plainText, name: "Aftertaste Trace Report.md")
        case .json: save(Data(TraceReportText.json(report).utf8), as: .json, name: "Aftertaste Trace Report.json")
        }
        return true
    }

    /// The card at 2x: 1200x630 px, drawn by the same view as the on-screen preview (flat, fixed colours).
    /// VERIFY on macOS 13 and 26 that `ImageRenderer` really returns 1200x630 (BUILD_PLAN §12).
    private static func render(_ card: ShareCard) -> NSBitmapImageRep? {
        let renderer = ImageRenderer(content: TraceCardView(card: card))
        renderer.scale = 2
        return renderer.cgImage.map { NSBitmapImageRep(cgImage: $0) }
    }

    static func pngData(_ card: ShareCard) -> Data? {
        render(card)?.representation(using: .png, properties: [:])
    }

    /// Puts the card on the pasteboard as an image (PNG and TIFF, so every paste target finds one). If rendering fails the
    /// text version is copied instead and this returns false.
    @discardableResult static func copyImage(_ card: ShareCard) -> Bool {
        let pasteboard = NSPasteboard.general
        guard let rep = render(card), let png = rep.representation(using: .png, properties: [:]) else {
            copyToPasteboard(TraceReportText.plainText(card, footer: TraceCardView.address))
            NSSound.beep()
            return false
        }
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        pasteboard.setData(rep.tiffRepresentation, forType: .tiff)
        return true
    }

    /// For the DEBUG demo (`-demoCardOut <png path>`): no panel; false if it could not render or write.
    static func writePNG(_ card: ShareCard, to url: URL) -> Bool {
        guard let data = pngData(card) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// A sheet on the key window when there is one (the Trace Report is itself a sheet), a standalone panel otherwise.
    private static func save(_ data: Data, as type: UTType, name: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = name
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: finish) } else { panel.begin(completionHandler: finish) }
    }
}

/// Plain text to the pasteboard (Copy Path, Copy Diagnostics, the card's text fallback). Here rather than in the design system
/// because the pasteboard is allowed only in AppModel.swift and Export.swift (safety_greps.sh check 8g).
@MainActor func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

/// "Copy as image" for the Trace Report card. The label says "Copied as text" when the card could not be drawn and the text
/// version went on the pasteboard instead.
struct CopyCardButton: View {
    let title: String
    let report: () -> TraceReport?
    @State private var done: String?

    var body: some View {
        Button(done ?? title) {
            guard let report = report() else { return NSSound.beep() }
            done = Export.run(.copyCard, report: report) ? "Copied" : "Copied as text"
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                done = nil
            }
        }
    }
}
