// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//! In-process verification of OpenSSH signatures (PROTOCOL.sshsig) made by `ssh-keygen -Y sign` with an
//! Ed25519 key, the way the release's SHA256SUMS.sig is made (design section 8.1). No `ssh-keygen` is run.

use crate::b64;
use ed25519_dalek::{Signature, VerifyingKey};
use sha2::{Digest, Sha256, Sha512};

pub const NAMESPACE: &str = "siliconforest-release";
const MAGIC: &[u8] = b"SSHSIG";
const BEGIN: &str = "-----BEGIN SSH SIGNATURE-----";
const END: &str = "-----END SSH SIGNATURE-----";

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PublicKey(pub [u8; 32]);

impl PublicKey {
    pub fn blob(&self) -> Vec<u8> {
        let mut b = Vec::new();
        put_string(&mut b, b"ssh-ed25519");
        put_string(&mut b, &self.0);
        b
    }
    /// `SHA256:…` as `ssh-keygen -l -E sha256` prints it.
    pub fn fingerprint(&self) -> String {
        format!("SHA256:{}", b64::encode(&Sha256::digest(self.blob()), false))
    }
    pub fn from_blob(blob: &[u8]) -> Option<PublicKey> {
        let mut r = Reader { b: blob, i: 0 };
        if r.string()? != b"ssh-ed25519" {
            return None;
        }
        let k = r.string()?;
        if r.i != blob.len() || k.len() != 32 {
            return None;
        }
        Some(PublicKey(k.try_into().ok()?))
    }
    /// One `ssh-ed25519 AAAA… comment` or allowed_signers line (`principal [options] ssh-ed25519 AAAA…`).
    pub fn from_openssh_line(line: &str) -> Option<PublicKey> {
        let words: Vec<&str> = line.split_whitespace().collect();
        let at = words.iter().position(|w| *w == "ssh-ed25519")?;
        PublicKey::from_blob(&b64::decode(words.get(at + 1)?)?)
    }
}

fn put_string(b: &mut Vec<u8>, s: &[u8]) {
    b.extend_from_slice(&(s.len() as u32).to_be_bytes());
    b.extend_from_slice(s);
}

struct Reader<'a> {
    b: &'a [u8],
    i: usize,
}

impl<'a> Reader<'a> {
    fn u32(&mut self) -> Option<u32> {
        let v = self.b.get(self.i..self.i + 4)?;
        self.i += 4;
        Some(u32::from_be_bytes(v.try_into().ok()?))
    }
    fn string(&mut self) -> Option<&'a [u8]> {
        let n = self.u32()? as usize;
        if n > self.b.len() {
            return None;
        }
        let v = self.b.get(self.i..self.i.checked_add(n)?)?;
        self.i += n;
        Some(v)
    }
}

#[derive(Debug, PartialEq, Eq)]
pub enum SigError {
    Malformed(&'static str),
    Namespace,
    UnknownKey(String),
    Invalid,
}

impl std::fmt::Display for SigError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SigError::Malformed(w) => write!(f, "the signature is malformed ({w})"),
            SigError::Namespace => write!(f, "the signature is for another namespace, not {NAMESPACE}"),
            SigError::UnknownKey(fp) => write!(f, "the signature is by {fp}, which is not in this machine's trust anchor"),
            SigError::Invalid => write!(f, "the signature does not verify"),
        }
    }
}

/// The armoured signature's binary blob.
pub fn unarmor(text: &[u8]) -> Result<Vec<u8>, SigError> {
    let t = std::str::from_utf8(text).map_err(|_| SigError::Malformed("not text"))?;
    let t = t.trim();
    let inner = t.strip_prefix(BEGIN).and_then(|r| r.strip_suffix(END)).ok_or(SigError::Malformed("no SSH SIGNATURE armour"))?;
    let joined: String = inner.split_whitespace().collect();
    b64::decode(&joined).ok_or(SigError::Malformed("bad base64"))
}

