import Foundation
import SFInstallKit

/// Every user-facing string in the installer, in one reviewed place (DESIGN §4, VISUAL §9).
/// Source: docs/installer/UX-FLOW.md. Voice: calm, exact, short; say what happens to the person's
/// Mac and files; buttons name the action; never claim more than the journal proves.
public enum Copy {
    public static let product = "SiliconForest"
    public static let installer = "SiliconForest Installer"

    public enum Common {
        public static let `continue` = "Continue"
        public static let back = "Back"
        public static let details = "Details"
        public static let hideDetails = "Hide Details"
        public static let quit = "Quit"
        public static let cancel = "Cancel"
        public static let done = "Done"
        public static let checkAgain = "Check Again"
        public static let learnMore = "Learn More"
        public static let tryAgain = "Try Again"
        public static let exportDiagnostics = "Export Diagnostics"
        public static let dryRun = "Dry Run"
        public static let dryRunDetail = "Simulated disk · nothing is written"
        public static let readOnly = "Read-Only"
        public static let readOnlyDetail = "Analysing this Mac · nothing is written"
        public static let dryRunComplete = "Dry run complete. No disk was changed."
    }

    /// Step dots: Check · Prepare · Space · Review · Install · Recovery · Finish.
    public static let stepDots = ["Check", "Prepare", "Space", "Review", "Install", "Recovery", "Finish"]

    // MARK: 1. Welcome
    public enum Welcome {
        public static let title = "SiliconForest"
        public static let lead = "Built on Darwin and XNU. Runs Mac apps."
        public static let body = "macOS and your files are not changed. You choose which system to start when you turn on your Mac."
        public static let primary = "Get Started"
        public static let whatIs = "What is SiliconForest?"
        public static let remove = "Remove SiliconForest…"
        public static func footer(model: String, macOS: String) -> String { "\(model) · macOS \(macOS)" }
        public static let whatIsTitle = "What is SiliconForest?"
        public static let whatIsBody = "SiliconForest is an open-source operating system based on Darwin, the core of macOS, for Macs with Apple silicon. It installs in its own partitions and starts only when you choose it."
        public static let moveTitle = "Move to Applications first"
        public static let moveBody = "SiliconForest Installer needs to run from your Applications folder."
        public static let moveAndReopen = "Move and Reopen"
    }

    // MARK: 2. Compatibility check
    public enum Check {
        public static let title = "Checking your Mac"
        public static let lead = "This doesn't change anything."
        public static let ready = "Your Mac is ready"
        public static let readyLead = "All requirements are met."

        public static func label(_ k: CompatibilityCheck.Kind) -> String {
            switch k {
            case .thisMac: return "This Mac"
            case .macOS: return "macOS"
            case .firmware: return "Startup firmware"
            case .account: return "Your account"
            case .fileVault: return "FileVault"
            case .disk: return "Disk"
            case .freeSpace: return "Free space"
            case .power: return "Power"
            case .internet: return "Internet"
            }
        }

