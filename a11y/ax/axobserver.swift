
import Foundation
import AppKit
import ApplicationServices

let socketPath = "/tmp/com.siliconforest.axuiserver"

func sendJSON(_ dict: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: dict),
          let msg = String(data: data, encoding: .utf8) else { return }
    let full = msg + "\n"
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return }
    defer { close(fd) }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        socketPath.withCString { src in _ = strcpy(UnsafeMutablePointer(OpaquePointer(ptr)), src) }
    }
    let r = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard r == 0 else { return }
    _ = full.withCString { write(fd, $0, strlen($0)) }
}

func axStr(_ elem: AXUIElement, _ attr: String) -> String? {
    var val: CFTypeRef?
    guard AXUIElementCopyAttributeValue(elem, attr as CFString, &val) == .success else { return nil }
    return val as? String
}

var currentObserver: AXObserver?
var currentPid: pid_t = 0

let axCB: AXObserverCallback = { _, elem, notif, _ in
    let role  = { var v: CFTypeRef?; AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &v); return v as? String ?? "AXUnknown" }()
    let title = { var v: CFTypeRef?; AXUIElementCopyAttributeValue(elem, kAXTitleAttribute as CFString, &v); return v as? String ?? "" }()
    let desc  = { var v: CFTypeRef?; AXUIElementCopyAttributeValue(elem, kAXDescriptionAttribute as CFString, &v); return v as? String ?? "" }()
    let value = { var v: CFTypeRef?; AXUIElementCopyAttributeValue(elem, kAXValueAttribute as CFString, &v); return v as? String ?? "" }()
    let label = title.isEmpty ? desc : title
    var pid: pid_t = 0
    AXUIElementGetPid(elem, &pid)
    print("[AX] \(role) | \(label) | \(value)", terminator: "\n")
    fflush(stdout)
    sendJSON(["type":"focus_changed","pid":pid,"role":role,"label":label,"value":value,"frame":[0,0,0,0]])
}

func attach(_ app: NSRunningApplication) {
    let pid = app.processIdentifier
    guard pid != currentPid else { return }
    currentPid = pid
    let name = app.localizedName ?? ""
    print("[WIN] \(name)", terminator: "\n"); fflush(stdout)
    sendJSON(["type":"window_activated","pid":pid,"title":name])
    var obs: AXObserver?
    guard AXObserverCreate(pid, axCB, &obs) == .success, let observer = obs else { return }
    let appElem = AXUIElementCreateApplication(pid)
    for n in [kAXFocusedUIElementChangedNotification, kAXValueChangedNotification] {
        AXObserverAddNotification(observer, appElem, n as CFString, nil)
    }
    CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
    currentObserver = observer
    // Report current focused element
    var focused: CFTypeRef?
    if AXUIElementCopyAttributeValue(appElem, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
       let f = focused {
        let fElem = f as! AXUIElement
        let r = { var v: CFTypeRef?; AXUIElementCopyAttributeValue(fElem, kAXRoleAttribute as CFString, &v); return v as? String ?? "AXUnknown" }()
        let t = { var v: CFTypeRef?; AXUIElementCopyAttributeValue(fElem, kAXTitleAttribute as CFString, &v); return v as? String ?? "" }()
        print("[AX] initial: \(r) | \(t)", terminator: "\n"); fflush(stdout)
        sendJSON(["type":"focus_changed","pid":pid,"role":r,"label":t,"value":"","frame":[0,0,0,0]])
    }
}

class Watcher: NSObject {
    @objc func activated(_ n: Notification) {
        guard let a = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        attach(a)
    }
}
let w = Watcher()
NSWorkspace.shared.notificationCenter.addObserver(w, selector: #selector(Watcher.activated(_:)),
    name: NSWorkspace.didActivateApplicationNotification, object: nil)
if let active = NSWorkspace.shared.frontmostApplication { attach(active) }

print("SiliconForest AX Observer lauft — forwarding to \(socketPath)")
RunLoop.main.run()
