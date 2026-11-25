// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//! Dependency resolution (design section 4.4): one version per package in the channel, so this is a
//! closure and a check, not a search. Holds are failures, never silent overrides. No removal by
//! dependency. Ordered topologically, `sap` first.

use crate::error::Result;
use crate::manifest::{Dep, Manifest};
use crate::version::compare;
use crate::{bail, err};
use std::cmp::Ordering;
use std::collections::{BTreeMap, BTreeSet};

pub const BOOT_KINDS: &[&str] = &["kc-input", "kc-recipe", "boot-stage2"];

pub struct InstalledView {
    pub version: String,
    pub depends: Vec<Dep>,
    pub conflicts: Vec<Dep>,
}

#[derive(Debug, Default)]
pub struct Resolution {
    /// Package names to install or upgrade, dependencies first.
    pub order: Vec<String>,
    pub notes: Vec<String>,
}

pub struct Request<'a> {
    /// None: every upgradable installed package. Some: these names (install if absent).
    pub names: Option<&'a [String]>,
    pub reinstall: &'a [String],
    pub held: &'a [String],
    pub allow_boot: bool,
}

pub fn resolve(installed: &BTreeMap<String, InstalledView>, m: &Manifest, req: &Request) -> Result<Resolution> {
    let mut res = Resolution::default();
    let mut t: BTreeSet<String> = BTreeSet::new();
    let mut why: BTreeMap<String, String> = BTreeMap::new();
    let is_boot = |n: &str| m.get(n).map(|e| BOOT_KINDS.contains(&e.kind.as_str())).unwrap_or(false);
    let held = |n: &str| req.held.iter().any(|h| h == n);
    match req.names {
        None => {
            for (n, iv) in installed {
                let Some(e) = m.get(n) else { continue };
                match compare(&e.version, &iv.version) {
                    Ordering::Greater if held(n) => res.notes.push(format!("{n} is held at {} ({} available)", iv.version, e.version)),
                    Ordering::Greater if is_boot(n) && !req.allow_boot => {
                        res.notes.push(format!("{n} {} needs --boot (kernel or boot-partition update)", e.version))
                    }
                    Ordering::Greater => {
                        t.insert(n.clone());
                    }
                    Ordering::Less => res.notes.push(format!("{n}: the channel has {}, older than the installed {}; not downgrading", e.version, iv.version)),
                    Ordering::Equal => {}
                }
            }
        }
        Some(names) => {
            for n in names {
                let e = m.get(n).ok_or_else(|| err!(Conflict, "{n} is not in the channel"))?;
                if held(n) {
                    bail!(Conflict, "{n} is held; run sap unhold {n} first");
                }
                if is_boot(n) && !req.allow_boot {
                    bail!(Conflict, "{n} is a kernel or boot-partition package; pass --boot");
                }
                if let Some(iv) = installed.get(n) {
                    match compare(&e.version, &iv.version) {
                        Ordering::Less => {
                            res.notes.push(format!("{n}: the channel has {}, older than the installed {}; not downgrading", e.version, iv.version));
                            continue;
                        }
                        Ordering::Equal if !req.reinstall.contains(n) => {
                            res.notes.push(format!("{n} {} is already installed", iv.version));
                            continue;
                        }
                        _ => {}
                    }
                }
                t.insert(n.clone());
            }
        }
    }
    // Closure: every package of the after-state must have its dependencies met by the after-state.
    loop {
        let after = |n: &str, t: &BTreeSet<String>| -> Option<String> {
            if t.contains(n) {
                m.get(n).map(|e| e.version.clone())
            } else {
                installed.get(n).map(|i| i.version.clone())
            }
        };
        let mut add: Option<(String, String)> = None;
        let mut names: Vec<String> = installed.keys().cloned().collect();
        names.extend(t.iter().cloned());
        names.sort();
        names.dedup();
        'outer: for p in &names {
            let deps: &[Dep] = if t.contains(p) { &m.get(p).unwrap().depends } else { &installed[p].depends };
            for d in deps {
                let ok = after(&d.name, &t).map(|v| d.constraint.as_ref().is_none_or(|c| c.allows(&v))).unwrap_or(false);
                if ok {
                    continue;
                }
                let chain = {
                    let mut c = vec![p.clone()];
                    let mut x = p.clone();
                    while let Some(w) = why.get(&x) {
                        c.push(w.clone());
                        x = w.clone();
                        if c.len() > 64 {
                            break;
                        }
                    }
                    c.reverse();
                    c.join(" -> ")
                };
                let want = match &d.constraint {
                    Some(c) => format!("{} ({c})", d.name),
                    None => d.name.clone(),
                };
                let Some(e) = m.get(&d.name) else {
                    bail!(Conflict, "{chain} needs {want}, which is not installed and not in the channel");
                };
                if t.contains(&d.name) || !d.constraint.as_ref().is_none_or(|c| c.allows(&e.version)) {
                    bail!(Conflict, "{chain} needs {want}; the channel has {} {}", d.name, e.version);
                }
                if let Some(iv) = installed.get(&d.name) {
                    if held(&d.name) {
                        bail!(Conflict, "{chain} needs {want}, but {} is held at {}", d.name, iv.version);
                    }
                    if compare(&e.version, &iv.version) == Ordering::Less {
                        bail!(Conflict, "{chain} needs {want}, which would be a downgrade");
                    }
                }
                if is_boot(&d.name) && !req.allow_boot {
                    bail!(Conflict, "{chain} needs {want}, a kernel or boot-partition package; pass --boot");
                }
                add = Some((d.name.clone(), p.clone()));
                break 'outer;
            }
        }
        match add {
            Some((n, parent)) => {
                why.insert(n.clone(), parent);
                t.insert(n);
            }
            None => break,
        }
    }
    // Topological order over the transaction (dependencies first), rejecting cycles.
    let mut order = Vec::new();
    let mut left: BTreeSet<String> = t.clone();
    while !left.is_empty() {
        let ready: Vec<String> = left.iter().filter(|n| m.get(n).unwrap().depends.iter().all(|d| !left.contains(&d.name) || d.name == **n)).cloned().collect();
        if ready.is_empty() {
            bail!(Conflict, "dependency cycle among {}", left.iter().cloned().collect::<Vec<_>>().join(", "));
        }
        for n in ready {
            if m.get(&n).unwrap().depends.iter().any(|d| d.name == n) {
                bail!(Conflict, "{n} depends on itself");
            }
            left.remove(&n);
            order.push(n);
        }
    }
    // sap first (design section 6.3, rule 5), keeping its own dependencies before it.
    if let Some(i) = order.iter().position(|n| n == "sap") {
        let mut first: Vec<String> = Vec::new();
        let mut stack = vec!["sap".to_string()];
        while let Some(x) = stack.pop() {
            if first.contains(&x) || !t.contains(&x) {
                continue;
            }
            first.push(x.clone());
            for d in &m.get(&x).unwrap().depends {
                stack.push(d.name.clone());
            }
        }
        let _ = i;
        let (mut a, b): (Vec<String>, Vec<String>) = order.into_iter().partition(|n| first.contains(n));
        a.extend(b);
        order = a;
    }
    res.order = order;
    Ok(res)
}

