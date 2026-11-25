// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//! The update loop (design section 3.1): compare, plan, download, verify, stage, commit, record, activate.
//! Nothing outside staging, the download cache and the verified-manifest cache is written before the
//! journal's intent record (the commit point).

use crate::error::{Code, Context, Error, Result};
use crate::json::Value;
use crate::manifest::{self, IndexEntry, Pin, Record};
use crate::repo::{self, Loaded};
use crate::resolve::{self, InstalledView, Request, BOOT_KINDS};
use crate::sys::{Installed, Sys};
use crate::tsv::{self, Entry, Kind};
use crate::txn::{self, Journal, Op};
use crate::version::compare;
use crate::{bail, boot, kc, paths, payload, util};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;

#[derive(Default, Clone)]
pub struct UpgradeArgs {
    pub names: Vec<String>,
    pub install_all: bool,
    pub reinstall: Vec<String>,
    pub dry_run: bool,
    pub download_only: bool,
    pub boot: bool,
    pub adopt: Vec<String>,
    pub yes: bool,
}

pub struct Pkg {
    pub idx: IndexEntry,
    pub rec: Record,
    pub files: Vec<Entry>,
    pub files_text: String,
    pub payload: Option<PathBuf>,
}

pub const EXIT_REBOOT: i32 = 50;

fn rel(sys: &Sys, abs: &Path) -> String {
    abs.strip_prefix(&sys.root).unwrap_or(abs).to_string_lossy().to_string()
}

fn dirname(u: &str) -> &str {
    u.rfind('/').map(|i| &u[..i]).unwrap_or("")
}

/// Fetch a package's record and file list, each checked against the hash its parent pins.
pub fn fetch_meta(sys: &Sys, l: &Loaded, idx: &IndexEntry) -> Result<(Record, Vec<Entry>, String)> {
    let rp = repo::pinned(sys, &l.url, &idx.record, manifest::MAX_RECORD)?;
    let rec = manifest::parse_record(&fs::read(&rp)?, idx)?;
    let Some(fp) = &rec.files else { return Ok((rec, Vec::new(), String::new())) };
    let d = dirname(&idx.record.url);
    let url = if d.is_empty() { fp.name.clone() } else { format!("{d}/{}", fp.name) };
    let p = repo::pinned(sys, &l.url, &Pin { url, sha256: fp.sha256.clone() }, manifest::MAX_FILELIST)?;
    let text = fs::read_to_string(&p).map_err(|_| Error::new(Code::Verify, format!("{}: file list is not text", idx.name)))?;
    let files = tsv::parse(&text).map_err(|e| Error::new(Code::Verify, format!("{}: {e}", idx.name)))?;
    let bytes: u64 = files.iter().filter(|e| e.kind == Kind::File).map(|e| e.size).sum();
    if files.len() as i64 != fp.count || bytes as i64 != fp.bytes {
        bail!(Verify, "{}: the file list has {} entries / {} bytes, the record says {} / {}", idx.name, files.len(), bytes, fp.count, fp.bytes);
    }
    Ok((rec, files, text))
}

fn installed_map(inst: &[Installed]) -> BTreeMap<String, InstalledView> {
    inst.iter()
        .map(|i| {
            let d = manifest::parse_deps(&i.record, "depends", &i.name).unwrap_or_default();
            let c = manifest::parse_deps(&i.record, "conflicts", &i.name).unwrap_or_default();
            (i.name.clone(), InstalledView { version: i.version.clone(), depends: d, conflicts: c })
        })
        .collect()
}

pub fn statvfs_free(p: &Path) -> Option<u64> {
    let c = std::ffi::CString::new(p.to_string_lossy().as_bytes()).ok()?;
    let mut s: libc::statvfs = unsafe { std::mem::zeroed() };
    if unsafe { libc::statvfs(c.as_ptr(), &mut s) } != 0 {
        return None;
    }
    #[allow(clippy::unnecessary_cast)]
    Some(s.f_bavail as u64 * s.f_frsize as u64)
}

