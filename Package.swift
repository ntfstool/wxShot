// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "wxShot",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "wxShot", targets: ["wxShot"])
    ],
    targets: [
        .target(
            name: "SystemSettingsKit",
            path: "ThirdParty/PermissionFlow/Sources/SystemSettingsKit"
        ),
        .target(
            name: "PermissionFlow",
            dependencies: ["SystemSettingsKit"],
            path: "ThirdParty/PermissionFlow/Sources/PermissionFlow",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "wxShot",
            dependencies: [
                "PermissionFlow"
            ],
            path: "Sources/wxShot",
            exclude: ["App/Info.plist"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Vision"),
                .linkedFramework("VisionKit"),
                .linkedFramework("CoreImage"),
                .linkedFramework("ImageIO"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("Carbon"),
                .linkedFramework("VideoToolbox"),
                .linkedLibrary("z"),
            ]
        ),
        .testTarget(name: "wxShotTests", dependencies: ["wxShot"], path: "Tests/wxShotTests"),
    ]
)
