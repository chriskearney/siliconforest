// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//! The read-mostly commands: check, list, show, verify, history, hold, unhold, recover.

use crate::apply::{self, UpgradeArgs};
use crate::error::{Code, Result};
use crate::json::Value;
use crate::repo;
use crate::sys::Sys;
use crate::tsv::Kind;
use crate::txn::{self, Journal};
use crate::version::compare;
use crate::{bail, paths, util};
use std::os::unix::fs::MetadataExt;

pub const EXIT_UPDATES: i32 = 10;

fn upgradable(sys: &Sys, m: &crate::manifest::Manifest) -> Result<Vec<(String, String, String)>> {
    let mut out = Vec::new();
    for i in sys.installed()? {
        if let Some(e) = m.get(&i.name) {
            if compare(&e.version, &i.version).is_gt() {
                out.push((i.name.clone(), i.version.clone(), e.version.clone()));
            }
        }
    }
    Ok(out)
}

pub fn check(sys: &Sys) -> Result<i32> {
    let l = if util::is_root() || sys.require_writer().is_ok() {
        let _lock = sys.lock()?;
        repo::load_and_remember(sys)?
    } else {
        repo::load(sys, false)?
    };
    let up = upgradable(sys, &l.m)?;
    let held = sys.state()?.held;
    if sys.opts.json {
        let v = Value::obj(vec![
            ("release", Value::str(l.m.release.clone())),
            ("sequence", Value::Int(l.m.sequence)),
            ("expires", Value::str(util::format_rfc3339(l.m.expires))),
            (
                "upgradable",
                Value::Array(
                    up.iter()
                        .map(|(n, a, b)| {
                            Value::obj(vec![
                                ("name", Value::str(n.clone())),
                                ("installed", Value::str(a.clone())),
                                ("available", Value::str(b.clone())),
                                ("held", Value::Bool(held.contains(n))),
                            ])
                        })
                        .collect(),
                ),
            ),
        ]);
        print!("{}", v.to_string_pretty());
    } else {
        println!("Manifest: release {}, sequence {}, valid until {}.", l.m.release, l.m.sequence, util::format_rfc3339(l.m.expires));
        if up.is_empty() {
            println!("Up to date.");
        }
        for (n, a, b) in &up {
            println!("  {n}: {a} -> {b}{}", if held.contains(n) { " (held)" } else { "" });
        }
    }
    Ok(if up.is_empty() { 0 } else { EXIT_UPDATES })
}

pub fn list(sys: &Sys, filter: &str) -> Result<i32> {
    let inst = sys.installed()?;
    let m = repo::load(sys, true).ok().map(|l| l.m);
    let mut names: Vec<String> = inst.iter().map(|i| i.name.clone()).collect();
    if let Some(m) = &m {
        names.extend(m.packages.iter().map(|p| p.name.clone()));
    }
    names.sort();
    names.dedup();
    let mut rows = Vec::new();
    for n in names {
        let i = inst.iter().find(|i| i.name == n);
        let a = m.as_ref().and_then(|m| m.get(&n));
        let up = matches!((i, a), (Some(i), Some(a)) if compare(&a.version, &i.version).is_gt());
        let keep = match filter {
            "installed" => i.is_some(),
            "upgradable" => up,
            "available" => a.is_some(),
            _ => true,
        };
        if keep {
            let kind = i.map(|x| x.kind.clone()).or(a.map(|x| x.kind.clone())).unwrap_or_default();
            rows.push((n, i.map(|x| x.version.clone()).unwrap_or("-".into()), a.map(|x| x.version.clone()).unwrap_or("-".into()), kind));
        }
    }
    if sys.opts.json {
        print!(
            "{}",
            Value::Array(
                rows.iter()
                    .map(|(n, i, a, k)| Value::obj(vec![
                        ("name", Value::str(n.clone())),
                        ("installed", Value::str(i.clone())),
                        ("available", Value::str(a.clone())),
                        ("kind", Value::str(k.clone()))
                    ]))
                    .collect()
            )
            .to_string_pretty()
        );
    } else {
        println!("{:<32} {:<16} {:<16} KIND", "NAME", "INSTALLED", "AVAILABLE");
        for (n, i, a, k) in rows {
            println!("{n:<32} {i:<16} {a:<16} {k}");
        }
    }
    Ok(0)
}