/// `sap upgrade` / `sap install`. Returns the exit code.
pub fn upgrade(sys: &Sys, a: &UpgradeArgs) -> Result<i32> {
    sys.require_writer()?;
    let _lock = sys.lock()?;
    for line in txn::recover(sys, false)? {
        eprintln!("sap: recovered {line}");
    }
    let l = repo::load_and_remember(sys)?;
    let m = &l.m;
    let st = sys.state()?;
    let inst = sys.installed()?;
    let imap = installed_map(&inst);
    let names: Option<Vec<String>> = if a.install_all {
        Some(
            m.packages
                .iter()
                .filter(|p| a.boot || !BOOT_KINDS.contains(&p.kind.as_str()))
                .map(|p| p.name.clone())
                .filter(|n| !imap.contains_key(n) || compare(&m.get(n).unwrap().version, &imap[n].version).is_gt())
                .collect(),
        )
    } else if a.names.is_empty() {
        None
    } else {
        Some(a.names.clone())
    };
    let req = Request { names: names.as_deref(), reinstall: &a.reinstall, held: &st.held, allow_boot: a.boot };
    let mut res = resolve::resolve(&imap, m, &req)?;
    for n in &res.notes {
        println!("note: {n}");
    }
    // min_sap and self-update first (design section 6.3, rule 5).
    let self_updated = std::env::var("SAP_SELF_UPDATED").is_ok();
    let too_old = m.min_sap.as_ref().is_some_and(|v| compare(manifest::SAP_VERSION, v).is_lt());
    let sap_at = res.order.iter().position(|n| n == "sap");
    let mut reexec = false;
    if too_old {
        if self_updated || sap_at.is_none() {
            bail!(Verify, "this manifest needs sap {} or newer (this is {}); update SAP first", m.min_sap.as_ref().unwrap(), manifest::SAP_VERSION);
        }
        res.order.truncate(sap_at.unwrap() + 1);
        reexec = true;
    } else if let Some(i) = sap_at {
        if res.order.len() > i + 1 && !self_updated {
            res.order.truncate(i + 1);
            reexec = true;
        }
    }
    let rotate = match &m.trust {
        Some(t) => {
            let anchor = sys.anchor()?;
            if t.version > anchor.version {
                if a.boot {
                    Some(t.clone())
                } else {
                    println!("note: the manifest rotates the trust anchor to version {}; run sap upgrade --boot to write it into the boot chain", t.version);
                    None
                }
            } else {
                None
            }
        }
        None => None,
    };
    // A/B slots (design 10.5): the inactive slot gets a complete pair, so its stage 2 comes from
    // sf-boot even when only the kernel changes; bring sf-boot into the plan (same version: no-op).
    let boot_work = rotate.is_some() || res.order.iter().any(|n| m.get(n).map(|e| BOOT_KINDS.contains(&e.kind.as_str())).unwrap_or(false));
    if boot_work
        && a.boot
        && !res.order.iter().any(|n| n == "sf-boot")
        && imap.contains_key("sf-boot")
        && m.get("sf-boot").is_some()
        && !st.held.iter().any(|h| h == "sf-boot")
        && boot::backend(sys)? == boot::Backend::Slots
    {
        res.order.push("sf-boot".into());
    }
    if res.order.is_empty() && rotate.is_none() {
        println!("Nothing to do: everything is up to date (manifest sequence {}).", m.sequence);
        return Ok(0);
    }
    // Plan: records and file lists, before any payload.
    let mut pkgs: Vec<Pkg> = Vec::new();
    for n in &res.order {
        let idx = m.get(n).unwrap().clone();
        let (rec, files, text) = fetch_meta(sys, &l, &idx)?;
        pkgs.push(Pkg { idx, rec, files, files_text: text, payload: None });
    }
    // Conflicts between packages of the after-state.
    let mut after: BTreeMap<String, (String, Vec<manifest::Dep>)> = imap.iter().map(|(n, v)| (n.clone(), (v.version.clone(), v.conflicts.clone()))).collect();
    for p in &pkgs {
        after.insert(p.rec.name.clone(), (p.rec.version.clone(), p.rec.conflicts.clone()));
    }
    resolve::check_conflicts(&after)?;
    let own = ownership(sys, m, &inst, &pkgs, &a.adopt)?;
    println!("{:<28} {:<16} {:<16} DOWNLOAD", "PACKAGE", "INSTALLED", "NEW");
    let mut dl = 0u64;
    let mut unpacked = 0u64;
    for p in &pkgs {
        let cached = p.idx.payload.as_ref().map(|pp| sys.cache.join(&pp.sha256).exists()).unwrap_or(true);
        let sz = p.rec.payload.as_ref().map(|x| x.bytes as u64).unwrap_or(0);
        if !cached {
            dl += sz;
        }
        unpacked += p.files.iter().map(|e| e.size).sum::<u64>();
        let iv = imap.get(&p.rec.name).map(|v| v.version.as_str()).unwrap_or("-");
        println!("{:<28} {:<16} {:<16} {}", p.rec.name, iv, p.rec.version, if cached { "cached".to_string() } else { format!("{sz} B") });
    }
    if let Some(t) = &rotate {
        println!("trust anchor: version {} ({} keys) will be written into sf/kernel.bin", t.version, t.keys.len());
    }
    if let Some(free) = statvfs_free(&sys.root) {
        let need = dl + unpacked + (1 << 20);
        if need > free {
            bail!(Conflict, "not enough free space: {need} bytes needed, {free} free");
        }
    }
    if a.dry_run {
        println!("Dry run: nothing downloaded or changed.");
        return Ok(0);
    }
    // Download only what changed.
    for p in pkgs.iter_mut() {
        if let Some(pin) = &p.idx.payload {
            let max = p.rec.payload.as_ref().map(|x| x.bytes as u64).unwrap_or(0);
            p.payload = Some(repo::pinned(sys, &l.url, pin, max)?);
        }
    }
    if a.download_only {
        println!("Downloaded; nothing installed (--download-only).");
        return Ok(0);
    }
    let mut j = Journal::create(sys)?;
    let begin = Value::obj(vec![
        ("kind", Value::str(if a.reinstall.is_empty() { "upgrade" } else { "repair" })),
        ("sequence", Value::Int(m.sequence)),
        ("release", Value::str(m.release.clone())),
        (
            "packages",
            Value::Array(
                pkgs.iter()
                    .map(|p| {
                        Value::obj(vec![
                            ("name", Value::str(p.rec.name.clone())),
                            ("from", imap.get(&p.rec.name).map(|v| Value::str(v.version.clone())).unwrap_or(Value::Null)),
                            ("to", Value::str(p.rec.version.clone())),
                        ])
                    })
                    .collect(),
            ),
        ),
    ]);
    j.append("begin", vec![("txn", Value::str(j.id.clone())), ("plan", begin)])?;
    let staged = match stage(sys, &j.id, &pkgs, &inst, &own, rotate.as_ref(), m.sequence as u32) {
        Ok(s) => s,
        Err(e) => {
            let _ = fs::remove_dir_all(sys.lib.join("staging").join(&j.id));
            if let Some(b) = &sys.sfboot {
                let _ = fs::remove_dir_all(b.join("sf/.sap-staging").join(&j.id));
            }
            j.append("aborted", vec![("reason", Value::str(e.msg.clone())), ("recovered", Value::str("nothing changed"))])?;
            return Err(e);
        }
    };
    txn::commit(sys, &mut j, &staged.ops)?;
    j.append("done", vec![])?;
    let _ = fs::remove_dir_all(sys.lib.join("staging").join(&j.id));
    if let Some(b) = &sys.sfboot {
        let _ = fs::remove_dir_all(b.join("sf/.sap-staging").join(&j.id));
    }
    txn::prune_backups(sys, 2);
    println!("Transaction {} done: {} package(s).", j.id, pkgs.len());
    let reboot = activate(sys, &pkgs, staged.boot_changed);
    if reexec {
        println!("sap was updated; continuing with the new sap.");
        return reexec_self(sys);
    }
    if reboot {
        println!("Reboot required.");
        return Ok(EXIT_REBOOT);
    }
    Ok(0)
}

