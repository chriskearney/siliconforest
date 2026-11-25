// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//! The machine SAP operates on (design section 7): its root, configuration, state, installed database,
//! trust anchor and boot partition.

use crate::error::{Code, Context, Error, Result};
use crate::json::Value;
use crate::sshsig::PublicKey;
use crate::tsv::{self, Entry};
use crate::{bail, util};
use std::fs;
use std::path::{Path, PathBuf};

pub struct Options {
    pub root: PathBuf,
    pub sfboot: Option<PathBuf>,
    pub manifest_url: Option<String>,
    pub channel: Option<String>,
    pub trust_anchor: Option<PathBuf>,
    pub offline: bool,
    pub json: bool,
    pub verbose: bool,
}

pub struct Config {
    pub channel: String,
    pub manifest_url: Option<String>,
    pub sfboot: Option<PathBuf>,
    pub boot_backend: String,
    /// sf-bootslot (abboot) for boot_backend slots; default boot::DEFAULT_TOOL.
    pub bootslot_tool: Option<String>,
}

pub struct Sys {
    pub root: PathBuf,
    pub image_mode: bool,
    pub db: PathBuf,
    pub cache: PathBuf,
    pub lib: PathBuf,
    pub sfboot: Option<PathBuf>,
    pub cfg: Config,
    pub opts: Options,
}

#[derive(Clone, Debug, Default)]
pub struct State {
    pub highest_sequence: i64,
    pub manifest_sha256: Option<String>,
    pub held: Vec<String>,
    pub lineage: Option<String>,
    pub anchor_version: i64,
}

#[derive(Clone, Debug)]
pub struct Installed {
    pub name: String,
    pub version: String,
    pub kind: String,
    pub txn: String,
    pub record: Value,
    pub files: Vec<Entry>,
}

impl Installed {
    pub fn config_files(&self) -> Vec<String> {
        self.record.get("config_files").and_then(|v| v.as_array()).map(|a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect()).unwrap_or_default()
    }
    pub fn target(&self) -> &str {
        self.record.get("target").and_then(|t| t.as_str()).unwrap_or("root")
    }
}

pub struct Anchor {
    pub version: i64,
    pub keys: Vec<PublicKey>,
    pub source: String,
    pub warnings: Vec<String>,
}

fn parse_config(text: &str) -> Result<Config> {
    let mut c = Config { channel: "stable".into(), manifest_url: None, sfboot: None, boot_backend: "auto".into(), bootslot_tool: None };
    for (i, line) in text.lines().enumerate() {
        let l = line.trim();
        if l.is_empty() || l.starts_with('#') {
            continue;
        }
        let (k, v) = l.split_once('=').ok_or_else(|| Error::new(Code::Failure, format!("sap.conf line {}: expected key = value", i + 1)))?;
        let (k, v) = (k.trim(), v.trim().to_string());
        match k {
            "channel" => c.channel = v,
            "manifest_url" => c.manifest_url = Some(v),
            "sfboot" => c.sfboot = Some(PathBuf::from(v)),
            "boot_backend" => c.boot_backend = v,
            "bootslot_tool" => c.bootslot_tool = Some(v),
            "mirrors" => {}
            _ => {} // unknown keys are ignored, like the manifest's
        }
    }
    Ok(c)
}

impl Sys {
    pub fn open(opts: Options) -> Result<Sys> {
        let root = opts.root.clone();
        let image_mode = root != Path::new("/");
        if !root.is_dir() {
            bail!(Failure, "root {} is not a directory", root.display());
        }
        let conf_path = crate::paths::resolve(&root, "/etc/sap.conf").unwrap_or_else(|_| root.join("etc/sap.conf"));
        let mut cfg = match fs::read_to_string(&conf_path) {
            Ok(t) => parse_config(&t)?,
            Err(_) => parse_config("")?,
        };
        if let Some(c) = &opts.channel {
            cfg.channel = c.clone();
        }
        if cfg.channel != "stable" {
            bail!(Verify, "this SAP follows only the stable channel (got {:?})", cfg.channel);
        }
        if let Some(u) = &opts.manifest_url {
            cfg.manifest_url = Some(u.clone());
        }
        let sfboot = opts
            .sfboot
            .clone()
            .or_else(|| cfg.sfboot.as_ref().map(|p| if image_mode && p.is_absolute() { root.join(p.strip_prefix("/").unwrap()) } else { p.clone() }));
        if opts.trust_anchor.is_some() && !image_mode {
            bail!(Failure, "--trust-anchor is only for images (--root); a running system trusts its boot-chain anchor");
        }
        Ok(Sys {
            db: root.join("private/var/db/sap"),
            cache: root.join("private/var/cache/sap"),
            lib: root.join("private/var/lib/sap"),
            root,
            image_mode,
            sfboot,
            cfg,
            opts,
        })
    }