pub fn show(sys: &Sys, name: &str) -> Result<i32> {
    let inst = sys.installed()?.into_iter().find(|i| i.name == name);
    let l = repo::load(sys, true).ok();
    let idx = l.as_ref().and_then(|l| l.m.get(name).cloned());
    let rec = match (&l, &idx) {
        (Some(l), Some(i)) => apply::fetch_meta(sys, l, i).ok().map(|(r, f, _)| (r, f)),
        _ => None,
    };
    if inst.is_none() && idx.is_none() {
        bail!(Failure, "{name}: no such package installed or in the cached manifest");
    }
    let summary = rec
        .as_ref()
        .map(|(r, _)| r.summary.clone())
        .or(inst.as_ref().and_then(|i| i.record.get("summary").and_then(|s| s.as_str()).map(String::from)))
        .unwrap_or_default();
    println!("Package:    {name}");
    if !summary.is_empty() {
        println!("Summary:    {summary}");
    }
    if let Some(i) = &inst {
        println!("Installed:  {} (transaction {})", i.version, i.txn);
        println!("Kind:       {}", i.kind);
        let bytes: u64 = i.files.iter().filter(|e| e.kind == Kind::File).map(|e| e.size).sum();
        println!("Files:      {} entries, {bytes} bytes", i.files.len());
    }
    if let Some(i) = &idx {
        println!("Available:  {}", i.version);
        let deps: Vec<String> = i
            .depends
            .iter()
            .map(|d| match &d.constraint {
                Some(c) => format!("{} ({c})", d.name),
                None => d.name.clone(),
            })
            .collect();
        println!("Depends:    {}", if deps.is_empty() { "-".into() } else { deps.join(", ") });
        println!("Activate:   {}", i.activate);
    }
    if let Some((r, f)) = &rec {
        if let Some(p) = &r.payload {
            println!("Payload:    {} bytes ({})", p.bytes, p.format);
        }
        println!("New files:  {} entries", f.len());
        if !r.services.is_empty() {
            println!("Services:   {}", r.services.iter().map(|s| format!("{} ({})", s.label, s.activate)).collect::<Vec<_>>().join(", "));
        }
        if !r.config_files.is_empty() {
            println!("Config:     {}", r.config_files.join(", "));
        }
        println!("Reboot:     {}", if r.activate == "reboot" || r.services.iter().any(|s| s.activate == "reboot") { "yes" } else { "no" });
    }
    if sys.opts.verbose {
        if let Some(i) = &inst {
            for e in &i.files {
                println!("  {}", e.path);
            }
        }
    }
    Ok(0)
}

