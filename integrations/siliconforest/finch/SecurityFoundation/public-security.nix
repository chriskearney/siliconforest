# SPDX-License-Identifier: MIT
# Published Apple OSS source, not an SDK. AuthorizationPlugin is public source.
let e = import ../environment.nix;
in (import ../../../../release/fetch.nix { pkgs = e.pkgs; }) "apple-security-oss"
