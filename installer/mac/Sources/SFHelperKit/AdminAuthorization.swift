import Foundation
import Security

/// The administrator's approval for one write (preview6): the app asks the system for the admin right
/// (the standard macOS password / Touch ID sheet; the installer never sees the password) and hands the
/// helper the authorization's external form. The helper re-checks the same right on it without any UI:
/// it is granted only if an administrator just authenticated in that authorization.
public enum AdminAuthorization {
    public static let right = "system.privilege.admin"

    /// App side. Prompts; throws if the person cancels or isn't an administrator. Keep the result alive
    /// until the helper has answered: the authorization ends when it is released.
    public static func request(prompt: String) throws -> AdminApproval {
        var ref: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &ref) == errAuthorizationSuccess, let ref else { throw HelperError.make(.refused, "couldn't start an authorization") }
        let holder = AdminApproval(ref)
        let status: OSStatus = right.withCString { name in
            var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { ip in
                var rights = AuthorizationRights(count: 1, items: ip)
                return prompt.withCString { p in
                    var env = AuthorizationItem(name: kAuthorizationEnvironmentPrompt, valueLength: strlen(p), value: UnsafeMutableRawPointer(mutating: p), flags: 0)
                    return withUnsafeMutablePointer(to: &env) { ep in
                        var environment = AuthorizationEnvironment(count: 1, items: ep)
                        return AuthorizationCopyRights(ref, &rights, &environment, [.interactionAllowed, .extendRights, .preAuthorize], nil)
                    }
                }
            }
        }
        guard status == errAuthorizationSuccess else {
            _ = holder
            throw HelperError.make(.refused, status == errAuthorizationCanceled ? "the administrator approval was cancelled" : "an administrator didn't approve (\(status))")
        }
        var ext = AuthorizationExternalForm()
        guard AuthorizationMakeExternalForm(ref, &ext) == errAuthorizationSuccess else { throw HelperError.make(.refused, "couldn't pass the approval to the helper") }
        holder.externalForm = withUnsafeBytes(of: &ext) { Data($0) }
        return holder
    }
}

/// One administrator approval, alive until released (then its rights are destroyed).
public final class AdminApproval: @unchecked Sendable {
    private let ref: AuthorizationRef
    public fileprivate(set) var externalForm = Data()
    init(_ ref: AuthorizationRef) { self.ref = ref }
    deinit { AuthorizationFree(ref, [.destroyRights]) }
}

/// Helper side. Tests inject their own.
public struct AdminCheck: Sendable {
    public var verify: @Sendable (Data) -> Bool
    public init(verify: @escaping @Sendable (Data) -> Bool) { self.verify = verify }

    /// Re-checks the admin right on the app's authorization, without interaction.
    public static let system = AdminCheck { data in
        guard data.count == MemoryLayout<AuthorizationExternalForm>.size else { return false }
        var ext = AuthorizationExternalForm()
        withUnsafeMutableBytes(of: &ext) { _ = data.copyBytes(to: $0) }
        var ref: AuthorizationRef?
        guard AuthorizationCreateFromExternalForm(&ext, &ref) == errAuthorizationSuccess, let ref else { return false }
        defer { AuthorizationFree(ref, []) }
        return AdminAuthorization.right.withCString { name in
            var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { ip in
                var rights = AuthorizationRights(count: 1, items: ip)
                return AuthorizationCopyRights(ref, &rights, nil, [.extendRights], nil) == errAuthorizationSuccess
            }
        }
    }

    /// Nobody is ever approved (the default for anything that isn't the shipped helper).
    public static let never = AdminCheck { _ in false }
}