        public static func text(_ f: Finding) -> String {
            switch f {
            case .supportedMac(let m): return "\(m) is supported"
            case .unsupportedMac(let this, _): return "\(this) isn't supported yet"
            case .macOSSupported(let v): return "macOS \(v) is supported"
            case .macOSTooOld(let have, let need): return "macOS \(have). Needs \(need) or later"
            case .macOSBlocked(let major, _): return "macOS \(major) isn't tested yet"
            case .macOSUntested(let have, _): return "macOS \(have) isn't tested yet"
            case .macOSUnknown: return "Couldn't read the macOS version"
            case .firmwareCurrent: return "Up to date"
            case .firmwareOld: return "Needs a macOS update"
            case .firmwareUnknown: return "Couldn't read the firmware version"
            case .admin(let u): return "\(u) is an administrator"
            case .notAdmin(let u): return "\(u) isn't an administrator"
            case .fileVaultOn: return "On"
            case .fileVaultOff: return "Off"
            case .fileVaultConverting(let pct): return pct.map { "Still encrypting, \($0)% done" } ?? "Still encrypting"
            case .fileVaultUnknown: return "Couldn't read FileVault's state"
            case .diskHealthy(let size): return "Healthy layout, \(Bytes.format(size))"
            case .diskNonStandard: return "Not the standard Apple layout"
            case .lockedVolume(let v): return "“\(v)” is locked"
            case .enoughSpace: return "Enough free space"
            case .notEnoughSpace(_, _, let short): return "Free up \(Bytes.format(short))"
            case .noMacOSContainer: return "macOS's container wasn't found"
            case .powerConnected: return "Connected"
            case .onBattery(let pct): return pct.map { "On battery (\($0)%). Connect the charger" } ?? "On battery. Connect the charger"
            case .onBatteryEnough(let pct): return "On battery (\(pct)%). Enough to continue"
            case .internetConnected: return "Connected"
            case .internetOffline: return "Not connected"
            case .internetNotChecked: return "Checked before downloading"
            }
        }

        /// Blocked variants: headline, body and actions replace the screen's title.
        public struct Blocked { public var title: String; public var body: String; public var actions: [String] }

        public static func blocked(_ f: Finding, profileName: String = "MacBook Pro (13-inch, M1, 2020)") -> Blocked? {
            switch f {
            case .unsupportedMac:
                return .init(title: "This Mac isn't supported yet",
                             body: "Supported: \(profileName). Other models are added after they are tested on hardware.",
                             actions: ["See Supported Macs", Common.quit])
            case .macOSTooOld(let have, let need):
                return .init(title: "Update macOS first", body: "SiliconForest needs macOS \(need) or later. You have macOS \(have).",
                             actions: ["Open Software Update", Common.checkAgain])
            case .macOSBlocked(let major, _):
                return .init(title: "macOS \(major) isn't tested yet",
                             body: "Resizing the disk on macOS \(major) has failed for others, so the installer won't risk it. Your Mac hasn't been changed.",
                             actions: [Common.learnMore, Common.quit])
            case .notAdmin:
                return .init(title: "An administrator is needed", body: "Sign in with an administrator account and open the installer again.", actions: [Common.quit])
            case .fileVaultConverting(let pct):
                return .init(title: "FileVault is still working",
                             body: "Wait for encryption to finish.\(pct.map { " It's \($0)% done." } ?? "")", actions: [Common.checkAgain])
            case .lockedVolume(let v):
                return .init(title: "A volume is locked", body: "“\(v)” must be unlocked before the disk can be resized.",
                             actions: ["Open Disk Utility", Common.checkAgain])
            case .notEnoughSpace(let need, let reserve, let short):
                return .init(title: "Not enough free space",
                             body: "SiliconForest needs at least \(Bytes.format(need)), and macOS must keep \(Bytes.format(reserve)). Free up \(Bytes.format(short)), then check again.",
                             actions: ["Open Storage Settings", Common.checkAgain])
            case .onBattery:
                return .init(title: "Connect your charger", body: "The battery is at 50% or lower, and the disk shouldn't be resized on a low battery. Plug in your Mac, then check again.",
                             actions: [Common.checkAgain])
            case .firmwareOld:
                return .init(title: "Update macOS first", body: "Your Mac's startup firmware is older than SiliconForest needs. A macOS update brings it up to date.",
                             actions: ["Open Software Update", Common.checkAgain])
            case .diskNonStandard, .noMacOSContainer:
                return .init(title: "This disk layout isn't supported", body: "The installer only works with Apple's standard layout. Your Mac hasn't been changed.",
                             actions: [Common.learnMore, Common.quit])
            case .internetOffline:
                return .init(title: "Connect to the internet", body: "The installer downloads SiliconForest and Apple's startup files before it changes anything.",
                             actions: [Common.checkAgain])
            default: return nil
            }
        }

        public static func entry(_ e: EntryState) -> Blocked? {
            switch e {
            case .fresh: return nil
            case .handMade:
                return .init(title: "SiliconForest was installed another way",
                             body: "This installer changes only installations it created. Nothing was changed.",
                             actions: [Common.learnMore, Common.quit])
            case .unfinished(let step):
                return .init(title: "Resume the installation", body: "An earlier installation stopped at “\(step)”.", actions: [Common.continue, "Undo It"])
            case .awaitingRecovery:
                return .init(title: "Finish in Recovery", body: "The last step runs in Recovery.", actions: ["Show Me How"])
            case .installed(let i):
                return .init(title: "SiliconForest is installed", body: "Version \(i.version ?? "?") on “\(i.name)”.", actions: ["Update", "Remove…", Common.quit])
            }
        }
    }