fn reexec_self(sys: &Sys) -> Result<i32> {
    use std::os::unix::process::CommandExt;
    let exe = if sys.image_mode { std::env::current_exe()? } else { sys.root.join("usr/bin/sap") };
    let args: Vec<String> = std::env::args().skip(1).collect();
    let e = std::process::Command::new(exe).args(args).env("SAP_SELF_UPDATED", "1").exec();
    bail!(Failure, "could not re-execute sap: {e}")
}

/// Who owns what after the transaction, and the checks of design section 4.5.
pub struct Ownership {
    /// Paths that move out of sf-base (incoming package replaces sf-base for them).
    pub from_base: BTreeSet<String>,
    /// Config files to keep locally (write `.sap-new` beside them).
    pub keep_local: BTreeSet<String>,
}

fn ownership(sys: &Sys, m: &manifest::Manifest, inst: &[Installed], pkgs: &[Pkg], adopt: &[String]) -> Result<Ownership> {
    let mut owner: BTreeMap<&str, &str> = BTreeMap::new();
    for i in inst {
        for e in &i.files {
            if e.kind != Kind::Dir {
                owner.insert(&e.path, &i.name);
            }
        }
    }
    let incoming: BTreeMap<&str, &Pkg> = pkgs.iter().map(|p| (p.rec.name.as_str(), p)).collect();
    let mut claimed: BTreeMap<&str, &str> = BTreeMap::new();
    let mut from_base = BTreeSet::new();
    let mut keep_local = BTreeSet::new();
    let plan_links: BTreeSet<&str> =
        pkgs.iter().filter(|p| p.rec.target != "sfboot").flat_map(|p| p.files.iter().filter(|e| e.kind == Kind::Link).map(|e| e.path.as_str())).collect();
    for p in pkgs {
        let boot = p.rec.target == "sfboot";
        for e in &p.files {
            let path = e.path.as_str();
            if boot {
                if !paths::under(path, "/sf") || e.kind != Kind::File {
                    bail!(Conflict, "{}: boot packages may only hold files under /sf ({path})", p.rec.name);
                }
                continue;
            }
            if paths::is_protected(path) {
                bail!(Conflict, "{}: {path} is protected (fixed-offset installer file); refused", p.rec.name);
            }
            if paths::is_denied(path) {
                bail!(Conflict, "{}: {path} is outside what packages may write", p.rec.name);
            }
            if !m.allowed_prefixes.iter().any(|a| paths::under(path, a)) {
                bail!(Conflict, "{}: {path} is outside the manifest's allowed prefixes", p.rec.name);
            }
            // No path may go through a symlink, on disk or in the plan: a package could otherwise write
            // another package's file (or a protected one) under an alias, past every check above.
            let mut anc = path;
            while let Some(i) = anc.rfind('/') {
                anc = &anc[..i];
                if anc.is_empty() {
                    break;
                }
                if plan_links.contains(anc) {
                    bail!(Conflict, "{}: {path} lies under the symlink {anc} in this update; refused", p.rec.name);
                }
            }
            let target = paths::resolve(&sys.root, path).map_err(|e| Error::new(Code::Conflict, e))?;
            if target != sys.root.join(&path[1..]) {
                bail!(Conflict, "{}: {path} goes through a symlink on disk (to {}); packages must name real paths", p.rec.name, target.display());
            }
            if e.kind == Kind::Dir {
                continue;
            }
            if let Some(o) = claimed.insert(path, &p.rec.name) {
                bail!(Conflict, "{path} is claimed by both {o} and {}", p.rec.name);
            }
            match owner.get(path) {
                Some(o) if *o == p.rec.name => {}
                Some(o) => {
                    let still = match incoming.get(o) {
                        Some(op) => op.files.iter().any(|x| x.path == path),
                        None => inst.iter().find(|i| i.name == *o).map(|i| i.files.iter().any(|x| x.path == path)).unwrap_or(false),
                    };
                    let replaces = p.rec.replaces.iter().any(|r| r == o);
                    if !still && replaces {
                    } else if still && *o == "sf-base" && replaces && !incoming.contains_key("sf-base") {
                        from_base.insert(path.to_string());
                    } else {
                        bail!(Conflict, "{path} belongs to {o}; {} cannot take it{}", p.rec.name, if replaces { "" } else { " (no replaces)" });
                    }
                }
                None => {
                    // Unowned on disk: equal content is adopted, anything else needs --adopt.
                    let target = paths::resolve(&sys.root, path).map_err(|e| Error::new(Code::Conflict, e))?;
                    let cur = txn::state_of(&target);
                    let want = match e.kind {
                        Kind::File => Some(format!("f:{}", e.data)),
                        Kind::Link => Some(format!("l:{}", e.data)),
                        Kind::Dir => None,
                    };
                    if cur.is_some() && cur != want && !adopt.iter().any(|x| x == path) {
                        bail!(
                            Conflict,
                            "{path} exists, is owned by no package and differs from {}'s; refusing to overwrite it (pass --adopt {path} to take it)",
                            p.rec.name
                        );
                    }
                }
            }
            // Config files edited locally: keep them (three-way by hash).
            if p.rec.config_files.iter().any(|c| c == path) {
                if let Some(old) = inst.iter().find(|i| i.name == p.rec.name).and_then(|i| i.files.iter().find(|x| x.path == path)) {
                    let target = paths::resolve(&sys.root, path).map_err(|e| Error::new(Code::Conflict, e))?;
                    if let Some(h) = util::file_hash_if_regular(&target) {
                        if Some(h.as_str()) != old.sha256() && Some(h.as_str()) != e.sha256() {
                            keep_local.insert(path.to_string());
                        }
                    }
                }
            }
        }
    }
    Ok(Ownership { from_base, keep_local })
}

