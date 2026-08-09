// swift-tools-version: 6.2
import PackageDescription

// Command Line Tools-only environments ship Swift Testing outside SwiftPM's
// default search paths. These flags make it discoverable and linkable; with a
// full Xcode toolchain the paths are simply ignored.
let cltFrameworksPath = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let cltSwiftLibrariesPath = "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

let package = Package(
    name: "launchPad",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        .target(
            name: "launchPadCore",
            resources: [
                .copy("Resources/AppIcon.icns")
            ]
        ),
        .executableTarget(
            name: "launchPad",
            dependencies: ["launchPadCore"]
        ),
        .executableTarget(
            name: "launchPadTests",
            dependencies: ["launchPadCore"],
            path: "Tests/launchPadTests",
            swiftSettings: [
                .unsafeFlags(["-F", cltFrameworksPath])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", cltFrameworksPath,
                    "-Xlinker", "-rpath", "-Xlinker", cltFrameworksPath,
                    "-Xlinker", "-rpath", "-Xlinker", cltSwiftLibrariesPath
                ])
            ]
        )
    ]
)
