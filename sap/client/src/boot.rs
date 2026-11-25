// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//! How SAP writes the boot partition (docs/sap/BOOT-INTERFACE.md). Two backends:
//!
//! * `legacy`: design section 3.5. Stage under `sf/.sap-staging/<txn>/` on SFBOOT, fsync, read back
//!   and compare, keep the current file as `<file>.old`, rename the new one over it; journaled with the
//!   rest of the transaction. No automatic fallback at boot. For machines whose stage 1 is v1.
//! * `slots`: design section 10 (A/B try-once boot, stage 1 v2). The update goes into the slot that is
//!   not the default, through `sf-bootslot` (integrations/siliconforest/m1-native-boot/install/abboot):
//!   `begin-stage <slot>`, write that slot's `boot.bin` and `kernel.bin` (with `sf_slot` in CONFIG),
//!   fsync and read back, then `arm <slot>` as the last operation of the transaction. No file of the
//!   default (running) slot is ever written. `sap mark-good` runs `sf-bootslot mark-good` after a clean
//!   start.
//!
//! `boot_backend = auto` (the default) uses `slots` when SFBOOT holds `sf/bootstate.bin` (only
//! `sf-bootslot init`, run where stage 1 v2 is installed, creates it) and `legacy` otherwise, so a
//! stage 1 v1 machine is never staged into slot B (design 10.6).

use crate::error::{Code, Error, Result};
use crate::sys::Sys;
use crate::{bail, util};
use std::path::{Path, PathBuf};
use std::process::Command;

pub const STATE_FILE: &str = "sf/bootstate.bin";
pub const DEFAULT_TOOL: &str = "/usr/libexec/sf-bootslot";

pub fn boot_path(slot: char) -> &'static str {
    if slot == 'b' {
        "sf/b/boot.bin"
    } else {
        "sf/boot.bin"
    }
}

pub fn kernel_path(slot: char) -> &'static str {
    if slot == 'b' {
        "sf/b/kernel.bin"
    } else {
        "sf/kernel.bin"
    }
}

pub fn other(slot: char) -> char {
    if slot == 'a' {
        'b'
    } else {
        'a'
    }
}

/// Boot arguments for a slot: `sf_slot=b` for B, none for A (absent means A, design 10.1).
pub fn with_slot(args: &str, slot: char) -> String {
    let mut w: Vec<&str> = args.split_whitespace().filter(|w| !w.starts_with("sf_slot=")).collect();
    let tok = "sf_slot=b";
    if slot == 'b' {
        w.push(tok);
    }
    w.join(" ")
}

#[derive(Debug, Clone, PartialEq)]
pub enum Backend {
    Legacy,
    Slots,
}

pub fn backend(sys: &Sys) -> Result<Backend> {
    let has_record = sys.sfboot.as_ref().map(|b| b.join(STATE_FILE).exists()).unwrap_or(false);
    match sys.cfg.boot_backend.as_str() {
        "legacy" => {
            if has_record {
                // Writing slot A in place under a v2 record would make stage 1 see a size/CRC mismatch.
                bail!(Conflict, "boot_backend = legacy, but SFBOOT has {STATE_FILE} (stage 1 v2): use boot_backend = auto or slots");
            }
            Ok(Backend::Legacy)
        }
        "slots" => {
            if !has_record {
                bail!(Conflict, "boot_backend = slots, but SFBOOT has no {STATE_FILE}; run sf-bootslot init on a machine with stage 1 v2 first");
            }
            Ok(Backend::Slots)
        }
        "auto" | "" => Ok(if has_record { Backend::Slots } else { Backend::Legacy }),
        o => bail!(Failure, "unknown boot_backend {o:?} (auto, legacy or slots)"),
    }
}

#[derive(Debug, Clone, Default)]
pub struct Status {
    pub running: char,
    pub default: char,
    pub trial: Option<char>,
    pub trial_state: String,
    pub reason: String,
    pub raw: String,
}

pub struct Tool {
    pub path: PathBuf,
    pub sfboot: PathBuf,
    /// Image mode: the machine is not running from this SFBOOT; act as if its default slot were running.
    pub image: bool,
    /// Tests only (SAP_RUNNING_SLOT, feature `testing`): act as the machine started from this slot.
    pub running: Option<char>,
}

impl Tool {
    pub fn new(sys: &Sys) -> Result<Tool> {
        let sfboot = sys.sfboot.clone().ok_or_else(|| Error::new(Code::Failure, "no SFBOOT mount (sfboot in /etc/sap.conf or --sfboot)".to_string()))?;
        let path = if sys.image_mode {
            match std::env::var_os("SAP_BOOTSLOT_TOOL") {
                Some(p) => PathBuf::from(p),
                None => bail!(Failure, "image mode with a slots SFBOOT: set SAP_BOOTSLOT_TOOL to a host build of sf-bootslot"),
            }
        } else {
            PathBuf::from(sys.cfg.bootslot_tool.clone().unwrap_or_else(|| DEFAULT_TOOL.into()))
        };
        #[cfg(feature = "testing")]
        let running = std::env::var("SAP_RUNNING_SLOT").ok().and_then(|v| v.chars().next()).filter(|c| *c == 'a' || *c == 'b');
        #[cfg(not(feature = "testing"))]
        let running = None;
        Ok(Tool { path, sfboot, image: sys.image_mode && running.is_none(), running })
    }

