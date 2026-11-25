// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//! Transport (design section 8.5): plain GETs of static files, no cookies, no identifiers, no query,
//! a fixed User-Agent. Not a trust root: everything fetched is checked against a signature or a pinned
//! hash. `file://` and `http://` are handled here; `https://` runs /usr/bin/curl with fixed arguments.

use crate::error::{Code, Error, Result};
use crate::util;
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::net::TcpStream;
use std::path::{Path, PathBuf};
use std::time::Duration;

pub fn user_agent() -> String {
    format!("sap/{}", crate::manifest::SAP_VERSION.split('.').next().unwrap_or("1"))
}

fn neterr(msg: String) -> Error {
    Error::new(Code::Failure, msg)
}

/// `base` is the manifest's URL; `rel` is already checked by manifest::check_rel_url.
pub fn resolve(base: &str, rel: &str) -> String {
    match base.rfind('/') {
        Some(i) => format!("{}/{}", &base[..i], rel),
        None => rel.to_string(),
    }
}

/// Fetch a whole small object, refusing anything larger than `max`.
pub fn get(url: &str, max: u64) -> Result<Vec<u8>> {
    let tmp = std::env::temp_dir().join(format!("sap-get-{}-{}", std::process::id(), util::sha256(url.as_bytes())));
    let _ = fs::remove_file(&tmp);
    let r = download(url, &tmp, max, false);
    let out = r.and_then(|_| Ok(fs::read(&tmp)?));
    let _ = fs::remove_file(&tmp);
    out
}

/// Download into `dest`, resuming a partial file when `resume` is set, never writing more than `max`.
pub fn download(url: &str, dest: &Path, max: u64, resume: bool) -> Result<()> {
    if let Some(p) = url.strip_prefix("file://") {
        let src = PathBuf::from(p);
        let n = fs::metadata(&src).map_err(|e| neterr(format!("{url}: {e}")))?.len();
        if n > max {
            return Err(Error::new(Code::Verify, format!("{url} is larger than its pinned size")));
        }
        fs::copy(&src, dest).map_err(|e| neterr(format!("{url}: {e}")))?;
        return Ok(());
    }
    if url.starts_with("http://") {
        return http_get(url, dest, max, resume, 0);
    }
    if url.starts_with("https://") {
        return curl(url, dest, max, resume);
    }
    Err(neterr(format!("unsupported URL scheme: {url}")))
}

fn curl(url: &str, dest: &Path, max: u64, resume: bool) -> Result<()> {
    let tool = ["/usr/bin/curl", "/bin/curl"].iter().map(PathBuf::from).find(|p| p.exists());
    let tool = tool.ok_or_else(|| {
        neterr("https needs /usr/bin/curl, which is not installed; use an http:// or file:// mirror (the trust comes from the signature, not TLS)".into())
    })?;
    let mut c = std::process::Command::new(tool);
    c.env_clear().env("PATH", "/usr/bin:/bin").args(["--proto", "=https", "--tlsv1.2", "-q", "-sS", "--fail", "--max-redirs", "0", "--connect-timeout", "30"]);
    c.args(["-A", &user_agent(), "-H", "Accept:", "--max-filesize", &max.to_string()]);
    // The system's CA bundle, named: curl's built-in default differs between builds.
    if let Some(ca) =
        ["/etc/ssl/cert.pem", "/private/etc/ssl/cert.pem", "/etc/ssl/certs/ca-certificates.crt"].iter().find(|p| std::path::Path::new(p).is_file())
    {
        c.args(["--cacert", ca]);
    }
    c.arg("-o").arg(dest);
    if resume && dest.exists() {
        c.args(["-C", "-"]);
    }
    c.arg("--").arg(url);
    let st = c.status().map_err(|e| neterr(format!("curl: {e}")))?;
    if !st.success() {
        return Err(neterr(format!("{url}: download failed (curl {})", st.code().unwrap_or(-1))));
    }
    Ok(())
}

