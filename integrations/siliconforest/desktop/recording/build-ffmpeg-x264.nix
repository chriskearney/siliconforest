# SPDX-License-Identifier: MIT
# (this recipe; the programs it builds are GPL-2.0-or-later, see below)
#
# The screen recorder's encoder for SiliconForest (DESK11): `ffmpeg` and `ffprobe` for the arm64
# userland, with x264 (H.264) linked in statically, against the lab's default libSystem only. The
# compositor runs `ffmpeg` as a separate program and writes raw frames to its standard input; it
# is never linked into our code. x264 is GPL-2.0-or-later, so FFmpeg is configured with
# --enable-gpl and the two programs are GPL-2.0-or-later: the licence texts and this recipe go
# with them (share/doc/ffmpeg-x264/).
#
# Sources: the pinned nixpkgs' FFmpeg (8.1.2) and x264 (0-unstable-2025-01-03) source paths,
# unchanged. Only what recording and checking a recording need is enabled: raw NV12 frames in a
# Matroska stream (which carries each frame's time) from a pipe in, libx264 out into QuickTime/MP4,
# swscale; decoders for H.264, Photo-JPEG and raw video and the framemd5/rawvideo/image2 (PPM)
# outputs to check a file on the machine itself.
#
# Built 2026-11-17 (DESK11): output /nix/store/bszwvf0yh6nsyhzfh38dm73idi7psj0i-siliconforest-ffmpeg-
# x264-arm64-darwin-8.1.2, ffmpeg sha256 014a854f..., ffprobe ce441b9e... (both link only
# /usr/lib/libSystem.B.dylib). Installed on the M1 as new files /usr/local/bin/{ffmpeg,ffprobe} and
# /usr/local/share/doc/ffmpeg-x264/ (revert: delete those three paths); the binaries are not in git.
#
#   nix-build --extra-experimental-features 'nix-command flakes' --no-out-link --cores 8 \
#     --max-jobs 1 build-ffmpeg-x264.nix
#
# Output: usr/local/bin/{ffmpeg,ffprobe}, usr/local/share/doc/ffmpeg-x264/{COPYING.GPLv2,
# x264-COPYING,README,config-summary.txt,LINKAGE.txt}
let
  r = import ../../rebase/pd.nix;
  inherit (r) pd pkgs;
  lib = pkgs.lib;
  p = pd.packages.${pd.buildSystem};
  libSystem = import ../../libsystem-default/build-libsystem.nix;
  tc = p.arm64-cross-toolchain;
  triple = "arm64-apple-darwin20.4";
  sdk = "${p.apple-sdk}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
  cflags = [
    "-isysroot" sdk "-mmacosx-version-min=26.5" "-U_FORTIFY_SOURCE" "-D_FORTIFY_SOURCE=0" "-fno-stack-protector"
    "-I${libSystem}/usr/include"
  ];
  ldflags = [
    "-isysroot" sdk "-mmacosx-version-min=26.5"
    "-fuse-ld=${p.native-ld}/bin/ld" "-nostdlib" "-L${libSystem}/usr/lib"
    "-Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libSystem}/usr/lib/system/libdyld.dylib"
    "-Wl,-platform_version,macos,26.5,26.5" "-Wl,-fixup_chains"
  ];
  x264 = pkgs.stdenv.mkDerivation {
    pname = "siliconforest-x264-arm64-darwin-static";
    version = pkgs.x264.version;
    src = pkgs.x264.src;
    nativeBuildInputs = [ pkgs.nasm ];
    postPatch = "patchShebangs .";
    dontAddPrefix = true;
    enableParallelBuilding = true;
    # x264 runs `$(STRIP) -x` on every assembled object (local symbols out, for profilers); the
    # cross strip leaves relocations that name removed symbols ("symbol index out of range" at
    # the link), so nothing is stripped.
    makeFlags = [ "STRIP=true" ];
    configurePhase = ''
      runHook preConfigure
      CC=${tc}/bin/${triple}-clang AR=${tc}/bin/${triple}-ar RANLIB=${tc}/bin/${triple}-ranlib \
      STRIP=true AS=${tc}/bin/${triple}-clang \
      ./configure --prefix=$out --host=aarch64-apple-darwin --enable-static --enable-pic \
        --disable-cli --disable-opencl --disable-avs --disable-swscale --disable-lavf --disable-ffms \
        --disable-gpac --disable-lsmash --bit-depth=8 --chroma-format=all \
        --extra-cflags=${lib.escapeShellArg (lib.concatStringsSep " " cflags)} \
        --extra-asflags=${lib.escapeShellArg (lib.concatStringsSep " " [ "-isysroot" sdk "-mmacosx-version-min=26.5" ])} \
        --extra-ldflags=${lib.escapeShellArg (lib.concatStringsSep " " (ldflags ++ [ "-lSystem" ]))} \
        || { tail -n 60 config.log; exit 1; }
      grep -E '^#define (HAVE_AARCH64|HAVE_NEON|HAVE_THREAD|HAVE_BEOSTHREAD|HAVE_POSIXTHREAD|HAVE_GPL|HAVE_BITDEPTH8|HAVE_INTERLACED|ARCH_AARCH64)' config.h | tee x264-config-summary.txt
      grep -q '^#define HAVE_NEON 1' config.h
      runHook postConfigure
    '';
    installPhase = ''
      runHook preInstall
      make install-lib-static
      # libSystem has the thread and math functions; /usr/lib/libpthread and libm are separate names
      sed -i -e "s|^Libs:.*|Libs: -L$out/lib -lx264|" -e 's/^Libs.private:.*/Libs.private:/' $out/lib/pkgconfig/x264.pc
      ! grep -n 'lpthread\|lm\b' $out/lib/pkgconfig/x264.pc
      install -Dm644 COPYING $out/share/doc/COPYING
      install -Dm644 x264-config-summary.txt $out/share/doc/x264-config-summary.txt
      runHook postInstall
    '';
    dontFixup = true;
    dontStrip = true;
  };
  list = name: xs: map (x: "--enable-${name}=${x}") xs;
  components =
    list "demuxer" [ "matroska" "rawvideo" "mov" "h264" "yuv4mpegpipe" "image2" ]
    ++ list "decoder" [ "h264" "mjpeg" "rawvideo" "ppm" ]
    ++ list "encoder" [ "libx264" "rawvideo" "ppm" "wrapped_avframe" ]
    ++ list "parser" [ "h264" "mjpeg" ]
    ++ list "bsf" [ "h264_mp4toannexb" "extract_extradata" "null" ]
    ++ list "protocol" [ "file" "pipe" ]
    ++ list "muxer" [ "mov" "mp4" "h264" "rawvideo" "framemd5" "md5" "null" "image2" "yuv4mpegpipe" ]
    ++ list "filter" [ "scale" "format" "fps" "setpts" "null" "copy" "crop" "vflip" "select" "showinfo" ];
