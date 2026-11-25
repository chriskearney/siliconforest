// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//! `sf`, the umbrella command: `sf NAME ARGS…` execs `NAME`-specific tools, the way `git foo` finds
//! `git-foo`. `sf sap …` execs `sap …` (design section 2: no behavioural difference). SAP itself never
//! depends on `sf`, because SAP is what repairs it.

use std::os::unix::process::CommandExt;
use std::path::PathBuf;

fn main() {
    let mut args = std::env::args().skip(1);
    let Some(cmd) = args.next() else {
        eprintln!("usage: sf COMMAND [ARGS…]\n  sf sap …   the system updater (same as sap …)");
        std::process::exit(2);
    };
    if cmd.is_empty() || !cmd.bytes().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'-') {
        eprintln!("sf: bad command name");
        std::process::exit(2);
    }
    // Next to this binary first (so an image's own tools are used), then /usr/bin.
    let here = std::env::current_exe().ok().and_then(|p| p.parent().map(|d| d.to_path_buf()));
    let names = if cmd == "sap" { vec!["sap".to_string()] } else { vec![format!("sf-{cmd}")] };
    for n in &names {
        for dir in here.iter().cloned().chain([PathBuf::from("/usr/bin"), PathBuf::from("/usr/libexec/sf")]) {
            let p = dir.join(n);
            if p.is_file() {
                let e = std::process::Command::new(&p).args(args).exec();
                eprintln!("sf: {}: {e}", p.display());
                std::process::exit(1);
            }
        }
    }
    eprintln!("sf: unknown command {cmd}");
    std::process::exit(2);
}
