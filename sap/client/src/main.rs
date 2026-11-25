// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//! `sap`: the SiliconForest system updater. See docs/sap/README.md.

use sap::apply::{self, UpgradeArgs};
use sap::cmd;
use sap::error::{Code, Error};
use sap::sys::{Options, Sys};
use std::path::PathBuf;

const USAGE: &str = "usage: sap [global options] COMMAND [ARGS]

commands:
  check                          fetch and verify the manifest; exit 10 if updates are available
  list [--installed|--upgradable|--available]
  show PKG
  upgrade [PKG…] [--dry-run] [--download-only] [--boot [--ignore-power]] [--adopt PATH]… [-y]
  install PKG… | --all [--boot]  install packages not yet installed (same verified path)
  verify [PKG…] [--repair]
  history
  rollback [TXN]
  hold PKG… | unhold PKG…
  recover [--rollback]
  boot-status                    the A/B boot slots (stage 1 v2), or the legacy layout
  mark-good [--wait S] [--no-health]  after a clean start from an updated slot (the services the
                                 records name are running): make it the default
  version

global options:
  --root DIR          operate on an image mounted at DIR, not the running system
  --sfboot DIR        the boot partition (SFBOOT) mount, for kernel and stage 2 updates
  --manifest-url URL  override /etc/sap.conf manifest_url (http, https, file)
  --channel NAME      v1 accepts only stable
  --trust-anchor FILE public keys to trust (images only, with --root)
  --offline           use only the cached manifest and downloads
  --json              machine-readable output
  -v                  verbose

exit codes: 0 ok, 10 updates available, 20 verification failure (system unchanged), 21 manifest expired
or replayed, 30 conflict or dependency failure, 40 transaction interrupted (run sap recover),
50 reboot required after success";

fn main() {
    let code = match run() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("sap: {}", e.msg);
            if e.code == Code::Verify {
                eprintln!("sap: nothing was changed.");
            }
            e.code as i32
        }
    };
    std::process::exit(code);
}

fn usage(msg: &str) -> Error {
    Error::new(Code::Failure, format!("{msg}\n{USAGE}"))
}

fn run() -> Result<i32, Error> {
    let mut args: Vec<String> = std::env::args().skip(1).collect();
    let mut o =
        Options { root: PathBuf::from("/"), sfboot: None, manifest_url: None, channel: None, trust_anchor: None, offline: false, json: false, verbose: false };
    let mut rest = Vec::new();
    let mut i = 0;
    while i < args.len() {
        let a = args[i].clone();
        let mut val = || -> Result<String, Error> {
            i += 1;
            args.get(i).cloned().ok_or_else(|| usage(&format!("{a} needs a value")))
        };
        match a.as_str() {
            "--root" => o.root = PathBuf::from(val()?),
            "--sfboot" => o.sfboot = Some(PathBuf::from(val()?)),
            "--manifest-url" => o.manifest_url = Some(val()?),
            "--channel" => o.channel = Some(val()?),
            "--trust-anchor" => o.trust_anchor = Some(PathBuf::from(val()?)),
            "--offline" => o.offline = true,
            "--json" => o.json = true,
            "-v" | "--verbose" => o.verbose = true,
            "-h" | "--help" => {
                println!("{USAGE}");
                return Ok(0);
            }
            _ => rest.push(a),
        }
        i += 1;
    }
    args = rest;
    let Some(command) = args.first().cloned() else { return Err(usage("no command")) };
    let rest: Vec<String> = args[1..].to_vec();
    if command == "version" {
        println!("sap {}", sap::manifest::SAP_VERSION);
        return Ok(0);
    }
    let sys = Sys::open(o)?;
    let pending = sap::txn::interrupted(&sys);
    if !pending.is_empty() && ["check", "list", "show", "verify", "history"].contains(&command.as_str()) {
        eprintln!("sap: warning: transaction {} was interrupted; run sap recover", pending.join(", "));
        if command == "verify" {
            return Ok(Code::Interrupted as i32);
        }
    }
    let flags = |allowed: &[&str]| -> Result<(Vec<String>, Vec<String>), Error> {
        let (f, p): (Vec<String>, Vec<String>) = rest.iter().cloned().partition(|x| x.starts_with('-'));
        for x in &f {
            if !allowed.contains(&x.as_str()) {
                return Err(usage(&format!("unknown option {x} for {command}")));
            }
        }
        Ok((f, p))
    };
    match command.as_str() {
        "check" => {
            flags(&[])?;
            cmd::check(&sys)
        }
        "list" => {
            let (f, _) = flags(&["--installed", "--upgradable", "--available"])?;
            cmd::list(&sys, f.first().map(|x| x.trim_start_matches('-')).unwrap_or("all"))
        }
        "show" => {
            let (_, p) = flags(&[])?;
            if p.len() != 1 {
                return Err(usage("show takes one package"));
            }
            cmd::show(&sys, &p[0])
        }
        "upgrade" | "install" => {
            let mut a = UpgradeArgs::default();
            let mut j = 0;
            while j < rest.len() {
                match rest[j].as_str() {
                    "--dry-run" => a.dry_run = true,
                    "--download-only" => a.download_only = true,
                    "--boot" => a.boot = true,
                    "--ignore-power" => a.ignore_power = true,
                    "-y" | "--yes" => a.yes = true,
                    "--all" if command == "install" => a.install_all = true,
                    "--adopt" => {
                        j += 1;
                        a.adopt.push(rest.get(j).cloned().ok_or_else(|| usage("--adopt needs a path"))?);
                    }
                    x if x.starts_with('-') => return Err(usage(&format!("unknown option {x}"))),
                    x => a.names.push(x.to_string()),
                }
                j += 1;
            }
            if command == "install" && a.names.is_empty() && !a.install_all {
                return Err(usage("install needs package names or --all"));
            }
            apply::upgrade(&sys, &a)
        }
        "verify" => {
            let (f, p) = flags(&["--repair"])?;
            cmd::verify(&sys, &p, !f.is_empty())
        }
        "history" => {
            flags(&[])?;
            cmd::history(&sys)
        }
        "rollback" => {
            let (_, p) = flags(&[])?;
            apply::rollback(&sys, p.first().map(|s| s.as_str()))
        }
        "hold" | "unhold" => {
            let (_, p) = flags(&[])?;
            if p.is_empty() {
                return Err(usage("hold needs package names"));
            }
            cmd::hold(&sys, &p, command == "hold")
        }
        "recover" => {
            let (f, _) = flags(&["--rollback"])?;
            cmd::recover(&sys, !f.is_empty())
        }
        "boot-status" => {
            flags(&[])?;
            cmd::boot_status(&sys)
        }
        "mark-good" => {
            let mut wait = 0u64;
            let mut force = false;
            let mut j = 0;
            while j < rest.len() {
                match rest[j].as_str() {
                    "--wait" => {
                        j += 1;
                        wait = rest.get(j).and_then(|v| v.parse().ok()).ok_or_else(|| usage("--wait needs seconds"))?;
                    }
                    "--no-health" => force = true,
                    x => return Err(usage(&format!("unknown option {x}"))),
                }
                j += 1;
            }
            cmd::mark_good(&sys, wait, force)
        }
        c => Err(usage(&format!("unknown command {c}"))),
    }
}
