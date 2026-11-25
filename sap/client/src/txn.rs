// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//! The journaled swap (design sections 3.1 Commit, 3.6, 3.7). A transaction's journal is one file of
//! JSON lines in /var/db/sap/journal/, each record fsynced and hash-chained to the one before:
//! `begin`, `intent` (every operation: path, old state, new state, staged copy, backup), `swapped N`,
//! then `done` or `aborted`. Backups are hard links to the replaced inodes. Recovery decides from the
//! files on disk, not from the `swapped` records, so a crash between a rename and its record is safe.

use crate::error::{Code, Context, Error, Result};
use crate::json::Value;
use crate::sys::Sys;
use crate::{bail, util};
use std::fs;
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

#[derive(Clone, Debug, PartialEq)]
pub struct Op {
    /// put, remove, mkdir, rmdir
    pub op: String,
    /// root or sfboot
    pub area: String,
    /// On-disk path relative to the area's base (already resolved).
    pub path: String,
    /// What the user knows it as (package path), for messages.
    pub label: String,
    /// State before: `f:<sha256>`, `l:<target>`, `d`, or None for absent.
    pub old: Option<String>,
    pub new: Option<String>,
    pub staged: Option<String>,
    pub backup: Option<String>,
    pub mode: u32,
    pub uid: u32,
    pub gid: u32,
}

impl Op {
    fn to_json(&self) -> Value {
        let o = |x: &Option<String>| x.as_ref().map(|s| Value::str(s.clone())).unwrap_or(Value::Null);
        Value::obj(vec![
            ("op", Value::str(self.op.clone())),
            ("area", Value::str(self.area.clone())),
            ("path", Value::str(self.path.clone())),
            ("label", Value::str(self.label.clone())),
            ("old", o(&self.old)),
            ("new", o(&self.new)),
            ("staged", o(&self.staged)),
            ("backup", o(&self.backup)),
            ("mode", Value::Int(self.mode as i64)),
            ("uid", Value::Int(self.uid as i64)),
            ("gid", Value::Int(self.gid as i64)),
        ])
    }
    fn from_json(v: &Value) -> Option<Op> {
        let s = |k: &str| v.get(k).and_then(|x| x.as_str()).map(String::from);
        let n = |k: &str| v.get(k).and_then(|x| x.as_i64()).unwrap_or(0) as u32;
        Some(Op {
            op: s("op")?,
            area: s("area")?,
            path: s("path")?,
            label: s("label").unwrap_or_default(),
            old: s("old"),
            new: s("new"),
            staged: s("staged"),
            backup: s("backup"),
            mode: n("mode"),
            uid: n("uid"),
            gid: n("gid"),
        })
    }
}

// ---- fault injection (tests only) ----

static RECORDS: AtomicUsize = AtomicUsize::new(0);
static SWAPS: AtomicUsize = AtomicUsize::new(0);

#[allow(unused_variables)]
fn fault(kind: &str, n: usize) {
    #[cfg(feature = "testing")]
    if let Ok(f) = std::env::var("SAP_FAULT") {
        if f == format!("{kind}:{n}") {
            eprintln!("sap: SAP_FAULT {f}: aborting");
            std::process::abort();
        }
    }
}

// ---- the journal ----

pub struct Journal {
    pub path: PathBuf,
    pub id: String,
    prev: String,
}

pub struct Record {
    pub kind: String,
    pub v: Value,
}

impl Journal {
    pub fn create(sys: &Sys) -> Result<Journal> {
        let dir = sys.journal_dir();
        fs::create_dir_all(&dir).ctx(|| format!("create {}", dir.display()))?;
        let base = util::format_rfc3339(util::now()).replace(['-', ':'], "");
        for k in 0..1000 {
            let id = format!("{base}-{k:03}");
            let path = dir.join(format!("{id}.jsonl"));
            if !path.exists() && !dir.join(format!("{id}.jsonl")).exists() {
                return Ok(Journal { path, id, prev: "0".repeat(64) });
            }
        }
        bail!(Failure, "cannot name a new transaction")
    }

