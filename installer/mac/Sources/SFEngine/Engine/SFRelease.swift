// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// The signed payload release (docs/installer/PAYLOAD.md §7): verify SHA256SUMS.sig, the sums, and
// install.json, and build the ReleaseManifest the engine uses. This is the reference the Python
// verifier (verify_release.py) is tested against; a production install refuses a rehearsal.

import Foundation
import SFInstallKit

public enum SFRelease {
    public static let namespace = "siliconforest-release"
    public static let format = "siliconforest-install/3"

    public struct Refusal: Error, LocalizedError, Equatable, Sendable {
        public var reason: String
        public var errorDescription: String? { "Refused: \(reason)" }
        public init(_ reason: String) { self.reason = reason }
    }

    /// allowed_signers: SF_ALLOWED_SIGNERS, the app bundle, or the repo layout.
    public static func allowedSignersURL() throws -> URL {
        if let e = ProcessInfo.processInfo.environment["SF_ALLOWED_SIGNERS"], !e.isEmpty {
            let u = URL(fileURLWithPath: e)
            guard FileManager.default.isReadableFile(atPath: u.path) else { throw Refusal("SF_ALLOWED_SIGNERS is not a readable file") }
            return u
        }
        if let u = Bundle.main.url(forResource: "allowed_signers", withExtension: nil) { return u }
        let repo = SourceTree.installerRoot.appendingPathComponent("payload/release/allowed_signers")
        if FileManager.default.isReadableFile(atPath: repo.path) { return repo }
        throw Refusal("no allowed_signers file (bundle it in the app, or set SF_ALLOWED_SIGNERS)")
    }

    /// Verify the directory is a signed SiliconForest release and return the manifest the engine uses.
    /// `allowRehearsal` is for tests only; a production install leaves it false.
    public static func verify(directory: URL, allowedSigners: URL? = nil, allowRehearsal: Bool = false) throws -> ReleaseManifest {
        let d = directory.resolvingSymlinksInPath()
        let sums = d.appendingPathComponent("SHA256SUMS")
        let sig = d.appendingPathComponent("SHA256SUMS.sig")
        guard FileManager.default.isReadableFile(atPath: sums.path), FileManager.default.isReadableFile(atPath: sig.path) else {
            throw Refusal("SHA256SUMS or its signature is missing")
        }
        let signers = try allowedSigners ?? allowedSignersURL()
        try verifySignature(sums: sums, signature: sig, allowedSigners: signers)

        let entries = try parseSums(try String(contentsOf: sums, encoding: .utf8))
        var present = Set<String>()
        let fm = FileManager.default
        for name in try fm.contentsOfDirectory(atPath: d.path) {
            if name == "SHA256SUMS" || name == "SHA256SUMS.sig" { continue }
            let u = d.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: u.path, isDirectory: &isDir), !isDir.boolValue else { throw Refusal("\(name) is not a plain file") }
            if (try? u.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { throw Refusal("\(name) is not a plain file") }
            present.insert(name)
        }
        if present != Set(entries.keys) {
            let extra = present.subtracting(entries.keys).sorted()
            let missing = Set(entries.keys).subtracting(present).sorted()
            throw Refusal("files and SHA256SUMS differ: unlisted \(extra), missing \(missing)")
        }
        var sizes: [String: Int64] = [:]
        for (name, digest) in entries {
            let got = try SHA256Hasher.file(d.appendingPathComponent(name))
            guard got == digest else { throw Refusal("\(name) does not match its SHA-256") }
            sizes[name] = (try fm.attributesOfItem(atPath: d.appendingPathComponent(name).path)[.size] as? NSNumber)?.int64Value ?? 0
        }
        guard entries["install.json"] != nil else { throw Refusal("install.json is not in SHA256SUMS") }
        let instData = try Data(contentsOf: d.appendingPathComponent("install.json"))
        guard let inst = try JSONSerialization.jsonObject(with: instData) as? [String: Any] else { throw Refusal("install.json is not an object") }
        guard inst["format"] as? String == format else { throw Refusal("install.json format is \(inst["format"] ?? "missing")") }
        guard let arts = inst["artifacts"] as? [[String: Any]] else { throw Refusal("install.json has no artifacts") }
        var listed: [String: (bytes: Int64, sha256: String, role: String)] = [:]
        for a in arts {
            guard let name = a["name"] as? String, let sha = a["sha256"] as? String, let role = a["role"] as? String,
                  let n = int64(a["bytes"]) else { throw Refusal("install.json artifact is malformed") }
            listed[name] = (n, sha, role)
        }
        if Set(listed.keys) != Set(entries.keys).subtracting(["install.json"]) {
            throw Refusal("install.json artifacts and SHA256SUMS differ")
        }
        for (name, a) in listed {
            guard a.sha256 == entries[name], a.bytes == sizes[name] else { throw Refusal("install.json disagrees with SHA256SUMS about \(name)") }
        }
        let signing = inst["signing_key"] as? [String: Any] ?? [:]
        let rehearsal = (inst["rehearsal"] as? Bool ?? false) || (signing["test_only"] as? Bool ?? false)
        if rehearsal && !allowRehearsal { throw Refusal("this is a rehearsal release (TEST-ONLY key); refused") }

        guard let root = inst["root"] as? [String: Any], let boot = inst["boot"] as? [String: Any] else { throw Refusal("install.json is missing root or boot") }
        let img = int64(root["image_bytes"]) ?? 0
        let minB = int64(root["min_bytes"]) ?? img
        let grow = root["grow"] as? [String: Any]
        let maxB = int64(grow?["max_bytes"]) ?? 0
        if img <= 0 || img % 4096 != 0 || minB < img || maxB < img { throw Refusal("root sizes are inconsistent") }
        func slot(_ key: String) throws -> (offset: Int64, bytes: Int64) {
            guard let s = inst[key] as? [String: Any], let off = int64(s["offset"]), let n = int64(s["bytes"]) else { throw Refusal("\(key) is missing") }
            if off % 4096 != 0 || off <= 0 || off + n > img { throw Refusal("\(key) is outside the image or unaligned") }
            return (off, n)
        }
        let fw = try slot("firmware_slot"), rec = try slot("receipt_slot")
        if fw.offset < rec.offset + rec.bytes && rec.offset < fw.offset + fw.bytes { throw Refusal("slots overlap") }
        guard let stage1 = boot["stage1"] as? String, let stage2 = boot["stage2"] as? String, let bootargs = boot["bootargs"] as? String,
              listed[stage1] != nil, listed[stage2] != nil, listed[bootargs] != nil else { throw Refusal("boot files are not listed artifacts") }
        if boot["kernel"] != nil { throw Refusal("a prelinked kernel collection is not part of format 3") }
        let parts = (root["parts"] as? [String]) ?? []
        if parts.isEmpty { throw Refusal("root parts are missing") }
        for p in parts {
            guard listed[p]?.role == "root-part" else { throw Refusal("root part \(p) is not a listed root part") }
        }
        // Optional SFBOOT files (A/B boot, SAP's trust anchor): each must be a listed artifact.
        func optionalBoot(_ key: String) throws -> String? {
            guard let v = boot[key] else { return nil }
            guard let name = v as? String, listed[name] != nil else { throw Refusal("boot \(key) is not a listed artifact") }
            return name
        }
        let stage2B = try optionalBoot("stage2_b"), bootState = try optionalBoot("bootstate"), trust = try optionalBoot("trust")
        if bootState != nil && stage2B == nil { throw Refusal("the A/B boot record comes without slot B's stage 2") }
        let (kc, fsUUID) = try KernelCollection.fromInstallJSON(instData)
        if !rehearsal, kc.toolSigning != "developer-id" { throw Refusal("a release's kc-builder must be Developer ID signed") }

        var artifacts = listed.map { ReleaseManifest.Artifact(name: $0.key, bytes: $0.value.bytes, sha256: $0.value.sha256) }
        artifacts.sort { $0.name < $1.name }
        return ReleaseManifest(
            version: inst["release"] as? String ?? "",
            artifacts: artifacts,
            rootImage: parts[0],
            rootImageBytes: img,
            rootImageSHA256: root["image_sha256"] as? String ?? "",
            rootImageCompressed: (root["compression"] as? String) == "xz",
            rootMinBytes: minB,
            firmwareSlotOffset: fw.offset,
            firmwareSlotBytes: fw.bytes,
            receiptSlotOffset: rec.offset,
            receiptSlotBytes: rec.bytes,
            stubFiles: [],
            stage1: stage1,
            stage2: stage2,
            kernel: kc.kernel,
            firmware: "",
            kernelCollection: kc,
            rootFilesystemUUID: fsUUID,
            rootParts: parts,
            stage2B: stage2B,
            bootState: bootState,
            trust: trust)
    }

