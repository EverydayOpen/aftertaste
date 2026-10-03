// swift-tools-version:6.0
import PackageDescription

// AftertasteCore is Foundation-only (builds and tests on Linux and Windows-Docker too).
// AftertasteMac holds AppKit/Security/Darwin, so it only exists on macOS. AftertasteFixture is the tiny sleeping
// executable the Mac tests copy into a fake .app bundle and run, to prove the running-app guard.
var products: [Product] = [.library(name: "AftertasteCore", targets: ["AftertasteCore"])]
var targets: [Target] = [
    .target(name: "AftertasteCore"),
    // Fixtures are read from disk via #filePath, not bundled (keeps Linux builds warning-free).
    .testTarget(name: "AftertasteCoreTests", dependencies: ["AftertasteCore"], exclude: ["Fixtures"]),
]

#if os(macOS)
products.append(.library(name: "AftertasteMac", targets: ["AftertasteMac"]))
targets += [
    .target(name: "AftertasteMac", dependencies: ["AftertasteCore"]),
    .executableTarget(name: "AftertasteFixture"),
    .testTarget(name: "AftertasteMacTests", dependencies: ["AftertasteMac", "AftertasteCore"]),
]
#endif

let package = Package(
    name: "Aftertaste",
    // macOS 13: ImageRenderer, NavigationSplitView and NSWorkspace.urlsForApplications(withBundleIdentifier:) need it (BUILD_PLAN §1).
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets,
    // ponytail: Swift 5 mode keeps strict-concurrency diagnostics as warnings while the Mac code is unverified
    // on real hardware; move to .v6 once CI is green and warnings are cleaned up.
    swiftLanguageModes: [.v5]
)
