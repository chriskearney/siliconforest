// SPDX-License-Identifier: MIT
// Generated-by: LLM
// A self-contained checksum utility for Recovery, which need not ship OpenSSL,
// Perl, Python, or shasum. Uses only Go's standard library; no cgo or third-party
// dependencies. It never writes an input file or invokes a system command.
package main

import (
	"crypto/sha256"
	"fmt"
	"io"
	"os"
	"strings"
	"syscall"
)

func selfTest() error {
	for _, vector := range []struct {
		input  string
		digest string
	}{
		{"", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},
		{"abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"},
		{strings.Repeat("a", 1000000), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"},
	} {
		if fmt.Sprintf("%x", sha256.Sum256([]byte(vector.input))) != vector.digest {
			return fmt.Errorf("SHA-256 known-answer test failed")
		}
	}
	return nil
}

func run(args []string) error {
	if len(args) == 1 && args[0] == "--self-test" {
		if err := selfTest(); err != nil {
			return err
		}
		fmt.Println("SHA-256 self-test PASS")
		return nil
	}
	if len(args) != 1 {
		return fmt.Errorf("usage: sf-sha256 FILE | --self-test")
	}
	item, err := os.Lstat(args[0])
	if err != nil {
		return err
	}
	if !item.Mode().IsRegular() {
		return fmt.Errorf("input is not a regular non-symlink file")
	}
	fd, err := syscall.Open(args[0], syscall.O_RDONLY|syscall.O_CLOEXEC|syscall.O_NOFOLLOW|syscall.O_NONBLOCK, 0)
	if err != nil {
		return err
	}
	f := os.NewFile(uintptr(fd), args[0])
	defer f.Close()
	before, err := f.Stat()
	if err != nil {
		return err
	}
	if !before.Mode().IsRegular() || !os.SameFile(item, before) {
		return fmt.Errorf("input is not a regular file")
	}
	h := sha256.New()
	n, err := io.Copy(h, f)
	if err != nil {
		return err
	}
	after, err := f.Stat()
	if err != nil {
		return err
	}
	if n != before.Size() || n != after.Size() || !before.ModTime().Equal(after.ModTime()) {
		return fmt.Errorf("input changed during hashing")
	}
	fmt.Printf("%x\n", h.Sum(nil))
	return nil
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "sf-sha256:", err)
		os.Exit(1)
	}
}
