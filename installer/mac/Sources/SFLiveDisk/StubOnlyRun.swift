// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// The supervised stub-only run on the Air (docs/installer/STUB-ONLY-RUN-J313.md), as code: the plan, the
// engine with SFStub, and its target. On a disk image the target is `ImageTargetAuthority` (the M5 dress
// rehearsal, the same live backend and protection receipt). On the internal disk it is
// `InternalDiskAuthority`, which exists only in a build with the compile key and opens only with Chris's
// runtime authorization file for this plan and disk (RealDiskGate). Nothing here can open that gate.

import Foundation
import SFEngine
import SFInstallKit

public enum StubOnlyRun {
    public enum Target: Sendable {
        case image(URL)
        /// The internal disk's GPT UUID (`diskutil info -plist <disk> DiskUUID`).
        case internalDisk(String)
    }

    /// Read-only: the internal physical whole disk whose GPT UUID is `diskUUID` (the same identity checks as
    /// `InternalDiskAuthority.wholeDisk`, without any write authority).
    public static func internalWholeDisk(diskUUID: String, query: ToolRunner = ProcessToolRunner()) throws -> String {
        let want = diskUUID.uppercased()
        let list = try Query.dict(query, ["/usr/sbin/diskutil", "list", "-plist"])
        var found: [String] = []
        for e in list["AllDisksAndPartitions"] as? [[String: Any]] ?? [] {
            guard let id = e["DeviceIdentifier"] as? String, e["Content"] as? String == "GUID_partition_scheme",
                  id.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil else { continue }
            let info = try Query.dict(query, ["/usr/sbin/diskutil", "info", "-plist", id])
            guard (try? WholeDiskIdentity.uuid(id, info: info)) == want else { continue }
            guard info["WholeDisk"] as? Bool == true, info["Internal"] as? Bool == true,
                  info["VirtualOrPhysical"] as? String != "Virtual", info["BusProtocol"] as? String != "Disk Image" else {
                throw SafetyRefusal("\(id) has that UUID but isn't an internal physical whole disk")
            }
            found.append(id)
        }
        guard found.count == 1, let w = found.first else { throw SafetyRefusal("exactly one internal disk must have UUID \(want) (found \(found.count))") }
        return w
    }

    /// The target's authority. The internal disk's exists only with the compile key, and its init throws
    /// unless the runtime authorization names this plan and disk.
    public static func authority(_ t: Target, planDigest: String) throws -> any TargetAuthority {
        switch t {
        case .image(let url): return ImageTargetAuthority(imagePath: url)
        case .internalDisk(let uuid):
            #if SF_REAL_DISK_WRITES
            guard geteuid() == 0 else { throw SafetyRefusal("the internal disk needs root") }
            return try InternalDiskAuthority(planDigest: planDigest, diskUUID: uuid)
            #else
            _ = uuid
            throw SafetyRefusal("this build can't write to an internal disk (no SF_REAL_DISK_WRITES): only disk images")
            #endif
        }
    }

    /// The topology and resize limits the plan is made from, read-only.
    public static func read(_ t: Target, query: ToolRunner = ProcessToolRunner()) throws -> (ImageTopology, TopologyReader.ResizeLimits) {
        let whole: String
        switch t {
        case .image(let url): whole = try ImageTargetAuthority(imagePath: url, query: query).wholeDisk()
        case .internalDisk(let uuid): whole = try internalWholeDisk(diskUUID: uuid, query: query)
        }
        let topo = try TopologyReader.read(whole, query: query)
        guard let mac = topo.macOS else { throw SafetyRefusal("no macOS container on \(whole)") }
        return (topo, try TopologyReader.limits(mac.identifier, query: query))
    }

    /// The stub-only plan (InstallRequest.stubOnly): macOS gives up exactly the profile's stub size.
    public static func plan(topology: ImageTopology, limits: TopologyReader.ResizeLimits, profile: DeviceProfile,
                            release: ReleaseManifest, name: String = "SiliconForest", installID: String) throws -> EnginePlan {
        let req = InstallRequest(siliconForestBytes: profile.partitioning.stubContainerBytes, installName: name, installID: installID, stubOnly: true)
        return try EnginePlanner.installPlan(topology: topology, limits: limits, profile: profile, release: release, request: req)
    }

    /// The runtime authorization Chris writes (root-owned, 0600, at `RealDiskGate.authorizationPath`) for this
    /// plan and disk. Printed for him to check and place; this code never writes it.
    public static func authorizationTemplate(plan: EnginePlan, diskUUID: String, from: Date = Date(), hours: Double = 2) throws -> String {
        let a = RealDiskGate.Authorization(planDigest: plan.digest, diskUUID: diskUUID.uppercased(), notBefore: from,
                                           notAfter: from.addingTimeInterval(min(hours * 3600, RealDiskGate.maxValidity)))
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601
        return String(decoding: try e.encode(a), as: UTF8.self)
    }

    /// A one-line description of each stub-only step, for the person approving the plan.
    public static func summary(_ plan: EnginePlan, release: ReleaseManifest) -> [String] {
        var out = ["plan \(plan.digest)", "macOS container \(plan.macOS.store): \(plan.macOS.from) B → \(plan.macOS.to) B",
                   "new: " + plan.partitions.map { "\($0.role) \($0.bytes) B \($0.content) “\($0.label)”" }.joined(separator: ", "),
                   "stage 1: \(release.stage1) \(release.artifacts.first?.bytes ?? 0) B sha256 \(release.artifacts.first?.sha256 ?? "")",
                   "stage 1 chainloads PARTUUID \(plan.absentBootPartUUID) (on no disk: it stops, \"can't find stage 2\")",
                   "steps: " + StepCode.order(plan).map(\.rawValue).joined(separator: " ")]
        if plan.isStubOnly == false { out.append("NOT A STUB-ONLY PLAN") }
        return out
    }
}