    pub fn installed_dir(&self) -> PathBuf {
        self.db.join("installed")
    }
    pub fn journal_dir(&self) -> PathBuf {
        self.db.join("journal")
    }
    pub fn state_path(&self) -> PathBuf {
        self.db.join("state.json")
    }

    pub fn require_writer(&self) -> Result<()> {
        if util::is_root() {
            return Ok(());
        }
        #[cfg(feature = "testing")]
        if self.image_mode && std::env::var("SAP_ALLOW_NONROOT").is_ok() {
            return Ok(());
        }
        bail!(Failure, "this command changes the system and must run as root")
    }

    /// Writing commands hold an exclusive lock on the database for their whole run.
    pub fn lock(&self) -> Result<fs::File> {
        fs::create_dir_all(&self.db).ctx(|| format!("create {}", self.db.display()))?;
        let f = fs::OpenOptions::new().create(true).truncate(false).write(true).open(self.db.join("lock"))?;
        use std::os::unix::io::AsRawFd;
        if unsafe { libc::flock(f.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
            bail!(Failure, "another sap is running");
        }
        Ok(f)
    }

    // ---- state ----

    pub fn state(&self) -> Result<State> {
        let p = self.state_path();
        let b = match fs::read(&p) {
            Ok(b) => b,
            Err(_) => return Ok(State::default()),
        };
        let v = crate::json::parse(&b).map_err(|e| Error::new(Code::Failure, format!("state.json: {e}")))?;
        Ok(State {
            highest_sequence: v.get("highest_sequence").and_then(|x| x.as_i64()).unwrap_or(0),
            manifest_sha256: v.get("manifest_sha256").and_then(|x| x.as_str()).map(String::from),
            held: v.get("held").and_then(|x| x.as_array()).map(|a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect()).unwrap_or_default(),
            lineage: v.get("lineage").and_then(|x| x.as_str()).map(String::from),
            anchor_version: v.get("anchor_version").and_then(|x| x.as_i64()).unwrap_or(0),
        })
    }

    pub fn write_state(&self, s: &State) -> Result<()> {
        let opt = |x: &Option<String>| x.as_ref().map(|s| Value::str(s.clone())).unwrap_or(Value::Null);
        let v = Value::obj(vec![
            ("schema", Value::str("sap-state/1")),
            ("highest_sequence", Value::Int(s.highest_sequence)),
            ("manifest_sha256", opt(&s.manifest_sha256)),
            ("held", Value::Array(s.held.iter().map(|h| Value::str(h.clone())).collect())),
            ("lineage", opt(&s.lineage)),
            ("anchor_version", Value::Int(s.anchor_version)),
        ]);
        util::write_atomic(&self.state_path(), v.to_string_pretty().as_bytes(), 0o644)
    }

    // ---- installed database ----

    pub fn installed(&self) -> Result<Vec<Installed>> {
        let dir = self.installed_dir();
        let mut out = Vec::new();
        let rd = match fs::read_dir(&dir) {
            Ok(r) => r,
            Err(_) => return Ok(out),
        };
        let mut names: Vec<String> =
            rd.filter_map(|e| e.ok()).map(|e| e.file_name().to_string_lossy().to_string()).filter(|n| n.ends_with(".json") && !n.starts_with('.')).collect();
        names.sort();
        for n in names {
            let b = fs::read(dir.join(&n))?;
            let v = crate::json::parse(&b).map_err(|e| Error::new(Code::Failure, format!("installed/{n}: {e}")))?;
            let name = v.get("name").and_then(|x| x.as_str()).unwrap_or("").to_string();
            let files = match fs::read_to_string(dir.join(format!("{name}.files.tsv"))) {
                Ok(t) => tsv::parse(&t).map_err(|e| Error::new(Code::Failure, format!("installed/{name}.files.tsv: {e}")))?,
                Err(_) => Vec::new(),
            };
            out.push(Installed {
                version: v.get("version").and_then(|x| x.as_str()).unwrap_or("").into(),
                kind: v.get("kind").and_then(|x| x.as_str()).unwrap_or("").into(),
                txn: v.get("txn").and_then(|x| x.as_str()).unwrap_or("").into(),
                record: v.get("record").cloned().unwrap_or(Value::Null),
                name,
                files,
            });
        }
        Ok(out)
    }

    /// The database entry for a package, as bytes, for the transaction to write.
    pub fn db_entry(name: &str, version: &str, kind: &str, txn: &str, record: &Value) -> Vec<u8> {
        Value::obj(vec![
            ("schema", Value::str("sap-installed/1")),
            ("name", Value::str(name)),
            ("version", Value::str(version)),
            ("kind", Value::str(kind)),
            ("txn", Value::str(txn)),
            ("record", record.clone()),
        ])
        .to_string_pretty()
        .into_bytes()
    }

    // ---- trust anchor (design section 8.2) ----

    pub fn anchor(&self) -> Result<Anchor> {
        let builtin = builtin_keys();
        let mut warnings = Vec::new();
        let (version, keys, source) = if let Some(p) = &self.opts.trust_anchor {
            let t = fs::read_to_string(p).ctx(|| format!("read {}", p.display()))?;
            let (v, k) = parse_key_list(&t);
            (v, k, format!("file {}", p.display()))
        } else if let Some(tok) = self.bootargs_token()? {
            let (v, k) = parse_trust_token(&tok).ok_or_else(|| Error::new(Code::Verify, "the boot-chain trust anchor (sf_trust=) is malformed".to_string()))?;
            (v, k, "boot chain (sf_trust)".into())
        } else {
            warnings.push("no boot-chain trust anchor (sf_trust=) on this machine; using the keys compiled into sap (design 8.2 option A, interim)".into());
            let (v, k) = builtin.clone();
            (v, k, "compiled-in".into())
        };
        if keys.is_empty() {
            bail!(Verify, "the trust anchor ({source}) holds no keys");
        }
        if source != "compiled-in" && !builtin.1.iter().all(|k| keys.contains(k)) {
            warnings.push(format!("the trust anchor ({source}) differs from the keys sap was built with"));
        }
        Ok(Anchor { version, keys, source, warnings })
    }

    /// `sf_trust=` from the running kernel's boot arguments, or in image mode from the image's
    /// sf/kernel.bin CONFIG record.
    fn bootargs_token(&self) -> Result<Option<String>> {
        let args = if self.image_mode {
            // With A/B slots, the default slot's kernel is what the machine boots with.
            let rel = match crate::boot::backend(self) {
                Ok(crate::boot::Backend::Slots) => {
                    crate::boot::Tool::new(self).and_then(|t| t.status()).map(|st| crate::boot::kernel_path(st.default)).unwrap_or("sf/kernel.bin")
                }
                _ => "sf/kernel.bin",
            };
            match self.sfboot.as_ref().map(|b| b.join(rel)) {
                Some(p) if p.exists() => crate::kc::read_bootargs(&fs::read(&p)?).ok(),
                _ => None,
            }
        } else {
            kern_bootargs()
        };
        Ok(args.and_then(|a| a.split_whitespace().find_map(|w| w.strip_prefix("sf_trust=").map(String::from))))
    }
}

pub fn builtin_keys() -> (i64, Vec<PublicKey>) {
    parse_key_list(include_str!("../../trust/release-keys"))
}

/// allowed_signers or authorized_keys style lines; `# version N` sets the anchor version (default 1).
pub fn parse_key_list(t: &str) -> (i64, Vec<PublicKey>) {
    let mut v = 1;
    let mut keys = Vec::new();
    for l in t.lines() {
        if let Some(n) = l.trim().strip_prefix("# version ") {
            v = n.trim().parse().unwrap_or(1);
        } else if !l.trim_start().starts_with('#') {
            if let Some(k) = PublicKey::from_openssh_line(l) {
                keys.push(k);
            }
        }
    }
    (v, keys)
}

/// `sf_trust=<version>:<base64 key>,<base64 key>` (raw 32-byte Ed25519 keys, unpadded base64).
pub fn parse_trust_token(tok: &str) -> Option<(i64, Vec<PublicKey>)> {
    let (v, ks) = tok.split_once(':')?;
    let v: i64 = v.parse().ok()?;
    let mut keys = Vec::new();
    for k in ks.split(',') {
        let b = crate::b64::decode(k)?;
        keys.push(PublicKey(b.try_into().ok()?));
    }
    Some((v, keys))
}

pub fn trust_token(version: i64, keys: &[PublicKey]) -> String {
    format!("sf_trust={version}:{}", keys.iter().map(|k| crate::b64::encode(&k.0, false)).collect::<Vec<_>>().join(","))
}

#[cfg(target_os = "macos")]
fn kern_bootargs() -> Option<String> {
    let name = std::ffi::CString::new("kern.bootargs").ok()?;
    let mut len: libc::size_t = 0;
    unsafe {
        if libc::sysctlbyname(name.as_ptr(), std::ptr::null_mut(), &mut len, std::ptr::null_mut(), 0) != 0 || len == 0 {
            return None;
        }
        let mut buf = vec![0u8; len];
        if libc::sysctlbyname(name.as_ptr(), buf.as_mut_ptr() as *mut libc::c_void, &mut len, std::ptr::null_mut(), 0) != 0 {
            return None;
        }
        buf.truncate(len);
        while buf.last() == Some(&0) {
            buf.pop();
        }
        String::from_utf8(buf).ok()
    }
}

#[cfg(not(target_os = "macos"))]
fn kern_bootargs() -> Option<String> {
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn token_roundtrip() {
        let (_, keys) = builtin_keys();
        let t = trust_token(3, &keys);
        assert!(t.len() < 120, "{t}");
        let (v, k) = parse_trust_token(t.strip_prefix("sf_trust=").unwrap()).unwrap();
        assert_eq!((v, k), (3, keys));
        assert!(parse_trust_token("x:abc").is_none());
    }
}
