import Foundation
import Security
import SFIdentity

/// Who may talk to the helper (DESIGN §6.2): the signing requirement, enforced by the system on
/// the connection before any message is delivered, and a minimum client build, because a signing
/// requirement alone admits older signed builds.
public struct ConnectionPolicy: Sendable {
    /// A code-signing requirement the client must satisfy. Production: the app's Developer ID
    /// requirement (`SigningIdentity.appRequirement`). Tests pin the test binary's own requirement.
    public var clientRequirement: String
    public var minimumClientBuild: Int

    public init(clientRequirement: String = SigningIdentity.appRequirement, minimumClientBuild: Int = 1) {
        self.clientRequirement = clientRequirement; self.minimumClientBuild = minimumClientBuild
    }
}

public enum CodeIdentity {
    /// This process's designated requirement as text ("cdhash H\"…\"" for an ad hoc signature).
    public static func ownDesignatedRequirement() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var req: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &req) == errSecSuccess, let req else { return nil }
        var text: CFString?
        guard SecRequirementCopyString(req, [], &text) == errSecSuccess else { return nil }
        return text as String?
    }

    /// True if the requirement text compiles (a typo must fail the build's tests, not the field).
    public static func requirementCompiles(_ text: String) -> Bool {
        var req: SecRequirement?
        return SecRequirementCreateWithString(text as CFString, [], &req) == errSecSuccess
    }

    /// CFBundleVersion of a running process's signed Info.plist; 0 when it has none (a bare tool).
    public static func bundleBuild(pid: pid_t) -> Int {
        var code: SecCode?
        let attrs = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess, let code else { return 0 }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return 0 }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any], let plist = dict[kSecCodeInfoPList as String] as? [String: Any],
              let v = plist["CFBundleVersion"] as? String else { return 0 }
        return Int(v) ?? 0
    }
}

/// The owner's password while the helper needs it: locked out of swap, zeroed on release, never
/// logged or journaled (DESIGN §14.9).
public final class SecureBytes: @unchecked Sendable {
    private var buffer: UnsafeMutableRawBufferPointer
    public private(set) var isWiped = false

    public init(_ data: Data) {
        buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: max(1, data.count), alignment: 16)
        mlock(buffer.baseAddress, buffer.count)
        data.copyBytes(to: buffer)
        count = data.count
    }
    public let count: Int

    /// Calls `body` with the bytes; the caller writes them to a child's stdin or PTY and nowhere else.
    public func withBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try body(UnsafeRawBufferPointer(rebasing: buffer[0..<count]))
    }

    public func wipe() {
        guard !isWiped else { return }
        memset_s(buffer.baseAddress, buffer.count, 0, buffer.count)
        munlock(buffer.baseAddress, buffer.count)
        isWiped = true
    }

    /// For tests: every byte is zero.
    public var isZeroed: Bool { buffer.allSatisfy { $0 == 0 } }

    deinit { wipe(); buffer.deallocate() }
}

/// The helper lives only while needed (D2): it exits when no client is connected and no job is
/// running, after `idleTimeout`. launchd starts it again on the next connection.
public final class HelperLifecycle: @unchecked Sendable {
    private let lock = NSLock()
    private var connections = 0, running = 0
    private var pending: DispatchWorkItem?
    public let idleTimeout: TimeInterval
    private let onIdle: @Sendable () -> Void

    public init(idleTimeout: TimeInterval = 30, onIdle: @escaping @Sendable () -> Void = { exit(0) }) {
        self.idleTimeout = idleTimeout; self.onIdle = onIdle
    }

    public func connectionStarted() { change { $0.connections += 1 } }
    public func connectionEnded() { change { $0.connections -= 1 } }
    public func jobStarted() { change { $0.running += 1 } }
    public func jobEnded() { change { $0.running -= 1 } }

    private func change(_ f: (HelperLifecycle) -> Void) {
        lock.lock()
        f(self)
        pending?.cancel(); pending = nil
        if connections <= 0 && running <= 0 {
            let item = DispatchWorkItem { [onIdle] in onIdle() }
            pending = item
            DispatchQueue.global().asyncAfter(deadline: .now() + idleTimeout, execute: item)
        }
        lock.unlock()
    }
}
