// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//! A strict JSON reader and a deterministic writer (design section 6.3, rule 6): duplicate keys are an
//! error, numbers are integers only, nesting and size are bounded. Objects keep their key order.

use std::fmt::Write as _;

#[derive(Clone, Debug, PartialEq)]
pub enum Value {
    Null,
    Bool(bool),
    Int(i64),
    Str(String),
    Array(Vec<Value>),
    Object(Vec<(String, Value)>),
}

pub const MAX_DEPTH: usize = 64;

#[derive(Debug, PartialEq)]
pub struct JsonError(pub String);

impl std::fmt::Display for JsonError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

pub fn parse(bytes: &[u8]) -> Result<Value, JsonError> {
    let text = std::str::from_utf8(bytes).map_err(|_| JsonError("JSON is not UTF-8".into()))?;
    let mut p = Parser { s: text.as_bytes(), i: 0 };
    p.ws();
    let v = p.value(0)?;
    p.ws();
    if p.i != p.s.len() {
        return Err(p.err("trailing data"));
    }
    Ok(v)
}

struct Parser<'a> {
    s: &'a [u8],
    i: usize,
}

impl<'a> Parser<'a> {
    fn err(&self, what: &str) -> JsonError {
        JsonError(format!("JSON: {what} at byte {}", self.i))
    }
    fn ws(&mut self) {
        while self.i < self.s.len() && matches!(self.s[self.i], b' ' | b'\t' | b'\n' | b'\r') {
            self.i += 1;
        }
    }
    fn peek(&self) -> Option<u8> {
        self.s.get(self.i).copied()
    }
    fn lit(&mut self, word: &str, v: Value) -> Result<Value, JsonError> {
        if self.s[self.i..].starts_with(word.as_bytes()) {
            self.i += word.len();
            Ok(v)
        } else {
            Err(self.err("bad literal"))
        }
    }
    fn value(&mut self, depth: usize) -> Result<Value, JsonError> {
        if depth > MAX_DEPTH {
            return Err(self.err("nested too deeply"));
        }
        match self.peek() {
            Some(b'{') => self.object(depth),
            Some(b'[') => self.array(depth),
            Some(b'"') => Ok(Value::Str(self.string()?)),
            Some(b't') => self.lit("true", Value::Bool(true)),
            Some(b'f') => self.lit("false", Value::Bool(false)),
            Some(b'n') => self.lit("null", Value::Null),
            Some(c) if c == b'-' || c.is_ascii_digit() => self.number(),
            _ => Err(self.err("expected a value")),
        }
    }
    fn number(&mut self) -> Result<Value, JsonError> {
        let start = self.i;
        if self.peek() == Some(b'-') {
            self.i += 1;
        }
        let digits = self.i;
        while matches!(self.peek(), Some(c) if c.is_ascii_digit()) {
            self.i += 1;
        }
        if self.i == digits {
            return Err(self.err("bad number"));
        }
        if self.s[digits] == b'0' && self.i - digits > 1 {
            return Err(self.err("leading zero"));
        }
        if matches!(self.peek(), Some(b'.' | b'e' | b'E')) {
            return Err(self.err("numbers must be integers"));
        }
        let t = std::str::from_utf8(&self.s[start..self.i]).unwrap();
        t.parse::<i64>().map(Value::Int).map_err(|_| self.err("integer out of range"))
    }
    fn hex4(&mut self) -> Result<u32, JsonError> {
        if self.i + 4 > self.s.len() {
            return Err(self.err("short \\u escape"));
        }
        let t = std::str::from_utf8(&self.s[self.i..self.i + 4]).map_err(|_| self.err("bad \\u"))?;
        let v = u32::from_str_radix(t, 16).map_err(|_| self.err("bad \\u"))?;
        self.i += 4;
        Ok(v)
    }
    fn string(&mut self) -> Result<String, JsonError> {
        self.i += 1;
        let mut out = String::new();
        loop {
            let c = self.peek().ok_or_else(|| self.err("unterminated string"))?;
            match c {
                b'"' => {
                    self.i += 1;
                    return Ok(out);
                }
                b'\\' => {
                    self.i += 1;
                    let e = self.peek().ok_or_else(|| self.err("bad escape"))?;
                    self.i += 1;
                    match e {
                        b'"' => out.push('"'),
                        b'\\' => out.push('\\'),
                        b'/' => out.push('/'),
                        b'b' => out.push('\u{8}'),
                        b'f' => out.push('\u{c}'),
                        b'n' => out.push('\n'),
                        b'r' => out.push('\r'),
                        b't' => out.push('\t'),
                        b'u' => {
                            let mut cp = self.hex4()?;
                            if (0xD800..0xDC00).contains(&cp) {
                                if !self.s[self.i..].starts_with(b"\\u") {
                                    return Err(self.err("lone surrogate"));
                                }
                                self.i += 2;
                                let lo = self.hex4()?;
                                if !(0xDC00..0xE000).contains(&lo) {
                                    return Err(self.err("bad surrogate pair"));
                                }
                                cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                            } else if (0xDC00..0xE000).contains(&cp) {
                                return Err(self.err("lone surrogate"));
                            }
                            out.push(char::from_u32(cp).ok_or_else(|| self.err("bad code point"))?);
                        }
                        _ => return Err(self.err("bad escape")),
                    }
                }
                0..=0x1f => return Err(self.err("control character in string")),
                _ => {
                    // Copy one UTF-8 sequence (input is valid UTF-8).
                    let len = match c {
                        0x00..=0x7f => 1,
                        0xc0..=0xdf => 2,
                        0xe0..=0xef => 3,
                        _ => 4,
                    };
                    out.push_str(std::str::from_utf8(&self.s[self.i..self.i + len]).unwrap());
                    self.i += len;
                }
            }
        }
    }
    fn array(&mut self, depth: usize) -> Result<Value, JsonError> {
        self.i += 1;
        let mut v = Vec::new();
        self.ws();
        if self.peek() == Some(b']') {
            self.i += 1;
            return Ok(Value::Array(v));
        }
        loop {
            self.ws();
            v.push(self.value(depth + 1)?);
            self.ws();
            match self.peek() {
                Some(b',') => self.i += 1,
                Some(b']') => {
                    self.i += 1;
                    return Ok(Value::Array(v));
                }
                _ => return Err(self.err("expected , or ]")),
            }
        }
    }
    fn object(&mut self, depth: usize) -> Result<Value, JsonError> {
        self.i += 1;
        let mut v: Vec<(String, Value)> = Vec::new();
        self.ws();
        if self.peek() == Some(b'}') {
            self.i += 1;
            return Ok(Value::Object(v));
        }
        loop {
            self.ws();
            if self.peek() != Some(b'"') {
                return Err(self.err("expected a key"));
            }
            let k = self.string()?;
            if v.iter().any(|(x, _)| *x == k) {
                return Err(self.err(&format!("duplicate key {k:?}")));
            }
            self.ws();
            if self.peek() != Some(b':') {
                return Err(self.err("expected :"));
            }
            self.i += 1;
            self.ws();
            let val = self.value(depth + 1)?;
            v.push((k, val));
            self.ws();
            match self.peek() {
                Some(b',') => self.i += 1,
                Some(b'}') => {
                    self.i += 1;
                    return Ok(Value::Object(v));
                }
                _ => return Err(self.err("expected , or }")),
            }
        }
    }
}

