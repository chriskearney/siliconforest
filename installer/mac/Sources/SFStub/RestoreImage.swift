// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// Identity selection ported from Asahi Linux installer v0.9.2 (commit dffbb38e), src/stub.py
// StubInstaller.load_identity: Copyright (c) 2021 The Asahi Linux contributors, MIT (LICENSES/third-party/asahi-installer-LICENSE.txt).
// Change from upstream: exactly one identity must match (upstream took the first), and the version and
// build must equal the profile's.

import Foundation

/// The `stub` section of an installer profile (installer/profiles/*.json).
public struct StubProfile: Codable, Sendable, Equatable {
    public struct RestoreImageRef: Codable, Sendable, Equatable { public var url: String; public var bytes: UInt64 }
    public struct Identity: Codable, Sendable, Equatable {
        public var ap_board_id: String
        public var ap_chip_id: String
        public var device_class: String
        public var restore_behavior: String
        public var variant: String
    }
    public var version: String
    public var build: String
    public var restore_image: RestoreImageRef
    public var identity: Identity
    public var partition_bytes: UInt64
    public var skip_manifest_keys: [String]

    /// Reads the `stub` object of a profile file.
    public static func load(profile url: URL) throws -> StubProfile {
        struct File: Decodable { var stub: StubProfile }
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).stub
    }

    /// Upstream's fixed skip list, which the profile must repeat (checked so the two cannot drift).
    public static let upstreamSkip = ["BaseSystem", "OS", "Ap,SystemVolumeCanonicalMetadata", "RestoreRamDisk", "RestoreTrustCache", "Cryptex*"]

    func skips(_ key: String) -> Bool {
        skip_manifest_keys.contains { $0.hasSuffix("*") ? key.hasPrefix(String($0.dropLast())) : key == $0 }
    }
}

/// An opened restore image: the zip, its BuildManifest, bootcaches and SystemVersion, and the one build
/// identity for this Mac.
public struct RestoreImage {
    public let zip: ZipReader
    public let manifest: PValue
    public let bootcaches: PValue
    public let systemVersion: PValue
    public let identity: PValue
    public let profile: StubProfile

    /// Erase (full IPSW) only; OTA packages (upstream's `is_ota` paths) are not supported.
    public init(zip: ZipReader, profile: StubProfile) throws {
        guard profile.skip_manifest_keys == StubProfile.upstreamSkip else {
            throw StubError("the profile's skip_manifest_keys differ from upstream's stub.py list")
        }
        self.zip = zip
        self.profile = profile
        manifest = try PValue.parse(zip.read("BuildManifest.plist"))
        bootcaches = try PValue.parse(zip.read("usr/standalone/bootcaches.plist"))
        systemVersion = try PValue.parse(zip.read("SystemVersion.plist"))
        guard systemVersion["ProductVersion"]?.string == profile.version, systemVersion["ProductBuildVersion"]?.string == profile.build else {
            throw StubError("restore image is \(systemVersion["ProductVersion"]?.string ?? "?") (\(systemVersion["ProductBuildVersion"]?.string ?? "?")), the profile wants \(profile.version) (\(profile.build))")
        }
        identity = try Self.selectIdentity(manifest, profile.identity)
    }

    public static func selectIdentity(_ manifest: PValue, _ want: StubProfile.Identity) throws -> PValue {
        let all = manifest["BuildIdentities"]?.array ?? []
        let found = all.filter {
            $0["ApBoardID"]?.string == want.ap_board_id && $0["ApChipID"]?.string == want.ap_chip_id
                && $0["Info"]?["DeviceClass"]?.string == want.device_class
                && $0["Info"]?["RestoreBehavior"]?.string == want.restore_behavior
                && $0["Info"]?["Variant"]?.string == want.variant
        }
        guard found.count == 1 else {
            throw StubError("expected one build identity for \(want.device_class) \(want.variant) \(want.restore_behavior), found \(found.count)")
        }
        return found[0]
    }

    /// The manifest as upstream writes it into the stub: every key kept, BuildIdentities cut to this one.
    public var trimmedManifest: PValue {
        guard case .dict(var d) = manifest else { return manifest }
        d["BuildIdentities"] = .array([identity])
        return .dict(d)
    }

    /// The manifest entries (key order is irrelevant: duplicates are skipped by path) the stub copies to its
    /// restore bundle, in upstream's sense: every key except the skip list, deduplicated by path, sorted by key
    /// for a stable order.
    public var restoreBundleMembers: [String] {
        var seen = Set<String>(), out: [String] = []
        for (key, val) in (identity["Manifest"]?.dict ?? [:]).sorted(by: { $0.key < $1.key }) where !profile.skips(key) {
            guard let path = val["Info"]?["Path"]?.string, !seen.contains(path) else { continue }
            seen.insert(path); out.append(path)
        }
        return out
    }

    public var baseSystemMember: String? { identity["Manifest"]?["BaseSystem"]?["Info"]?["Path"]?.string }
}

public enum RestoreImageSource {
    /// The restore image as a zip: an `https://` URL read with range requests (the profile's pinned size), or a local
    /// file (tests and the differential test's cached copy). Every read goes through a bounded block cache.
    public static func open(_ src: String, expectedSize: UInt64?) throws -> ZipReader {
        let base: RangeSource = src.hasPrefix("https://")
            ? try HTTPRangeSource(url: URL(string: src)!, expectedSize: expectedSize)
            : try FileRangeSource(path: src)
        return try ZipReader(BlockCache(base))
    }
}