    // MARK: 3. Before you begin
    public enum Prepare {
        public static let title = "Before you begin"
        public static let lead = "What the installer changes and what it doesn't."
        public static let changesHeader = "What changes"
        public static let keepsHeader = "What doesn't"
        public static let changes = ["macOS's partition gets smaller", "Three new partitions for SiliconForest", "SiliconForest appears at startup"]
        public static let keeps = ["Your files and apps", "macOS's security settings", "Any other system on this Mac"]
        public static let backupTitle = "Back up first."
        public static let backupBody = "A power failure or existing disk damage during the resize can cause data loss."
        public static func lastBackup(_ when: String, _ disk: String) -> String { "Last Time Machine backup: \(when) on “\(disk)”" }
        public static let noBackupKnown = "No Time Machine backup found on this Mac."
        /// Dry-run sample (the real app reads `tmutil latestbackup` when it can).
        public static let sampleBackupTime = "Today, 9:42 AM"
        public static let sampleBackupDisk = "Basecamp"
        public static let openTimeMachine = "Open Time Machine Settings"
        public static let checkbox = "I have a current backup of this Mac"
        public static let aboutSecurity = "About security"
        public static let aboutSecurityBody = "SiliconForest uses a custom kernel, so its startup security must be set to Permissive. This applies only to SiliconForest. macOS keeps its own security level. Apple doesn't provide or support custom kernels."
    }

    // MARK: 4. Choose your space
    public enum Space {
        public static let title = "Choose a size"
        public static let lead = "Drag to set the size of SiliconForest. Removing it later returns the space to macOS."
        public static let macOS = "macOS"
        public static let siliconForest = "SiliconForest"
        public static func used(_ b: Int64) -> String { "used \(Bytes.format(b))" }
        public static func free(_ b: Int64) -> String { "free \(Bytes.format(b))" }
        public static func new(_ b: Int64) -> String { "new \(Bytes.format(b))" }
        public static func keepsFree(_ b: Int64) -> String { "Keeps \(Bytes.format(b)) free in macOS" }
        public static func preset(_ id: String) -> String {
            ["recommended": "Recommended", "half": "Half", "minimum": "Minimum", "maximum": "Maximum"][id] ?? id
        }
        public static func limitReserve(_ b: Int64) -> String { "macOS needs to keep \(Bytes.format(b)) free for updates." }
        public static func limitGrowCap(_ b: Int64) -> String { "This release can grow the SiliconForest root to at most \(Bytes.format(b))." }
        public static func limitMinimum(_ b: Int64) -> String { "SiliconForest needs at least \(Bytes.format(b))." }
        public static let lowSpace = "Enough to start, with little room for files."
        public static func fixed(_ b: Int64) -> String { "This release uses a fixed size of \(Bytes.format(b))." }
        public static let showDetails = "Show partition details"
        public static let hideDetails = "Hide partition details"
        public static func voiceOver(sf: Int64, mac: Int64) -> String { "SiliconForest size, \(Bytes.format(sf)). macOS keeps \(Bytes.format(mac))." }
        public static let gb = "GB"
        public static let partStub = "Startup volume"
        public static let partBoot = "SFBOOT"
        public static let partRoot = "SF root"
        public static func partDetail(_ role: String) -> String {
            ["stub": "APFS · Apple's startup files, stage 1", "boot": "FAT32 · stage 2 and the kernel", "root": "ext4 · SiliconForest and your files"][role] ?? ""
        }
    }