in pkgs.stdenv.mkDerivation {
  pname = "siliconforest-ffmpeg-x264-arm64-darwin";
  version = pkgs.ffmpeg.version;
  src = pkgs.ffmpeg.src;
  nativeBuildInputs = [ pkgs.perl pkgs.pkg-config ];
  # as ../../m1-avd/player/build-ffmpeg.nix: configure would link CoreFoundation, CoreMedia,
  # CoreVideo and CoreAudio on every Darwin target and libm as its own library; nothing here
  # uses them (libSystem exports the math functions itself).
  postPatch = ''
    patchShebangs .
    sed -i -e '/^check_apple_framework \(CoreFoundation\|CoreMedia\|CoreVideo\|CoreAudio\)$/d' \
           -e 's/^check_lib libm math.h sin -lm$/check_lib libm math.h sin/' configure
    ! grep -n '^check_apple_framework Core\|^check_lib libm math.h sin -lm' configure
  '';
  dontAddPrefix = true;
  enableParallelBuilding = true;
  configurePhase = ''
    runHook preConfigure
    export PKG_CONFIG_PATH=${x264}/lib/pkgconfig PKG_CONFIG_LIBDIR=${x264}/lib/pkgconfig
    ./configure \
      --prefix=$out/usr/local \
      --enable-cross-compile --target-os=darwin --arch=aarch64 \
      --cc=${tc}/bin/${triple}-clang --as=${tc}/bin/${triple}-clang --ld=${tc}/bin/${triple}-clang \
      --cxx=${tc}/bin/${triple}-clang++ --objcc=${tc}/bin/${triple}-clang \
      --ar=${tc}/bin/${triple}-ar --ranlib=${tc}/bin/${triple}-ranlib --nm=${tc}/bin/${triple}-nm \
      --strip=${tc}/bin/${triple}-strip --host-cc=$CC --pkg-config=pkg-config --pkg-config-flags=--static \
      --extra-cflags=${lib.escapeShellArg (lib.concatStringsSep " " cflags)} \
      --extra-ldflags=${lib.escapeShellArg (lib.concatStringsSep " " ldflags)} \
      --extra-libs=-lSystem \
      --enable-gpl --enable-libx264 \
      --disable-autodetect --disable-everything --disable-doc --disable-debug --disable-stripping \
      --disable-network --disable-ffplay --enable-ffmpeg --enable-ffprobe \
      --disable-avdevice --enable-avfilter --enable-swscale --disable-swresample \
      --enable-static --disable-shared --enable-pic --enable-pthreads \
      --disable-videotoolbox --disable-audiotoolbox --disable-securetransport --disable-appkit \
      --disable-avfoundation --disable-coreimage --disable-metal \
      ${lib.concatStringsSep " " components} \
      || { tail -n 60 ffbuild/config.log; exit 1; }
    grep -E '^#define (ARCH_AARCH64|HAVE_NEON|HAVE_PTHREADS|HAVE_SYSCTL|CONFIG_GPL|CONFIG_NONFREE|CONFIG_LIBX264|CONFIG_LIBX264_ENCODER|CONFIG_VIDEOTOOLBOX) ' config.h | tee config-summary.txt
    grep -q '^#define CONFIG_LIBX264_ENCODER 1' config_components.h
    grep -q '^#define CONFIG_MATROSKA_DEMUXER 1' config_components.h
    runHook postConfigure
  '';
  installPhase = ''
    runHook preInstall
    d=$out/usr/local/share/doc/ffmpeg-x264
    install -Dm755 ffmpeg $out/usr/local/bin/ffmpeg
    install -Dm755 ffprobe $out/usr/local/bin/ffprobe
    install -Dm644 COPYING.GPLv2 $d/COPYING.GPLv2
    install -Dm644 ${x264}/share/doc/COPYING $d/x264-COPYING
    install -Dm644 config-summary.txt $d/config-summary.txt
    install -Dm644 ${x264}/share/doc/x264-config-summary.txt $d/x264-config-summary.txt
    cat > $d/README <<EOF
    ffmpeg and ffprobe for SiliconForest's screen recorder (Command-Shift-5, chonkstep-darwin-desktop).
    FFmpeg ${pkgs.ffmpeg.version} (source ${pkgs.ffmpeg.src}) configured with --enable-gpl --enable-libx264,
    x264 ${pkgs.x264.version} (source ${pkgs.x264.src}) linked statically: both GPL-2.0-or-later
    (COPYING.GPLv2, x264-COPYING). The compositor starts ffmpeg as a separate program and writes raw
    frames to it through a pipe; ffmpeg is not linked into any other program.
    Built from darwin-lab integrations/siliconforest/desktop/recording/build-ffmpeg-x264.nix (the recipe,
    with the exact configure line in ffmpeg -buildconf). Source code: the FFmpeg and x264 releases
    named above, unchanged (https://ffmpeg.org, https://code.videolan.org/videolan/x264).
    EOF
    sed -i 's/^    //' $d/README
    { for f in $out/usr/local/bin/*; do ${tc}/bin/${triple}-otool -L "$f"; done; } > $d/LINKAGE.txt
    if grep -v '^/nix/store.*:$' $d/LINKAGE.txt | grep -v '/usr/lib/libSystem.B.dylib'; then
      echo "unexpected library reference" >&2; exit 1
    fi
    runHook postInstall
  '';
  dontFixup = true;
  dontStrip = true;
}
