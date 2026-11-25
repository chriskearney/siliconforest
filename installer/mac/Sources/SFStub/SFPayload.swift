// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// The SiliconForest payload of the boot stub (DESIGN section 7.1, PAYLOAD section 9): what goes where
// Asahi v0.9.2's "Finish Installation.app", step2.sh, logo and boot object went. Our own code. The
// structure around it is SFStub's port (StubPlan.swift) and does not change with the payload.
//
//   System volume:
//     .VolumeIcon.icns
//     .IAPhysicalMedia                                 AppName = SiliconForest Setup.app
//     SiliconForest Setup.app/Contents/Info.plist
//                                     /MacOS/sf-launcher, /MacOS/SFRecovery
//                                     /Resources/sf-step2.sh
//                                     /Resources/boot.bin   stage 1 + the profile's variables (m1n1.build)
//     SFInstall/plan.json, SFInstall/state/
//
// Stage 1 is the release's `sf-stage1.bin` (Omacom's m1n1 121fcbf plus our patches). Its variables come from
// the profile's `boot.stage1.variables`, with @SF_BOOT_PARTUUID@ the PARTUUID of the SFBOOT partition the
// installer made: `chosen.asahi,efi-system-partition=<uuid>` and `chainload=<uuid>;sf/boot.bin`.

import CommonCrypto
import Foundation

public enum SFPayload {
    public static let appName = "SiliconForest Setup.app"
    public static let bootObjectPath = "Contents/Resources/boot.bin"
    public static let planPath = "SFInstall/plan.json"
    public static let statePath = "SFInstall/state"
    /// install.json's `format`, and the kernel collection's (installer/payload/release: INSTALL_FORMAT, KC_FORMAT).
    public static let installFormat = "siliconforest-install/3"
    public static let kcFormat = "siliconforest-kc/1"
    /// The G2 RAM-boot collection (g2-pins.json `kernel_sha256`). It has no NVMe driver and exists only for the
    /// console-only RAM boot; an installed system must never be built on it.
    public static let ramBootCollectionSHA256 = "ff0238cc345bbf33e90c39e7a909eef002c85113394b67fb5137d4857499812c"
    public static let partUUIDToken = "@SF_BOOT_PARTUUID@"

    /// Same bytes as the engine's S60 (`RecoveryPayload.files()`); a test keeps them equal.
    public static let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleExecutable</key><string>sf-launcher</string>
        <key>CFBundleIdentifier</key><string>org.siliconforest.setup</string>
        <key>CFBundleName</key><string>SiliconForest Setup</string>
        <key>CFBundlePackageType</key><string>APPL</string>
        <key>LSMinimumSystemVersion</key><string>13.5</string>
        </dict></plist>

        """

    /// Same bytes as the engine's S68 marker.
    public static let physicalMedia = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>AppName</key><string>SiliconForest Setup.app</string></dict></plist>

        """

    public struct Inputs {
        public var profile: URL
        public var launcher: URL        // installer/mac/Recovery/sf-launcher
        public var step2: URL           // installer/mac/Recovery/sf-step2.sh
        public var recoveryBinary: URL  // the signed SFRecovery
        public var stage1: URL          // the release's sf-stage1.bin
        public var stage1SHA256: String? // from install.json's artifact list; required for a real build
        public var bootPartUUID: String // the SFBOOT partition's PARTUUID
        public var planJSON: Data       // SFInstall/plan.json, as the engine wrote it
        public var volumeIcon: URL
        /// Extra files for Contents/Resources (fonts, artwork): (name, file).
        public var resources: [(String, URL)]
        public init(profile: URL, launcher: URL, step2: URL, recoveryBinary: URL, stage1: URL, stage1SHA256: String?, bootPartUUID: String,
                    planJSON: Data, volumeIcon: URL, resources: [(String, URL)] = []) {
            self.profile = profile; self.launcher = launcher; self.step2 = step2; self.recoveryBinary = recoveryBinary
            self.stage1 = stage1; self.stage1SHA256 = stage1SHA256; self.bootPartUUID = bootPartUUID; self.planJSON = planJSON
            self.volumeIcon = volumeIcon; self.resources = resources
        }
    }

    public struct ManifestEntry: Equatable, Sendable {
        public var path: String      // relative to the System volume root
        public var type: String      // "dir" | "file"
        public var mode: Int
        public var size: Int
        public var sha256: String    // files only
    }