    private static func verifySignature(sums: URL, signature: URL, allowedSigners: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        p.arguments = ["-Y", "verify", "-f", allowedSigners.path, "-I", namespace, "-n", namespace, "-s", signature.path]
        p.standardInput = try FileHandle(forReadingFrom: sums)
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        do { try p.run() } catch { throw Refusal("ssh-keygen could not be started") }
        p.waitUntilExit()
        let msg = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard p.terminationStatus == 0 else {
            throw Refusal("signature does not verify: \(msg.split(whereSeparator: \.isNewline).last.map(String.init) ?? msg)")
        }
    }

    private static func parseSums(_ text: String) throws -> [String: String] {
        var entries: [String: String] = [:]
        let re = try! NSRegularExpression(pattern: #"^([0-9a-f]{64})  (\S+)$"#)
        for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).enumerated() {
            if line.isEmpty { continue }
            let ns = line as NSString
            guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                  m.numberOfRanges == 3 else { throw Refusal("SHA256SUMS line \(i + 1) is malformed") }
            let digest = ns.substring(with: m.range(at: 1)), name = ns.substring(with: m.range(at: 2))
            if name == "SHA256SUMS" || name == "SHA256SUMS.sig" || name.contains("/") { throw Refusal("bad artifact name \(name)") }
            if entries[name] != nil { throw Refusal("\(name) is listed twice") }
            entries[name] = digest
        }
        if entries.isEmpty { throw Refusal("SHA256SUMS is empty") }
        return entries
    }

    private static func int64(_ v: Any?) -> Int64? {
        if let i = v as? Int64 { return i }
        if let i = v as? Int { return Int64(i) }
        if let n = v as? NSNumber { return n.int64Value }
        return nil
    }
}
