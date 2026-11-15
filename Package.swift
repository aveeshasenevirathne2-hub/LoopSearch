// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CircleToSearch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CircleToSearch", targets: ["CircleToSearch"])
    ],
    targets: [
        .executableTarget(
            name: "CircleToSearch",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AuthenticationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CryptoKit"),
                .linkedFramework("Network"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Security"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("Vision"),
                .linkedFramework("WebKit")
            ]
        )
    ]
)
