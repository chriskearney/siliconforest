// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//! Package names and versions (design section 4.3): `upstream-revision`, compared component-wise
//! numerically, then by revision. Constraints: `=`, `>=`, `<=`, `<<`, `>>`.

use std::cmp::Ordering;

pub fn valid_name(n: &str) -> bool {
    let b = n.as_bytes();
    !b.is_empty()
        && b.len() <= 128
        && (b[0].is_ascii_lowercase() || b[0].is_ascii_digit())
        && b.iter().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || b"+._-".contains(c))
}

/// A version: upstream components (split on `.`, `+`, `~`; each compared numerically when both are
/// numbers, else as text) and an optional numeric revision after the last `-`.
pub fn valid_version(v: &str) -> bool {
    !v.is_empty()
        && v.len() <= 64
        && v.as_bytes()[0].is_ascii_alphanumeric()
        && v.bytes().all(|c| c.is_ascii_alphanumeric() || b".+~-".contains(&c))
        && split(v).1.is_none_or(|r| !r.is_empty() && r.bytes().all(|c| c.is_ascii_digit()))
}

fn split(v: &str) -> (&str, Option<&str>) {
    match v.rfind('-') {
        Some(i) => (&v[..i], Some(&v[i + 1..])),
        None => (v, None),
    }
}

fn cmp_part(a: &str, b: &str) -> Ordering {
    match (a.parse::<u64>(), b.parse::<u64>()) {
        (Ok(x), Ok(y)) => x.cmp(&y),
        (Ok(_), Err(_)) => Ordering::Less,
        (Err(_), Ok(_)) => Ordering::Greater,
        _ => a.cmp(b),
    }
}

pub fn compare(a: &str, b: &str) -> Ordering {
    let (ua, ra) = split(a);
    let (ub, rb) = split(b);
    let pa: Vec<&str> = ua.split(['.', '+', '~']).collect();
    let pb: Vec<&str> = ub.split(['.', '+', '~']).collect();
    for i in 0..pa.len().max(pb.len()) {
        let o = match (pa.get(i), pb.get(i)) {
            (Some(x), Some(y)) => cmp_part(x, y),
            (Some(_), None) => Ordering::Greater,
            (None, Some(_)) => Ordering::Less,
            _ => Ordering::Equal,
        };
        if o != Ordering::Equal {
            return o;
        }
    }
    let r = |x: Option<&str>| x.and_then(|s| s.parse::<u64>().ok()).unwrap_or(0);
    r(ra).cmp(&r(rb))
}

#[derive(Clone, Debug, PartialEq)]
pub struct Constraint {
    pub op: String,
    pub version: String,
}

impl Constraint {
    /// `"= 1.0-1"`, `">= 6.4"`, or empty/absent for any version.
    pub fn parse(s: &str) -> Option<Option<Constraint>> {
        let s = s.trim();
        if s.is_empty() {
            return Some(None);
        }
        for op in [">=", "<=", "<<", ">>", "="] {
            if let Some(rest) = s.strip_prefix(op) {
                let v = rest.trim();
                if !valid_version(v) {
                    return None;
                }
                return Some(Some(Constraint { op: op.into(), version: v.into() }));
            }
        }
        None
    }
    pub fn allows(&self, v: &str) -> bool {
        let o = compare(v, &self.version);
        match self.op.as_str() {
            "=" => o == Ordering::Equal,
            ">=" => o != Ordering::Less,
            "<=" => o != Ordering::Greater,
            "<<" => o == Ordering::Less,
            ">>" => o == Ordering::Greater,
            _ => false,
        }
    }
}

impl std::fmt::Display for Constraint {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{} {}", self.op, self.version)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn ordering() {
        assert_eq!(compare("9.1.0-2", "9.1.0-10"), Ordering::Less);
        assert_eq!(compare("9.10.0", "9.9.9-99"), Ordering::Greater);
        assert_eq!(compare("1.0", "1.0-0"), Ordering::Equal);
        assert_eq!(compare("1.0.1", "1.0"), Ordering::Greater);
        assert_eq!(compare("0.1.1-1", "0.1.0-7"), Ordering::Greater);
        assert!(valid_version("9.1.0-2") && !valid_version("9.1-x") && !valid_version("-1") && !valid_version(""));
        assert!(valid_name("sf-base") && valid_name("libc++") && !valid_name("Vim") && !valid_name("../x"));
    }
    #[test]
    fn constraints() {
        let c = Constraint::parse(">= 6.4").unwrap().unwrap();
        assert!(c.allows("6.4") && c.allows("6.5-1") && !c.allows("6.3.9"));
        assert!(Constraint::parse("<< 2").unwrap().unwrap().allows("1.9"));
        assert!(Constraint::parse("= 1.0-1").unwrap().unwrap().allows("1.0-1"));
        assert!(Constraint::parse("~> 1").is_none());
        assert_eq!(Constraint::parse(""), Some(None));
    }
}
