import Foundation
import SFIdentity
import SFInstallKit
import SFEngine
import SFHelperKit

// SFHelper: the privileged half of the installer (DESIGN §6), started by launchd through
// SMAppService when the app connects to its Mach service.
//
// This build has no disk backend for a real Mac (no LiveDiskBackend): every verb that would touch
// a disk answers `noTarget`. The full verb set runs against disk images in-process in the tests
// (anonymous XPC listener) and through `sfinstallctl rehearse-image`.
//
//   SFHelper                      listen on the Mach service (launchd)
//   SFHelper --write-plists DIR   write the LaunchDaemon plist and the helper's Info.plist (make-app.sh)

let args = CommandLine.arguments
if args.count >= 3, args[1] == "--write-plists" {
    let v = ProcessInfo.processInfo.environment["VERSION"] ?? "0.9.0", b = ProcessInfo.processInfo.environment["BUILD_NUMBER"] ?? "1"
    do { try HelperBundle.write(to: URL(fileURLWithPath: args[2]), version: v, build: b); exit(0) }
    catch { FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1) }
}

func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buf = [UInt8](repeating: 0, count: size)
    guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
    return String(decoding: buf.prefix { $0 != 0 }, as: UTF8.self)
}
var facts = SystemFacts()
facts.hwModel = sysctlString("hw.model")
facts.board = sysctlString("hw.target")
let profileID = ProfileStore.profile(matching: facts)?.id ?? "unknown"
let config = HelperConfig(target: .none,
                          journalDirectory: ChainJournal.defaultDirectory,
                          workDirectory: URL(fileURLWithPath: "/var/db/org.siliconforest.installer/work"),
                          profileID: profileID, release: nil, releaseSource: nil,
                          policy: ConnectionPolicy(clientRequirement: SigningIdentity.appRequirement, minimumClientBuild: 1))
let service = HelperService(config: config)
let delegate = HelperListenerDelegate(service: service)
let listener = NSXPCListener(machServiceName: SigningIdentity.helperMachService)
listener.delegate = delegate
listener.resume()
service.lifecycle.connectionStarted(); service.lifecycle.connectionEnded()   // arm the idle timer
RunLoop.main.run()
