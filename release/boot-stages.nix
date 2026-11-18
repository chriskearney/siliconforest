# SPDX-License-Identifier: MIT
# Copyright (c) 2026 SiliconForest contributors
# Generic builds admit RAM roots only. A disk installation supplies its own
# root UUID explicitly; the existing exact-root guard remains in force.
{ base ? import ./base.nix, rootUUID ? "" }:
assert rootUUID == "" || builtins.match "[0-9a-fA-F-]{36}" rootUUID != null;
let
  inherit (base) pkgs sources;
  lib = pkgs.lib;
  boot = ../integrations/siliconforest/m1-native-boot;
  rust = import ./rust.nix { inherit pkgs; };
  lock = builtins.fromJSON (builtins.readFile ../sources.lock);
  cargoDeps = pkgs.rustPlatform.importCargoLock {
    lockFile = sources.m1n1.outPath + "/rust/Cargo.lock";
    outputHashes."fatfs-0.4.0" = lock.sources.fatfs.narHash;
  };
  patches = dir: map (name: dir + "/${name}")
    (lib.filter (lib.hasSuffix ".patch") (builtins.attrNames (builtins.readDir dir)));
  rootHeader = pkgs.writeText "pdsf_root.h" ''
    #define PDSF_ROOT_UUID "${rootUUID}"
  '';
  makeStage = stage: pkgs.stdenv.mkDerivation {
    pname = "siliconforest-boot-stage${toString stage}";
    version = builtins.substring 0 12 lock.sources.m1n1.rev;
    src = sources.m1n1;
    patches = lib.optionals (stage == 2) (patches (boot + "/b1/patches"))
      ++ patches (boot + "/install/patches")
      ++ lib.optionals (stage == 2) (patches (boot + "/install/patches/stage2"));
    nativeBuildInputs = [
      rust pkgs.llvmPackages_21.clang-unwrapped pkgs.llvmPackages_21.lld
      pkgs.llvmPackages_21.llvm pkgs.librsvg pkgs.imagemagick pkgs.python3
    ];
    dontConfigure = true;
    enableParallelBuilding = true;
    postPatch = lib.optionalString (stage == 2) ''
      cp ${boot + "/b1/src"}/{pdsf.c,pdsf.h,pdsf_boot.c,pdsf_el2.S} src/
      cp ${boot + "/install/src/pdsf_file.c"} src/pdsf_file.c
      cp ${rootHeader} src/pdsf_root.h
    '';
    buildPhase = ''
      runHook preBuild
      export CARGO_HOME="$TMPDIR/cargo-home"
      mkdir -p "$CARGO_HOME" build
      cp ${cargoDeps}/.cargo/config.toml "$CARGO_HOME/config.toml"
      substituteInPlace "$CARGO_HOME/config.toml" --replace-fail '"cargo-vendor-dir"' '"${cargoDeps}"'
      for size in 128 256; do
        rsvg-convert -w "$size" -h "$size" ${../integrations/siliconforest/branding/siliconforest-boot.svg} -o "boot-$size.png"
        magick "boot-$size.png" -background black -flatten -depth 8 "rgba:data/siliconforest_$size.bin"
        test "$(stat -c %s data/siliconforest_$size.bin)" -eq "$((size * size * 4))"
      done
      ${lib.optionalString (stage == 2) ''
        clang --target=aarch64-none-elf -march=armv8.5-a -c ${boot + "/stub/el2_drop.S"} -o build/pdsf_el2_stub.o
        llvm-objcopy -O binary build/pdsf_el2_stub.o build/pdsf_el2.bin
        want=$(sed -n "s/^STUB_SHA256 = '\(.*\)'/\1/p" ${boot + "/native_stub.py"})
        test -n "$want"
        echo "$want  build/pdsf_el2.bin" | sha256sum -c -
      ''}
      M1N1_VERSION_TAG=${lock.sources.m1n1.rev}-siliconforest-stage${toString stage}-public \
        make -j "$NIX_BUILD_CORES" USE_CLANG=1 RELEASE=1 CHAINLOADING=1 SF_INSTALLED=1 \
        ${lib.optionalString (stage == 2) "SF_KERNEL_FILE=1"} \
        CARGO_FLAGS="--locked --offline --features chainload" BUILTIN_LOGO=siliconforest build/m1n1.bin
      grep -a -q SF_STOPPED build/m1n1.bin
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/licenses/m1n1"
      cp build/m1n1.bin "$out/sf-stage${toString stage}.bin"
      cp LICENSE "$out/share/licenses/m1n1/LICENSE"
      ${lib.optionalString (stage == 2) ''
        cp build/m1n1.bin "$out/boot.bin"
        ${lib.optionalString (rootUUID != "") ''
          python3 -c 'import pathlib,sys; data=pathlib.Path(sys.argv[1]).read_bytes(); assert data.count(sys.argv[2].encode()) == 1, "root UUID must occur exactly once"' "$out/boot.bin" ${lib.escapeShellArg rootUUID}
        ''}
        first=$(stat -c %s ${stage1}/sf-stage1.bin)
        second=$(stat -c %s "$out/boot.bin")
        span=$(((second + 512 + 4 + 16383) / 16384 * 16384))
        test "$((span + 32768))" -le "$first"
        printf 'stage1=%s stage2=%s span=%s spare=%s\n' "$first" "$second" "$span" "$((first - span))" > "$out/fit.txt"
      ''}
      runHook postInstall
    '';
    dontStrip = true;
    dontPatchELF = true;
  };
  stage1 = makeStage 1;
in {
  inherit stage1;
  stage2 = makeStage 2;
}
