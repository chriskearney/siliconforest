# SPDX-License-Identifier: MIT
# FFmpeg 8.1.2 (the source of the pinned nixpkgs) for the SiliconForest arm64 userland:
# static libraries plus the `ffmpeg` and `ffprobe` programs, arm64 Mach-O against the lab's
# default libSystem only. No Apple framework (VideoToolbox, AudioToolbox, AVFoundation,
# CoreMedia, Security, AppKit ...), nothing autodetected, LGPL configuration (no --enable-gpl,
# no --enable-nonfree), software decoders only.
#
#   nix-build --extra-experimental-features nix-command --extra-experimental-features flakes \
#     --no-out-link --cores 4 --max-jobs 1 build-ffmpeg.nix
#
# Output:  usr/bin/{ffmpeg,ffprobe}   usr/lib/libav*.a libsw*.a   usr/lib/pkgconfig   usr/include
#
# Hooks for the hardware decoder (hwaccel `sfavd`):
#   extraPatches         patches applied to the FFmpeg source (-p1)
#   extraConfigureFlags  further ./configure arguments (for example "--enable-sfavd")
#   extraBuildInputs     derivations whose include/ and lib/ are put on the search paths
#   extraCFlags, extraLdFlags   further compiler and linker arguments
#   extraLibs            libraries appended to every link (for example "-lsfavd"), also
#                        recorded in the .pc files' Libs.private
# Example:
#   import ./build-ffmpeg.nix { extraPatches = [ ./sfavd.patch ]; extraConfigureFlags = [ "--enable-sfavd" ];
#                               extraBuildInputs = [ libsfavd ]; extraLibs = [ "-lsfavd" ]; }
{ extraPatches ? [], extraConfigureFlags ? [], extraBuildInputs ? [], extraCFlags ? [], extraLdFlags ? []
, extraLibs ? [], nameSuffix ? "" }:
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
  ] ++ map (d: "-I${lib.getDev d}/include") extraBuildInputs ++ extraCFlags;
  ldflags = [
    "-isysroot" sdk "-mmacosx-version-min=26.5"
    "-fuse-ld=${p.native-ld}/bin/ld" "-nostdlib" "-L${libSystem}/usr/lib"
    "-Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libSystem}/usr/lib/system/libdyld.dylib"
    "-Wl,-platform_version,macos,26.5,26.5" "-Wl,-fixup_chains"
  ] ++ map (d: "-L${lib.getLib d}/lib") extraBuildInputs ++ extraLdFlags;
  list = name: xs: map (x: "--enable-${name}=${x}") xs;
  components =
    list "demuxer" [ "mov" "matroska" "h264" "hevc" "ivf" "wav" "mp3" "flac" "ogg" "aac" "ac3" "mpegts" "rawvideo"
                     "pcm_s16le" "yuv4mpegpipe" ]
    ++ list "decoder" [ "h264" "hevc" "vp9" "vp8" "aac" "aac_latm" "opus" "vorbis" "mp3" "mp3float" "flac" "ac3" "eac3"
                        "pcm_s16le" "pcm_s16be" "pcm_s24le" "pcm_s32le" "pcm_f32le" "pcm_u8" "pcm_alaw" "pcm_mulaw"
                        "rawvideo" "wrapped_avframe" ]
    ++ list "parser" [ "h264" "hevc" "vp9" "vp8" "av1" "aac" "aac_latm" "opus" "vorbis" "mpegaudio" "flac" "ac3" ]
    ++ list "bsf" [ "h264_mp4toannexb" "hevc_mp4toannexb" "vp9_superframe_split" "vp9_superframe" "aac_adtstoasc"
                    "extract_extradata" "null" "trace_headers" "h264_metadata" "hevc_metadata" "vp9_metadata" ]
    ++ list "protocol" [ "file" "pipe" ]
    ++ list "encoder" [ "rawvideo" "wrapped_avframe" "pcm_s16le" "pcm_s24le" "pcm_f32le" ]
    ++ list "muxer" [ "rawvideo" "framemd5" "md5" "hash" "framehash" "framecrc" "crc" "wav" "null" "pcm_s16le"
                      "yuv4mpegpipe" "h264" "hevc" "ivf" ]
    ++ list "filter" [ "scale" "format" "aformat" "aresample" "null" "anull" "trim" "atrim" "hflip" "vflip" "transpose"
                       "setpts" "asetpts" "fps" "copy" "crop" "hwdownload" "hwupload" "volume" ];
