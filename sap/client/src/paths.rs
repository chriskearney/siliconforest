// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//! Path rules (design sections 4.3, 4.5, 7): safe absolute paths, protected and denied paths, and
//! resolution of a package path under a root directory without following a symlink out of it.

use std::path::{Path, PathBuf};

/// Absolute, no `..` or `.`, no empty components, no NUL or newline/tab, bounded.
pub fn is_safe(p: &str) -> bool {
    p.len() > 1
        && p.len() <= 1024
        && p.starts_with('/')
        && !p.ends_with('/')
        && !p.bytes().any(|b| b == 0 || b == b'\n' || b == b'\t' || b == b'\r')
        && p[1..].split('/').all(|c| !c.is_empty() && c != "." && c != ".." && c.len() <= 255)
}

/// Fixed-extent files whose physical offsets the installer reads back (PAYLOAD.md sections 3 and 4).
pub const PROTECTED: &[&str] = &["/private/var/db/sf-firmware-slot", "/private/var/db/sf-boot-receipt", "/var/db/sf-firmware-slot", "/var/db/sf-boot-receipt"];

/// Never writable by a package, whatever the manifest says (SAP's own state, devices).
pub const DENIED_PREFIXES: &[&str] =
    &["/private/var/db/sap", "/var/db/sap", "/private/var/lib/sap", "/var/lib/sap", "/private/var/cache/sap", "/var/cache/sap", "/dev", "/sf"];

pub fn under(p: &str, prefix: &str) -> bool {
    prefix == "/" || p == prefix || (p.starts_with(prefix) && p.as_bytes().get(prefix.len()) == Some(&b'/'))
}

pub fn is_protected(p: &str) -> bool {
    PROTECTED.contains(&p)
}

pub fn is_denied(p: &str) -> bool {
    DENIED_PREFIXES.iter().any(|d| under(p, d))
}

/// Join a safe package path onto a root.
pub fn join(root: &Path, p: &str) -> PathBuf {
    root.join(&p[1..])
}

/// The on-disk location of a package path's parent directory under `root`, following symlinks in the
/// parent chain as the running system would (an absolute target is taken relative to `root`), and
/// refusing any that leaves `root`. Darwin's `/var -> private/var` and `/etc -> private/etc` resolve.
pub fn resolve_parent(root: &Path, p: &str) -> Result<PathBuf, String> {
    let comps: Vec<&str> = p[1..].split('/').collect();
    let mut stack: Vec<String> = Vec::new();
    let mut queue: std::collections::VecDeque<String> = comps[..comps.len() - 1].iter().map(|s| s.to_string()).collect();
    let mut hops = 0;
    while let Some(c) = queue.pop_front() {
        match c.as_str() {
            "" | "." => continue,
            ".." => {
                if stack.pop().is_none() {
                    return Err(format!("{p}: a symlink in its path leaves the root"));
                }
                continue;
            }
            _ => {}
        }
        let mut here = root.to_path_buf();
        for s in &stack {
            here.push(s);
        }
        here.push(&c);
        match std::fs::symlink_metadata(&here) {
            Ok(m) if m.file_type().is_symlink() => {
                hops += 1;
                if hops > 32 {
                    return Err(format!("{p}: too many symlinks"));
                }
                let t = std::fs::read_link(&here).map_err(|e| format!("{p}: {e}"))?;
                let t = t.to_string_lossy().to_string();
                if t.starts_with('/') {
                    stack.clear();
                }
                let mut parts: std::collections::VecDeque<String> = t.split('/').map(|s| s.to_string()).collect();
                parts.append(&mut queue);
                queue = parts;
            }
            Ok(m) if !m.is_dir() => return Err(format!("{p}: {} is not a directory", here.display())),
            _ => stack.push(c),
        }
    }
    let mut out = root.to_path_buf();
    for s in &stack {
        out.push(s);
    }
    Ok(out)
}

/// The on-disk path for a package path: its resolved parent plus its own name (never followed).
pub fn resolve(root: &Path, p: &str) -> Result<PathBuf, String> {
    let name = p.rsplit('/').next().unwrap();
    Ok(resolve_parent(root, p)?.join(name))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn safety() {
        assert!(is_safe("/usr/bin/vim"));
        for bad in ["usr/bin", "/", "/a//b", "/a/./b", "/a/../b", "/a/", "/a\tb", "/a\0"] {
            assert!(!is_safe(bad), "{bad}");
        }
        assert!(is_denied("/var/db/sap/state.json") && is_denied("/dev/disk0") && !is_denied("/var/db/sapx"));
        assert!(is_protected("/private/var/db/sf-boot-receipt"));
    }
    #[test]
    fn resolution() {
        let d = std::env::temp_dir().join(format!("sap-paths-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(d.join("private/var/db")).unwrap();
        std::os::unix::fs::symlink("private/var", d.join("var")).unwrap();
        std::os::unix::fs::symlink("/private/etc", d.join("etc")).unwrap();
        std::fs::create_dir_all(d.join("private/etc")).unwrap();
        std::os::unix::fs::symlink("../../..", d.join("private/var/up")).unwrap();
        assert_eq!(resolve(&d, "/var/db/x").unwrap(), d.join("private/var/db/x"));
        assert_eq!(resolve(&d, "/etc/vimrc").unwrap(), d.join("private/etc/vimrc"));
        assert!(resolve(&d, "/var/up/x/y").is_err());
        let _ = std::fs::remove_dir_all(&d);
    }
}
