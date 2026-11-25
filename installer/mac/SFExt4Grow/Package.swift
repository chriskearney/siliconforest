// swift-tools-version:5.9
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
import PackageDescription

// SFExt4Grow: the installer's offline ext4 root grower (S48), clean-room Swift, no GPL code.
//   SFExt4              library: on-disk format, preflight checks, the grow planner, the ordered
//                       executor with its undo log, and the macOS target guard (hdiutil + DiskArbitration)
//   sf-ext4grow         command-line tool over the library (inspect, plan, grow, undo)
//   sfext4grow-selftest framework-free unit checks (Command Line Tools Macs have no XCTest)
// Images and plain files only: TargetGuard refuses any device that `hdiutil info` does not list as an
// attached disk image. There is no real-disk path in this package; the helper's gate is untouched.
let package = Package(
    name: "SFExt4Grow",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SFExt4", targets: ["SFExt4"]),
        .executable(name: "sf-ext4grow", targets: ["sf-ext4grow"]),
    ],
    targets: [
        .target(name: "SFExt4", linkerSettings: [.linkedFramework("DiskArbitration")]),
        .executableTarget(name: "sf-ext4grow", dependencies: ["SFExt4"]),
        .executableTarget(name: "sfext4grow-selftest", dependencies: ["SFExt4"]),
    ]
)