    // MARK: 5. Options
    public enum Options {
        public static let title = "Options"
        public static let lead = "Most people can keep the defaults."
        public static let nameLabel = "Name at startup"
        public static let nameHelp = "The name in the startup picker"
        public static let afterSetup = "After setup"
        public static let startOnce = "Start SiliconForest once, keep your current startup system"
        public static let startOnceHelp = "If the first start has any trouble, your Mac goes back to the system it starts today"
        public static let makeDefault = "Make SiliconForest the default after it starts successfully"
        public static let advanced = "Advanced"
        public static let channel = "Release channel"
        public static let keepDownloads = "Keep the downloaded files after install"
        public static let localRelease = "Use a local release folder (developer builds only)"
        public static let stable = "Stable"
        public static let atStartup = "At startup"
        public static let defaultLabel = "Default"
        public static func nameError(_ code: String) -> String {
            ["empty": "Give it a name.", "long": "Keep it to 28 characters or fewer.", "characters": "Use letters, numbers, spaces and dashes."][code] ?? code
        }
    }

    // MARK: 6. Review
    public enum Review {
        public static let title = "Review and install"
        public static let lead = "Nothing has changed yet."
        public static let now = "Now"
        public static let after = "After"
        public static let willHeader = "The installer will"
        public static let shrink = "Shrink macOS"
        public static func shrinkValue(from: Int64, to: Int64, free: Int64) -> String { "\(Bytes.format(from)) → \(Bytes.format(to)) (keeps \(Bytes.format(free)) free)" }
        public static let add = "Add SiliconForest"
        public static func addValue(_ b: Int64) -> String { "\(Bytes.format(b)) in three partitions" }
        public static let download = "Download"
        public static func downloadValue(release: Int64, apple: Int64) -> String { "\(Bytes.format(release)) from SiliconForest, \(Bytes.format(apple)) from Apple" }
        public static let time = "Time"
        public static let timeValue = "About 25 minutes, then one step from you"
        public static let oneThingTitle = "One step must be done by you."
        public static let oneThingBody = "After the installation, you restart into Recovery and approve SiliconForest with your password. The installer shows the steps."
        public static let showWhatWouldHappen = "Show What Would Happen"
        public static let primary = "Install SiliconForest"
        public static let commandsTitle = "What would happen"
        public static let commandsLead = "Every command the installer would run, in order."
    }

    // MARK: Permissions (preview10, preview12)
    public enum Privileges {
        public static let title = "Permissions"
        public static let lead = "The installer needs these permissions before it downloads anything or changes your disk. Nothing has been changed."
        public static let helperRow = "The installer's helper is allowed (Login Items)"
        public static let diskRow = "The helper has Full Disk Access"
        public static let openLoginItems = "Open Login Items"
        public static let openFullDiskAccess = "Open Full Disk Access Settings"
        public static let showHelper = "Show SFHelper in Finder"
        public static let copyHelperPath = "Copy SFHelper path"
        public static let fdaStep1 = "Click Open Full Disk Access Settings. A Finder window shows SFHelper."
        public static let fdaStep2 = "Turn on SFHelper in the list. macOS may ask for your password."
        public static let fdaStep3 = "Not in the list? Drag SFHelper from the Finder window into the list. Or click +, press ⌘⇧G, paste the path below, click Open, then turn SFHelper on."
        public static let restarting = "Restarting the installer's helper…"
        public static let waiting = "Waiting for approval…"
        public static let waitingBody = "The installer's helper does the disk work, and macOS needs your approval to run it. Click Open Login Items, then under Allow in the Background turn on “SiliconForest Installer”. The installer continues automatically."
        public static let waitingLine = "Checking every few seconds. System Settings opens only when you click."
        public static let checking = "Checking…"
        public static let continuing = "Continuing…"
    }