    pub fn open(sys: &Sys, id: &str) -> Result<(Journal, Vec<Record>)> {
        let path = sys.journal_dir().join(format!("{id}.jsonl"));
        let text = fs::read_to_string(&path).ctx(|| format!("read {}", path.display()))?;
        let mut prev = "0".repeat(64);
        let mut recs = Vec::new();
        let lines: Vec<&str> = text.lines().collect();
        for (i, l) in lines.iter().enumerate() {
            let v = match crate::json::parse(l.as_bytes()) {
                Ok(v) => v,
                Err(_) if i + 1 == lines.len() && !text.ends_with('\n') => break, // torn final write
                Err(e) => bail!(Interrupted, "journal {id} is corrupt at record {}: {e}", i + 1),
            };
            if v.get("prev").and_then(|p| p.as_str()) != Some(prev.as_str()) {
                bail!(Interrupted, "journal {id} hash chain is broken at record {}", i + 1);
            }
            prev = util::sha256(l.as_bytes());
            recs.push(Record { kind: v.get("record").and_then(|k| k.as_str()).unwrap_or("").to_string(), v });
        }
        Ok((Journal { path, id: id.to_string(), prev }, recs))
    }

    pub fn append(&mut self, kind: &str, mut fields: Vec<(&str, Value)>) -> Result<()> {
        let mut items = vec![("record", Value::str(kind)), ("time", Value::str(util::format_rfc3339(util::now()))), ("prev", Value::str(self.prev.clone()))];
        items.append(&mut fields);
        let line = Value::obj(items).to_string_compact();
        util::append_line_durable(&self.path, &line)?;
        if self.prev == "0".repeat(64) {
            util::fsync_dir(self.path.parent().unwrap());
        }
        self.prev = util::sha256(line.as_bytes());
        let n = RECORDS.fetch_add(1, Ordering::SeqCst) + 1;
        fault("rec", n);
        Ok(())
    }
}

pub fn list(sys: &Sys) -> Vec<String> {
    let mut ids: Vec<String> = fs::read_dir(sys.journal_dir())
        .map(|r| r.filter_map(|e| e.ok()).filter_map(|e| e.file_name().to_string_lossy().strip_suffix(".jsonl").map(String::from)).collect())
        .unwrap_or_default();
    ids.sort();
    ids
}

pub fn outcome(recs: &[Record]) -> Option<&str> {
    recs.iter().rev().find(|r| r.kind == "done" || r.kind == "aborted").map(|r| r.kind.as_str())
}

pub fn intent(recs: &[Record]) -> Option<Vec<Op>> {
    let r = recs.iter().find(|r| r.kind == "intent")?;
    r.v.get("ops")?.as_array()?.iter().map(Op::from_json).collect()
}

// ---- operations ----

pub fn base(sys: &Sys, area: &str) -> Result<PathBuf> {
    match area {
        "root" => Ok(sys.root.clone()),
        "sfboot" => sys
            .sfboot
            .clone()
            .ok_or_else(|| Error::new(Code::Failure, "the boot partition (SFBOOT) is not available; pass --sfboot or set sfboot in /etc/sap.conf".to_string())),
        _ => bail!(Failure, "unknown area {area}"),
    }
}

/// `f:<sha256>`, `l:<target>`, `d`, `x` (other), or None if absent. Never follows a final symlink.
pub fn state_of(p: &Path) -> Option<String> {
    let m = fs::symlink_metadata(p).ok()?;
    let t = m.file_type();
    Some(if t.is_symlink() {
        format!("l:{}", fs::read_link(p).map(|x| x.to_string_lossy().to_string()).unwrap_or_default())
    } else if t.is_dir() {
        "d".into()
    } else if t.is_file() {
        format!("f:{}", util::sha256_file(p).map(|x| x.0).unwrap_or_default())
    } else {
        "x".into()
    })
}

