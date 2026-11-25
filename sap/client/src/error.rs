// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//! Errors and the exit codes of docs/sap/README.md (design section 2).

use std::fmt;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Code {
    /// 1: usage or an unexpected local problem (I/O, permissions).
    Failure = 1,
    /// 20: verification failure; the system is unchanged.
    Verify = 20,
    /// 21: manifest expired or replayed.
    Stale = 21,
    /// 30: conflict, dependency or space failure; nothing downloaded or written.
    Conflict = 30,
    /// 40: a transaction is interrupted; run `sap recover`.
    Interrupted = 40,
}

#[derive(Debug)]
pub struct Error {
    pub code: Code,
    pub msg: String,
}

impl Error {
    pub fn new(code: Code, msg: impl Into<String>) -> Self {
        Error { code, msg: msg.into() }
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.msg)
    }
}

impl From<std::io::Error> for Error {
    fn from(e: std::io::Error) -> Self {
        Error::new(Code::Failure, format!("I/O error: {e}"))
    }
}

pub type Result<T> = std::result::Result<T, Error>;

#[macro_export]
macro_rules! bail {
    ($code:ident, $($arg:tt)*) => {
        return Err($crate::error::Error::new($crate::error::Code::$code, format!($($arg)*)))
    };
}

#[macro_export]
macro_rules! err {
    ($code:ident, $($arg:tt)*) => {
        $crate::error::Error::new($crate::error::Code::$code, format!($($arg)*))
    };
}

pub trait Context<T> {
    fn ctx(self, what: impl FnOnce() -> String) -> Result<T>;
}

impl<T> Context<T> for std::io::Result<T> {
    fn ctx(self, what: impl FnOnce() -> String) -> Result<T> {
        self.map_err(|e| Error::new(Code::Failure, format!("{}: {e}", what())))
    }
}
