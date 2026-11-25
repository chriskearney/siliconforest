// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//! Payload format `xz-bodies/1` (docs/sap/FORMATS.md): one xz stream whose output is the bodies of the
//! package's regular files, concatenated in files.tsv order, nothing else. Names, sizes, modes, owners,
//! hashes, directories and symlinks come from the signed files.tsv; the payload only carries bytes.

use crate::error::{Code, Error, Result};
use crate::tsv::{Entry, Kind};
use crate::util::hex;
use sha2::{Digest, Sha256};
use std::fs::File;
use std::io::{BufReader, Write};
use std::path::{Path, PathBuf};

pub const FORMAT: &str = "xz-bodies/1";

struct Splitter<'a> {
    files: Vec<&'a Entry>,
    dir: &'a Path,
    i: usize,
    left: u64,
    cur: Option<File>,
    hash: Sha256,
    out: Vec<PathBuf>,
    err: Option<String>,
}

impl<'a> Splitter<'a> {
    fn open_next(&mut self) -> std::io::Result<()> {
        while self.i < self.files.len() {
            let e = self.files[self.i];
            let p = self.dir.join(format!("{:06}", self.out.len()));
            let f = File::create(&p)?;
            self.out.push(p);
            self.left = e.size;
            self.hash = Sha256::new();
            if e.size > 0 {
                self.cur = Some(f);
                return Ok(());
            }
            f.sync_all()?;
            self.finish_one()?;
        }
        self.cur = None;
        Ok(())
    }
    fn finish_one(&mut self) -> std::io::Result<()> {
        let e = self.files[self.i];
        let got = hex(&std::mem::take(&mut self.hash).finalize());
        if got != e.data {
            self.err = Some(format!("{} does not match its SHA-256 in the signed file list", e.path));
            return Err(std::io::Error::other("hash mismatch"));
        }
        if let Some(f) = self.cur.take() {
            f.sync_all()?;
        }
        self.i += 1;
        Ok(())
    }
}

impl<'a> Write for Splitter<'a> {
    fn write(&mut self, mut buf: &[u8]) -> std::io::Result<usize> {
        let n = buf.len();
        while !buf.is_empty() {
            if self.cur.is_none() {
                self.err = Some("the payload holds more bytes than its file list".into());
                return Err(std::io::Error::other("extra bytes"));
            }
            let k = (self.left.min(buf.len() as u64)) as usize;
            self.cur.as_mut().unwrap().write_all(&buf[..k])?;
            self.hash.update(&buf[..k]);
            self.left -= k as u64;
            buf = &buf[k..];
            if self.left == 0 {
                self.finish_one()?;
                self.open_next()?;
            }
        }
        Ok(n)
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

/// Unpack `payload` into `dir`, one file per regular-file row of `entries` (in order), checking every
/// file's size and SHA-256. Returns the staged path of each regular-file row. On any error `dir` is
/// left for the caller to delete.
pub fn unpack(payload: &Path, entries: &[Entry], dir: &Path) -> Result<Vec<PathBuf>> {
    std::fs::create_dir_all(dir)?;
    let files: Vec<&Entry> = entries.iter().filter(|e| e.kind == Kind::File).collect();
    let mut s = Splitter { files, dir, i: 0, left: 0, cur: None, hash: Sha256::new(), out: Vec::new(), err: None };
    s.open_next()?;
    let mut r = BufReader::new(File::open(payload)?);
    let res = lzma_rs::xz_decompress(&mut r, &mut s);
    if let Some(e) = s.err.take() {
        return Err(Error::new(Code::Verify, e));
    }
    if let Err(e) = res {
        return Err(Error::new(Code::Verify, format!("the payload does not decompress: {e:?}")));
    }
    if s.i != s.files.len() {
        return Err(Error::new(Code::Verify, "the payload is shorter than its file list".to_string()));
    }
    Ok(s.out)
}

/// Build a payload (used by tests; the publisher is sap/tools/sap_build.py).
pub fn pack(bodies: &[&[u8]]) -> Vec<u8> {
    let all: Vec<u8> = bodies.concat();
    let mut out = Vec::new();
    lzma_rs::xz_compress(&mut std::io::Cursor::new(all), &mut out).unwrap();
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::util::sha256;

    fn ent(p: &str, b: &[u8]) -> Entry {
        Entry { path: p.into(), kind: Kind::File, mode: 0o644, uid: 0, gid: 0, size: b.len() as u64, data: sha256(b) }
    }

    #[test]
    fn roundtrip_and_tamper() {
        let d = std::env::temp_dir().join(format!("sap-payload-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        let (a, b, c) = (b"alpha".as_slice(), b"".as_slice(), vec![7u8; 100000]);
        let entries = vec![
            ent("/a", a),
            ent("/b", b),
            Entry { path: "/d".into(), kind: Kind::Dir, mode: 0o755, uid: 0, gid: 0, size: 0, data: "-".into() },
            ent("/c", &c),
        ];
        let p = d.join("p.sappkg");
        std::fs::write(&p, pack(&[a, b, &c])).unwrap();
        let out = unpack(&p, &entries, &d.join("s1")).unwrap();
        assert_eq!(out.len(), 3);
        assert_eq!(std::fs::read(&out[2]).unwrap(), c);
        // One flipped byte inside a body.
        let mut c2 = c.clone();
        c2[500] ^= 1;
        std::fs::write(&p, pack(&[a, b, &c2])).unwrap();
        assert_eq!(unpack(&p, &entries, &d.join("s2")).unwrap_err().code, Code::Verify);
        // Extra and missing bytes.
        std::fs::write(&p, pack(&[a, b, &c, b"x"])).unwrap();
        assert!(unpack(&p, &entries, &d.join("s3")).is_err());
        std::fs::write(&p, pack(&[a, b, &c[..10]])).unwrap();
        assert!(unpack(&p, &entries, &d.join("s4")).is_err());
        // Not xz.
        std::fs::write(&p, b"garbage").unwrap();
        assert!(unpack(&p, &entries, &d.join("s5")).is_err());
        let _ = std::fs::remove_dir_all(&d);
    }
}