    public struct Assembled {
        public var payload: StubPayload
        /// Every path the payload puts on the System volume, with the mode, size and SHA-256 it must have there.
        public var manifest: [ManifestEntry]
        public var variables: [String]
        public var bootObject: Data
    }

    // MARK: - what the release says

    public struct ReleaseFacts: Equatable, Sendable { public var stage1SHA256: String; public var collectionSHA256: String }

    /// install.json: `siliconforest-install/3`, a `siliconforest-kc/1` kernel collection that is not the RAM-boot
    /// one, and the stage 1 artifact's SHA-256.
    public static func checkRelease(installJSON data: Data) throws -> ReleaseFacts {
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw StubError("install.json is not an object") }
        guard o["format"] as? String == installFormat else { throw StubError("install.json format is \(o["format"] as? String ?? "missing"), not \(installFormat)") }
        guard let kc = o["kernel_collection"] as? [String: Any], kc["format"] as? String == kcFormat else {
            throw StubError("install.json has no \(kcFormat) kernel_collection")
        }
        guard let sha = kc["collection_sha256"] as? String, isSHA256(sha) else { throw StubError("kernel_collection has no collection_sha256") }
        guard sha != ramBootCollectionSHA256 else {
            throw StubError("the kernel collection is the G2 RAM-boot one (\(sha.prefix(8))…), which has no storage driver and is never installed")
        }
        guard let boot = o["boot"] as? [String: Any], let stageName = boot["stage1"] as? String,
              let arts = o["artifacts"] as? [[String: Any]],
              let art = arts.first(where: { $0["name"] as? String == stageName }), let s1 = art["sha256"] as? String, isSHA256(s1)
        else { throw StubError("install.json doesn't name a stage 1 artifact with a SHA-256") }
        return ReleaseFacts(stage1SHA256: s1, collectionSHA256: sha)
    }

    static func isSHA256(_ s: String) -> Bool { s.count == 64 && s.allSatisfy { "0123456789abcdef".contains($0) } }

    // MARK: - boot variables

    struct BootProfile: Decodable {
        struct Boot: Decodable {
            struct Stage1: Decodable { var source_revision: String; var variables: [String] }
            struct Stage2: Decodable { var path: String }
            var stage1: Stage1; var stage2: Stage2
        }
        var boot: Boot
    }

    /// The profile's variables with the SFBOOT PARTUUID in. Refuses anything that would not boot where the
    /// installer put stage 2.
    public static func variables(profile: URL, bootPartUUID: String) throws -> [String] {
        let bp = try JSONDecoder().decode(BootProfile.self, from: Data(contentsOf: profile)).boot
        let uuid = bootPartUUID.lowercased()
        guard uuid.range(of: #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#, options: .regularExpression) != nil else {
            throw StubError("the SFBOOT PARTUUID is not a UUID")
        }
        let vars = bp.stage1.variables.map { $0.replacingOccurrences(of: partUUIDToken, with: uuid) }
        for v in vars {
            guard !v.isEmpty, v.utf8.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }), !v.contains("@SF_") else { throw StubError("bad stage 1 variable \(v)") }
        }
        guard vars.contains("chosen.asahi,efi-system-partition=\(uuid)"), vars.contains("chainload=\(uuid);\(bp.stage2.path)") else {
            throw StubError("the profile's stage 1 variables don't point at \(bp.stage2.path) on the SFBOOT partition")
        }
        return vars
    }

    public static func bootObject(stage1: Data, variables: [String]) -> Data { stage1 + M1n1.variablesBlob(variables) }

    // MARK: - assembly

    /// Builds the app directory and the other inputs under `dir` (private, empty or absent) and the StubPayload that copies them.
    public static func assemble(_ i: Inputs, into dir: URL) throws -> Assembled {
        let fm = FileManager.default
        let vars = try variables(profile: i.profile, bootPartUUID: i.bootPartUUID)
        let stage1 = try Data(contentsOf: i.stage1)
        guard !stage1.isEmpty else { throw StubError("stage 1 is empty") }
        if let want = i.stage1SHA256 {
            guard SHA256Hex.hex(stage1) == want.lowercased() else { throw StubError("stage 1 doesn't match the release's SHA-256") }
        }
        let plan = try checkPlan(i.planJSON, bootPartUUID: i.bootPartUUID)
        guard stage1.count < 64 << 20 else { throw StubError("stage 1 is implausibly large") }

        if fm.fileExists(atPath: dir.path) { try fm.removeItem(at: dir) }
        let app = dir.appendingPathComponent(appName)
        var files: [(rel: String, data: Data, mode: Int)] = [
            ("\(appName)/Contents/Info.plist", Data(infoPlist.utf8), 0o644),
            ("\(appName)/Contents/MacOS/sf-launcher", try Data(contentsOf: i.launcher), 0o755),
            ("\(appName)/Contents/MacOS/SFRecovery", try Data(contentsOf: i.recoveryBinary), 0o755),
            ("\(appName)/Contents/Resources/sf-step2.sh", try Data(contentsOf: i.step2), 0o755),
        ]
        for (name, url) in i.resources.sorted(by: { $0.0 < $1.0 }) {
            guard !name.isEmpty, !name.contains("/"), name != "boot.bin", name != "sf-step2.sh" else { throw StubError("bad resource name \(name)") }
            files.append(("\(appName)/Contents/Resources/\(name)", try Data(contentsOf: url), 0o644))
        }
        guard files[1].data.starts(with: Data("#!/bin/sh".utf8)), files[3].data.starts(with: Data("#!/bin/sh".utf8)) else {
            throw StubError("sf-launcher and sf-step2.sh must be /bin/sh scripts")
        }
        guard !files[2].data.isEmpty else { throw StubError("SFRecovery is empty") }
        var dirs: Set<String> = [appName]
        for f in files {
            var d = (f.rel as NSString).deletingLastPathComponent
            while !d.isEmpty { dirs.insert(d); d = (d as NSString).deletingLastPathComponent }
        }
        for d in dirs.sorted() {
            try fm.createDirectory(at: dir.appendingPathComponent(d), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        }
        for f in files {
            let u = dir.appendingPathComponent(f.rel)
            try f.data.write(to: u)
            try fm.setAttributes([.posixPermissions: f.mode], ofItemAtPath: u.path)
        }
        let media = dir.appendingPathComponent("IAPhysicalMedia.plist")
        try Data(physicalMedia.utf8).write(to: media)
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: media.path)

        let boot = bootObject(stage1: stage1, variables: vars)
        let payload = StubPayload(
            volumeIcon: i.volumeIcon, appSource: app, appName: appName, script: nil, physicalMedia: media,
            bootObject: (bootObjectPath, i.stage1, vars),
            systemExtras: [StubExtra("SFInstall", nil), StubExtra(planPath, plan), StubExtra(statePath, nil)])

        // What must be on the System volume afterwards.
        var m: [ManifestEntry] = []
        func file(_ path: String, _ d: Data, _ mode: Int) { m.append(ManifestEntry(path: path, type: "file", mode: mode, size: d.count, sha256: SHA256Hex.hex(d))) }
        for d in dirs.sorted() { m.append(ManifestEntry(path: d, type: "dir", mode: 0o755, size: 0, sha256: "")) }
        for f in files { file(f.rel, f.data, f.mode) }
        file("\(appName)/\(bootObjectPath)", boot, 0o644)
        m.append(ManifestEntry(path: "SFInstall", type: "dir", mode: 0o755, size: 0, sha256: ""))
        m.append(ManifestEntry(path: statePath, type: "dir", mode: 0o755, size: 0, sha256: ""))
        file(planPath, plan, 0o644)
        file(".IAPhysicalMedia", Data(physicalMedia.utf8), 0o644)
        let icon = try Data(contentsOf: i.volumeIcon)
        var st = stat(); stat(i.volumeIcon.path, &st)
        file(".VolumeIcon.icns", icon, Int(st.st_mode & 0o7777))
        m.sort { $0.path < $1.path }
        return Assembled(payload: payload, manifest: m, variables: vars, bootObject: boot)
    }

    /// plan.json as the engine writes it (RecoveryPlan): the keys SFRecovery and sf-step2.sh rely on, and the
    /// boot partition it names must be the one stage 1 will chainload.
    static func checkPlan(_ data: Data, bootPartUUID: String) throws -> Data {
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw StubError("plan.json is not an object") }
        for k in ["job", "installID", "stub", "boot", "root", "planDigest"] {
            guard let v = o[k] as? String, !v.isEmpty else { throw StubError("plan.json has no \(k)") }
        }
        guard (o["boot"] as? String)?.lowercased() == bootPartUUID.lowercased() else { throw StubError("plan.json's boot partition isn't the one stage 1 chainloads") }
        return data
    }
}

public enum SHA256Hex {
    public static func hex(_ d: Data) -> String {
        var h = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        d.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(d.count), &h) }
        return h.map { String(format: "%02x", $0) }.joined()
    }
}
