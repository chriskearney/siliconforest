// swift-tools-version:6.0
import PackageDescription
import Foundation

// Command Line Tools ship Swift Testing outside the default framework search path; Xcode doesn't
// need this. Only added when that directory exists.
let cltFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let hasCLTTesting = FileManager.default.fileExists(atPath: cltFrameworks + "/Testing.framework")
let testSwiftSettings: [SwiftSetting] = hasCLTTesting ? [.unsafeFlags(["-F", cltFrameworks])] : []
let testLinkerSettings: [LinkerSetting] = hasCLTTesting
    ? [.unsafeFlags(["-F", cltFrameworks, "-framework", "Testing", "-Xlinker", "-rpath", "-Xlinker", cltFrameworks,
                     "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"])]
    : []

// SiliconForest macOS installer (CHL-27).
//
// Safety: real-disk writes are compiled out. `SF_REAL_DISK_WRITES` is never defined here, and even
// with it the only executor in this phase refuses every mutating operation (see RealDiskBackend).
let package = Package(
    name: "SiliconForestInstaller",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SFInstallKit", targets: ["SFInstallKit"]),
        .executable(name: "SFInstaller", targets: ["SFInstaller"]),
        .executable(name: "sfinstallctl", targets: ["sfinstallctl"]),
    ],
    targets: [
        .target(name: "SFInstallKit"),
        .executableTarget(
            name: "SFInstaller",
            dependencies: ["SFInstallKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "sfinstallctl",
            dependencies: ["SFInstallKit"]
        ),
        // Same tests as an executable, for Command Line Tools-only Macs (see scripts/test.sh).
        .executableTarget(
            name: "sfinstallkit-selftest",
            dependencies: ["SFInstallKit"],
            path: "Tests/CLTRunner",
            swiftSettings: testSwiftSettings,
            linkerSettings: testLinkerSettings
        ),
        .testTarget(
            name: "SFInstallKitTests",
            dependencies: ["SFInstallKit"],
            swiftSettings: testSwiftSettings,
            linkerSettings: testLinkerSettings
        ),
    ]
)