/// Conflicts between packages of the after-state (`conflicts` in records).
pub fn check_conflicts(after: &BTreeMap<String, (String, Vec<Dep>)>) -> Result<()> {
    for (n, (_, conflicts)) in after {
        for c in conflicts {
            if let Some((v, _)) = after.get(&c.name) {
                if c.name != *n && c.constraint.as_ref().is_none_or(|k| k.allows(v)) {
                    bail!(Conflict, "{n} conflicts with {} {v}", c.name);
                }
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest::{IndexEntry, Pin};
    use crate::version::Constraint;

    fn dep(n: &str, c: &str) -> Dep {
        Dep { name: n.into(), constraint: Constraint::parse(c).unwrap() }
    }
    fn ent(n: &str, v: &str, kind: &str, deps: Vec<Dep>) -> IndexEntry {
        IndexEntry {
            name: n.into(),
            version: v.into(),
            kind: kind.into(),
            depends: deps,
            activate: "none".into(),
            bytes: 0,
            record: Pin { url: "x".into(), sha256: "0".repeat(64) },
            payload: None,
            components: vec![],
        }
    }
    fn man(p: Vec<IndexEntry>) -> Manifest {
        Manifest {
            channel: "stable".into(),
            release: "x".into(),
            sequence: 1,
            issued: 0,
            expires: 1,
            min_sap: None,
            base_sums: None,
            packages: p,
            skipped_kinds: vec![],
            removed: vec![],
            allowed_prefixes: vec![],
            trust: None,
            sha256: String::new(),
        }
    }
    fn inst(v: &[(&str, &str, Vec<Dep>)]) -> BTreeMap<String, InstalledView> {
        v.iter().map(|(n, ver, d)| (n.to_string(), InstalledView { version: ver.to_string(), depends: d.clone(), conflicts: vec![] })).collect()
    }
    fn up<'a>(held: &'a [String]) -> Request<'a> {
        Request { names: None, reinstall: &[], held, allow_boot: false }
    }

    #[test]
    fn upgrades_and_pulls_deps() {
        let m = man(vec![
            ent("vim", "2", "files", vec![dep("libncurses", ">= 6.4")]),
            ent("libncurses", "6.4", "files", vec![]),
            ent("sf-base", "1", "base", vec![]),
        ]);
        let i = inst(&[("vim", "1", vec![]), ("sf-base", "1", vec![])]);
        let r = resolve(&i, &m, &up(&[])).unwrap();
        assert_eq!(r.order, vec!["libncurses", "vim"]);
    }

    #[test]
    fn holds_fail_not_override() {
        let m = man(vec![ent("vim", "2", "files", vec![dep("lib", ">= 2")]), ent("lib", "2", "files", vec![])]);
        let i = inst(&[("vim", "1", vec![]), ("lib", "1", vec![])]);
        let held = vec!["lib".to_string()];
        let e = resolve(&i, &m, &up(&held)).unwrap_err();
        assert!(e.msg.contains("held"), "{}", e.msg);
        let held = vec!["vim".to_string()];
        let r = resolve(&i, &m, &up(&held)).unwrap();
        assert_eq!(r.order, vec!["lib"]);
        assert!(r.notes[0].contains("held"));
    }

    #[test]
    fn unsatisfiable_cycles_boot() {
        let m = man(vec![ent("a", "2", "files", vec![dep("b", ">= 3")]), ent("b", "2", "files", vec![])]);
        let i = inst(&[("a", "1", vec![])]);
        assert!(resolve(&i, &m, &up(&[])).unwrap_err().msg.contains("needs b"));
        let m = man(vec![ent("a", "2", "files", vec![dep("b", "")]), ent("b", "2", "files", vec![dep("a", "")])]);
        let i = inst(&[("a", "1", vec![]), ("b", "1", vec![])]);
        assert!(resolve(&i, &m, &up(&[])).unwrap_err().msg.contains("cycle"));
        let m = man(vec![ent("k", "2", "kc-input", vec![])]);
        let i = inst(&[("k", "1", vec![])]);
        let r = resolve(&i, &m, &up(&[])).unwrap();
        assert!(r.order.is_empty() && r.notes[0].contains("--boot"));
        let r = resolve(&i, &m, &Request { names: None, reinstall: &[], held: &[], allow_boot: true }).unwrap();
        assert_eq!(r.order, vec!["k"]);
    }

    #[test]
    fn sap_first_and_no_downgrade() {
        let m = man(vec![
            ent("a", "2", "files", vec![]),
            ent("sap", "2", "files", vec![dep("libz", "")]),
            ent("libz", "2", "files", vec![]),
            ent("old", "1", "files", vec![]),
        ]);
        let i = inst(&[("a", "1", vec![]), ("sap", "1", vec![]), ("libz", "1", vec![]), ("old", "5", vec![])]);
        let r = resolve(&i, &m, &up(&[])).unwrap();
        assert_eq!(r.order, vec!["libz", "sap", "a"]);
        assert!(r.notes.iter().any(|n| n.contains("not downgrading")));
    }

    #[test]
    fn reverse_dependency_pulls_upgrade() {
        // Upgrading lib to 3 breaks nothing; app installed requires lib << 3 -> must fail, not silently break.
        let m = man(vec![ent("lib", "3", "files", vec![]), ent("app", "1", "files", vec![dep("lib", "<< 3")])]);
        let i = inst(&[("lib", "2", vec![]), ("app", "1", vec![dep("lib", "<< 3")])]);
        assert!(resolve(&i, &m, &up(&[])).is_err());
    }

    #[test]
    fn conflicts() {
        let mut a = BTreeMap::new();
        a.insert("x".to_string(), ("1".to_string(), vec![dep("y", "")]));
        a.insert("y".to_string(), ("1".to_string(), vec![]));
        assert!(check_conflicts(&a).is_err());
        a.insert("x".to_string(), ("1".to_string(), vec![dep("y", ">= 2")]));
        assert!(check_conflicts(&a).is_ok());
    }
}