    fn run(&self, running: Option<char>, args: &[String]) -> Result<(i32, String, String)> {
        let mut c = Command::new(&self.path);
        c.arg("--boot").arg(&self.sfboot);
        if let Some(r) = running {
            c.arg("--running").arg(r.to_string());
        }
        c.args(args).env_remove("SF_BOOT_DIR");
        let out = c.output().map_err(|e| Error::new(Code::Failure, format!("cannot run {}: {e}", self.path.display())))?;
        Ok((out.status.code().unwrap_or(2), String::from_utf8_lossy(&out.stdout).into_owned(), String::from_utf8_lossy(&out.stderr).into_owned()))
    }

    pub fn status(&self) -> Result<Status> {
        let (rc, out, err) = self.run(None, &["status".into()])?;
        if rc != 0 {
            bail!(Failure, "sf-bootslot status failed ({rc}): {}", err.trim());
        }
        let mut s = Status { raw: out.clone(), ..Default::default() };
        let slot = |v: &str| v.chars().next().filter(|c| *c == 'a' || *c == 'b');
        for l in out.lines() {
            if let Some((k, v)) = l.split_once('=') {
                match k {
                    "running" => s.running = slot(v).unwrap_or('a'),
                    "default" => s.default = slot(v).ok_or_else(|| Error::new(Code::Failure, format!("sf-bootslot: bad default {v:?}")))?,
                    "trial" => s.trial = slot(v),
                    "trial_state" => s.trial_state = v.to_string(),
                    "reason" => s.reason = v.to_string(),
                    _ => {}
                }
            }
        }
        if s.default == '\0' {
            bail!(Failure, "sf-bootslot status: no boot state record ({})", out.trim());
        }
        if let Some(r) = self.running {
            s.running = r;
        } else if self.image {
            s.running = s.default;
        }
        Ok(s)
    }

    fn running_arg(&self, st: &Status) -> Option<char> {
        // On the machine the tool reads sf_slot from kern.bootargs itself; for an image, say it.
        if self.running.is_some() {
            self.running
        } else if self.image {
            Some(st.default)
        } else {
            None
        }
    }

    pub fn begin_stage(&self, st: &Status, slot: char) -> Result<()> {
        let (rc, _, err) = self.run(self.running_arg(st), &["begin-stage".into(), slot.to_string()])?;
        if rc != 0 {
            bail!(Conflict, "sf-bootslot begin-stage {slot} refused ({rc}): {}", err.trim());
        }
        Ok(())
    }

    /// Idempotent for recovery: already armed for this slot with these files counts as done.
    pub fn arm(&self, slot: char, generation: u32) -> Result<()> {
        let st = self.status()?;
        if st.trial == Some(slot) && st.trial_state == "armed" && slot_file_matches(&st.raw, slot) {
            return Ok(());
        }
        let (rc, _, err) = self.run(self.running_arg(&st), &["--generation".into(), generation.to_string(), "arm".into(), slot.to_string()])?;
        if rc != 0 {
            bail!(Conflict, "sf-bootslot arm {slot} refused ({rc}): {}", err.trim());
        }
        Ok(())
    }

    /// Cancel an ARMED trial of slot (a rollback before the restart). Nothing to do when that slot
    /// is not armed; a trial already TRIED is the running system's to resolve (early / mark-good).
    pub fn disarm(&self, slot: char) -> Result<bool> {
        let st = self.status()?;
        if st.trial != Some(slot) || st.trial_state != "armed" {
            return Ok(false);
        }
        let (rc, _, err) = self.run(self.running_arg(&st), &["disarm".into(), slot.to_string()])?;
        if rc != 0 {
            bail!(Conflict, "sf-bootslot disarm {slot} refused ({rc}): {}", err.trim());
        }
        Ok(true)
    }

    pub fn mark_good(&self) -> Result<String> {
        if self.image {
            bail!(Failure, "mark-good is for the running system (after a clean start), not an image");
        }
        let (rc, out, err) = self.run(self.running, &["mark-good".into()])?;
        if rc != 0 {
            bail!(Conflict, "sf-bootslot mark-good refused ({rc}): {}", err.trim());
        }
        Ok(out)
    }
}

fn slot_file_matches(raw: &str, slot: char) -> bool {
    raw.lines().any(|l| l.starts_with(&format!("slot_{slot}=")) && l.contains("file:matches"))
}

/// Write one slot file durably on SFBOOT (FAT: temp file in the same directory, fsync, rename, read
/// back). Only ever called for the inactive slot, so a torn write cannot hurt the slot that boots.
pub fn write_slot_file(sfboot: &Path, rel: &str, data: &[u8]) -> Result<()> {
    let p = sfboot.join(rel);
    if let Some(d) = p.parent() {
        std::fs::create_dir_all(d)?;
    }
    let tmp = p.with_extension("sap-tmp");
    {
        use std::io::Write;
        let mut f = std::fs::File::create(&tmp)?;
        f.write_all(data)?;
        f.sync_all()?;
    }
    std::fs::rename(&tmp, &p)?;
    util::fsync_dir(p.parent().unwrap());
    if util::sha256_file(&p)?.0 != util::sha256(data) {
        bail!(Verify, "read-back of SFBOOT/{rel} does not match what was written");
    }
    Ok(())
}