pub struct Staged {
    pub ops: Vec<Op>,
    pub boot_changed: bool,
}

/// Unpack, verify, and lay out every new file in staging; return the operations of the commit.
fn stage(sys: &Sys, id: &str, pkgs: &[Pkg], inst: &[Installed], own: &Ownership, rotate: Option<&manifest::Trust>, generation: u32) -> Result<Staged> {
    let needs_boot = rotate.is_some() || pkgs.iter().any(|p| p.rec.target == "sfboot" || p.rec.kind == "kc-recipe" || p.rec.kind == "kc-input");
    let backend = if needs_boot { boot::backend(sys)? } else { boot::Backend::Legacy };
    // slots: package path (/sf/boot.bin, /sf/b/boot.bin) -> staged stage 2 body (root-side staging)
    let mut slot_boot: BTreeMap<String, PathBuf> = BTreeMap::new();
    let sdir = sys.lib.join("staging").join(id);
    let bdir = sys.lib.join("backup").join(id);
    fs::create_dir_all(&sdir).ctx(|| format!("create {}", sdir.display()))?;
    let mut mkdirs: Vec<Op> = Vec::new();
    let mut puts: Vec<Op> = Vec::new();
    let mut removes: Vec<Op> = Vec::new();
    let mut rmdirs: Vec<Op> = Vec::new();
    let mut dbops: Vec<Op> = Vec::new();
    let mut bootops: Vec<Op> = Vec::new();
    let mut n = 0usize;
    let mut next = || {
        n += 1;
        format!("{n:06}")
    };
    // pkg -> path -> staged file (for the kernel relink)
    let mut staged_files: BTreeMap<(String, String), (PathBuf, String)> = BTreeMap::new();
    let mut boot_changed = false;
    let after_claims: BTreeSet<String> = pkgs.iter().flat_map(|p| p.files.iter().map(|e| e.path.clone())).collect();
    for p in pkgs {
        let pdir = sdir.join(&p.rec.name);
        let bodies = match &p.payload {
            Some(pl) => payload::unpack(pl, &p.files, &pdir.join("bodies"))?,
            None => {
                if p.files.iter().any(|e| e.kind == Kind::File) {
                    bail!(Verify, "{} lists files but has no payload", p.rec.name);
                }
                Vec::new()
            }
        };
        let mut bi = bodies.into_iter();
        let boot = p.rec.target == "sfboot";
        for e in &p.files {
            if boot && backend == boot::Backend::Slots {
                let body = bi.next().unwrap();
                let keep = pdir.join(next());
                fs::rename(&body, &keep)?;
                slot_boot.insert(e.path.clone(), keep);
                continue;
            }
            if boot && paths::under(&e.path, "/sf/b") {
                bi.next(); // slot B's stage 2: only for stage 1 v2 machines (boot_backend slots)
                continue;
            }
            if boot {
                let body = bi.next().unwrap();
                let sb = txn::base(sys, "sfboot")?;
                let rel_t = e.path[1..].to_string();
                let st = sb.join("sf/.sap-staging").join(id).join(e.path[1..].replace('/', "_"));
                fs::create_dir_all(st.parent().unwrap())?;
                fs::copy(&body, &st)?;
                fs::File::open(&st)?.sync_all()?;
                if util::sha256_file(&st)?.0 != e.data {
                    bail!(Verify, "{}: read-back of the staged copy on SFBOOT does not match", e.path);
                }
                boot_changed = true;
                bootops.push(Op {
                    op: "put".into(),
                    area: "sfboot".into(),
                    path: rel_t.clone(),
                    label: format!("SFBOOT{}", e.path),
                    old: txn::state_of(&sb.join(&rel_t)),
                    new: Some(format!("f:{}", e.data)),
                    staged: Some(st.strip_prefix(&sb).unwrap().to_string_lossy().to_string()),
                    backup: Some(format!("{rel_t}.old")),
                    mode: 0o644,
                    uid: 0,
                    gid: 0,
                });
                continue;
            }
            let target = paths::resolve(&sys.root, &e.path).map_err(|x| Error::new(Code::Conflict, x))?;
            let trel = rel(sys, &target);
            let old = txn::state_of(&target);
            match e.kind {
                Kind::Dir => {
                    if old.is_none() {
                        mkdirs.push(Op {
                            op: "mkdir".into(),
                            area: "root".into(),
                            path: trel,
                            label: e.path.clone(),
                            old: None,
                            new: Some("d".into()),
                            staged: None,
                            backup: None,
                            mode: e.mode,
                            uid: e.uid,
                            gid: e.gid,
                        });
                    } else if old.as_deref() != Some("d") {
                        bail!(Conflict, "{}: a non-directory is in the way", e.path);
                    }
                }
                Kind::File | Kind::Link => {
                    if old.as_deref() == Some("d") {
                        bail!(Conflict, "{}: a directory is in the way", e.path);
                    }
                    let want = if e.kind == Kind::File { format!("f:{}", e.data) } else { format!("l:{}", e.data) };
                    if !own.keep_local.contains(&e.path) && old.as_deref() == Some(want.as_str()) && txn::meta_matches(&target, e.mode, e.uid, e.gid) {
                        if e.kind == Kind::File {
                            bi.next();
                        }
                        continue; // already exactly right on disk: nothing to write, back up or roll back
                    }
                    let s = pdir.join(next());
                    let new = if e.kind == Kind::File {
                        let body = bi.next().unwrap();
                        fs::rename(&body, &s)?;
                        staged_files.insert((p.rec.name.clone(), e.path.clone()), (s.clone(), e.data.clone()));
                        format!("f:{}", e.data)
                    } else {
                        std::os::unix::fs::symlink(&e.data, &s)?;
                        format!("l:{}", e.data)
                    };
                    txn::finish_staged(&s, e.mode, e.uid, e.gid)?;
                    // Same content already there: only mode/owner may differ; the rename still applies them.
                    let (path, label, oldst) = if own.keep_local.contains(&e.path) {
                        let t2 = PathBuf::from(format!("{}.sap-new", target.display()));
                        (rel(sys, &t2), format!("{}.sap-new", e.path), txn::state_of(&t2))
                    } else {
                        (trel, e.path.clone(), old)
                    };
                    puts.push(Op {
                        op: "put".into(),
                        area: "root".into(),
                        path,
                        label,
                        old: oldst,
                        new: Some(new),
                        staged: Some(rel(sys, &s)),
                        backup: Some(rel(sys, &bdir.join(next()))),
                        mode: e.mode,
                        uid: e.uid,
                        gid: e.gid,
                    });
                }
            }
        }
        // Files the new version no longer lists, and nobody else claims after the transaction.
        if let Some(i) = inst.iter().find(|i| i.name == p.rec.name) {
            let new_paths: BTreeSet<&str> = p.files.iter().map(|e| e.path.as_str()).collect();
            for e in &i.files {
                if new_paths.contains(e.path.as_str()) || after_claims.contains(&e.path) {
                    continue;
                }
                if i.target() == "sfboot" {
                    continue; // boot files are never deleted by an update
                }
                let target = paths::resolve(&sys.root, &e.path).map_err(|x| Error::new(Code::Conflict, x))?;
                let cur = txn::state_of(&target);
                if e.kind == Kind::Dir {
                    rmdirs.push(Op {
                        op: "rmdir".into(),
                        area: "root".into(),
                        path: rel(sys, &target),
                        label: e.path.clone(),
                        old: cur,
                        new: None,
                        staged: None,
                        backup: None,
                        mode: e.mode,
                        uid: e.uid,
                        gid: e.gid,
                    });
                } else if cur.is_some() {
                    removes.push(Op {
                        op: "remove".into(),
                        area: "root".into(),
                        path: rel(sys, &target),
                        label: e.path.clone(),
                        old: cur,
                        new: None,
                        staged: None,
                        backup: Some(rel(sys, &bdir.join(next()))),
                        mode: e.mode,
                        uid: e.uid,
                        gid: e.gid,
                    });
                }
            }
        }
        // Database entries, swapped with everything else.
        let put_db = |name: String, data: Vec<u8>, dbops: &mut Vec<Op>, k: String, kb: String| -> Result<()> {
            let s = sdir.join("db").join(&k);
            util::write_atomic(&s, &data, 0o644)?;
            let t = sys.installed_dir().join(&name);
            dbops.push(Op {
                op: "put".into(),
                area: "root".into(),
                path: rel(sys, &t),
                label: format!("database {name}"),
                old: txn::state_of(&t),
                new: Some(format!("f:{}", util::sha256(&data))),
                staged: Some(rel(sys, &s)),
                backup: Some(rel(sys, &bdir.join(kb))),
                mode: 0o644,
                uid: 0,
                gid: 0,
            });
            Ok(())
        };
        put_db(format!("{}.json", p.rec.name), Sys::db_entry(&p.rec.name, &p.rec.version, &p.rec.kind, id, &p.rec.raw), &mut dbops, next(), next())?;
        put_db(format!("{}.files.tsv", p.rec.name), p.files_text.clone().into_bytes(), &mut dbops, next(), next())?;
    }
    // Paths moving out of sf-base: rewrite sf-base's list without them.
    if !own.from_base.is_empty() {
        if let Some(b) = inst.iter().find(|i| i.name == "sf-base") {
            let kept: Vec<Entry> = b.files.iter().filter(|e| !own.from_base.contains(&e.path)).cloned().collect();
            let data = tsv::render(&kept).into_bytes();
            let s = sdir.join("db").join(next());
            util::write_atomic(&s, &data, 0o644)?;
            let t = sys.installed_dir().join("sf-base.files.tsv");
            dbops.push(Op {
                op: "put".into(),
                area: "root".into(),
                path: rel(sys, &t),
                label: "database sf-base.files.tsv".into(),
                old: txn::state_of(&t),
                new: Some(format!("f:{}", util::sha256(&data))),
                staged: Some(rel(sys, &s)),
                backup: Some(rel(sys, &bdir.join(next()))),
                mode: 0o644,
                uid: 0,
                gid: 0,
            });
        }
    }
    // The kernel collection: relink when any input or the recipe changes, or the trust anchor rotates.
    let kc_changed = pkgs.iter().any(|p| p.rec.kind == "kc-recipe" || p.rec.kind == "kc-input");
    if backend == boot::Backend::Slots && (kc_changed || rotate.is_some() || !slot_boot.is_empty()) {
        bootops.push(stage_slot(sys, id, pkgs, inst, &staged_files, rotate, kc_changed, &slot_boot, generation)?);
        boot_changed = true;
    } else if kc_changed || rotate.is_some() {
        let op = stage_kernel(sys, id, pkgs, inst, &staged_files, rotate, kc_changed)?;
        if let Some(op) = op {
            boot_changed = true;
            bootops.push(op);
        }
    }
    mkdirs.sort_by_key(|o| o.path.matches('/').count());
    rmdirs.sort_by_key(|o| std::cmp::Reverse(o.path.matches('/').count()));
    let mut ops = mkdirs;
    ops.extend(puts);
    ops.extend(removes);
    ops.extend(rmdirs);
    ops.extend(dbops);
    ops.extend(bootops);
    Ok(Staged { ops, boot_changed })
}