fn set_owner(p: &Path, uid: u32, gid: u32, follow: bool) -> Result<()> {
    if !util::is_root() {
        return Ok(()); // fake roots in tests (sys.require_writer allowed it); owners are checked by verify as root
    }
    let r = if follow { std::os::unix::fs::chown(p, Some(uid), Some(gid)) } else { std::os::unix::fs::lchown(p, Some(uid), Some(gid)) };
    r.ctx(|| format!("chown {}", p.display()))
}

/// Whether an existing path already has the op's mode and owner (links: always; owners only as root).
pub fn meta_matches(p: &Path, mode: u32, uid: u32, gid: u32) -> bool {
    use std::os::unix::fs::MetadataExt;
    match fs::symlink_metadata(p) {
        Ok(m) if m.file_type().is_symlink() => true,
        Ok(m) => (m.mode() & 0o7777) == mode && (!util::is_root() || (m.uid() == uid && m.gid() == gid)),
        Err(_) => false,
    }
}

/// Give a staged file or link its final mode and owner (from the signed file list).
pub fn finish_staged(p: &Path, mode: u32, uid: u32, gid: u32) -> Result<()> {
    let m = fs::symlink_metadata(p)?;
    if !m.file_type().is_symlink() {
        set_owner(p, uid, gid, true)?;
        fs::set_permissions(p, fs::Permissions::from_mode(mode)).ctx(|| format!("chmod {}", p.display()))?;
        fs::File::open(p)?.sync_all()?;
    } else {
        set_owner(p, uid, gid, false)?;
    }
    Ok(())
}

fn backup_copy(src: &Path, dst: &Path, hardlink: bool) -> Result<()> {
    if let Some(d) = dst.parent() {
        fs::create_dir_all(d)?;
    }
    let m = fs::symlink_metadata(src)?;
    if m.file_type().is_symlink() {
        std::os::unix::fs::symlink(fs::read_link(src)?, dst)?;
        return Ok(());
    }
    if hardlink && fs::hard_link(src, dst).is_ok() {
        return Ok(());
    }
    // FAT32 (SFBOOT) or another filesystem: a durable copy, mode and owner kept.
    let tmp = dst.with_extension("sap-tmp");
    fs::copy(src, &tmp).ctx(|| format!("copy {} to {}", src.display(), tmp.display()))?;
    let _ = set_owner(&tmp, m.uid(), m.gid(), true);
    fs::File::open(&tmp)?.sync_all()?;
    fs::rename(&tmp, dst)?;
    util::fsync_dir(dst.parent().unwrap());
    Ok(())
}

fn rename_durable(from: &Path, to: &Path) -> Result<()> {
    fs::rename(from, to).ctx(|| format!("rename {} to {}", from.display(), to.display()))?;
    util::fsync_dir(to.parent().unwrap());
    if from.parent() != to.parent() {
        util::fsync_dir(from.parent().unwrap());
    }
    Ok(())
}

