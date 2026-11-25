// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//! The kernel collection on an installed machine (design sections 3.5, 5.2): relink with kc-builder
//! exactly as the installer's S17 does (installer/payload/release/kc_release.py `assemble`), accept only
//! the recipe's collection_sha256/bytes, and pack `sf/kernel.bin` as PDSF records (CONFIG, gzip KERNEL,
//! END) the way S42 does (installer/mac/Sources/SFEngine/Engine/KernelCollection.swift `PDSF`).

use crate::error::{Code, Error, Result};
use crate::json::Value;
use crate::{bail, util};
use flate2::write::GzEncoder;
use flate2::{Compression, GzBuilder};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

pub const KC_FORMAT: &str = "siliconforest-kc/1";
pub const OUTPUT: &str = "@OUTPUT@";
const MAGIC: u32 = 0x4653_4450;
const ALIGN: usize = 16;
const END: u16 = 0;
const CONFIG: u16 = 1;
const KERNEL: u16 = 2;
const GZIP: u32 = 1;
pub const BOOTARGS_CAPACITY: usize = 608;

fn verr(m: String) -> Error {
    Error::new(Code::Verify, m)
}

fn part_ok(s: &str) -> bool {
    let b = s.as_bytes();
    !b.is_empty() && b.len() <= 81 && b[0].is_ascii_alphanumeric() && b.iter().all(|c| c.is_ascii_alphanumeric() || b"._+-".contains(c))
}

/// kc_release.parse_link_args: (bundle dirs in order, kc_base). Anything outside the format is refused.
pub fn parse_link_args(args: &[String]) -> Result<(Vec<String>, String)> {
    let (mut kernel, mut out, mut base, mut bundles) = (false, false, None::<String>, Vec::<String>::new());
    let mut i = 0;
    while i < args.len() {
        let opt = args[i].as_str();
        let val = args.get(i + 1).ok_or_else(|| verr(format!("link option {opt} has no value")))?;
        match opt {
            "-kernel" => {
                if kernel || val != "kernel" {
                    bail!(Verify, "link_args: -kernel must be given once, as 'kernel'");
                }
                kernel = true;
            }
            "-kext" | "-codeless" => {
                let want = if opt == "-kext" { "kexts" } else { "codeless" };
                let ok = match val.split_once('/') {
                    Some((k, n)) => k == want && part_ok(n) && n.ends_with(".kext") && n.len() > 5,
                    None => false,
                };
                if !ok || bundles.contains(val) {
                    bail!(Verify, "link_args: bad or repeated bundle {val:?}");
                }
                bundles.push(val.clone());
            }
            "-kc-base" => {
                if base.is_some() || val.is_empty() || val.len() > 16 || !val.bytes().all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c)) {
                    bail!(Verify, "link_args: bad -kc-base {val:?}");
                }
                base = Some(val.clone());
            }
            "-o" => {
                if out || val != OUTPUT {
                    bail!(Verify, "link_args: -o must be given once, as @OUTPUT@");
                }
                out = true;
            }
            _ => bail!(Verify, "link_args: option {opt:?} is not part of the release link format"),
        }
        i += 2;
    }
    if !kernel || !out || base.is_none() {
        bail!(Verify, "link_args: -kernel, -kc-base and -o are required");
    }
    Ok((bundles, base.unwrap()))
}

/// The kc-recipe record's `kernel_collection` (docs/sap/FORMATS.md): where each linker input lives in
/// the root, which package owns it, and what the result must be.
#[derive(Clone, Debug)]
pub struct Recipe {
    pub link_args: Vec<String>,
    /// (assembly-relative path, root path, mode, owning package)
    pub inputs: Vec<(String, String, u32, String)>,
    pub tool: (String, String),
    pub collection_sha256: String,
    pub collection_bytes: u64,
    pub bootargs_template: String,
}

