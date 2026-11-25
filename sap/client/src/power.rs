// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//! Power and service health on the running machine.
//!
//! * AC power: boot and kernel updates need it (design 3.5 step 4, like the installer's
//!   preflight). The state comes from `pmset -g batt`, the Darwin interface; SiliconForest
//!   reports battery and charger state once SF-K K4 exposes them. Without a power source SAP
//!   cannot tell, warns, and goes on (a desktop, a VM, or K4 not there yet).
//! * Health: `sap mark-good` makes an updated slot the default only once the services the
//!   installed records name (design 3.4) are running (design 10.4, "clean start").

use crate::error::{Code, Error, Result};
use crate::sys::Sys;
use std::process::Command;
use std::time::{Duration, Instant};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Power {
    Ac,
    Battery(Option<u32>),
    Unknown(String),
}

/// `pmset -g batt` output: "Now drawing from 'AC Power'" / "'Battery Power'", then per battery "NN%;".
pub fn parse_pmset(out: &str) -> Power {
    let pct = out.split(|c: char| c.is_whitespace() || c == ';').find_map(|w| w.strip_suffix('%').and_then(|n| n.parse::<u32>().ok()));
    if out.contains("'AC Power'") {
        Power::Ac
    } else if out.contains("'Battery Power'") {
        Power::Battery(pct)
    } else {
        Power::Unknown(out.lines().next().unwrap_or("").trim().to_string())
    }
}

pub fn state() -> Power {
    #[cfg(feature = "testing")]
    if let Ok(v) = std::env::var("SAP_POWER") {
        return match v.as_str() {
            "ac" => Power::Ac,
            b if b.starts_with("battery") => Power::Battery(b.split(':').nth(1).and_then(|n| n.parse().ok())),
            _ => Power::Unknown("SAP_POWER".into()),
        };
    }
    for tool in ["/usr/bin/pmset", "/usr/sbin/pmset"] {
        if std::path::Path::new(tool).exists() {
            return match Command::new(tool).args(["-g", "batt"]).output() {
                Ok(o) if o.status.success() => parse_pmset(&String::from_utf8_lossy(&o.stdout)),
                Ok(o) => Power::Unknown(format!("pmset exited {}", o.status)),
                Err(e) => Power::Unknown(format!("pmset: {e}")),
            };
        }
    }
    Power::Unknown("no power source information on this machine".into())
}

/// Before boot and kernel updates on the machine (never in image mode).
pub fn require_ac(sys: &Sys, ignore: bool) -> Result<()> {
    #[cfg(feature = "testing")]
    let image = sys.image_mode && std::env::var_os("SAP_POWER").is_none();
    #[cfg(not(feature = "testing"))]
    let image = sys.image_mode;
    if image || sys.cfg.require_ac == "no" {
        return Ok(());
    }
    match state() {
        Power::Ac => Ok(()),
        Power::Battery(p) if ignore => {
            eprintln!("sap: warning: on battery ({}); going on because of --ignore-power", p.map(|p| format!("{p}%")).unwrap_or("level unknown".into()));
            Ok(())
        }
        Power::Battery(p) => Err(Error::new(
            Code::Conflict,
            format!(
                "on battery ({}): boot and kernel updates need AC power; connect the charger and run it again (--ignore-power to go on anyway)",
                p.map(|p| format!("{p}%")).unwrap_or("level unknown".into())
            ),
        )),
        Power::Unknown(why) => {
            eprintln!("sap: warning: cannot tell whether AC power is connected ({why}); keep the charger connected");
            Ok(())
        }
    }
}

fn launchctl() -> String {
    #[cfg(feature = "testing")]
    if let Ok(t) = std::env::var("SAP_LAUNCHCTL") {
        return t;
    }
    "/bin/launchctl".into()
}

/// One service: loaded, and running when it has a process. `launchctl list LABEL` (the launchd of
/// PureDarwin and macOS) prints the job's dictionary, with `"PID" = N;` while it runs.
pub fn service_running(label: &str) -> std::result::Result<(), String> {
    let o = Command::new(launchctl()).args(["list", label]).output().map_err(|e| format!("launchctl: {e}"))?;
    if !o.status.success() {
        return Err("not loaded".into());
    }
    let out = String::from_utf8_lossy(&o.stdout);
    if out.contains("\"PID\"") {
        return Ok(());
    }
    // A job that ran to completion (no PID) is healthy only with exit status 0.
    match out.lines().find_map(|l| l.trim().strip_prefix("\"LastExitStatus\" = ").map(|v| v.trim_end_matches(';').trim().to_string())) {
        Some(s) if s == "0" => Ok(()),
        Some(s) => Err(format!("not running, last exit status {s}")),
        None => Err("not running".into()),
    }
}

/// The services a clean start needs: those the installed records name, plus `health_services` in sap.conf.
pub fn health_labels(sys: &Sys) -> Result<Vec<String>> {
    let mut labels: Vec<String> = Vec::new();
    for i in sys.installed()? {
        for l in i.service_labels() {
            if !labels.contains(&l) {
                labels.push(l);
            }
        }
    }
    for l in sys.cfg.health_services.iter() {
        if !labels.contains(l) {
            labels.push(l.clone());
        }
    }
    labels.sort();
    Ok(labels)
}

/// Wait up to `wait` for every service to run. Err lists the ones that did not.
pub fn wait_healthy(labels: &[String], wait: Duration) -> std::result::Result<(), Vec<String>> {
    let start = Instant::now();
    loop {
        let bad: Vec<String> = labels.iter().filter_map(|l| service_running(l).err().map(|e| format!("{l}: {e}"))).collect();
        if bad.is_empty() {
            return Ok(());
        }
        if start.elapsed() >= wait {
            return Err(bad);
        }
        std::thread::sleep(Duration::from_secs(2).min(wait.saturating_sub(start.elapsed()).max(Duration::from_millis(100))));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pmset() {
        assert_eq!(parse_pmset("Now drawing from 'AC Power'\n -InternalBattery-0 (id=1)\t100%; charged; 0:00 remaining present: true\n"), Power::Ac);
        assert_eq!(
            parse_pmset("Now drawing from 'Battery Power'\n -InternalBattery-0 (id=1)\t42%; discharging; 3:10 remaining present: true\n"),
            Power::Battery(Some(42))
        );
        assert!(matches!(parse_pmset(""), Power::Unknown(_)));
    }
}
