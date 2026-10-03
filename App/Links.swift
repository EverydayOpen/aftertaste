import Foundation

/// The website (GitHub Pages), the repository and two Apple pages. tools/doctor.sh checks `website` matches
/// site/site.json's baseURL. Opened only by `AppModel`, and only on a click (no network of our own).
enum Links {
    static let website = URL(string: "https://everydayopen.github.io/aftertaste")!
    static let releases = URL(string: "https://github.com/EverydayOpen/aftertaste/releases")!
    static let issues = URL(string: "https://github.com/EverydayOpen/aftertaste/issues")!
    static let eraseAllContent = URL(string: "https://support.apple.com/guide/mac-help/erase-your-mac-mchl7676b710/mac")!   // VERIFY the page
    static let fullDiskAccess = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"    // VERIFY on 15/26; text steps always beside it
}