/// design 10.5: stage into the slot that is not the default, through sf-bootslot. Returns the `arm`
/// operation, which the transaction runs last.
#[allow(clippy::too_many_arguments)]
fn stage_slot(
    sys: &Sys,
    id: &str,
    pkgs: &[Pkg],
    inst: &[Installed],
    staged: &BTreeMap<(String, String), (PathBuf, String)>,
    rotate: Option<&manifest::Trust>,
    relink: bool,
    slot_boot: &BTreeMap<String, PathBuf>,
    generation: u32,
) -> Result<Op> {
    let tool = boot::Tool::new(sys)?;
    let st = tool.status()?;
    if st.trial_state == "armed" || st.trial_state == "tried" {
        bail!(
            Conflict,
            "a boot update is waiting in slot {} ({}); start it and run sap mark-good, or let it fall back, before staging another",
            st.trial.unwrap_or('?'),
            st.trial_state
        );
    }
    let t = boot::other(st.default);
    if t == st.running {
        bail!(Conflict, "the slot to stage ({t}) is the running slot; refusing (sf-bootslot status: default {})", st.default);
    }
    let sb = txn::base(sys, "sfboot")?;
    let cur_path = sb.join(boot::kernel_path(st.default));
    let current = fs::read(&cur_path)
        .map_err(|_| Error::new(Code::Failure, format!("the default slot has no {} (is SFBOOT mounted?)", boot::kernel_path(st.default))))?;
    let (args, collection) = kernel_parts(sys, pkgs, inst, staged, rotate, relink, &current, &sys.lib.join("staging").join(id).join("kc"))?;
    let kbin = kc::kernel_bin(&boot::with_slot(&args, t), &collection)?;
    let boot_rel = boot::boot_path(t);
    let pkg_path = format!("/{boot_rel}");
    let body = match slot_boot.get(&pkg_path) {
        Some(f) => fs::read(f)?,
        None => bail!(Conflict, "slot {t} needs the stage 2 built for it ({pkg_path} in sf-boot), and this release's sf-boot does not ship one; the update cannot be staged into slot {t}"),
    };
    // Check the stage 2 against the signed file list of the sf-boot being installed.
    let want = pkgs.iter().filter(|p| p.rec.target == "sfboot").flat_map(|p| p.files.iter()).find(|e| e.path == pkg_path).map(|e| e.data.clone());
    if want.as_deref() != Some(util::sha256(&body).as_str()) {
        bail!(Verify, "{pkg_path}: the staged stage 2 does not match its signed hash");
    }
    tool.begin_stage(&st, t)?;
    boot::write_slot_file(&sb, boot::kernel_path(t), &kbin)?;
    boot::write_slot_file(&sb, boot_rel, &body)?;
    println!("boot: staged slot {t} (default stays {}); it is armed when the transaction commits", st.default);
    Ok(Op {
        op: "arm".into(),
        area: "sfboot".into(),
        path: boot_rel.into(),
        label: format!("SFBOOT slot {t} (arm)"),
        old: None,
        new: Some(format!("f:{}", util::sha256(&body))),
        staged: None,
        backup: None,
        mode: generation,
        uid: 0,
        gid: 0,
    })
}