pub fn parse_recipe(rec: &Value) -> Result<Recipe> {
    let kc = rec.get("kernel_collection").ok_or_else(|| verr("kc-recipe record has no kernel_collection".into()))?;
    if kc.get("format").and_then(|f| f.as_str()) != Some(KC_FORMAT) {
        bail!(Verify, "kernel_collection: unknown format");
    }
    let link_args: Vec<String> = kc
        .get("link_args")
        .and_then(|a| a.as_array())
        .ok_or_else(|| verr("kernel_collection: no link_args".into()))?
        .iter()
        .filter_map(|x| x.as_str().map(String::from))
        .collect();
    let (bundles, base) = parse_link_args(&link_args)?;
    if kc.get("kc_base").and_then(|b| b.as_str()) != Some(base.as_str()) {
        bail!(Verify, "kernel_collection: kc_base disagrees with link_args");
    }
    let s = |v: &Value, k: &str| v.get(k).and_then(|x| x.as_str()).map(String::from).ok_or_else(|| verr(format!("kernel_collection: {k} missing")));
    let mut inputs = Vec::new();
    let kern = kc.get("kernel").ok_or_else(|| verr("kernel_collection: kernel missing".into()))?;
    inputs.push(("kernel".to_string(), s(kern, "path")?, 0o444, s(kern, "package")?));
    let listed = kc.get("bundles").and_then(|b| b.as_array()).ok_or_else(|| verr("kernel_collection: bundles missing".into()))?;
    if listed.iter().map(|b| b.get("dir").and_then(|d| d.as_str()).unwrap_or("")).collect::<Vec<_>>() != bundles.iter().map(|s| s.as_str()).collect::<Vec<_>>()
    {
        bail!(Verify, "kernel_collection: bundles are not exactly link_args' bundles, in order");
    }
    for b in listed {
        let dir = s(b, "dir")?;
        let pkg = s(b, "package")?;
        let files = b.get("files").and_then(|f| f.as_array()).ok_or_else(|| verr("kernel_collection: bundle files".into()))?;
        if files.is_empty() {
            bail!(Verify, "kernel_collection: {dir} has no files");
        }
        for f in files {
            let rel = s(f, "path")?;
            if !rel.split('/').all(part_ok) {
                bail!(Verify, "kernel_collection: unusual path {rel:?}");
            }
            let mode = f.get("mode").and_then(|m| m.as_i64()).unwrap_or(-1);
            if mode != 0o644 && mode != 0o755 {
                bail!(Verify, "kernel_collection: bad mode for {rel}");
            }
            inputs.push((format!("{dir}/{rel}"), s(f, "root_path")?, mode as u32, pkg.clone()));
        }
    }
    let tool = kc.get("tool").ok_or_else(|| verr("kernel_collection: tool missing".into()))?;
    let sha = s(kc, "collection_sha256")?;
    if !crate::tsv::is_hex64(&sha) {
        bail!(Verify, "kernel_collection: bad collection_sha256");
    }
    let bytes = kc.get("collection_bytes").and_then(|b| b.as_i64()).filter(|b| *b > 0).ok_or_else(|| verr("kernel_collection: bad collection_bytes".into()))?;
    Ok(Recipe {
        link_args,
        inputs,
        tool: (s(tool, "path")?, s(tool, "package")?),
        collection_sha256: sha,
        collection_bytes: bytes as u64,
        bootargs_template: rec.get("bootargs_template").and_then(|t| t.as_str()).unwrap_or("").trim_end_matches('\n').to_string(),
    })
}

/// S17 on the machine: copy every input (located by `locate`, which returns a file and the SHA-256 the
/// signed file list pins) into a fresh private directory, re-hashing each copy, run kc-builder with
/// exactly link_args, accept only the pinned result. Returns the collection's path inside `work`.
/// Where an input file is on disk, and its signed SHA-256: (package, root path) -> (path, sha256).
pub type Locate<'a> = dyn Fn(&str, &str) -> Result<(PathBuf, String)> + 'a;

