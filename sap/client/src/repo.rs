// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//! Discover, authenticate and freshness-check the manifest (design section 3.1 steps 1-3), and fetch
//! hash-pinned objects into the download cache (steps 5-6).

use crate::error::{Code, Error, Result};
use crate::manifest::{self, Manifest, Pin};
use crate::sys::Sys;
use crate::{bail, fetch, sshsig, util};
use std::fs;
use std::path::PathBuf;

pub struct Loaded {
    pub m: Manifest,
    pub url: String,
    pub fresh: bool,
    pub raw: Option<(Vec<u8>, Vec<u8>)>,
}

fn cache_paths(sys: &Sys) -> (PathBuf, PathBuf, PathBuf) {
    (sys.cache.join("manifest.json"), sys.cache.join("manifest.json.sig"), sys.cache.join("manifest.url"))
}

/// Authenticate exactly these bytes, then parse, then check freshness against state.json.
pub fn authenticate(sys: &Sys, bytes: &[u8], sig: &[u8]) -> Result<Manifest> {
    if bytes.len() as u64 > manifest::MAX_MANIFEST {
        bail!(Verify, "the manifest is larger than 4 MiB");
    }
    let anchor = sys.anchor()?;
    for w in &anchor.warnings {
        eprintln!("sap: warning: {w}");
    }
    sshsig::verify(bytes, sig, sshsig::NAMESPACE, &anchor.keys).map_err(|e| Error::new(Code::Verify, format!("manifest: {e}")))?;
    let m = manifest::parse(bytes, &sys.cfg.channel)?;
    for (n, k) in &m.skipped_kinds {
        eprintln!("sap: warning: skipping {n}: package kind {k:?} is unknown to this SAP");
    }
    let st = sys.state()?;
    let now = util::now();
    if now >= m.expires {
        bail!(
            Stale,
            "the manifest expired at {}; refusing it (a stale mirror, or updates are being withheld). It is not 'up to date'",
            util::format_rfc3339(m.expires)
        );
    }
    if m.sequence < st.highest_sequence {
        bail!(Stale, "the manifest's sequence {} is lower than {} already seen: an old manifest is being replayed", m.sequence, st.highest_sequence);
    }
    if m.sequence == st.highest_sequence && st.manifest_sha256.as_deref().is_some_and(|h| h != m.sha256) {
        bail!(Stale, "a different manifest with the same sequence {} was already seen", m.sequence);
    }
    if let (Some(l), Some(b)) = (&st.lineage, &m.base_sums) {
        if l != b {
            bail!(Verify, "the manifest extends another installer release (base {}…), not this machine's ({}…)", &b[..12], &l[..12]);
        }
    }
    Ok(m)
}

/// Fetch and verify a fresh manifest (or with `offline`, re-verify the cached one).
pub fn load(sys: &Sys, offline: bool) -> Result<Loaded> {
    let (cm, cs, cu) = cache_paths(sys);
    if offline || sys.opts.offline {
        let (b, s) = match (fs::read(&cm), fs::read(&cs)) {
            (Ok(b), Ok(s)) => (b, s),
            _ => bail!(Failure, "no cached manifest; run sap check"),
        };
        let url = fs::read_to_string(&cu).unwrap_or_default().trim().to_string();
        let m = authenticate(sys, &b, &s)?;
        return Ok(Loaded { m, url, fresh: false, raw: None });
    }
    let url = sys
        .cfg
        .manifest_url
        .clone()
        .ok_or_else(|| Error::new(Code::Failure, "no manifest_url (set it in /etc/sap.conf or pass --manifest-url)".to_string()))?;
    let bytes = fetch::get(&url, manifest::MAX_MANIFEST)?;
    // The manifest was reachable, so a missing signature is a verification failure, not an outage.
    let sig = fetch::get(&format!("{url}.sig"), 64 << 10)
        .map_err(|e| Error::new(Code::Verify, format!("the manifest has no usable signature ({}); an unsigned manifest is never used", e.msg)))?;
    let m = authenticate(sys, &bytes, &sig)?;
    Ok(Loaded { m, url, fresh: true, raw: Some((bytes, sig)) })
}

/// After a verified fresh manifest: cache it and raise the sequence floor (design section 7).
pub fn remember(sys: &Sys, l: &Loaded, bytes_sig: Option<(&[u8], &[u8])>) -> Result<()> {
    let mut st = sys.state()?;
    st.highest_sequence = st.highest_sequence.max(l.m.sequence);
    st.manifest_sha256 = Some(l.m.sha256.clone());
    if st.lineage.is_none() {
        st.lineage = l.m.base_sums.clone();
    }
    sys.write_state(&st)?;
    if let Some((b, s)) = bytes_sig {
        let (cm, cs, cu) = cache_paths(sys);
        util::write_atomic(&cm, b, 0o644)?;
        util::write_atomic(&cs, s, 0o644)?;
        util::write_atomic(&cu, l.url.as_bytes(), 0o644)?;
    }
    Ok(())
}

pub fn load_and_remember(sys: &Sys) -> Result<Loaded> {
    let mut l = load(sys, false)?;
    let raw = l.raw.take();
    remember(sys, &l, raw.as_ref().map(|(b, s)| (b.as_slice(), s.as_slice())))?;
    Ok(l)
}

/// A hash-pinned object in the cache, downloaded (resuming a partial file) if needed.
pub fn pinned(sys: &Sys, base_url: &str, pin: &Pin, max: u64) -> Result<PathBuf> {
    fs::create_dir_all(&sys.cache)?;
    let dest = sys.cache.join(&pin.sha256);
    if dest.exists() {
        if util::sha256_file(&dest)?.0 == pin.sha256 {
            return Ok(dest);
        }
        let _ = fs::remove_file(&dest);
    }
    if sys.opts.offline {
        bail!(Failure, "{} is not in the cache and --offline is set", pin.url);
    }
    let part = sys.cache.join(format!("{}.part", pin.sha256));
    let url = fetch::resolve(base_url, &pin.url);
    let r = fetch::download(&url, &part, max, true);
    if let Err(e) = r {
        if e.code == Code::Verify {
            let _ = fs::remove_file(&part);
        }
        return Err(e);
    }
    let (got, _) = util::sha256_file(&part)?;
    if got != pin.sha256 {
        let _ = fs::remove_file(&part);
        bail!(Verify, "{} does not match the SHA-256 the signed manifest pins (mirror tampering or corruption); deleted", pin.url);
    }
    fs::rename(&part, &dest)?;
    Ok(dest)
}