/// Audit installed files against the stored file lists (mode, owner, size, SHA-256).
pub fn verify(sys: &Sys, names: &[String], repair: bool) -> Result<i32> {
    let inst = sys.installed()?;
    let check_owner = util::is_root();
    let mut damaged: Vec<String> = Vec::new();
    let mut problems = 0;
    // Boot packages: with A/B slots only the slot SAP last staged (the trial, else the default) holds
    // the installed sf-boot; with the legacy layout slot B's files are not installed at all.
    let checked_slot: Option<char> = if sys.sfboot.is_some() && inst.iter().any(|i| i.target() == "sfboot") {
        match crate::boot::backend(sys)? {
            crate::boot::Backend::Slots => {
                let st = crate::boot::Tool::new(sys)?.status()?;
                let sb = sys.sfboot.clone().unwrap();
                Some(match (st.trial, st.trial_state.as_str()) {
                    // A trial cancelled by a rollback (its stage 2 renamed away) no longer counts.
                    (Some(t), "armed" | "tried") if sb.join(crate::boot::boot_path(t)).exists() => t,
                    _ => st.default,
                })
            }
            crate::boot::Backend::Legacy => None,
        }
    } else {
        None
    };
    let skip_boot = |path: &str| -> bool {
        match checked_slot {
            Some(c) => (path == "/sf/boot.bin" || path == "/sf/b/boot.bin") && path[1..] != *crate::boot::boot_path(c),
            None => paths::under(path, "/sf/b"),
        }
    };
    for i in &inst {
        if !names.is_empty() && !names.contains(&i.name) {
            continue;
        }
        let cfg = i.config_files();
        let boot = i.target() == "sfboot";
        let mut bad = false;
        for e in &i.files {
            if paths::is_protected(&e.path) {
                continue;
            }
            if boot && skip_boot(&e.path) {
                continue;
            }
            let p = if boot {
                match &sys.sfboot {
                    Some(b) => b.join(&e.path[1..]),
                    None => continue,
                }
            } else {
                match paths::resolve(&sys.root, &e.path) {
                    Ok(p) => p,
                    Err(x) => {
                        println!("{}: {x}", i.name);
                        bad = true;
                        continue;
                    }
                }
            };
            let mut why = Vec::new();
            match std::fs::symlink_metadata(&p) {
                Err(_) => why.push("missing".to_string()),
                Ok(m) => {
                    let ft = m.file_type();
                    match e.kind {
                        Kind::File if !ft.is_file() => why.push("not a regular file".into()),
                        Kind::Dir if !ft.is_dir() => why.push("not a directory".into()),
                        Kind::Link if !ft.is_symlink() => why.push("not a symlink".into()),
                        Kind::Link => {
                            if std::fs::read_link(&p).map(|t| t.to_string_lossy() != e.data).unwrap_or(true) {
                                why.push("link target differs".into());
                            }
                        }
                        Kind::File => {
                            if m.len() != e.size {
                                why.push(format!("size {} (expected {})", m.len(), e.size));
                            } else if util::sha256_file(&p).map(|x| x.0 != e.data).unwrap_or(true) {
                                why.push("content differs".into());
                            }
                        }
                        _ => {}
                    }
                    if e.kind != Kind::Link && !boot && m.mode() & 0o7777 != e.mode {
                        why.push(format!("mode {:04o} (expected {:04o})", m.mode() & 0o7777, e.mode));
                    }
                    if check_owner && e.kind != Kind::Link && !boot && (m.uid() != e.uid || m.gid() != e.gid) {
                        why.push(format!("owner {}:{} (expected {}:{})", m.uid(), m.gid(), e.uid, e.gid));
                    }
                }
            }
            if !why.is_empty() {
                if cfg.contains(&e.path) && why.iter().all(|w| w.starts_with("content") || w.starts_with("size")) {
                    println!("{}: {} locally modified (config file)", i.name, e.path);
                    continue;
                }
                println!("{}: {} {}", i.name, e.path, why.join(", "));
                problems += 1;
                bad = true;
            }
        }
        if bad {
            damaged.push(i.name.clone());
        }
    }
    if damaged.is_empty() {
        println!("All installed files match their packages.");
        return Ok(0);
    }
    println!("{problems} problem(s) in: {}", damaged.join(", "));
    if !repair {
        return Ok(Code::Verify as i32);
    }
    let a = UpgradeArgs { names: damaged.clone(), reinstall: damaged, boot: true, ..Default::default() };
    apply::upgrade(sys, &a)
}

