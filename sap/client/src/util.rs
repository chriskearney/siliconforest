// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//! Hashing, durable writes, time.

use crate::error::{Context, Result};
use sha2::{Digest, Sha256};
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::path::Path;

pub fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

pub fn sha256(b: &[u8]) -> String {
    hex(&Sha256::digest(b))
}

/// (sha256, bytes) of a regular file, streamed.
pub fn sha256_file(p: &Path) -> std::io::Result<(String, u64)> {
    let mut f = File::open(p)?;
    let mut h = Sha256::new();
    let mut buf = vec![0u8; 1 << 20];
    let mut n = 0u64;
    loop {
        let k = f.read(&mut buf)?;
        if k == 0 {
            break;
        }
        h.update(&buf[..k]);
        n += k as u64;
    }
    Ok((hex(&h.finalize()), n))
}

/// SHA-256 of a path if it is a regular file (not following a final symlink); None otherwise.
pub fn file_hash_if_regular(p: &Path) -> Option<String> {
    let m = fs::symlink_metadata(p).ok()?;
    if !m.file_type().is_file() {
        return None;
    }
    sha256_file(p).ok().map(|x| x.0)
}

pub fn fsync_dir(dir: &Path) {
    if let Ok(f) = File::open(dir) {
        let _ = f.sync_all();
    }
}

/// Write `data` to `path` durably: temp file in the same directory, fsync, rename, fsync the directory.
pub fn write_atomic(path: &Path, data: &[u8], mode: u32) -> Result<()> {
    use std::os::unix::fs::OpenOptionsExt;
    let dir = path.parent().unwrap();
    fs::create_dir_all(dir).ctx(|| format!("create {}", dir.display()))?;
    let tmp = dir.join(format!(".{}.tmp{}", path.file_name().unwrap().to_string_lossy(), std::process::id()));
    {
        let mut f = OpenOptions::new().write(true).create(true).truncate(true).mode(mode).open(&tmp).ctx(|| format!("write {}", tmp.display()))?;
        f.write_all(data)?;
        f.sync_all()?;
    }
    fs::rename(&tmp, path).ctx(|| format!("rename onto {}", path.display()))?;
    fsync_dir(dir);
    Ok(())
}

pub fn append_line_durable(path: &Path, line: &str) -> Result<()> {
    let mut f = OpenOptions::new().append(true).create(true).open(path).ctx(|| format!("open {}", path.display()))?;
    f.write_all(line.as_bytes())?;
    f.write_all(b"\n")?;
    f.sync_all()?;
    Ok(())
}

pub fn is_root() -> bool {
    unsafe { libc::geteuid() == 0 }
}

/// Seconds since the epoch. With the `testing` feature, SAP_NOW (RFC 3339) overrides the clock.
pub fn now() -> i64 {
    #[cfg(feature = "testing")]
    if let Ok(v) = std::env::var("SAP_NOW") {
        if let Some(t) = parse_rfc3339(&v) {
            return t;
        }
    }
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

/// `YYYY-MM-DDTHH:MM:SSZ` (UTC only, as the manifest requires).
pub fn parse_rfc3339(s: &str) -> Option<i64> {
    let b = s.as_bytes();
    if b.len() != 20 || b[4] != b'-' || b[7] != b'-' || b[10] != b'T' || b[13] != b':' || b[16] != b':' || b[19] != b'Z' {
        return None;
    }
    let n = |a: usize, z: usize| s[a..z].parse::<i64>().ok();
    let (y, mo, d, h, mi, se) = (n(0, 4)?, n(5, 7)?, n(8, 10)?, n(11, 13)?, n(14, 16)?, n(17, 19)?);
    if !(1..=12).contains(&mo) || !(1..=31).contains(&d) || h > 23 || mi > 59 || se > 60 {
        return None;
    }
    Some(days_from_civil(y, mo, d) * 86400 + h * 3600 + mi * 60 + se)
}

pub fn format_rfc3339(t: i64) -> String {
    let days = t.div_euclid(86400);
    let secs = t.rem_euclid(86400);
    let z = days + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    format!("{y:04}-{m:02}-{d:02}T{:02}:{:02}:{:02}Z", secs / 3600, secs / 60 % 60, secs % 60)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn time() {
        assert_eq!(parse_rfc3339("1970-01-01T00:00:00Z"), Some(0));
        assert_eq!(parse_rfc3339("2026-12-02T18:00:00Z"), Some(1796234400));
        assert_eq!(format_rfc3339(1796234400), "2026-12-02T18:00:00Z");
        assert!(parse_rfc3339("2026-12-02T18:00:00+01:00").is_none());
        assert!(parse_rfc3339("2026-13-02T18:00:00Z").is_none());
    }
}