    // MARK: Startup disk login (preview13)
    /// macOS needs a volume owner's login to change the startup disk on Apple Silicon.
    public enum Startup {
        public static let header = "Start SiliconForest next time"
        public static func body(volume: String) -> String { "To set your Mac to start SiliconForest, macOS needs the login password of a user who can unlock \(volume). This is your Mac login password." }
        public static let account = "Account"
        public static func field(owner: String) -> String { owner.isEmpty ? "Mac login password" : "Mac login password for \(owner)" }
        public static let optionalNote = "Optional. The installer uses it once, at the end. It stays in memory and is never saved or logged. Leave it empty to do this at the end instead."
        public static let finishNote = "Type the login password of a user who can unlock your Mac's startup disk. The installer uses it once and doesn't keep it."
        public static let setButton = "Set Startup Disk"
        public static let setting = "Setting the startup disk…"
        public static func failed(_ why: String) -> String { "The startup disk wasn't set: \(why)" }
        public static let noAccounts = "The installer couldn't find a user who can unlock this Mac's startup disk. Use the command below instead."
    }

    // MARK: Download row (preview13)
    public enum Download {
        public static let working = "Downloading…"
        public static let verifying = "Verifying…"
        /// The row's trailing text. `total` 0 means the file list isn't known yet: no counts, only the bytes so far.
        public static func label(done: Int64, total: Int64, bytes: Int64) -> String {
            if total > 0 {
                return done >= total ? verifying : "\(done) of \(total) files"
            }
            return bytes > 0 ? "\(working) \(Bytes.format(bytes))" : working
        }
    }

    // MARK: Confirm the change (preview13): one short block per partition
    /// The summary on the Confirm screens. Pure text from numbers, so a test can check every line.
    public enum Confirm {
        public static let installHeader = "What will change"
        public static let removeHeader = "What will be removed"
        public static let warning = "Back up your Mac first. This changes your disk."
        public static let filesStay = "Your files stay."

        public struct Block: Identifiable, Equatable, Sendable {
            public var name: String
            public var change: String
            public var detail: String?
            public var id: String { name }
            public init(name: String, change: String, detail: String? = nil) { self.name = name; self.change = change; self.detail = detail }
        }
        /// The partitions of a plan: the role ("stub", "boot", "root") and its size (zero when the plan doesn't say).
        public struct Part: Equatable, Sendable {
            public var role: String
            public var bytes: Int64
            public init(role: String, bytes: Int64) { self.role = role; self.bytes = bytes }
        }

        /// "245 GB", "2.5 GB", "512 MB": whole gigabytes (10^9, as Finder shows them) from 10 GB up.
        public static func size(_ bytes: Int64) -> String {
            let gb = Double(bytes) / 1e9
            if gb >= 10 { return String(format: "%.0f GB", gb) }
            if gb >= 1 { return String(format: "%.1f GB", gb) }
            return String(format: "%.0f MB", Double(bytes) / 1e6)
        }

        public static func partitionName(_ role: String) -> String {
            switch role {
            case "stub": return "SiliconForest launcher"
            case "boot": return "SiliconForest boot"
            case "root": return "SiliconForest system"
            default: return "SiliconForest \(role)"
            }
        }

        static let order = ["stub", "boot", "root"]
        private static func sorted(_ parts: [Part]) -> [Part] {
            parts.sorted { (order.firstIndex(of: $0.role) ?? 9) < (order.firstIndex(of: $1.role) ?? 9) }
        }

        public static func macOSName(_ volume: String) -> String { "macOS (\(volume))" }

