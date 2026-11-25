// swift-tools-version:6.0
import PackageDescription
import Foundation

// SiliconForest Installer for macOS (CHL-27). Module map follows docs/installer/DESIGN.md §4:
//   SFInstallKit  engine: profiles, disk model + classification, sizing, plan, journal, runner, backends
//   SFCopy        every user-facing string, in one reviewed place
//   SFDesign      tokens, The Grove background, disk bar, components
//   SFFlow        the screen state machine (one observable session)
//   SFInstaller   the app: AppKit shell, screens, snapshot renderer
//   SFEngine      the acting half: chokepoint, gate, journal, step machine, resize supervisor, image backend
//   SFLiveDisk    LiveDiskBackend: protection receipt, target authority, release checks (real disk only behind the two-key gate)
//   SFHelperKit   the helper's verb-only XPC protocol and service; SFHelper is its launchd executable
//   SFRecovery    recoveryOS app (AppKit only) over SFRecoveryKit (gate, steps, PTY driver)
//   SFStub        restore-image range reader, zip, stub builder (port of Asahi v0.9.2, MIT); sfstubctl drives it on images
//
// Safety: real-disk writes are compiled out. `SF_REAL_DISK_WRITES` is never defined here. Without it the
// only disk SFLiveDisk can write to is an attached disk image; with it, the internal disk still needs a
// root-owned, plan- and disk-bound runtime authorization (RealDiskGate) and the protection receipt.
// `RefusingExecutor` stays the default executor everywhere else.

// Command Line Tools ship Swift Testing outside the default framework search path; Xcode doesn't
// need this. Only added when that directory exists.
let cltFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let hasCLTTesting = FileManager.default.fileExists(atPath: cltFrameworks + "/Testing.framework")
let testSwiftSettings: [SwiftSetting] = hasCLTTesting ? [.unsafeFlags(["-F", cltFrameworks])] : []
let testLinkerSettings: [LinkerSetting] = hasCLTTesting
    ? [.unsafeFlags(["-F", cltFrameworks, "-framework", "Testing", "-Xlinker", "-rpath", "-Xlinker", cltFrameworks,
                     "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"])]
    : []
let ui: [SwiftSetting] = [.swiftLanguageMode(.v5)]

// Prefer a version-stamped helper Info.plist written by scripts/make-app.sh before the release build.
let helperInfoPlist = FileManager.default.fileExists(atPath: "build/SFHelper-Info.plist")
    ? "build/SFHelper-Info.plist"
    : "Support/SFHelper-Info.plist"

let package = Package(
    name: "SiliconForestInstaller",
    platforms: [.macOS(.v13)],   // D10: deployment target 13.5 (LSMinimumSystemVersion in the app)
    products: [
        .library(name: "SFInstallKit", targets: ["SFInstallKit"]),
        .executable(name: "SFInstaller", targets: ["SFInstaller"]),
        .executable(name: "sfinstallctl", targets: ["sfinstallctl"]),
    ],
    targets: [
        // The one place the Developer ID team and the frozen identifiers live (app, helper, recovery).
        .target(name: "SFIdentity"),
        .target(name: "SFInstallKit", dependencies: ["SFIdentity"]),
        // The acting half (DESIGN §4): typed verbs, gate, hash-chained journal, step machine, resize
        // supervisor, and the DiskImageBackend whose every write passes the image-only chokepoint.
        .target(name: "SFEngine", dependencies: ["SFInstallKit", "SFStub"]),
        .target(name: "SFCopy", dependencies: ["SFInstallKit"], swiftSettings: ui),
        .target(name: "SFDesign", dependencies: ["SFInstallKit", "SFCopy"], swiftSettings: ui),
        .target(name: "SFFlow", dependencies: ["SFInstallKit", "SFCopy", "SFDesign"], swiftSettings: ui),
        .executableTarget(name: "SFInstaller", dependencies: ["SFInstallKit", "SFCopy", "SFDesign", "SFFlow"], swiftSettings: ui),
        // The live disk backend (ENGINE §12): protection receipt, target authority, pre-write release checks and the
        // two-key real-disk gate. Without `SF_REAL_DISK_WRITES` its only target is a disk image.
        .target(name: "SFLiveDisk", dependencies: ["SFInstallKit", "SFEngine"]),
        // The helper's verb-only NSXPC protocol, service, trust checks, lifecycle and bundle layout.
        .target(name: "SFHelperKit", dependencies: ["SFIdentity", "SFInstallKit", "SFEngine", "SFLiveDisk"]),
        .executableTarget(name: "SFHelper", dependencies: ["SFHelperKit", "SFEngine", "SFInstallKit", "SFIdentity"],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                                                         "-Xlinker", helperInfoPlist])]),
        // recoveryOS (DESIGN §7): Foundation-only core (gate, steps, PTY driver) and the AppKit app.
        // scripts/check-recovery-links.sh fails the build if SFRecovery links anything §7.3 forbids.
        .target(name: "SFRecoveryKit", swiftSettings: ui),
        .executableTarget(name: "SFRecovery", dependencies: ["SFRecoveryKit"], swiftSettings: ui),
        .executableTarget(name: "sfinstallctl", dependencies: ["SFInstallKit", "SFCopy", "SFEngine"]),
        // The stub builder (DESIGN §6.4, ENGINE §10): Foundation + Compression only, no dependency on the engine (the engine runs it at S10/S32/S35/S55/S60).
        .target(name: "SFStub"),
        .executableTarget(name: "sfstubctl", dependencies: ["SFStub", "SFEngine"]),
        // Same tests as an executable, for Command Line Tools-only Macs (see scripts/test.sh).
        .executableTarget(name: "sfinstallkit-selftest", dependencies: ["SFInstallKit", "SFEngine", "SFLiveDisk", "SFHelperKit", "SFRecoveryKit", "SFStub"], path: "Tests/CLTRunner",
                          swiftSettings: testSwiftSettings, linkerSettings: testLinkerSettings),
        .testTarget(name: "SFInstallKitTests", dependencies: ["SFInstallKit", "SFEngine", "SFLiveDisk", "SFHelperKit", "SFRecoveryKit", "SFStub"],
                    swiftSettings: testSwiftSettings, linkerSettings: testLinkerSettings),
    ]
)
