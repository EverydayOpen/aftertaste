import SwiftUI

/// An app's own icon (from its bundle path, via `AppModel.icon(forApp:)`, the one place that asks the system), or a
/// neutral dashed-app symbol when there is no bundle: an orphan's owner, a path that is gone, sample data. Never a vendor
/// logo shipped by us. Decorative: the name beside it says it.
struct AppIconView: View {
    let path: String
    var size: CGFloat = 24
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let image = model.icon(forApp: path) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                // VERIFY app.dashed exists on macOS 13 (SF Symbols 4); `app` is the fallback.
                Image(systemName: "app.dashed").font(.system(size: size * 0.7, weight: .light)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
