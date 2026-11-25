// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//! The signed manifest, schema `siliconforest-update/1` (design section 6), and package records,
//! schema `siliconforest-package/1` (section 4.2). Parsed only after the signature verified.

use crate::error::{Code, Error, Result};
use crate::json::Value;
use crate::tsv::is_hex64;
use crate::version::{valid_name, valid_version, Constraint};
use crate::{bail, paths, util};

pub const SCHEMA: &str = "siliconforest-update/1";
pub const SCHEMA_PREFIX: &str = "siliconforest-update/";
pub const RECORD_SCHEMA: &str = "siliconforest-package/1";
pub const MAX_MANIFEST: u64 = 4 << 20;
pub const MAX_RECORD: u64 = 4 << 20;
pub const MAX_FILELIST: u64 = 64 << 20;
pub const SAP_VERSION: &str = env!("CARGO_PKG_VERSION");

/// Names this client understands when a manifest lists them in `critical` (fields and package kinds).
pub const UNDERSTOOD: &[&str] = &[
    "schema",
    "channel",
    "release",
    "sequence",
    "issued",
    "expires",
    "min_sap",
    "critical",
    "base",
    "signing_key",
    "packages",
    "removed",
    "allowed_prefixes",
    "trust",
    "components",
    "base",
    "files",
    "kc-input",
    "kc-recipe",
    "boot-stage2",
];
pub const KINDS: &[&str] = &["base", "files", "kc-input", "kc-recipe", "boot-stage2"];

#[derive(Clone, Debug, PartialEq)]
pub struct Dep {
    pub name: String,
    pub constraint: Option<Constraint>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Pin {
    pub url: String,
    pub sha256: String,
}

#[derive(Clone, Debug)]
pub struct IndexEntry {
    pub name: String,
    pub version: String,
    pub kind: String,
    pub depends: Vec<Dep>,
    pub activate: String,
    pub bytes: i64,
    pub record: Pin,
    pub payload: Option<Pin>,
    pub components: Vec<(String, Value)>,
}

#[derive(Clone, Debug)]
pub struct Trust {
    pub version: i64,
    pub keys: Vec<crate::sshsig::PublicKey>,
}

#[derive(Clone, Debug)]
pub struct Manifest {
    pub channel: String,
    pub release: String,
    pub sequence: i64,
    pub issued: i64,
    pub expires: i64,
    pub min_sap: Option<String>,
    pub base_sums: Option<String>,
    pub packages: Vec<IndexEntry>,
    pub skipped_kinds: Vec<(String, String)>,
    pub removed: Vec<String>,
    pub allowed_prefixes: Vec<String>,
    pub trust: Option<Trust>,
    pub sha256: String,
}

fn verr(msg: String) -> Error {
    Error::new(Code::Verify, msg)
}

pub(crate) fn req_str<'a>(o: &'a Value, k: &str, what: &str) -> Result<&'a str> {
    o.get(k).and_then(|v| v.as_str()).ok_or_else(|| verr(format!("{what}: {k} is missing or not a string")))
}

pub(crate) fn req_int(o: &Value, k: &str, what: &str) -> Result<i64> {
    o.get(k).and_then(|v| v.as_i64()).ok_or_else(|| verr(format!("{what}: {k} is missing or not an integer")))
}

fn opt_array<'a>(o: &'a Value, k: &str, what: &str) -> Result<&'a [Value]> {
    match o.get(k) {
        None | Some(Value::Null) => Ok(&[]),
        Some(Value::Array(a)) => Ok(a),
        _ => Err(verr(format!("{what}: {k} is not an array"))),
    }
}

fn str_list(o: &Value, k: &str, what: &str) -> Result<Vec<String>> {
    opt_array(o, k, what)?.iter().map(|v| v.as_str().map(String::from).ok_or_else(|| verr(format!("{what}: {k} holds a non-string")))).collect()
}

