# SPDX-License-Identifier: MIT
# Copyright (c) 2026 SiliconForest contributors
{ base ? import ./base.nix }:
let
  inherit (base) pkgs sources;
  lib = pkgs.lib;
  sf = ../integrations/siliconforest;
  rust = import ./rust.nix { inherit pkgs; };
  series = builtins.fromJSON (builtins.readFile ./chonkstep/series.json);
  source = pkgs.runCommand "siliconforest-chonkstep-source" {
    nativeBuildInputs = [ pkgs.patch pkgs.gzip pkgs.python3 ];
  } (''
    cp -R ${sources.chonkstep} "$out"
    chmod -R u+w "$out"
    gzip -dc ${./chonkstep/0001-darwin-port.patch.gz} | patch -d "$out" -p1 --batch --fuzz=0
    python3 ${base.renameTools}/sf_rename.py tree "$out"
    ${lib.concatMapStrings (entry: ''
      patch -d "$out" -p${toString entry.strip} --batch --fuzz=0 < ${sf + "/terminal-app/compositor/${entry.path}"}
    '') series}
  '' + lib.optionalString (pkgs.stdenv.buildPlatform.system == "aarch64-linux" && (base.parallelsGuest or false)) ''
    patch -d "$out" -p1 --batch --fuzz=0 < ${./patches/chonkstep-aarch64-linux-virtio-present.patch}
  '');
  terminalSource = pkgs.runCommand "siliconforest-terminal-source" {
    nativeBuildInputs = [ pkgs.patch ];
  } ''
    cp -R ${sf + "/chonkstep-darwin/client-terminal-application"} "$out"
    chmod -R u+w "$out"
    patch -d "$out" -p1 --batch --fuzz=0 < ${sf + "/terminal-app/compositor/terminal-application-daily.patch"}
    patch -d "$out" -p1 --batch --fuzz=0 < ${sf + "/terminal-app/compositor/terminal-click-no-highlight.patch"}
  '';
  linkInputs = import (sf + "/chonkstep-darwin/link-inputs.nix");
  darwinLinker = pkgs.writeShellScript "siliconforest-darwin-linker" ''
    # Cargo hashes RUSTFLAGS into crate identities. Keep the temporary native
    # object path out of those flags and add it only when the linker runs.
    if [ -n "''${DARWIN_SPAWN_OBJECT:-}" ]; then
      set -- "$@" "$DARWIN_SPAWN_OBJECT"
    fi
    exec ${pkgs.python3}/bin/python3 ${sf + "/chonkstep-darwin/darwin-linker-inputs.py"} "$@"
  '';
  build = { name, src, command, binaries, prepare ? "" }:
    let cargoDeps = pkgs.rustPlatform.importCargoLock { lockFile = src + "/Cargo.lock"; };
    in pkgs.stdenvNoCC.mkDerivation {
      pname = "siliconforest-${name}";
      version = "0.1";
      inherit src;
      nativeBuildInputs = [ rust pkgs.python3 pkgs.pkg-config pkgs.stdenv.cc ];
      dontConfigure = true;
      buildPhase = ''
        runHook preBuild
        export CARGO_HOME="$TMPDIR/cargo-home"
        mkdir -p "$CARGO_HOME"
        cp ${cargoDeps}/.cargo/config.toml "$CARGO_HOME/config.toml"
        substituteInPlace "$CARGO_HOME/config.toml" --replace-fail '"cargo-vendor-dir"' '"${cargoDeps}"'
        export DARWIN_LINK_INPUTS=${linkInputs}
        export CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER=${darwinLinker}
        get() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$DARWIN_LINK_INPUTS" "$1"; }
        export CC_aarch64_apple_darwin="$(get toolchain)/bin/arm64-apple-darwin20.4-clang"
        export AR_aarch64_apple_darwin="$(get toolchain)/bin/arm64-apple-darwin20.4-ar"
        export SDKROOT="$(get sdk)" DARWIN_SDK_ROOT="$(get sdk)"
        export MACOSX_DEPLOYMENT_TARGET=26.5
        ${prepare}
        ${command}
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        mkdir -p "$out/usr/bin" "$out/share/licenses/${name}"
        ${lib.concatMapStrings (b: ''
          install -m755 target/aarch64-apple-darwin/release/${b.from} "$out/usr/bin/${b.to}"
        '') binaries}
        cp ${../LICENSE} "$out/share/licenses/${name}/LICENSE.build-recipes"
        ${lib.optionalString (name == "desktop") ''
          cp ${sources.chonkstep}/LICENSE "$out/share/licenses/${name}/LICENSE"
        ''}
        runHook postInstall
      '';
      # These are Darwin executables on a Linux builder.
      dontStrip = true;
      dontPatchELF = true;
    };
  desktop = build {
    name = "desktop";
    src = source;
    prepare = ''
      "$(get toolchain)/bin/arm64-apple-darwin20.4-clang" -std=c11 -Wall -Wextra -Werror -Wpedantic -O1 \
        -isystem "$SDKROOT/usr/include" -I ${sf + "/chonkstep-darwin/darwin-spawn"} \
        -c ${sf + "/chonkstep-darwin/darwin-spawn/darwin_spawn.c"} -o "$TMPDIR/darwin_spawn.o"
      export DARWIN_SPAWN_OBJECT="$TMPDIR/darwin_spawn.o"
      # ld64's debug map otherwise records rustc's random temporary link path.
      export CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS="-L native=$(get xkb) -L native=$(get sfgop) -C panic=unwind -C link-arg=-Wl,-S"
    '';
    command = ''
      cargo rustc -j "$NIX_BUILD_CORES" --offline --locked --release -p wm-darwin \
        --features native-managed-spawn --bin chonkstep-darwin-desktop --target aarch64-apple-darwin -- -C link-arg=-Wl,-dead_strip_dylibs
      cargo build -j "$NIX_BUILD_CORES" --offline --locked --release -p chonk-dock --bin chonk-dock --target aarch64-apple-darwin
    '';
    binaries = [
      { from = "chonkstep-darwin-desktop"; to = "chonkstep-darwin-desktop"; }
      { from = "chonk-dock"; to = "chonkstep-dock"; }
    ];
  };
  terminal = build {
    name = "terminal";
    src = terminalSource;
    command = ''
      cargo build -j "$NIX_BUILD_CORES" --offline --locked --release --target aarch64-apple-darwin
    '';
    binaries = [ { from = "chonk-terminal-darwin"; to = "chonk-terminal-darwin"; } ];
  };
in { inherit desktop terminal source terminalSource rust; }