pub fn history(sys: &Sys) -> Result<i32> {
    let mut rows = Vec::new();
    for id in txn::list(sys) {
        let (_, recs) = match Journal::open(sys, &id) {
            Ok(x) => x,
            Err(e) => {
                println!("{id}: {e}");
                continue;
            }
        };
        let begin = recs.iter().find(|r| r.kind == "begin");
        let plan = begin.and_then(|b| b.v.get("plan")).cloned().unwrap_or(Value::Null);
        let kind = plan.get("kind").and_then(|k| k.as_str()).unwrap_or("?").to_string();
        let time = begin.and_then(|b| b.v.get("time")).and_then(|t| t.as_str()).unwrap_or("").to_string();
        let outcome = match txn::outcome(&recs) {
            Some(o) => {
                let rec = recs.iter().rev().find(|r| r.kind == o).and_then(|r| r.v.get("recovered")).and_then(|x| x.as_str());
                match rec {
                    Some(how) => format!("{o} (recovered: {how})"),
                    None => o.to_string(),
                }
            }
            None => "INTERRUPTED (run sap recover)".into(),
        };
        let pk: Vec<String> = plan
            .get("packages")
            .and_then(|p| p.as_array())
            .map(|a| {
                a.iter()
                    .map(|p| {
                        format!(
                            "{} {}->{}",
                            p.get("name").and_then(|x| x.as_str()).unwrap_or("?"),
                            p.get("from").and_then(|x| x.as_str()).unwrap_or("-"),
                            p.get("to").and_then(|x| x.as_str()).unwrap_or("?")
                        )
                    })
                    .collect()
            })
            .unwrap_or_default();
        let detail = if kind == "rollback" { format!("of {}", plan.get("of").and_then(|x| x.as_str()).unwrap_or("?")) } else { pk.join(", ") };
        let seq = plan.get("sequence").and_then(|s| s.as_i64()).map(|s| s.to_string()).unwrap_or("-".into());
        let keep = sys.lib.join("backup").join(&id).exists();
        rows.push((id, time, kind, seq, detail, outcome, keep));
    }
    if sys.opts.json {
        print!(
            "{}",
            Value::Array(
                rows.iter()
                    .map(|r| Value::obj(vec![
                        ("txn", Value::str(r.0.clone())),
                        ("time", Value::str(r.1.clone())),
                        ("kind", Value::str(r.2.clone())),
                        ("sequence", Value::str(r.3.clone())),
                        ("detail", Value::str(r.4.clone())),
                        ("outcome", Value::str(r.5.clone())),
                        ("backups_kept", Value::Bool(r.6))
                    ]))
                    .collect()
            )
            .to_string_pretty()
        );
    } else {
        for (id, time, kind, seq, detail, outcome, keep) in rows {
            println!("{id}  {time}  {kind:<8} seq {seq:<4} {outcome}{}  {detail}", if keep { ", rollbackable" } else { "" });
        }
    }
    Ok(0)
}

pub fn hold(sys: &Sys, names: &[String], on: bool) -> Result<i32> {
    sys.require_writer()?;
    let _lock = sys.lock()?;
    let mut st = sys.state()?;
    for n in names {
        if on {
            if !st.held.contains(n) {
                st.held.push(n.clone());
            }
            println!("{n} held");
        } else {
            st.held.retain(|h| h != n);
            println!("{n} no longer held");
        }
    }
    st.held.sort();
    sys.write_state(&st)?;
    Ok(0)
}

pub fn recover(sys: &Sys, rollback: bool) -> Result<i32> {
    sys.require_writer()?;
    let _lock = sys.lock()?;
    let lines = txn::recover(sys, rollback)?;
    if lines.is_empty() {
        println!("No interrupted transaction.");
    }
    for l in lines {
        println!("{l}");
    }
    Ok(0)
}

/// `sap boot-status`: the A/B boot record (sf-bootslot status), or the legacy layout.
pub fn boot_status(sys: &Sys) -> Result<i32> {
    match crate::boot::backend(sys)? {
        crate::boot::Backend::Legacy => {
            println!("boot: legacy layout (no {}); updates replace sf/boot.bin and sf/kernel.bin in place, keeping .old copies", crate::boot::STATE_FILE)
        }
        crate::boot::Backend::Slots => print!("{}", crate::boot::Tool::new(sys)?.status()?.raw),
    }
    Ok(0)
}

/// `sap mark-good`: after a clean start from an updated slot, make it the default (design 10.4).
pub fn mark_good(sys: &Sys) -> Result<i32> {
    sys.require_writer()?;
    if crate::boot::backend(sys)? != crate::boot::Backend::Slots {
        println!("boot: legacy layout; nothing to mark");
        return Ok(0);
    }
    print!("{}", crate::boot::Tool::new(sys)?.mark_good()?);
    Ok(0)
}