pub(crate) fn parse_deps(o: &Value, k: &str, what: &str) -> Result<Vec<Dep>> {
    let mut out = Vec::new();
    for d in opt_array(o, k, what)? {
        let name = req_str(d, "name", what)?;
        if !valid_name(name) {
            bail!(Verify, "{what}: bad dependency name {name:?}");
        }
        let c = match d.get("version") {
            None | Some(Value::Null) => None,
            Some(Value::Str(s)) => Constraint::parse(s).ok_or_else(|| verr(format!("{what}: bad constraint {s:?}")))?,
            _ => bail!(Verify, "{what}: bad constraint"),
        };
        out.push(Dep { name: name.into(), constraint: c });
    }
    Ok(out)
}

fn parse_pin(v: &Value, what: &str) -> Result<Pin> {
    let url = req_str(v, "url", what)?;
    let sha = req_str(v, "sha256", what)?;
    if !is_hex64(sha) {
        bail!(Verify, "{what}: bad sha256");
    }
    check_rel_url(url).map_err(|e| verr(format!("{what}: {e}")))?;
    Ok(Pin { url: url.into(), sha256: sha.into() })
}

/// URLs inside the manifest are relative to it, with no scheme, no `..`, no absolute path, no query.
pub fn check_rel_url(u: &str) -> std::result::Result<(), String> {
    if u.is_empty()
        || u.len() > 512
        || u.starts_with('/')
        || u.contains("://")
        || u.contains(['?', '#', '\\', ' '])
        || u.split('/').any(|c| c.is_empty() || c == "." || c == "..")
    {
        return Err(format!("unsafe URL {u:?}"));
    }
    Ok(())
}

pub fn schema_major(s: &str) -> Option<u32> {
    s.strip_prefix(SCHEMA_PREFIX)?.parse().ok()
}

