# SPDX-License-Identifier: MIT
# (this recipe; the programs it builds are GPL-2.0-or-later, as ../desktop/recording/build-ffmpeg-x264.nix)
# SiliconForest's ffmpeg and ffprobe with the hardware: the `sfavd` hwaccel for H.264 decode
# (../m1-avd/ffmpeg/0001-sfavd-hwaccel.patch) and the `h264_sfave` encoder
# (./ffmpeg/0001-h264-sfave-encoder.patch), on the recorder's build. libx264 stays the default H.264
# encoder and FFmpeg's software h264 decoder stays in: `-c:v h264_sfave` asks for the AVE, and
# `-hwaccel sfavd` falls back to software for a stream the AVD does not take.
#   nix-build --extra-experimental-features nix-command --extra-experimental-features flakes \
#     --no-out-link --cores 8 --max-jobs 1 build-ffmpeg-hw.nix
let
  base = import ../desktop/recording/build-ffmpeg-x264.nix;
  sfavd = import ../m1-avd/build-user.nix;
  flags = builtins.concatStringsSep " " [
    "--extra-cflags=-I${sfavd}/include"
    "--extra-cflags=-I${sfavd}/include/sfavd/compat"
    "--extra-cflags=-I${./include}"
    "--extra-ldflags=-L${sfavd}/lib"
    "--enable-sfavd"
  ];
  # after the recipe's --disable-everything, which would switch them off again
  components = "--enable-hwaccel=h264_sfavd --enable-encoder=h264_sfave";
in base.overrideAttrs (old: {
  pname = "siliconforest-ffmpeg-hw-arm64-darwin";
  patches = (old.patches or [ ]) ++ [ ../m1-avd/ffmpeg/0001-sfavd-hwaccel.patch ./ffmpeg/0001-h264-sfave-encoder.patch ];
  postConfigure = (old.postConfigure or "") + ''
    grep -q '^#define CONFIG_H264_SFAVE_ENCODER 1' config_components.h
    grep -q '^#define CONFIG_H264_SFAVD_HWACCEL 1' config_components.h
  '';
  configurePhase = builtins.replaceStrings
    [ "--extra-libs=-lSystem" "--enable-gpl --enable-libx264" "--disable-metal" ]
    [ "--extra-libs='-lsfavd -lSystem'" "--enable-gpl --enable-libx264 ${flags}" "--disable-metal ${components}" ]
    old.configurePhase;
})
