import Foundation
import SFIdentity
import SFInstallKit
import SFEngine
import SFHelperKit

// SFHelper: the privileged half of the installer (DESIGN §6), started by launchd through
// SMAppService when the app connects to its Mach service.
//
// Preview6: in a build with the compile key (SF_REAL_DISK_WRITES, set only by the release workflow) the
// target is `.internalDisk`: this Mac's startup disk, found by identity for each plan. The app imports and
// verifies the signed release, plans, and after the person's typed confirmation and an administrator's
// approval the helper writes the runtime authorization for exactly that plan and disk (≤ 2 h); the
// engine, the live backend's protection receipt and InternalDiskAuthority then do the install. Without
// the compile key the target stays `.none` and every disk verb answers `noTarget`. The same verbs run
// against disk images in-process in the tests and in `sfappimage` on the M5.
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
// The app bundle around this executable: Contents/MacOS/SFHelper.
// The executable's real path (launchd's argv[0] for a BundleProgram isn't guaranteed to be absolute).
let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
let contents = executable.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
let resources = contents.appendingPathComponent("Resources")
#if SF_REAL_DISK_WRITES
let target: HelperConfig.Target = .internalDisk
#else
let target: HelperConfig.Target = .none
#endif
var config = HelperConfig(target: target,
                          journalDirectory: ChainJournal.defaultDirectory,
                          workDirectory: URL(fileURLWithPath: "/var/db/org.siliconforest.installer/work"),
                          profileID: profileID, release: nil, releaseSource: nil,
                          policy: ConnectionPolicy(clientRequirement: SigningIdentity.appRequirement, minimumClientBuild: 1),
                          idleTimeout: 600)
config.releaseStore = URL(fileURLWithPath: "/var/db/org.siliconforest.installer/releases", isDirectory: true)
config.adminCheck = .system
config.allowedSigners = resources.appendingPathComponent("allowed_signers")
config.recoveryBinary = contents.appendingPathComponent("Helpers/SFRecovery")
#if SF_REAL_DISK_WRITES
// Preview7: the shipped app sets the one-time next boot itself and can restart the Mac (never a persistent default).
config.blessRunner = ProcessBlessRunner()
config.restartAction = SystemRestart.action
#endif
if let s = try? HelperResources.stubSource(profileID: profileID, resources: resources) { config.stubSource = s }
// Preview10: /Library/Logs/SiliconForest/helper.log and the unified log (org.siliconforest.installer).
let helperLog = InstallerLog(file: InstallerLog.helperLogURL, category: "helper")
config.log = helperLog
config.exitForFreshPrivilegeCheck = { exit(0) }
helperLog.info("SFHelper started: build \(config.helperBuild), profile \(profileID), target \(target), executable \(executable.path)")
let service = HelperService(config: config)
let delegate = HelperListenerDelegate(service: service)
let listener = NSXPCListener(machServiceName: SigningIdentity.helperMachService)
listener.delegate = delegate
listener.resume()
service.lifecycle.connectionStarted(); service.lifecycle.connectionEnded()   // arm the idle timer
RunLoop.main.run()