impl Value {
    pub fn get(&self, key: &str) -> Option<&Value> {
        match self {
            Value::Object(m) => m.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }
    pub fn as_str(&self) -> Option<&str> {
        if let Value::Str(s) = self {
            Some(s)
        } else {
            None
        }
    }
    pub fn as_i64(&self) -> Option<i64> {
        if let Value::Int(n) = self {
            Some(*n)
        } else {
            None
        }
    }
    pub fn as_bool(&self) -> Option<bool> {
        if let Value::Bool(b) = self {
            Some(*b)
        } else {
            None
        }
    }
    pub fn as_array(&self) -> Option<&Vec<Value>> {
        if let Value::Array(a) = self {
            Some(a)
        } else {
            None
        }
    }
    pub fn as_object(&self) -> Option<&Vec<(String, Value)>> {
        if let Value::Object(o) = self {
            Some(o)
        } else {
            None
        }
    }
    pub fn is_null(&self) -> bool {
        matches!(self, Value::Null)
    }
    pub fn str(s: impl Into<String>) -> Value {
        Value::Str(s.into())
    }
    pub fn obj(items: Vec<(&str, Value)>) -> Value {
        Value::Object(items.into_iter().map(|(k, v)| (k.to_string(), v)).collect())
    }
    pub fn to_string_compact(&self) -> String {
        let mut s = String::new();
        write_value(&mut s, self, None, 0);
        s
    }
    pub fn to_string_pretty(&self) -> String {
        let mut s = String::new();
        write_value(&mut s, self, Some(2), 0);
        s.push('\n');
        s
    }
}

fn write_str(out: &mut String, s: &str) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 || (c as u32) >= 0x7f => {
                let mut buf = [0u16; 2];
                for u in c.encode_utf16(&mut buf) {
                    let _ = write!(out, "\\u{:04x}", u);
                }
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

fn write_value(out: &mut String, v: &Value, indent: Option<usize>, level: usize) {
    let nl = |out: &mut String, l: usize| {
        if let Some(n) = indent {
            out.push('\n');
            for _ in 0..n * l {
                out.push(' ');
            }
        }
    };
    match v {
        Value::Null => out.push_str("null"),
        Value::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
        Value::Int(n) => {
            let _ = write!(out, "{n}");
        }
        Value::Str(s) => write_str(out, s),
        Value::Array(a) => {
            if a.is_empty() {
                out.push_str("[]");
                return;
            }
            out.push('[');
            for (i, x) in a.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                    if indent.is_none() {}
                }
                nl(out, level + 1);
                write_value(out, x, indent, level + 1);
            }
            nl(out, level);
            out.push(']');
        }
        Value::Object(o) => {
            if o.is_empty() {
                out.push_str("{}");
                return;
            }
            out.push('{');
            for (i, (k, x)) in o.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                nl(out, level + 1);
                write_str(out, k);
                out.push(':');
                if indent.is_some() {
                    out.push(' ');
                }
                write_value(out, x, indent, level + 1);
            }
            nl(out, level);
            out.push('}');
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strict() {
        assert!(parse(br#"{"a":1,"a":2}"#).is_err());
        assert!(parse(b"1.5").is_err());
        assert!(parse(b"1e3").is_err());
        assert!(parse(b"01").is_err());
        assert!(parse(b"[1,]").is_err());
        assert!(parse(b"{} x").is_err());
        assert!(parse(b"\"\\ud800\"").is_err());
        assert!(parse(&[b'"', 0xff, b'"']).is_err());
        let deep = "[".repeat(100) + &"]".repeat(100);
        assert!(parse(deep.as_bytes()).is_err());
    }

    #[test]
    fn roundtrip() {
        let src = r#"{"s":"a\"b\u00e9\n","n":-42,"b":[true,false,null],"o":{"x":{}},"e":[]}"#;
        let v = parse(src.as_bytes()).unwrap();
        assert_eq!(v.get("n").unwrap().as_i64(), Some(-42));
        assert_eq!(v.get("s").unwrap().as_str(), Some("a\"b\u{e9}\n"));
        let again = parse(v.to_string_compact().as_bytes()).unwrap();
        assert_eq!(v, again);
        let again = parse(v.to_string_pretty().as_bytes()).unwrap();
        assert_eq!(v, again);
    }

    #[test]
    fn fuzz_never_panics() {
        // Cheap deterministic fuzzing: mutate a valid document byte by byte.
        let base = br#"{"schema":"siliconforest-update/1","packages":[{"name":"a","v":[1,2,{"k":"\u0041"}]}]}"#;
        let mut seed: u64 = 0x5a5a_1234;
        for _ in 0..20000 {
            let mut d = base.to_vec();
            for _ in 0..3 {
                seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
                let at = (seed >> 33) as usize % d.len();
                d[at] = (seed >> 13) as u8;
            }
            let _ = parse(&d);
        }
    }
}