/// Parse a manifest whose bytes have already been authenticated.
pub fn parse(bytes: &[u8], want_channel: &str) -> Result<Manifest> {
    let v = crate::json::parse(bytes).map_err(|e| verr(format!("manifest: {e}")))?;
    if v.as_object().is_none() {
        bail!(Verify, "manifest is not a JSON object");
    }
    let schema = req_str(&v, "schema", "manifest")?;
    match schema_major(schema) {
        Some(1) => {}
        Some(_) => bail!(Verify, "the manifest uses schema {schema}; update SAP first"),
        None => bail!(Verify, "not a SAP manifest (schema {schema:?})"),
    }
    let what = "manifest";
    let critical = match v.get("critical") {
        Some(Value::Array(_)) => str_list(&v, "critical", what)?,
        _ => bail!(Verify, "manifest: critical is required (it may be empty)"),
    };
    for c in &critical {
        if !UNDERSTOOD.contains(&c.as_str()) {
            bail!(Verify, "the manifest needs {c:?}, which this SAP does not understand; update SAP first");
        }
    }
    let channel = req_str(&v, "channel", what)?;
    if channel != want_channel {
        bail!(Verify, "the manifest is for channel {channel:?}, this machine follows {want_channel:?}");
    }
    let release = req_str(&v, "release", what)?.to_string();
    let sequence = req_int(&v, "sequence", what)?;
    if sequence < 0 {
        bail!(Verify, "manifest: negative sequence");
    }
    let issued = util::parse_rfc3339(req_str(&v, "issued", what)?).ok_or_else(|| verr("manifest: issued is not UTC RFC 3339".into()))?;
    let expires = util::parse_rfc3339(req_str(&v, "expires", what)?).ok_or_else(|| verr("manifest: expires is not UTC RFC 3339".into()))?;
    if expires <= issued {
        bail!(Verify, "manifest: expires is not after issued");
    }
    let min_sap = match v.get("min_sap") {
        None | Some(Value::Null) => None,
        Some(Value::Str(s)) if valid_version(s) => Some(s.clone()),
        _ => bail!(Verify, "manifest: bad min_sap"),
    };
    let base_sums = match v.get("base") {
        None | Some(Value::Null) => None,
        Some(b) => match b.get("sums_sha256") {
            Some(Value::Str(s)) if is_hex64(s) => Some(s.clone()),
            None | Some(Value::Null) => None,
            _ => bail!(Verify, "manifest: bad base.sums_sha256"),
        },
    };
    let mut allowed_prefixes = str_list(&v, "allowed_prefixes", what)?;
    if v.get("allowed_prefixes").is_none() {
        allowed_prefixes = vec!["/".into()];
    }
    for p in &allowed_prefixes {
        if p != "/" && !paths::is_safe(p) {
            bail!(Verify, "manifest: bad allowed prefix {p:?}");
        }
    }
    let removed = str_list(&v, "removed", what)?;
    let trust = match v.get("trust") {
        None | Some(Value::Null) => None,
        Some(t) => {
            let version = req_int(t, "version", "manifest trust")?;
            let mut keys = Vec::new();
            for k in str_list(t, "keys", "manifest trust")? {
                keys.push(crate::sshsig::PublicKey::from_openssh_line(&k).ok_or_else(|| verr("manifest trust: bad key".into()))?);
            }
            if keys.is_empty() {
                bail!(Verify, "manifest trust: no keys");
            }
            Some(Trust { version, keys })
        }
    };
    let mut packages: Vec<IndexEntry> = Vec::new();
    let mut skipped_kinds = Vec::new();
    let list = match v.get("packages") {
        Some(Value::Array(a)) => a,
        _ => bail!(Verify, "manifest: packages is required"),
    };
    for p in list {
        let name = req_str(p, "name", "manifest package")?;
        let what = format!("package {name}");
        if !valid_name(name) {
            bail!(Verify, "manifest: bad package name {name:?}");
        }
        let version = req_str(p, "version", &what)?;
        if !valid_version(version) {
            bail!(Verify, "{what}: bad version {version:?}");
        }
        let kind = req_str(p, "kind", &what)?;
        if !KINDS.contains(&kind) {
            skipped_kinds.push((name.to_string(), kind.to_string()));
            continue;
        }
        if packages.iter().any(|x| x.name == name) {
            bail!(Verify, "manifest: {name} is listed twice");
        }
        let activate = p.get("activate").and_then(|a| a.as_str()).unwrap_or("none").to_string();
        if !["none", "restart", "reboot"].contains(&activate.as_str()) {
            bail!(Verify, "{what}: unknown activate {activate:?}");
        }
        let components = match p.get("components") {
            Some(Value::Object(o)) => o.clone(),
            None | Some(Value::Null) => Vec::new(),
            _ => bail!(Verify, "{what}: components is not an object"),
        };
        packages.push(IndexEntry {
            name: name.into(),
            version: version.into(),
            kind: kind.into(),
            depends: parse_deps(p, "depends", &what)?,
            activate,
            bytes: p.get("bytes").and_then(|b| b.as_i64()).unwrap_or(0),
            record: parse_pin(p.get("record").ok_or_else(|| verr(format!("{what}: no record")))?, &what)?,
            payload: match p.get("payload") {
                None | Some(Value::Null) => None,
                Some(x) => Some(parse_pin(x, &what)?),
            },
            components,
        });
    }
    Ok(Manifest {
        channel: channel.into(),
        release,
        sequence,
        issued,
        expires,
        min_sap,
        base_sums,
        packages,
        skipped_kinds,
        removed,
        allowed_prefixes,
        trust,
        sha256: util::sha256(bytes),
    })
}

impl Manifest {
    pub fn get(&self, name: &str) -> Option<&IndexEntry> {
        self.packages.iter().find(|p| p.name == name)
    }
}

#[derive(Clone, Debug)]
pub struct Service {
    pub label: String,
    pub activate: String,
}

