// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YaseenScreenshot",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "YaseenScreenshot", targets: ["YaseenScreenshot"]),
    ],
    targets: [
        // All the code lives in the library, so the tests can import it.
        .target(name: "ScreenshotKit"),
        .executableTarget(name: "YaseenScreenshot", dependencies: ["ScreenshotKit"]),
        .testTarget(name: "ScreenshotKitTests", dependencies: ["ScreenshotKit"]),
    ],
    // Swift 5 mode: Apple's capture types are not Sendable, and CI uses an older compiler.
    swiftLanguageModes: [.v5]
)