fn http_get(url: &str, dest: &Path, max: u64, resume: bool, redirects: u32) -> Result<()> {
    let rest = &url["http://".len()..];
    let (hostport, path) = match rest.find('/') {
        Some(i) => (&rest[..i], &rest[i..]),
        None => (rest, "/"),
    };
    let addr = if hostport.contains(':') { hostport.to_string() } else { format!("{hostport}:80") };
    let host = hostport.split(':').next().unwrap_or("");
    let have = if resume { fs::metadata(dest).map(|m| m.len()).unwrap_or(0) } else { 0 };
    let mut s = TcpStream::connect(&addr).map_err(|e| neterr(format!("{url}: {e}")))?;
    s.set_read_timeout(Some(Duration::from_secs(60))).ok();
    let mut req = format!("GET {path} HTTP/1.1\r\nHost: {host}\r\nUser-Agent: {}\r\nAccept-Encoding: identity\r\nConnection: close\r\n", user_agent());
    if have > 0 {
        req.push_str(&format!("Range: bytes={have}-\r\n"));
    }
    req.push_str("\r\n");
    s.write_all(req.as_bytes()).map_err(|e| neterr(format!("{url}: {e}")))?;
    // Headers.
    let mut head = Vec::new();
    let mut byte = [0u8; 1];
    while !head.ends_with(b"\r\n\r\n") {
        if head.len() > 65536 || s.read(&mut byte).map_err(|e| neterr(format!("{url}: {e}")))? == 0 {
            return Err(neterr(format!("{url}: bad HTTP response")));
        }
        head.push(byte[0]);
    }
    let head = String::from_utf8_lossy(&head).to_string();
    let mut lines = head.split("\r\n");
    let status: u32 = lines.next().and_then(|l| l.split_whitespace().nth(1)).and_then(|c| c.parse().ok()).unwrap_or(0);
    let mut length: Option<u64> = None;
    let mut chunked = false;
    let mut location = None;
    for l in lines {
        if let Some((k, v)) = l.split_once(':') {
            let v = v.trim();
            match k.to_ascii_lowercase().as_str() {
                "content-length" => length = v.parse().ok(),
                "transfer-encoding" => chunked = v.eq_ignore_ascii_case("chunked"),
                "location" => location = Some(v.to_string()),
                _ => {}
            }
        }
    }
    if (301..=308).contains(&status) {
        let loc = location.ok_or_else(|| neterr(format!("{url}: redirect without location")))?;
        if redirects >= 3 || !loc.starts_with("http://") {
            return Err(neterr(format!("{url}: refusing redirect to {loc}")));
        }
        return http_get(&loc, dest, max, resume, redirects + 1);
    }
    let append = status == 206 && have > 0;
    if status != 200 && !append {
        return Err(neterr(format!("{url}: HTTP {status}")));
    }
    let mut f = if append { OpenOptions::new().append(true).open(dest)? } else { File::create(dest)? };
    let mut total = if append { have } else { 0 };
    let mut body: Box<dyn Read> = Box::new(s);
    if chunked {
        let mut all = Vec::new();
        read_chunked(&mut body, &mut all, max).map_err(|e| neterr(format!("{url}: {e}")))?;
        body = Box::new(std::io::Cursor::new(all));
    }
    let mut buf = vec![0u8; 1 << 16];
    loop {
        let k = body.read(&mut buf).map_err(|e| neterr(format!("{url}: {e}")))?;
        if k == 0 {
            break;
        }
        total += k as u64;
        if total > max {
            return Err(Error::new(Code::Verify, format!("{url} is larger than its pinned size")));
        }
        f.write_all(&buf[..k])?;
    }
    f.sync_all()?;
    if let (Some(l), false) = (length, chunked) {
        if total != l + if append { have } else { 0 } {
            return Err(neterr(format!("{url}: short read")));
        }
    }
    Ok(())
}

fn read_chunked(r: &mut Box<dyn Read>, out: &mut Vec<u8>, max: u64) -> std::io::Result<()> {
    let mut line = Vec::new();
    let mut b = [0u8; 1];
    loop {
        line.clear();
        while !line.ends_with(b"\r\n") {
            if r.read(&mut b)? == 0 {
                return Err(std::io::Error::other("truncated chunk"));
            }
            line.push(b[0]);
        }
        let t = String::from_utf8_lossy(&line[..line.len() - 2]).to_string();
        let n = u64::from_str_radix(t.split(';').next().unwrap_or("").trim(), 16).map_err(|_| std::io::Error::other("bad chunk"))?;
        if n == 0 {
            return Ok(());
        }
        if out.len() as u64 + n > max {
            return Err(std::io::Error::other("larger than pinned"));
        }
        let mut chunk = vec![0u8; n as usize];
        r.read_exact(&mut chunk)?;
        out.extend_from_slice(&chunk);
        r.read_exact(&mut [0u8; 2])?;
    }
}