/// Verify `sig_armored` over `message` in `namespace` against any key of `trusted`. Returns the key used.
pub fn verify<'k>(message: &[u8], sig_armored: &[u8], namespace: &str, trusted: &'k [PublicKey]) -> Result<&'k PublicKey, SigError> {
    let blob = unarmor(sig_armored)?;
    if !blob.starts_with(MAGIC) {
        return Err(SigError::Malformed("no SSHSIG magic"));
    }
    let mut r = Reader { b: &blob, i: MAGIC.len() };
    let version = r.u32().ok_or(SigError::Malformed("short"))?;
    if version != 1 {
        return Err(SigError::Malformed("unsupported sshsig version"));
    }
    let pk_blob = r.string().ok_or(SigError::Malformed("short"))?;
    let ns = r.string().ok_or(SigError::Malformed("short"))?;
    let reserved = r.string().ok_or(SigError::Malformed("short"))?;
    let hash_alg = r.string().ok_or(SigError::Malformed("short"))?;
    let sig = r.string().ok_or(SigError::Malformed("short"))?;
    if r.i != blob.len() {
        return Err(SigError::Malformed("trailing bytes"));
    }
    if ns != namespace.as_bytes() {
        return Err(SigError::Namespace);
    }
    let pk = PublicKey::from_blob(pk_blob).ok_or(SigError::Malformed("not an Ed25519 key"))?;
    let key = trusted.iter().find(|k| **k == pk).ok_or_else(|| SigError::UnknownKey(pk.fingerprint()))?;
    let mut sr = Reader { b: sig, i: 0 };
    if sr.string() != Some(b"ssh-ed25519") {
        return Err(SigError::Malformed("not an Ed25519 signature"));
    }
    let raw = sr.string().ok_or(SigError::Malformed("short signature"))?;
    if sr.i != sig.len() || raw.len() != 64 {
        return Err(SigError::Malformed("bad signature length"));
    }
    let digest: Vec<u8> = match hash_alg {
        b"sha512" => Sha512::digest(message).to_vec(),
        b"sha256" => Sha256::digest(message).to_vec(),
        _ => return Err(SigError::Malformed("unknown hash algorithm")),
    };
    let mut signed = MAGIC.to_vec();
    put_string(&mut signed, ns);
    put_string(&mut signed, reserved);
    put_string(&mut signed, hash_alg);
    put_string(&mut signed, &digest);
    let vk = VerifyingKey::from_bytes(&key.0).map_err(|_| SigError::Malformed("bad public key"))?;
    let s = Signature::from_bytes(raw.try_into().unwrap());
    vk.verify_strict(&signed, &s).map_err(|_| SigError::Invalid)?;
    Ok(key)
}

#[cfg(test)]
mod tests {
    use super::*;

    // Made with: ssh-keygen -t ed25519 -C 'siliconforest-release TEST-ONLY unit-test'; printf 'hello\n' |
    // ssh-keygen -Y sign -n siliconforest-release -f key. TEST-ONLY throwaway key; its private half was deleted.
    const PUB: &str = include_str!("../testdata/unit.pub");
    const SIG: &[u8] = include_bytes!("../testdata/unit.sig");

    #[test]
    fn verifies_ssh_keygen_signature() {
        let k = PublicKey::from_openssh_line(PUB).unwrap();
        assert!(k.fingerprint().starts_with("SHA256:"));
        let keys = vec![k];
        assert!(verify(b"hello\n", SIG, NAMESPACE, &keys).is_ok());
        assert_eq!(verify(b"hello!\n", SIG, NAMESPACE, &keys), Err(SigError::Invalid));
        assert_eq!(verify(b"hello\n", SIG, "file", &keys), Err(SigError::Namespace));
        assert!(matches!(verify(b"hello\n", SIG, NAMESPACE, &[PublicKey([7; 32])]), Err(SigError::UnknownKey(_))));
        let mut bad = unarmor(SIG).unwrap();
        let n = bad.len();
        bad[n - 1] ^= 1;
        let arm = format!("{BEGIN}\n{}\n{END}\n", b64::encode(&bad, true));
        assert_eq!(verify(b"hello\n", arm.as_bytes(), NAMESPACE, &keys), Err(SigError::Invalid));
        assert!(verify(b"hello\n", b"garbage", NAMESPACE, &keys).is_err());
    }

    #[test]
    fn release_key_fingerprint() {
        // The real release key's public half (sap/trust/release-keys); fingerprint per sfrelease.py.
        let k = PublicKey::from_openssh_line(include_str!("../../trust/release-keys").lines().find(|l| l.starts_with("ssh-")).unwrap()).unwrap();
        assert_eq!(k.fingerprint(), "SHA256:y5XAQCFbvtrcB7JG73cXZajUSTrIOewSASbcoVKspQc");
    }
}
