import AppKit
import SFRecoveryKit

// SFRecovery: SiliconForest Setup in recoveryOS (DESIGN §7). AppKit only; launched by sf-launcher.
//
// Exit codes for sf-launcher: 0 finished (restarting), 75 the person chose Shut Down. Anything
// else, including a crash or a dyld failure, makes sf-launcher open Terminal with sf-step2.sh.
//
//   SFRecovery                               recoveryOS: the setup screen
//   SFRecovery --snapshot OUT.png [--size 1512x982@2] [--stage password|working|failed|not-recovery]
//                                            render the screen offscreen to PNG (no window)

let args = CommandLine.arguments
func arg(_ name: String) -> String? { args.firstIndex(of: name).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }

if let out = arg("--snapshot") {
    let spec = (arg("--size") ?? "1512x982@2").split(separator: "@")
    let wh = spec[0].split(separator: "x").compactMap { Double($0) }
    let scale = spec.count > 1 ? CGFloat(Double(spec[1]) ?? 2) : 2
    let size = NSSize(width: wh.first ?? 1512, height: wh.last ?? 982)
    _ = NSApplication.shared
    let v = RecoveryView(frame: NSRect(origin: .zero, size: size))
    v.appearance = NSAppearance(named: .darkAqua)
    switch arg("--stage") ?? "password" {
    case "working": v.stage = .working(step: 2)
    case "failed": v.stage = .failed("That password didn't work. Try again.")
    case "not-recovery": v.stage = .notRecovery
    default: v.stage = .password; v.password.stringValue = "correct horse"
    }
    v.layoutSubtreeIfNeeded()
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    v.cacheDisplay(in: v.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    do { try png.write(to: URL(fileURLWithPath: out)); print("✓ \(out)"); exit(0) } catch { print("✗ \(error)"); exit(1) }
}

// The app proper. Outside recoveryOS it explains and changes nothing.
let exe = URL(fileURLWithPath: args[0]).resolvingSymlinksInPath()
let setup = RecoverySetup(volume: RecoverySetup.volume(forExecutable: exe))

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let view: RecoveryView
    let setup: RecoverySetup
    init(setup: RecoverySetup) {
        self.setup = setup
        view = RecoveryView(frame: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 800))
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        let frame = NSScreen.main?.frame ?? view.frame
        // Spike S3 decides full screen in recoveryOS; until then a borderless window over the display.
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.appearance = NSAppearance(named: .darkAqua)
        window.makeKeyAndOrderFront(nil)
        buildMenu()
        view.onShutDown = { exit(75) }
        do { _ = try setup.gate() } catch {
            view.stage = FileManager.default.fileExists(atPath: "/System/Installation/CDIS") ? .failed(error.localizedDescription) : .notRecovery
            return
        }
        view.onContinue = { [weak self] pw in self?.finish(pw) }
        window.makeFirstResponder(view.password)
    }

    func finish(_ password: Data) {
        view.stage = .working(step: 1)
        DispatchQueue.global().async { [setup] in
            var pw = password
            defer { pw.resetBytes(in: 0..<pw.count) }
            do {
                _ = try setup.allowSiliconForest(password: pw)
                DispatchQueue.main.async { self.view.stage = .working(step: 2) }
                _ = try setup.installBootObject(password: pw)
                DispatchQueue.main.async { self.view.stage = .working(step: 3) }
                try setup.cleanUpMarkers()
                try setup.setNextBoot()
                DispatchQueue.main.async { exit(0) }   // sf-launcher returns; the restart follows
            } catch {
                DispatchQueue.main.async { self.view.stage = .failed(error.localizedDescription) }
            }
        }
    }

    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appMenu.addItem(withTitle: "Shut Down", action: #selector(shutDown), keyEquivalent: "q"); appItem.submenu = appMenu
        let utilItem = NSMenuItem(); main.addItem(utilItem)
        let util = NSMenu(title: "Utilities")
        util.addItem(withTitle: "Terminal", action: #selector(openTerminal), keyEquivalent: "")
        util.addItem(withTitle: "Show Details", action: #selector(showDetails), keyEquivalent: "")
        util.addItem(withTitle: "Shut Down", action: #selector(shutDown), keyEquivalent: "")
        utilItem.submenu = util
        NSApp.mainMenu = main
    }
    @objc func shutDown() { exit(75) }
    /// Leaving with a non-zero, non-75 status sends sf-launcher to Terminal + sf-step2.sh.
    @objc func openTerminal() { exit(70) }
    @objc func showDetails() {
        let a = NSAlert(); a.messageText = "Details"; a.informativeText = setup.log.suffix(6).joined(separator: "\n\n"); a.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate(setup: setup)
app.delegate = delegate
app.setActivationPolicy(.regular)
if !FileManager.default.fileExists(atPath: "/System/Installation/CDIS") {
    // Outside recoveryOS: never open a window, never touch anything.
    FileHandle.standardError.write(Data("SiliconForest Setup runs only in SiliconForest's recoveryOS. Nothing was changed.\n".utf8))
    exit(1)
}
app.run()