fn stage_kernel(
    sys: &Sys,
    id: &str,
    pkgs: &[Pkg],
    inst: &[Installed],
    staged: &BTreeMap<(String, String), (PathBuf, String)>,
    rotate: Option<&manifest::Trust>,
    relink: bool,
) -> Result<Option<Op>> {
    let sb = txn::base(sys, "sfboot")?;
    let target = sb.join("sf/kernel.bin");
    let current =
        fs::read(&target).map_err(|_| Error::new(Code::Failure, "the boot partition has no sf/kernel.bin to update (is SFBOOT mounted?)".to_string()))?;
    let cur_args = kc::read_bootargs(&current)?;
    let (args, collection) = kernel_parts(sys, pkgs, inst, staged, rotate, relink, &current, &sys.lib.join("staging").join(id).join("kc"))?;
    // Same boot arguments and the same collection: nothing to write, whatever compressor packed it.
    if args == cur_args && kc::read_collection(&current).map(|c| c == collection).unwrap_or(false) {
        return Ok(None);
    }
    let bin = kc::kernel_bin(&args, &collection)?;
    let st = sb.join("sf/.sap-staging").join(id).join("kernel.bin");
    fs::create_dir_all(st.parent().unwrap())?;
    {
        use std::io::Write;
        let mut f = fs::File::create(&st)?;
        f.write_all(&bin)?;
        f.sync_all()?;
    }
    if util::sha256_file(&st)?.0 != util::sha256(&bin) {
        bail!(Verify, "read-back of the staged kernel.bin on SFBOOT does not match");
    }
    Ok(Some(Op {
        op: "put".into(),
        area: "sfboot".into(),
        path: "sf/kernel.bin".into(),
        label: "SFBOOT/sf/kernel.bin".into(),
        old: Some(format!("f:{}", util::sha256(&current))),
        new: Some(format!("f:{}", util::sha256(&bin))),
        staged: Some(st.strip_prefix(&sb).unwrap().to_string_lossy().to_string()),
        backup: Some("sf/kernel.bin.old".into()),
        mode: 0o644,
        uid: 0,
        gid: 0,
    }))
}