in pkgs.stdenv.mkDerivation {
  pname = "darwin-lab-ffmpeg-arm64-darwin${nameSuffix}";
  version = pkgs.ffmpeg.version;
  src = pkgs.ffmpeg.src;
  patches = extraPatches;
  nativeBuildInputs = [ pkgs.perl pkgs.pkg-config ];
  # configure links CoreFoundation, CoreMedia, CoreVideo and CoreAudio on every Darwin target
  # when the SDK has them, and libm.dylib (a separate install name in the SDK; libSystem here
  # exports the math functions itself). Nothing in this configuration uses the frameworks.
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
    ./configure \
      --prefix=$out/usr \
      --enable-cross-compile --target-os=darwin --arch=aarch64 \
      --cc=${tc}/bin/${triple}-clang --as=${tc}/bin/${triple}-clang --ld=${tc}/bin/${triple}-clang \
      --cxx=${tc}/bin/${triple}-clang++ --objcc=${tc}/bin/${triple}-clang \
      --ar=${tc}/bin/${triple}-ar --ranlib=${tc}/bin/${triple}-ranlib --nm=${tc}/bin/${triple}-nm \
      --strip=${tc}/bin/${triple}-strip --host-cc=$CC --pkg-config=false \
      --extra-cflags=${lib.escapeShellArg (lib.concatStringsSep " " cflags)} \
      --extra-ldflags=${lib.escapeShellArg (lib.concatStringsSep " " ldflags)} \
      --extra-libs=${lib.escapeShellArg (lib.concatStringsSep " " (extraLibs ++ [ "-lSystem" ]))} \
      --disable-autodetect --disable-everything --disable-doc --disable-debug --disable-stripping \
      --disable-network --disable-ffplay --enable-ffmpeg --enable-ffprobe \
      --disable-avdevice --enable-avfilter --enable-swscale --enable-swresample \
      --enable-static --disable-shared --enable-pic --enable-pthreads \
      --disable-videotoolbox --disable-audiotoolbox --disable-securetransport --disable-appkit \
      --disable-avfoundation --disable-coreimage --disable-metal \
      ${lib.concatStringsSep " " components} \
      ${lib.escapeShellArgs extraConfigureFlags} \
      || { tail -n 60 ffbuild/config.log; exit 1; }
    grep -E '^#define (ARCH_AARCH64|HAVE_NEON|HAVE_ARMV8|HAVE_DOTPROD|HAVE_I8MM|HAVE_AS_FUNC|HAVE_AS_ARCH_DIRECTIVE|HAVE_PTHREADS|HAVE_SYSCTL|HAVE_CLOCK_GETTIME|HAVE_MACH_ABSOLUTE_TIME|CONFIG_GPL|CONFIG_NONFREE|CONFIG_VIDEOTOOLBOX|CONFIG_AUDIOTOOLBOX) ' config.h | tee config-summary.txt
    runHook postConfigure
  '';
  installPhase = ''
    runHook preInstall
    make install
    install -Dm644 config-summary.txt $out/share/config-summary.txt
    install -Dm644 ffbuild/config.log $out/share/config.log
    install -Dm644 config.h $out/share/config.h
    # every reference must be to libSystem
    { for f in $out/usr/bin/*; do ${tc}/bin/${triple}-otool -L "$f"; done; } > $out/share/LINKAGE.txt
    if grep -v '^/nix/store.*:$' $out/share/LINKAGE.txt | grep -v '/usr/lib/libSystem.B.dylib'; then
      echo "unexpected library reference" >&2; exit 1
    fi
    runHook postInstall
  '';
  dontFixup = true;
  dontStrip = true;
}