#[derive(Clone, Debug)]
pub struct FilesPin {
    pub name: String,
    pub count: i64,
    pub bytes: i64,
    pub sha256: String,
}

#[derive(Clone, Debug)]
pub struct PayloadPin {
    pub name: String,
    pub format: String,
    pub bytes: i64,
    pub sha256: String,
}

/// A package record (`*.record.json`), authenticated by the manifest's pin.
#[derive(Clone, Debug)]
pub struct Record {
    pub name: String,
    pub version: String,
    pub kind: String,
    pub summary: String,
    pub depends: Vec<Dep>,
    pub conflicts: Vec<Dep>,
    pub replaces: Vec<String>,
    pub files: Option<FilesPin>,
    pub config_files: Vec<String>,
    pub services: Vec<Service>,
    pub activate: String,
    pub payload: Option<PayloadPin>,
    /// `root` (the mounted root filesystem) or `sfboot` (the FAT32 boot partition).
    pub target: String,
    pub essential: bool,
    pub raw: Value,
}

pub const ESSENTIAL: &[&str] = &["sap", "sf-base", "sf-kernel-collection", "sf-boot"];

pub fn parse_record(bytes: &[u8], idx: &IndexEntry) -> Result<Record> {
    let v = crate::json::parse(bytes).map_err(|e| verr(format!("record of {}: {e}", idx.name)))?;
    let what = format!("record of {}", idx.name);
    if req_str(&v, "schema", &what)? != RECORD_SCHEMA {
        bail!(Verify, "{what}: unknown schema");
    }
    let name = req_str(&v, "name", &what)?;
    let version = req_str(&v, "version", &what)?;
    let kind = req_str(&v, "kind", &what)?;
    if name != idx.name || version != idx.version || kind != idx.kind {
        bail!(Verify, "{what}: name, version or kind disagree with the manifest");
    }
    let depends = parse_deps(&v, "depends", &what)?;
    if depends != idx.depends {
        bail!(Verify, "{what}: depends disagree with the manifest");
    }
    let files = match v.get("files") {
        None | Some(Value::Null) => None,
        Some(f) => {
            let n = req_str(f, "name", &what)?;
            check_rel_url(n).map_err(|e| verr(format!("{what}: {e}")))?;
            let sha = req_str(f, "sha256", &what)?;
            if !is_hex64(sha) {
                bail!(Verify, "{what}: bad files sha256");
            }
            Some(FilesPin { name: n.into(), count: req_int(f, "count", &what)?, bytes: req_int(f, "bytes", &what)?, sha256: sha.into() })
        }
    };
    let payload = match v.get("payload") {
        None | Some(Value::Null) => None,
        Some(f) => {
            let fmt = req_str(f, "format", &what)?;
            if fmt != crate::payload::FORMAT {
                bail!(Verify, "{what}: unknown payload format {fmt:?}; update SAP first");
            }
            let sha = req_str(f, "sha256", &what)?;
            if !is_hex64(sha) || idx.payload.as_ref().map(|p| p.sha256.as_str()) != Some(sha) {
                bail!(Verify, "{what}: payload hash disagrees with the manifest");
            }
            Some(PayloadPin { name: req_str(f, "name", &what)?.into(), format: fmt.into(), bytes: req_int(f, "bytes", &what)?, sha256: sha.into() })
        }
    };
    if payload.is_none() && idx.payload.is_some() {
        bail!(Verify, "{what}: the manifest pins a payload the record does not describe");
    }
    let mut services = Vec::new();
    for s in opt_array(&v, "services", &what)? {
        let label = req_str(s, "label", &what)?;
        let act = s.get("activate").and_then(|a| a.as_str()).unwrap_or("restart");
        if label.is_empty() || !label.bytes().all(|c| c.is_ascii_alphanumeric() || b".-_".contains(&c)) {
            bail!(Verify, "{what}: bad service label");
        }
        if !["none", "restart", "reboot"].contains(&act) {
            bail!(Verify, "{what}: bad service activate");
        }
        services.push(Service { label: label.into(), activate: act.into() });
    }
    let target = v.get("target").and_then(|t| t.as_str()).unwrap_or("root").to_string();
    if !["root", "sfboot"].contains(&target.as_str()) {
        bail!(Verify, "{what}: unknown target {target:?}");
    }
    if target == "sfboot" && kind != "boot-stage2" {
        bail!(Verify, "{what}: only boot-stage2 packages write the boot partition");
    }
    let config_files = str_list(&v, "config_files", &what)?;
    for c in &config_files {
        if !paths::is_safe(c) {
            bail!(Verify, "{what}: bad config file path");
        }
    }
    let replaces = str_list(&v, "replaces", &what)?;
    for r in &replaces {
        if !valid_name(r) {
            bail!(Verify, "{what}: bad replaces name");
        }
    }
    Ok(Record {
        name: name.into(),
        version: version.into(),
        kind: kind.into(),
        summary: v.get("summary").and_then(|s| s.as_str()).unwrap_or("").into(),
        depends,
        conflicts: parse_deps(&v, "conflicts", &what)?,
        replaces,
        files,
        config_files,
        services,
        activate: v.get("activate").and_then(|a| a.as_str()).unwrap_or(&idx.activate).into(),
        payload,
        target,
        essential: ESSENTIAL.contains(&name) || v.get("essential").and_then(|e| e.as_bool()).unwrap_or(false),
        raw: v,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn doc(extra: &str) -> String {
        format!(
            r#"{{"schema":"siliconforest-update/1","channel":"stable","release":"0.1.1","sequence":4,
            "issued":"2026-11-01T00:00:00Z","expires":"2026-12-01T00:00:00Z","critical":[]{extra},
            "packages":[{{"name":"vim","version":"9.1.0-2","kind":"files","depends":[{{"name":"sf-base","version":">= 0.1"}}],
            "record":{{"url":"pool/vim.record.json","sha256":"{h}"}},"payload":{{"url":"pool/vim.sappkg","sha256":"{h}"}},
            "x-future":{{"anything":1}}}},{{"name":"newthing","version":"1","kind":"oci-image","record":{{"url":"pool/x","sha256":"{h}"}}}}]}}"#,
            h = "ab".repeat(32)
        )
    }

    #[test]
    fn parses_and_ignores_unknown() {
        let m = parse(doc(r#","x-notes":"ignored","rollout":null,"delta":null"#).as_bytes(), "stable").unwrap();
        assert_eq!(m.packages.len(), 1);
        assert_eq!(m.skipped_kinds, vec![("newthing".to_string(), "oci-image".to_string())]);
        assert_eq!(m.allowed_prefixes, vec!["/"]);
    }

    #[test]
    fn critical_and_schema() {
        assert!(parse(doc(r#","x":1"#).replace(r#""critical":[]"#, r#""critical":["rollout"]"#).as_bytes(), "stable").is_err());
        assert!(parse(doc("").replace(r#""critical":[]"#, r#""critical":["trust"]"#).as_bytes(), "stable").is_ok());
        assert!(parse(doc("").replace("update/1", "update/2").as_bytes(), "stable").is_err());
        assert!(parse(doc("").as_bytes(), "beta").is_err());
        assert!(parse(doc("").replace("pool/vim.sappkg", "../etc/passwd").as_bytes(), "stable").is_err());
        assert!(parse(doc("").replace("pool/vim.sappkg", "https://evil/x").as_bytes(), "stable").is_err());
        assert!(parse(doc("").replace(r#""sequence":4"#, r#""sequence":4,"sequence":5"#).as_bytes(), "stable").is_err());
        assert!(parse(doc("").replace(r#""sequence":4"#, r#""sequence":4.0"#).as_bytes(), "stable").is_err());
    }
}