/// The boot arguments (machine values, trust token) and the collection for a new kernel.bin, from the
/// one the machine boots with now: relinked when kernel inputs changed, else the current collection.
#[allow(clippy::too_many_arguments)]
fn kernel_parts(
    sys: &Sys,
    pkgs: &[Pkg],
    inst: &[Installed],
    staged: &BTreeMap<(String, String), (PathBuf, String)>,
    rotate: Option<&manifest::Trust>,
    relink: bool,
    current: &[u8],
    work: &Path,
) -> Result<(String, Vec<u8>)> {
    let cur_args = kc::read_bootargs(current)?;
    let new_rec = pkgs.iter().find(|p| p.rec.kind == "kc-recipe").map(|p| p.rec.raw.clone());
    let old_rec = inst.iter().find(|i| i.kind == "kc-recipe").map(|i| i.record.clone());
    let recipe_v = new_rec
        .clone()
        .or(old_rec.clone())
        .ok_or_else(|| Error::new(Code::Conflict, "no kernel-collection recipe is installed or in this transaction".to_string()))?;
    let recipe = kc::parse_recipe(&recipe_v)?;
    // Boot arguments: the machine's own values, recovered from what it boots with now.
    let old_template = old_rec.as_ref().map(|r| kc::parse_recipe(r).map(|x| x.bootargs_template)).transpose()?;
    let base_args = if recipe.bootargs_template.is_empty() {
        kc::with_trust(&cur_args, None)
    } else {
        let vals = kc::personal_values(old_template.as_deref().unwrap_or(&recipe.bootargs_template), &cur_args)?;
        kc::fill_template(&recipe.bootargs_template, &vals)?
    };
    let cur_token = cur_args.split_whitespace().find(|w| w.starts_with("sf_trust=")).map(String::from);
    let token = match rotate {
        Some(t) => Some(crate::sys::trust_token(t.version, &t.keys)),
        None => cur_token,
    };
    let args = kc::with_trust(&base_args, token.as_deref());
    let collection = if relink {
        let locate = |pkg: &str, path: &str| -> Result<(PathBuf, String)> {
            if let Some(x) = staged.get(&(pkg.to_string(), path.to_string())) {
                return Ok(x.clone());
            }
            if let Some(p) = pkgs.iter().find(|p| p.rec.name == pkg) {
                // In the update but already right on disk (so not staged): the on-disk copy, hash-checked by relink.
                let e = p
                    .files
                    .iter()
                    .find(|e| e.path == path && e.kind == Kind::File)
                    .ok_or_else(|| Error::new(Code::Verify, format!("{path} is not a file of {pkg}")))?;
                return Ok((paths::resolve(&sys.root, path).map_err(|x| Error::new(Code::Verify, x))?, e.data.clone()));
            }
            let i = inst.iter().find(|i| i.name == pkg).ok_or_else(|| Error::new(Code::Conflict, format!("kernel input package {pkg} is not installed")))?;
            let e = i
                .files
                .iter()
                .find(|e| e.path == path && e.kind == Kind::File)
                .ok_or_else(|| Error::new(Code::Verify, format!("{path} is not a file of {pkg}")))?;
            Ok((paths::resolve(&sys.root, path).map_err(|x| Error::new(Code::Verify, x))?, e.data.clone()))
        };
        let out = kc::relink(&recipe, &locate, work, Duration::from_secs(600))?;
        fs::read(out)?
    } else {
        kc::read_collection(current)?
    };
    Ok((args, collection))
}

/// Restart the services the records name (design section 3.4). Returns whether a reboot is needed.
fn activate(sys: &Sys, pkgs: &[Pkg], boot_changed: bool) -> bool {
    let mut reboot = boot_changed;
    for p in pkgs {
        if p.rec.activate == "reboot" {
            reboot = true;
        }
        for s in &p.rec.services {
            match s.activate.as_str() {
                "reboot" => reboot = true,
                "restart" => restart(sys, &s.label),
                _ => {}
            }
        }
    }
    reboot
}

fn restart(sys: &Sys, label: &str) {
    let tool = {
        #[cfg(feature = "testing")]
        {
            std::env::var("SAP_LAUNCHCTL").ok()
        }
        #[cfg(not(feature = "testing"))]
        {
            None::<String>
        }
    };
    let tool = match tool {
        Some(t) => t,
        None if sys.image_mode => {
            println!("image mode: would restart {label}");
            return;
        }
        None => "/bin/launchctl".into(),
    };
    if label == "org.siliconforest.desktop" {
        println!("warning: the desktop session restarts now");
    }
    match std::process::Command::new(&tool).args(["kickstart", "-k", &format!("system/{label}")]).status() {
        Ok(s) if s.success() => println!("restarted {label}"),
        Ok(s) => eprintln!("sap: warning: restarting {label} failed ({s}); the update is applied; sap rollback is available"),
        Err(e) => eprintln!("sap: warning: restarting {label} failed ({e}); the update is applied; sap rollback is available"),
    }
}