pub fn forward(sys: &Sys, op: &Op) -> Result<()> {
    let b = base(sys, &op.area)?;
    let target = b.join(&op.path);
    let cur = state_of(&target);
    match op.op.as_str() {
        "put" => {
            if cur == op.new && (op.area != "root" || meta_matches(&target, op.mode, op.uid, op.gid)) {
                return Ok(());
            }
            let staged = b.join(op.staged.as_ref().ok_or_else(|| Error::new(Code::Failure, "put without a staged file".to_string()))?);
            if state_of(&staged) != op.new {
                bail!(Interrupted, "{}: the staged copy is missing or damaged", op.label);
            }
            if cur.is_some() {
                if cur.as_deref() == Some("d") {
                    bail!(Conflict, "{}: a directory is in the way", op.label);
                }
                if let Some(bk) = &op.backup {
                    let bk = b.join(bk);
                    if fs::symlink_metadata(&bk).is_err() {
                        backup_copy(&target, &bk, op.area == "root")?;
                    }
                }
            }
            if let Some(d) = target.parent() {
                fs::create_dir_all(d)?;
            }
            rename_durable(&staged, &target)?;
        }
        "remove" => {
            if cur.is_none() {
                return Ok(());
            }
            let bk = b.join(op.backup.as_ref().ok_or_else(|| Error::new(Code::Failure, "remove without a backup path".to_string()))?);
            if fs::symlink_metadata(&bk).is_ok() {
                fs::remove_file(&target)?;
                util::fsync_dir(target.parent().unwrap());
            } else {
                fs::create_dir_all(bk.parent().unwrap())?;
                rename_durable(&target, &bk)?;
            }
        }
        "mkdir" => {
            if cur.is_none() {
                fs::create_dir_all(&target).ctx(|| format!("mkdir {}", target.display()))?;
                set_owner(&target, op.uid, op.gid, true)?;
                fs::set_permissions(&target, fs::Permissions::from_mode(op.mode))?;
                util::fsync_dir(target.parent().unwrap());
            }
        }
        "rmdir" => {
            if cur.as_deref() == Some("d") {
                let _ = fs::remove_dir(&target); // only if empty; shared directories stay
            }
        }
        "arm" => {
            // A/B slots: the last operation. The slot's files were written before the commit point.
            if cur != op.new {
                bail!(Interrupted, "{}: the slot's stage 2 is missing or damaged; not arming it", op.label);
            }
            crate::boot::Tool::new(sys)?.arm(slot_of(&op.path), op.mode)?;
        }
        o => bail!(Failure, "unknown operation {o}"),
    }
    Ok(())
}

pub fn slot_of(boot_rel: &str) -> char {
    if boot_rel.starts_with("sf/b/") {
        'b'
    } else {
        'a'
    }
}

pub fn backward(sys: &Sys, op: &Op) -> Result<()> {
    let b = base(sys, &op.area)?;
    let target = b.join(&op.path);
    let cur = state_of(&target);
    match op.op.as_str() {
        "put" | "remove" => {
            if cur == op.old {
                return Ok(());
            }
            let bk = op.backup.as_ref().map(|x| b.join(x));
            match (&op.old, bk) {
                (Some(old), Some(bk)) if state_of(&bk).as_deref() == Some(old.as_str()) => {
                    if op.area == "root" {
                        rename_durable(&bk, &target)?;
                    } else {
                        let tmp = target.with_extension("sap-restore");
                        backup_copy(&bk, &tmp, false)?;
                        rename_durable(&tmp, &target)?;
                    }
                }
                (None, _) => {
                    if cur.is_some() && (cur == op.new || op.op == "put") {
                        fs::remove_file(&target).ctx(|| format!("remove {}", target.display()))?;
                        util::fsync_dir(target.parent().unwrap());
                    }
                }
                _ => bail!(Interrupted, "{}: cannot restore the old version, its backup is missing or damaged", op.label),
            }
        }
        "mkdir" => {
            if op.old.is_none() && cur.as_deref() == Some("d") {
                let _ = fs::remove_dir(&target);
            }
        }
        "arm" => {
            // Rolled back before the restart: cancel the ARMED trial (sf-bootslot disarm). The slot is
            // left unrecorded, as begin-stage left it; its files are put back by the operations before.
            crate::boot::Tool::new(sys)?.disarm(slot_of(&op.path))?;
        }
        "rmdir" if op.old.is_some() && cur.is_none() => {
            fs::create_dir_all(&target)?;
            fs::set_permissions(&target, fs::Permissions::from_mode(op.mode))?;
        }
        _ => {}
    }
    Ok(())
}

fn can_forward(sys: &Sys, op: &Op) -> bool {
    let Ok(b) = base(sys, &op.area) else { return false };
    match op.op.as_str() {
        "arm" => state_of(&b.join(&op.path)) == op.new,
        "put" => state_of(&b.join(&op.path)) == op.new || op.staged.as_ref().map(|s| state_of(&b.join(s)) == op.new).unwrap_or(false),
        _ => true,
    }
}