pub fn relink(recipe: &Recipe, locate: &Locate, work: &Path, timeout: Duration) -> Result<PathBuf> {
    use std::os::unix::fs::PermissionsExt;
    let _ = std::fs::remove_dir_all(work);
    let tree = work.join("inputs");
    std::fs::create_dir_all(&tree)?;
    std::fs::set_permissions(work, std::fs::Permissions::from_mode(0o700))?;
    let take = |pkg: &str, root_path: &str, dest: &Path, mode: u32| -> Result<()> {
        let (src, want) = locate(pkg, root_path)?;
        std::fs::create_dir_all(dest.parent().unwrap())?;
        std::fs::copy(&src, dest).map_err(|e| Error::new(Code::Failure, format!("copy {}: {e}", src.display())))?;
        if util::sha256_file(dest)?.0 != want {
            bail!(Verify, "{root_path} does not match its signed hash");
        }
        std::fs::set_permissions(dest, std::fs::Permissions::from_mode(mode))?;
        Ok(())
    };
    let tool = work.join("kc-builder");
    take(&recipe.tool.1, &recipe.tool.0, &tool, 0o755)?;
    for (rel, root_path, mode, pkg) in &recipe.inputs {
        take(pkg, root_path, &tree.join(rel), *mode)?;
    }
    let out = work.join("collection");
    let args: Vec<String> = recipe.link_args.iter().map(|a| if a == OUTPUT { out.to_string_lossy().to_string() } else { a.clone() }).collect();
    let log = std::fs::File::create(work.join("kc-builder.log"))?;
    let mut child = Command::new(&tool)
        .args(&args)
        .current_dir(&tree)
        .env_clear()
        .env("PATH", "/usr/bin:/bin")
        .env("LC_ALL", "C")
        .stdin(Stdio::null())
        .stdout(log.try_clone()?)
        .stderr(log)
        .spawn()
        .map_err(|e| Error::new(Code::Failure, format!("kc-builder did not start: {e}")))?;
    let start = Instant::now();
    let status = loop {
        if let Some(s) = child.try_wait()? {
            break s;
        }
        if start.elapsed() > timeout {
            let _ = child.kill();
            let _ = child.wait();
            let _ = std::fs::remove_file(&out);
            bail!(Failure, "kc-builder took longer than {} s", timeout.as_secs());
        }
        std::thread::sleep(Duration::from_millis(20));
    };
    let fail = |e: Error| {
        let _ = std::fs::remove_file(&out);
        e
    };
    if !status.success() {
        return Err(fail(Error::new(Code::Failure, format!("kc-builder failed ({status})"))));
    }
    let (sha, n) = util::sha256_file(&out).map_err(|e| fail(e.into()))?;
    if sha != recipe.collection_sha256 || n != recipe.collection_bytes {
        return Err(fail(verr(format!(
            "the relinked collection is {}… ({n} B), not the recipe's {}… ({} B)",
            &sha[..16],
            &recipe.collection_sha256[..16],
            recipe.collection_bytes
        ))));
    }
    std::fs::remove_dir_all(&tree)?;
    Ok(out)
}

fn crc32(d: &[u8]) -> u32 {
    let mut c = flate2::Crc::new();
    c.update(d);
    c.sum()
}

fn header(kind: u16, flags: u32, crc: u32, size: u64, raw: u64) -> Vec<u8> {
    let mut d = Vec::with_capacity(32);
    d.extend_from_slice(&MAGIC.to_le_bytes());
    d.extend_from_slice(&1u16.to_le_bytes());
    d.extend_from_slice(&kind.to_le_bytes());
    d.extend_from_slice(&flags.to_le_bytes());
    d.extend_from_slice(&crc.to_le_bytes());
    d.extend_from_slice(&size.to_le_bytes());
    d.extend_from_slice(&raw.to_le_bytes());
    d
}

fn record(kind: u16, data: &[u8], raw: usize, flags: u32) -> Vec<u8> {
    let mut r = header(kind, flags, crc32(data), data.len() as u64, raw as u64);
    r.extend_from_slice(data);
    let pad = (ALIGN - r.len() % ALIGN) % ALIGN;
    r.extend(std::iter::repeat_n(0u8, pad));
    r
}

pub fn check_bootargs(b: &str) -> Result<()> {
    if b.is_empty() || b.len() >= BOOTARGS_CAPACITY || !b.bytes().all(|c| (32..127).contains(&c)) {
        bail!(Verify, "the boot arguments must be 1 to {} printable ASCII characters", BOOTARGS_CAPACITY - 1);
    }
    Ok(())
}