/// `sap rollback [TXN]`: restore what a transaction replaced, from its backups, as a new transaction.
pub fn rollback(sys: &Sys, which: Option<&str>) -> Result<i32> {
    sys.require_writer()?;
    let _lock = sys.lock()?;
    for line in txn::recover(sys, false)? {
        eprintln!("sap: recovered {line}");
    }
    // Applied transactions, newest first, skipping ones already rolled back.
    let mut applied: Vec<String> = Vec::new();
    let mut undone: BTreeSet<String> = BTreeSet::new();
    for id in txn::list(sys).into_iter().rev() {
        let (_, recs) = Journal::open(sys, &id)?;
        if txn::outcome(&recs) != Some("done") {
            continue;
        }
        let begin = recs.iter().find(|r| r.kind == "begin");
        let kind = begin.and_then(|b| b.v.get("plan")).and_then(|p| p.get("kind")).and_then(|k| k.as_str()).unwrap_or("");
        if kind == "rollback" {
            if let Some(t) = begin.and_then(|b| b.v.get("plan")).and_then(|p| p.get("of")).and_then(|k| k.as_str()) {
                undone.insert(t.to_string());
            }
            continue;
        }
        if !undone.contains(&id) {
            applied.push(id);
        }
    }
    let target = applied.first().cloned().ok_or_else(|| Error::new(Code::Conflict, "there is no transaction to roll back".to_string()))?;
    if let Some(w) = which {
        if w != target {
            bail!(Conflict, "only the most recent applied transaction ({target}) can be rolled back; {w} is older or unknown");
        }
    }
    let (_, recs) = Journal::open(sys, &target)?;
    let ops = txn::intent(&recs).ok_or_else(|| Error::new(Code::Conflict, format!("{target} has no recorded operations")))?;
    let mut j = Journal::create(sys)?;
    j.append(
        "begin",
        vec![("txn", Value::str(j.id.clone())), ("plan", Value::obj(vec![("kind", Value::str("rollback")), ("of", Value::str(target.clone()))]))],
    )?;
    let sdir = sys.lib.join("staging").join(&j.id);
    let bdir = sys.lib.join("backup").join(&j.id);
    let mut new_ops = Vec::new();
    let res: Result<()> = (|| {
        for (k, o) in ops.iter().enumerate().rev() {
            if o.op == "arm" {
                // Not restarted yet: cancel the trial before its files are put back. Once started, the
                // default slot never changed and a trial without a clean start falls back by itself.
                match crate::boot::Tool::new(sys).and_then(|t| t.disarm(txn::slot_of(&o.path))) {
                    Ok(true) => println!("{}: the armed trial is cancelled (sf-bootslot disarm)", o.label),
                    Ok(false) => println!("note: {} is not armed any more; left as it is (sap boot-status)", o.label),
                    Err(e) => return Err(e),
                }
                continue;
            }
            let b = txn::base(sys, &o.area)?;
            let cur = txn::state_of(&b.join(&o.path));
            let expected = match o.op.as_str() {
                "put" | "remove" | "mkdir" => o.new.clone(),
                _ => None,
            };
            if o.op == "rmdir" {
                if o.old.is_some() && cur.is_none() {
                    new_ops.push(Op { op: "mkdir".into(), new: Some("d".into()), old: None, staged: None, backup: None, ..o.clone() });
                }
                continue;
            }
            if o.op == "mkdir" {
                if o.old.is_none() && cur.as_deref() == Some("d") {
                    new_ops.push(Op { op: "rmdir".into(), old: Some("d".into()), new: None, ..o.clone() });
                }
                continue;
            }
            if cur != expected {
                bail!(Conflict, "{} changed after {target}; refusing to roll back (run sap verify)", o.label);
            }
            match &o.old {
                Some(old) => {
                    let bk = b.join(o.backup.as_ref().unwrap());
                    if o.old == o.new && fs::symlink_metadata(&bk).is_err() {
                        continue; // the put found it already right and wrote nothing: nothing to undo
                    }
                    if txn::state_of(&bk).as_deref() != Some(old.as_str()) {
                        bail!(Conflict, "the backup of {} is gone (backups are kept for two transactions)", o.label);
                    }
                    let s = if o.area == "root" { sdir.join(format!("{k:06}")) } else { b.join("sf/.sap-staging").join(&j.id).join(format!("{k:06}")) };
                    fs::create_dir_all(s.parent().unwrap())?;
                    if old.starts_with("l:") {
                        std::os::unix::fs::symlink(fs::read_link(&bk)?, &s)?;
                    } else {
                        fs::copy(&bk, &s)?;
                        let m = fs::metadata(&bk)?;
                        use std::os::unix::fs::MetadataExt;
                        txn::finish_staged(&s, m.mode() & 0o7777, m.uid(), m.gid())?;
                    }
                    let srel = s.strip_prefix(&b).unwrap().to_string_lossy().to_string();
                    let bkrel = if o.area == "root" { rel(sys, &bdir.join(format!("{k:06}"))) } else { format!("{}.old", o.path) };
                    new_ops.push(Op { op: "put".into(), old: cur, new: Some(old.clone()), staged: Some(srel), backup: Some(bkrel), ..o.clone() });
                }
                None => {
                    let bkrel = if o.area == "root" { rel(sys, &bdir.join(format!("{k:06}"))) } else { format!("{}.removed", o.path) };
                    new_ops.push(Op { op: "remove".into(), old: cur, new: None, staged: None, backup: Some(bkrel), ..o.clone() });
                }
            }
        }
        Ok(())
    })();
    if let Err(e) = res {
        let _ = fs::remove_dir_all(&sdir);
        j.append("aborted", vec![("reason", Value::str(e.msg.clone())), ("recovered", Value::str("nothing changed"))])?;
        return Err(e);
    }
    txn::commit(sys, &mut j, &new_ops)?;
    j.append("done", vec![])?;
    let _ = fs::remove_dir_all(&sdir);
    if let Some(b) = &sys.sfboot {
        let _ = fs::remove_dir_all(b.join("sf/.sap-staging").join(&j.id));
    }
    println!("Rolled back {target} (transaction {}).", j.id);
    let boot = new_ops.iter().any(|o| o.area == "sfboot");
    if boot {
        println!("Reboot required.");
        return Ok(EXIT_REBOOT);
    }
    Ok(0)
}