/// Commit: write the intent, then every operation in order. A failure part-way rolls back the
/// operations already done, in reverse order (design section 3.6, "Rename fails").
pub fn commit(sys: &Sys, j: &mut Journal, ops: &[Op]) -> Result<()> {
    // SFBOOT keeps one `<file>.old` per file, named without the transaction: a leftover from an earlier
    // transaction is replaced, so this transaction's backup is of what it actually replaces.
    for op in ops.iter().filter(|o| o.area == "sfboot" && o.op == "put") {
        if let Some(bk) = &op.backup {
            let p = base(sys, "sfboot")?.join(bk);
            if fs::symlink_metadata(&p).is_ok() {
                fs::remove_file(&p).ctx(|| format!("remove the old backup {}", p.display()))?;
            }
        }
    }
    j.append("intent", vec![("ops", Value::Array(ops.iter().map(|o| o.to_json()).collect()))])?;
    for (i, op) in ops.iter().enumerate() {
        if let Err(e) = forward(sys, op) {
            let mut undo_err = None;
            for back in ops[..=i].iter().rev() {
                if let Err(u) = backward(sys, back) {
                    undo_err = Some(u);
                }
            }
            if let Some(u) = undo_err {
                return Err(Error::new(Code::Interrupted, format!("{e}; undoing it also failed ({u}); run sap recover")));
            }
            j.append("aborted", vec![("reason", Value::str(e.msg.clone())), ("recovered", Value::str("rollback"))])?;
            return Err(e);
        }
        let n = SWAPS.fetch_add(1, Ordering::SeqCst) + 1;
        fault("op", n);
        j.append("swapped", vec![("op", Value::Int(i as i64))])?;
    }
    Ok(())
}

/// Finish or undo every interrupted transaction. Returns a line per transaction handled.
pub fn recover(sys: &Sys, force_rollback: bool) -> Result<Vec<String>> {
    let mut out = Vec::new();
    for id in list(sys) {
        let (mut j, recs) = Journal::open(sys, &id)?;
        if outcome(&recs).is_some() || recs.is_empty() {
            continue;
        }
        let staging = sys.lib.join("staging").join(&id);
        match intent(&recs) {
            None => {
                j.append("aborted", vec![("reason", Value::str("interrupted before the commit point")), ("recovered", Value::str("nothing changed"))])?;
                out.push(format!("{id}: interrupted before the commit point; nothing had changed"));
            }
            Some(ops) => {
                let fwd = !force_rollback && ops.iter().all(|o| can_forward(sys, o));
                if fwd {
                    for o in &ops {
                        forward(sys, o)?;
                    }
                    j.append("done", vec![("recovered", Value::str("forward"))])?;
                    out.push(format!("{id}: finished (every new file was staged and intact); services were not restarted"));
                } else {
                    for o in ops.iter().rev() {
                        backward(sys, o)?;
                    }
                    j.append("aborted", vec![("reason", Value::str("interrupted during the swap")), ("recovered", Value::str("rollback"))])?;
                    out.push(format!("{id}: rolled back to the versions before it"));
                }
            }
        }
        let _ = fs::remove_dir_all(&staging);
        if let Some(sb) = &sys.sfboot {
            let _ = fs::remove_dir_all(sb.join("sf/.sap-staging").join(&id));
        }
    }
    Ok(out)
}

pub fn interrupted(sys: &Sys) -> Vec<String> {
    list(sys).into_iter().filter(|id| Journal::open(sys, id).map(|(_, r)| !r.is_empty() && outcome(&r).is_none()).unwrap_or(true)).collect()
}

/// Keep the backups of the last `keep` completed transactions; delete older ones.
pub fn prune_backups(sys: &Sys, keep: usize) {
    let done: Vec<String> = list(sys).into_iter().filter(|id| Journal::open(sys, id).map(|(_, r)| outcome(&r) == Some("done")).unwrap_or(false)).collect();
    let keepers: Vec<&String> = done.iter().rev().take(keep).collect();
    if let Ok(rd) = fs::read_dir(sys.lib.join("backup")) {
        for e in rd.filter_map(|e| e.ok()) {
            let n = e.file_name().to_string_lossy().to_string();
            if !keepers.iter().any(|k| **k == n) {
                let _ = fs::remove_dir_all(e.path());
            }
        }
    }
}