fn gzip(d: &[u8]) -> Vec<u8> {
    // No name, mtime 0, OS Unix: the same input gives the same bytes (as the installer's Gzip.compress).
    let mut e: GzEncoder<Vec<u8>> = GzBuilder::new().mtime(0).operating_system(3).write(Vec::new(), Compression::best());
    e.write_all(d).unwrap();
    e.finish().unwrap()
}

pub fn kernel_bin(bootargs: &str, collection: &[u8]) -> Result<Vec<u8>> {
    check_bootargs(bootargs)?;
    let cfg = format!("bootargs={bootargs}\n");
    let mut d = record(CONFIG, cfg.as_bytes(), cfg.len(), 0);
    let gz = gzip(collection);
    d.extend(record(KERNEL, &gz, collection.len(), GZIP));
    d.extend(header(END, 0, 0, 0, 0));
    Ok(d)
}

/// (kind, payload after gunzip) of every record, checking CRCs and sizes.
pub fn records(d: &[u8]) -> Result<Vec<(u16, Vec<u8>)>> {
    let mut out = Vec::new();
    let mut o = 0usize;
    let u32at = |at: usize| u32::from_le_bytes(d[at..at + 4].try_into().unwrap());
    let u64at = |at: usize| u64::from_le_bytes(d[at..at + 8].try_into().unwrap());
    while o + 32 <= d.len() {
        if u32at(o) != MAGIC {
            bail!(Verify, "kernel.bin: not a PDSF record at {o}");
        }
        let kind = u16::from_le_bytes([d[o + 6], d[o + 7]]);
        let (flags, crc, size, raw) = (u32at(o + 8), u32at(o + 12), u64at(o + 16) as usize, u64at(o + 24) as usize);
        if kind == END {
            return Ok(out);
        }
        if o + 32 + size > d.len() {
            bail!(Verify, "kernel.bin: record runs past the end");
        }
        let body = &d[o + 32..o + 32 + size];
        if crc32(body) != crc {
            bail!(Verify, "kernel.bin: record CRC");
        }
        let payload = if flags & GZIP != 0 {
            let mut g = flate2::read::GzDecoder::new(body);
            let mut v = Vec::new();
            std::io::Read::read_to_end(&mut g, &mut v).map_err(|_| verr("kernel.bin: bad gzip".into()))?;
            if v.len() != raw {
                bail!(Verify, "kernel.bin: gzip size");
            }
            v
        } else {
            body.to_vec()
        };
        out.push((kind, payload));
        o += 32 + size;
        o += (ALIGN - o % ALIGN) % ALIGN;
    }
    bail!(Verify, "kernel.bin: no END record")
}

pub fn read_bootargs(d: &[u8]) -> Result<String> {
    for (k, p) in records(d)? {
        if k == CONFIG {
            let t = String::from_utf8(p).map_err(|_| verr("kernel.bin: CONFIG is not text".into()))?;
            for l in t.lines() {
                if let Some(a) = l.strip_prefix("bootargs=") {
                    return Ok(a.to_string());
                }
            }
        }
    }
    bail!(Verify, "kernel.bin has no boot arguments")
}

pub fn read_collection(d: &[u8]) -> Result<Vec<u8>> {
    records(d)?.into_iter().find(|(k, _)| *k == KERNEL).map(|(_, p)| p).ok_or_else(|| verr("kernel.bin has no KERNEL record".into()))
}

const VARS: &[&str] = &["@SF_FSUUID@", "@SF_PARTUUID@", "@SF_PART_LBA@"];

/// Recover the personal values (@SF_FSUUID@, @SF_PARTUUID@, @SF_PART_LBA@) from boot arguments made
/// from `template`, by matching the template's words. Never guessed: a mismatch is an error.
pub fn personal_values(template: &str, bootargs: &str) -> Result<Vec<(String, String)>> {
    let tw: Vec<&str> = template.split_whitespace().collect();
    let bw: Vec<&str> = bootargs.split_whitespace().filter(|w| !w.starts_with("sf_trust=") && !w.starts_with("sf_slot=")).collect();
    if tw.len() != bw.len() {
        bail!(Verify, "the installed boot arguments were not made from the installed template");
    }
    let mut vals: Vec<(String, String)> = Vec::new();
    for (t, b) in tw.iter().zip(bw.iter()) {
        if let Some(var) = VARS.iter().find(|v| t.contains(*v)) {
            let (pre, post) = t.split_once(var).unwrap();
            if !b.starts_with(pre) || !b.ends_with(post) || b.len() < pre.len() + post.len() {
                bail!(Verify, "the installed boot arguments do not match the template at {t}");
            }
            let v = &b[pre.len()..b.len() - post.len()];
            if let Some((_, old)) = vals.iter().find(|(k, _)| k == var) {
                if old != v {
                    bail!(Verify, "{var} has two values in the installed boot arguments");
                }
            }
            vals.push((var.to_string(), v.to_string()));
        } else if t != b {
            bail!(Verify, "the installed boot arguments differ from the template at {t}");
        }
    }
    Ok(vals)
}

