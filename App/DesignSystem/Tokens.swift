import AftertasteCore
import AppKit
import SwiftUI

// docs/DESIGN.md §6.1. Spacing, radii, motion curves, the brand colours and the model-to-look mappings. No view lives here.

/// Spacing in points. `xxl` is the screen padding, `l` the bottom bar's.
enum Space {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
}

/// Concentric radii (DESIGN §6.1): plates 18, tiles 14, rows 12, chips 8.
enum Radius {
    static let card: CGFloat = 12
    static let chip: CGFloat = 8
    static let row: CGFloat = 12
    static let tile: CGFloat = 14
    static let plate: CGFloat = 18
}

/// docs/MOTION.md §1.2, spelled for macOS 13: the duration-and-bounce springs are macOS 14, these are the same curves.
enum Motion {
    /// `.smooth` is macOS 14. Under Reduce Motion callers also drop movement and keep only the fade.
    static func standard(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.15) : .easeInOut(duration: 0.28)
    }
    /// Surfaces: flips, deal-ins, a tilt settling back, the outline.
    static func spring(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.15) : .spring(response: 0.45, dampingFraction: 0.78)
    }
    static let hero = Animation.spring(response: 0.9, dampingFraction: 0.8)
    static let pop = Animation.spring(response: 0.32, dampingFraction: 0.62)
    static let follow = Animation.interactiveSpring(response: 0.25, dampingFraction: 0.86)
    /// Stagger between rows leaving for the Trash and between cards flipping in (MOTION §3.1).
    static let stagger = 0.045
    /// The delay of the i-th row, capped at index 8 so a long list never trickles.
    static func delay(_ index: Int, _ reduceMotion: Bool) -> Double { reduceMotion ? 0 : Double(min(max(index, 0), 8)) * stagger }
}

/// docs/DESIGN.md §1, §6. Violet is the one accent ("left behind"); green only for Nothing found and a moved row's check;
/// red only on a failed row's symbol. Teal exists only inside `Dawn` and the card: it is sky, not UI.
enum Brand {
    /// Violet-black: the soft shadow under porcelain surfaces is tinted with it, never neutral grey (rule 3).
    static let ink = Color(red: 0.086, green: 0.071, blue: 0.157)                                     // #161228
    /// The dusk key-cap fill and every violet fill. Near-black text on it (8.1:1).
    static let dusk = Color(red: 0.663, green: 0.608, blue: 1.0)                                      // #A99BFF
    static let onDusk = Color(red: 0.059, green: 0.043, blue: 0.118)                                  // #0F0B1E
    /// Violet as text, a symbol or the outline: readable on paper and on the night desk (5.8:1 / 8.1:1).
    static let duskInk = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.718, green: 0.659, blue: 1.0, alpha: 1)                              // #B7A8FF
            : NSColor(srgbRed: 0.353, green: 0.267, blue: 0.769, alpha: 1)                            // #5A44C4
    })
    /// The horizon. Never on a control, a chip or text.
    static let horizon = Color(red: 0.498, green: 0.890, blue: 0.839)                                 // #7FE3D6
    static let skyTop = Color(red: 0.055, green: 0.043, blue: 0.122)                                  // #0E0B1F
    static let skyLow = Color(red: 0.086, green: 0.188, blue: 0.227)                                  // #16303A
    /// The card's fixed night colours (an object, the same in both schemes; DESIGN §6.6).
    static let cardBottom = Color(red: 0.078, green: 0.094, blue: 0.153)                              // #141827
    static let cardText = Color(red: 0.933, green: 0.941, blue: 0.969)                                // #EEF0F7
    static let cardSecondary = Color(red: 0.639, green: 0.659, blue: 0.729)                           // #A3A8BA
    static let cardAccent = Color(red: 0.718, green: 0.659, blue: 1.0)                                // #B7A8FF
}

extension Tier {
    /// The chip word is `displayName` (Model). Tier is carried by the word, never by colour alone (§1.1 rule 4):
    /// only High gets the violet dot, because it is the only tier a scan ticks.
    var tint: Color { self == .high ? Brand.dusk : .secondary }
}

extension ResidueKind {
    /// Neutral SF Symbols, never vendor logos (BUILD_PLAN §8). VERIFY each in the SF Symbols app: availability macOS 13 or earlier.
    var symbol: String {
        switch self {
        case .app: return "app"
        case .cache: return "square.stack.3d.up"
        case .settings: return "slider.horizontal.3"
        case .state: return "macwindow"
        case .logs: return "doc.text"
        case .cookies: return "globe"
        case .launchItem: return "play.square"
        case .yourData: return "folder"
        case .shared: return "square.on.square"
        case .system: return "lock"
        }
    }
}

extension TrashStatus {
    /// Result and History rows: a symbol in a status colour, the word beside it. Red only here, only on failed.
    var symbol: String {
        switch self {
        case .moved: return "checkmark.circle.fill"
        case .alreadyGone: return "minus.circle"
        case .changedSinceScan, .blocked, .protectedByMacOS, .locked, .dataless: return "hand.raised"
        case .failed: return "xmark.circle.fill"
        case .notAttempted: return "circle.dashed"
        }
    }

    var tint: Color {
        switch self {
        case .moved: return .green
        case .failed: return .red
        default: return .secondary
        }
    }

    var word: String {
        switch self {
        case .moved: return "Moved to Trash"
        case .alreadyGone: return "Already gone"
        case .changedSinceScan: return "Changed since the scan"
        case .blocked: return "Left alone"
        case .protectedByMacOS: return "Protected by macOS"
        case .locked: return "Locked"
        case .dataless: return "Not downloaded"
        case .failed: return "Failed"
        case .notAttempted: return "Not attempted"
        }
    }
}

extension ReadinessText.Tone {
    /// Readiness lines: a dot beside the title. `attention` is violet, not red: the panel informs, it never alarms.
    var tint: Color {
        switch self {
        case .ok: return .green
        case .info: return .secondary
        case .attention: return Brand.dusk
        }
    }
}

extension HistoryState {
    /// History item rows (DESIGN §6.5): restored, still in the Trash, emptied.
    var symbol: String {
        switch self {
        case .restored: return "arrow.uturn.backward.circle"
        case .inTrash: return "trash"
        case .emptied: return "minus.circle"
        }
    }
}
