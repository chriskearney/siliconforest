// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//! The installer's per-file manifest TSV (design section 5.1; installer/payload/image/synthetic_base.py):
//! `path type mode uid gid size sha256-or-link-target`, tab separated, absolute paths, mode as four
//! octal digits. Types: `f` regular file, `d` directory, `l` symlink (Q6: confirm against the real generator).

use crate::paths;

pub const HEADER: &str = "# path\ttype\tmode\tuid\tgid\tsize\tsha256 or link target";

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Kind {
    File,
    Dir,
    Link,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Entry {
    pub path: String,
    pub kind: Kind,
    pub mode: u32,
    pub uid: u32,
    pub gid: u32,
    pub size: u64,
    /// sha256 hex for files, link target for links, `-` for directories.
    pub data: String,
}

impl Entry {
    pub fn line(&self) -> String {
        let t = match self.kind {
            Kind::File => "f",
            Kind::Dir => "d",
            Kind::Link => "l",
        };
        format!("{}\t{}\t{:04o}\t{}\t{}\t{}\t{}", self.path, t, self.mode, self.uid, self.gid, self.size, self.data)
    }
    pub fn sha256(&self) -> Option<&str> {
        if self.kind == Kind::File {
            Some(&self.data)
        } else {
            None
        }
    }
}

pub fn is_hex64(s: &str) -> bool {
    s.len() == 64 && s.bytes().all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c))
}

pub fn parse(text: &str) -> Result<Vec<Entry>, String> {
    let mut out: Vec<Entry> = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for (i, line) in text.lines().enumerate() {
        let n = i + 1;
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let c: Vec<&str> = line.split('\t').collect();
        if c.len() != 7 {
            return Err(format!("file list line {n}: expected 7 columns"));
        }
        if !paths::is_safe(c[0]) {
            return Err(format!("file list line {n}: unsafe path {:?}", c[0]));
        }
        if !seen.insert(c[0].to_string()) {
            return Err(format!("file list line {n}: {} is listed twice", c[0]));
        }
        let kind = match c[1] {
            "f" => Kind::File,
            "d" => Kind::Dir,
            "l" => Kind::Link,
            t => return Err(format!("file list line {n}: unsupported entry type {t:?}")),
        };
        if c[2].len() != 4 || !c[2].bytes().all(|b| (b'0'..=b'7').contains(&b)) {
            return Err(format!("file list line {n}: mode must be four octal digits"));
        }
        let mode = u32::from_str_radix(c[2], 8).unwrap();
        let num = |s: &str| s.parse::<u64>().map_err(|_| format!("file list line {n}: bad number {s:?}"));
        let (uid, gid, size) = (num(c[3])? as u32, num(c[4])? as u32, num(c[5])?);
        match kind {
            Kind::File if !is_hex64(c[6]) => return Err(format!("file list line {n}: bad SHA-256")),
            Kind::Dir if c[6] != "-" || size != 0 => return Err(format!("file list line {n}: directory rows have size 0 and -")),
            Kind::Link if c[6].is_empty() || c[6].contains('\0') || size != c[6].len() as u64 => return Err(format!("file list line {n}: bad link target")),
            _ => {}
        }
        out.push(Entry { path: c[0].into(), kind, mode, uid, gid, size, data: c[6].into() });
    }
    Ok(out)
}

pub fn render(entries: &[Entry]) -> String {
    let mut s = String::from(HEADER);
    s.push('\n');
    for e in entries {
        s.push_str(&e.line());
        s.push('\n');
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn parse_rows() {
        let t =
            format!("{HEADER}\n/etc/vimrc\tf\t0644\t0\t0\t3\t{}\n/usr/share/vim\td\t0755\t0\t0\t0\t-\n/usr/bin/vi\tl\t0777\t0\t0\t3\tvim\n", "a".repeat(64));
        let e = parse(&t).unwrap();
        assert_eq!(e.len(), 3);
        assert_eq!(render(&e), t);
        assert!(parse("/a/../b\tf\t0644\t0\t0\t1\tx").is_err());
        assert!(parse(&format!("/a\tf\t644\t0\t0\t1\t{}", "a".repeat(64))).is_err());
        assert!(parse(&format!("/a\tc\t0644\t0\t0\t1\t{}", "a".repeat(64))).is_err());
        assert!(parse(&format!("/a\tf\t0644\t0\t0\t1\t{0}\n/a\tf\t0644\t0\t0\t1\t{0}", "a".repeat(64))).is_err());
    }
}