        /// Install: macOS shrinks, then each new partition.
        public static func installBlocks(volume: String, macOSFrom: Int64, macOSTo: Int64, partitions: [Part]) -> [Block] {
            var b = [Block(name: macOSName(volume), change: "Shrinks from \(size(macOSFrom)) to \(size(macOSTo)).", detail: filesStay)]
            for p in sorted(partitions) { b.append(Block(name: partitionName(p.role), change: "New, \(size(p.bytes)).")) }
            return b
        }

        /// Removal: macOS grows back, then each SiliconForest partition is deleted.
        public static func removeBlocks(volume: String, macOSFrom: Int64, macOSTo: Int64, roles: [String]) -> [Block] {
            var b = [Block(name: macOSName(volume), change: "Grows back from \(size(macOSFrom)) to \(size(macOSTo)).", detail: filesStay)]
            for r in sorted(roles.map { Part(role: $0, bytes: 0) }) { b.append(Block(name: partitionName(r.role), change: "Deleted.")) }
            return b
        }

        /// The quiet footnote: release, signature, plan, and where it happens.
        public static func footnote(target: String, version: String, stage1: String?, plan: String, removal: Bool) -> String {
            if removal { return "Disk: \(target). Plan \(plan)." }
            let stage = stage1.map { " Stage 1 \($0) (pinned v2)." } ?? ""
            return "Release \(version), signature verified.\(stage) Disk: \(target). Plan \(plan)."
        }

        public static func installButton(gigabytes: Int64) -> String { "Erase \(gigabytes) GB and Install" }
        public static let removeButton = "Remove SiliconForest"

        /// The single typed confirmation.
        public static func typeName(_ volume: String) -> String { "Type the name of your macOS volume to confirm: \(volume)" }
        public static func typeNameAgain(_ volume: String) -> String { "To continue, confirm again. Type the name of your macOS volume: \(volume)" }
        public static let thenAdmin = "Then macOS asks an administrator to approve."
        public static let installAfter = "The installer writes a short-lived permission (2 hours) for exactly this plan and this disk."
        public static let removeIfStartup = "If the startup disk points at SiliconForest, it is set back to macOS first."
    }

    // MARK: 7. Approve the installer
    public enum Approve {

        public static let title = "Allow the installer to make changes"
        public static let lead = "macOS asks you to allow a helper. It can do only the steps you reviewed, and it is removed when the installation finishes."
        public static let steps = ["Click Open Login Items.", "Turn on SiliconForest Installer.", "Return to the installer. It continues automatically."]
        public static let open = "Open Login Items"
        public static let dryRunNote = "Dry run: no helper is installed. The installer continues on its own."
        public static let allowInBackground = "Allow in the Background"
        public static let developer = "SiliconForest contributors"
    }

    // MARK: 8. Preparing
    public enum Preparing {
        public static let title = "Preparing"
        public static let lead = "Your disk hasn't been touched. You can still cancel."
        public static func release(_ v: String) -> String { "SiliconForest \(v)" }
        public static let apple = "Apple startup files"
        public static let checking = "Checking every file"
        public static let verified = "verified"
        public static func progress(_ done: Int64, _ total: Int64) -> String { "\(Bytes.format(done)) of \(Bytes.format(total))" }
        public static let offline = "Waiting for a network connection. Downloads resume automatically."
    }

