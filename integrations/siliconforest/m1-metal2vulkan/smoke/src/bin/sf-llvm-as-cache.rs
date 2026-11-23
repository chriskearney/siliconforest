// SPDX-License-Identifier: MIT
// sf-llvm-as-cache: stands in for `llvm-as - -o -` on a machine with no LLVM (METAL2VULKAN_LLVM_AS).
// Reads LLVM text on stdin and writes the bitcode the build host's llvm-as made of exactly that text,
// found by SHA-256 in $SF_M2V_ASMCACHE (default: the `asmcache` directory beside this executable).
// A text that was never recorded is reported as a rejection (exit 1), never guessed.
use sha2::{Digest, Sha256};
use std::io::{Read, Write};
fn main() {
    let mut text = Vec::new();
    std::io::stdin().read_to_end(&mut text).expect("stdin");
    let hex: String = Sha256::digest(&text).iter().map(|b| format!("{b:02x}")).collect();
    let dir = std::env::var_os("SF_M2V_ASMCACHE").map(std::path::PathBuf::from).unwrap_or_else(|| {
        std::env::current_exe().expect("exe").parent().expect("dir").join("asmcache")
    });
    match std::fs::read(dir.join(format!("{hex}.bc"))) {
        Ok(bc) => std::io::stdout().write_all(&bc).expect("stdout"),
        Err(_) => {
            eprintln!("sf-llvm-as-cache: text {hex} was not assembled on the build host");
            std::process::exit(1)
        }
    }
}
