// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// Preview13: which accounts can authorise `bless` on this Mac (the volume owners of macOS's System volume),
// found read-only with `diskutil apfs listUsers / -plist` and `dscl . -list /Users GeneratedUID`. The helper
// offers only these names; it refuses to send a password for any other account.

import Foundation

public struct StartupDiskOwners: Codable, Sendable, Equatable {
    /// Short names of local accounts that are volume owners, console user first.
    public var owners: [String]
    /// The person at the keyboard when they are an owner; otherwise the first owner.
    public var defaultOwner: String?
    public init(owners: [String], defaultOwner: String?) { self.owners = owners; self.defaultOwner = defaultOwner }

    /// Pure parsing, for tests: `listUsers` is the plist, `accounts` is `dscl . -list /Users GeneratedUID` output.
    public static func parse(listUsersPlist: Data, accounts: String, console: String?) -> StartupDiskOwners {
        var ownerUUIDs: [String] = []
        if let obj = try? PropertyListSerialization.propertyList(from: listUsersPlist, options: [], format: nil) as? [String: Any],
           let users = obj["Users"] as? [[String: Any]] {
            for u in users {
                guard (u["VolumeOwner"] as? Bool) == true, let id = u["APFSCryptoUserUUID"] as? String else { continue }
                // Local accounts only: MDM recovery and iCloud recovery keys are not people who type a password.
                let type = (u["APFSCryptoUserType"] as? String) ?? ""
                if type.isEmpty || type == "LocalOpenDirectory" { ownerUUIDs.append(id.uppercased()) }
            }
        }
        var names: [String] = []
        for line in accounts.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count == 2, ownerUUIDs.contains(parts[1].uppercased()), BlessGuard.validOwner(parts[0]) else { continue }
            names.append(parts[0])
        }
        if let c = console, let i = names.firstIndex(of: c) { names.remove(at: i); names.insert(c, at: 0) }
        let def = console.flatMap { names.contains($0) ? $0 : nil } ?? names.first
        return StartupDiskOwners(owners: names, defaultOwner: def)
    }

    /// Reads the real thing through `run` (executable, arguments → standard output, nil if it failed).
    public static func find(run: (String, [String]) -> Data?, console: String?) -> StartupDiskOwners {
        guard let plist = run("/usr/sbin/diskutil", ["apfs", "listUsers", "/", "-plist"]) else { return StartupDiskOwners(owners: [], defaultOwner: nil) }
        let accounts = run("/usr/bin/dscl", [".", "-list", "/Users", "GeneratedUID"]).map { String(decoding: $0, as: UTF8.self) } ?? ""
        return parse(listUsersPlist: plist, accounts: accounts, console: console)
    }

    /// The account at the keyboard (the owner of /dev/console).
    public static func consoleUser() -> String? {
        (try? FileManager.default.attributesOfItem(atPath: "/dev/console"))?[.ownerAccountName] as? String
    }
}
