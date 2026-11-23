import Foundation
import SFInstallKit

// SFHelper: the privileged half of the installer (DESIGN §6). PLACEHOLDER.
//
// In this phase there is no helper: no XPC listener, no disk access, nothing privileged. The app's
// dry run simulates every step; its read-only mode only reads. When this is built it will:
//   - listen on the Mach service `HelperIdentity.machService`, accepting only clients that satisfy the
//     pinned code-signing requirement (team ID + `org.siliconforest.installer` + minimum build);
//   - implement `SFHelperProtocol` (verbs, no "run this command");
//   - pass every change through the gate (ENGINE §6) and the journal (ENGINE §9), with the resize
//     supervisor (ENGINE §8);
//   - become the `PrivilegedExecutor` the real disk backend uses.
// It can only be registered with SMAppService from a Developer ID-signed app.

FileHandle.standardError.write(Data("SFHelper (\(HelperIdentity.signingIdentifier)) is a placeholder in this build: no disk access.\n".utf8))
exit(1)