    // MARK: 9. Installing
    public enum Installing {
        public static let title = "Installing SiliconForest"
        public static let lead = "Keep your Mac open and plugged in."
        public static func phase(_ p: Phase) -> String {
            switch p {
            case .downloading: return "Downloading"
            case .verifying: return "Checking every file"
            case .makingRoom: return "Making room"
            case .startupVolume: return "Preparing the startup volume"
            case .writing: return "Writing SiliconForest"
            case .checking: return "Checking what was written"
            case .drivers: return "Adding drivers for your Mac"
            case .finalPreparations: return "Final preparations"
            case .removalStartup: return "Making macOS the startup disk"
            case .removalRemove: return "Removing SiliconForest"
            case .removalReturn: return "Returning the space to macOS"
            case .removalCheck: return "Checking the result"
            }
        }
        public static func doneIn(_ seconds: Double) -> String {
            seconds < 60 ? "Done" : "Done in \(Int((seconds / 60).rounded())) min"
        }
        public static func remaining(_ s: Double) -> String {
            if s < 60 { return "Less than a minute left" }
            let m = Int((s / 60).rounded())
            return m == 1 ? "About a minute left" : "About \(m) minutes left"
        }
        public static let whyNoStop = "Why can't I stop this?"
        public static let whyNoStopBody = "Stopping during this step could leave the disk partly changed. Let it finish; the installer can undo it afterwards."
        public static let stall = "macOS is still working on this. It can take a long time and may look stuck. Don't shut down."
        public static let plugIn = "Plug your Mac back in."
        public static let stop = "Stop"
        public static let showDetails = "Show Details"
    }

    // MARK: 10. Get ready for Recovery
    public enum Recovery {
        public static let title = "Approve SiliconForest in Recovery"
        public static let lead = "macOS requires you to approve a new operating system in Recovery. This takes about two minutes."
        public static func steps(holdCopy: String?, name: String) -> [String] {
            ["Your Mac will shut down.",
             "Wait for the screen to go dark, then 25 more seconds.",
             holdCopy ?? "Press and HOLD the power button until you see “Loading startup options”.",
             "Choose \(name), then click Continue.",
             "Enter your Mac password when asked."]
        }
        public static let practice = "Practice"
        public static let practiceHint = "Press and hold Space to feel the timing."
        public static let save = "Save These Steps"
        public static let note = "If you release the button too early, nothing changes. Try again."
        public static let primary = "Shut Down"
        public static let notNow = "Not Now"
        public static let dryRunPrimary = "Shut Down (simulated)"
        public static let holdLabel = "Hold"
        public static let loadingStartupOptions = "Loading startup options…"
    }

    // MARK: Part 2. In recoveryOS (SFRecovery; simulated in the dry run)
    public enum InRecovery {
        public static let title = "Finish installing SiliconForest"
        public static func lead(_ user: String) -> String { "Enter the password for \(user) to allow SiliconForest to start on this Mac." }
        public static let lowers = "This lowers security for SiliconForest only. macOS isn't affected."
        public static let allow = "Allow SiliconForest"
        public static let workingTitle = "Setting up SiliconForest"
        public static let working = ["Checking this recovery system", "Allowing SiliconForest to start", "Installing the startup software", "Finishing up"]
        public static let readyTitle = "Ready to restart"
        public static func readyBody(_ current: String) -> String {
            "Your Mac will start SiliconForest. If it doesn't start, turn your Mac off and on to return to \(current)."
        }
        public static let restart = "Restart"
        public static func countdown(_ s: Int) -> String { "Restarting in \(s) seconds" }
        public static let wait = "Wait"
        public static let simulatedBanner = "Simulated recoveryOS: the real step runs in SiliconForest Setup, an AppKit app on the startup volume."
        public static let password = "Password"
    }

    // MARK: Part 3. Back in macOS
    public enum Finish {
        public static let title = "SiliconForest is installed"
        public static let lead = "It started successfully on this Mac."
        public static let howToSwitch = "To switch: shut down, then hold the power button and choose."
        public static let makeDefault = "Make SiliconForest the Default"
        public static let removeAnyTime = "You can remove SiliconForest any time from this app."
        public static let verifying = "Reading the first-start receipt…"
        public static let switchLabel = "To switch:"
        public static let switchBody = "shut down, then hold the power button and choose."
        public static let partialTitle = "SiliconForest started, but didn't finish"
        public static func partialLead(_ stage: String) -> String { "It stopped at \(stage). macOS isn't affected." }
        public static let failedTitle = "SiliconForest didn't start"
        public static func failedLead(_ current: String) -> String { "Your Mac returned to \(current). Nothing in macOS was changed." }
    }