pub fn fill_template(template: &str, vals: &[(String, String)]) -> Result<String> {
    let mut s = template.trim().to_string();
    for v in VARS {
        if s.contains(v) {
            let val = vals.iter().find(|(k, _)| k == v).map(|(_, x)| x.clone()).ok_or_else(|| verr(format!("no installed value for {v}")))?;
            s = s.replace(v, &val);
        }
    }
    if s.contains("@SF_") {
        bail!(Verify, "the boot argument template names an unknown @SF_ variable");
    }
    Ok(s)
}

/// Replace (or add) the sf_trust= word.
pub fn with_trust(bootargs: &str, token: Option<&str>) -> String {
    let mut w: Vec<&str> = bootargs.split_whitespace().filter(|w| !w.starts_with("sf_trust=")).collect();
    if let Some(t) = token {
        w.push(t);
    }
    w.join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn pdsf_roundtrip() {
        let coll: Vec<u8> = (0..50000u32).map(|i| (i % 251) as u8).collect();
        let kb = kernel_bin("rd=uuid boot-uuid=ABC", &coll).unwrap();
        assert_eq!(kb.len() % 16, 0);
        assert_eq!(read_bootargs(&kb).unwrap(), "rd=uuid boot-uuid=ABC");
        assert_eq!(read_collection(&kb).unwrap(), coll);
        let mut bad = kb.clone();
        bad[40] ^= 1;
        assert!(records(&bad).is_err());
        assert!(kernel_bin("", &coll).is_err());
        assert!(kernel_bin(&"x".repeat(700), &coll).is_err());
    }
    #[test]
    fn personalisation() {
        let t = "rd=uuid boot-uuid=@SF_FSUUID@ sfnvme_part=@SF_PARTUUID@ sfnvme_part_lba=@SF_PART_LBA@";
        let b = "rd=uuid boot-uuid=37215ab4 sfnvme_part=AAAA-BB sfnvme_part_lba=12345 sf_trust=1:x";
        let v = personal_values(t, b).unwrap();
        let t2 = "rd=uuid boot-uuid=@SF_FSUUID@ wdt=-1 sfnvme_part=@SF_PARTUUID@ sfnvme_part_lba=@SF_PART_LBA@";
        assert_eq!(fill_template(t2, &v).unwrap(), "rd=uuid boot-uuid=37215ab4 wdt=-1 sfnvme_part=AAAA-BB sfnvme_part_lba=12345");
        assert!(personal_values(t, "rd=uuid boot-uuid=x").is_err());
        assert!(fill_template("x=@SF_OTHER@", &v).is_err());
        assert_eq!(with_trust("a b sf_trust=1:x", Some("sf_trust=2:y")), "a b sf_trust=2:y");
    }
    #[test]
    fn link_args() {
        let a: Vec<String> =
            "-kc-base fffffe0006000000 -kernel kernel -kext kexts/A.kext -codeless codeless/K.kext -o @OUTPUT@".split(' ').map(String::from).collect();
        assert_eq!(parse_link_args(&a).unwrap().0, vec!["kexts/A.kext", "codeless/K.kext"]);
        let mut b = a.clone();
        b.push("-sandbox".into());
        b.push("x".into());
        assert!(parse_link_args(&b).is_err());
        let c: Vec<String> = a.iter().map(|x| x.replace("kexts/A.kext", "kexts/../A.kext")).collect();
        assert!(parse_link_args(&c).is_err());
    }
}