    // MARK: Part 4. Remove
    public enum Remove {
        public static let title = "Remove SiliconForest"
        public static let lead = "This deletes SiliconForest and everything stored in it, then gives the space back to macOS."
        public static let removedHeader = "Removed"
        public static let keptHeader = "Kept"
        public static func removed(_ b: Int64) -> [String] { ["SiliconForest (\(Bytes.format(b)))", "All your files in SiliconForest"] }
        public static let kept = ["macOS and your files", "Any other system on this Mac"]
        public static func growsBack(_ b: Int64) -> String { "macOS grows back to \(Bytes.format(b))." }
        public static let notContiguous = "Another partition sits between macOS and this space, so it will stay free for now."
        public static let confirmTitle = "Type SiliconForest to confirm"
        public static let confirmWord = "SiliconForest"
        public static let typePrefix = "Type "
        public static let typeSuffix = " to confirm"
        public static let willBeDeleted = "All your files in SiliconForest will be deleted."
        public static let primary = "Remove SiliconForest"
        public static let removingTitle = "Removing SiliconForest"
        public static let removingLead = "Keep your Mac open and plugged in."
        public static let removedTitle = "SiliconForest has been removed"
        public static func removedLead(_ b: Int64) -> String { "macOS is back to \(Bytes.format(b)). A small unused security record remains in the system area. It has no effect." }
        public static let notOursTitle = "This installation wasn't made by this installer"
        public static let notOursBody = "Nothing was removed."
    }

    // MARK: Part 5. Failure and rollback
    public enum Failure {
        public static let stoppedTitle = "The installation stopped"
        public static let nothingChanged = "No changes were made to your disk."
        public static let canUndo = "macOS and your files aren't affected. The installer can undo the changes it made."
        public static let undoChanges = "Undo Changes"
        public static let changesSoFar = "Changes made so far"
        public static let undoingTitle = "Undoing changes"
        public static let undoing = ["Removing the partial installation", "Returning space to macOS", "Checking the result"]
        public static let undoneTitle = "Changes undone"
        public static let undoneLead = "Your disk matches how it was before the installation."
        public static let attentionTitle = "The disk isn't in the expected state"
        public static let attentionLead = "The installer stopped because the disk isn't in the expected state. macOS should still start. Don't erase anything."
        public static let attentionAction = "Export diagnostics and open an issue on GitHub."
        public static let resizeRunningTitle = "macOS is still resizing your disk"
        public static let resizeRunningLead = "The installer reconnected to it. Don't shut down."
        public static let repairTitle = "macOS found a problem with your disk"
        public static let repairLead = "This was there before the installer ran. Repair it from Recovery with First Aid, then try again. Nothing was changed."
        public static let removalStoppedTitle = "Removal stopped partway"
        public static let removalStoppedLead = "Completed and remaining steps are listed below."
        public static let diagnosticsTitle = "Export diagnostics"
        public static let diagnosticsBody = "A text file you can review before sharing. It contains no passwords, serial numbers, names or personal files. Nothing is sent."
        public static let save = "Save…"
    }

    // MARK: Quit
    public enum Quit {
        public static let title = "Quit the installer?"
        public static let nothingChanged = "Nothing has been changed on your Mac."
        public static let busyTitle = "Stop after this step?"
        public static let busyBody = "The current step finishes first. The installer then lists what changed and can undo it."
        public static let busyConfirm = "Stop After This Step"
        public static let keepGoing = "Keep Going"
        public static let recoveryTitle = "Quit before the Recovery step?"
        public static let recoveryBody = "SiliconForest is installed but won't start until you finish the step in Recovery. Open the installer again for the instructions."
    }
}
