#!/bin/bash
# SPDX-License-Identifier: MIT
# Runs on the M1 (as root, like the TextEdit scene). Starts the staged
# ChonkCraft on the SiliconForest desk.
#
#   run-m1.sh launcher|game|probe [seconds] [extra java options...]
# Logs and captures go to /private/var/db/sfchonkcraft/logs.
#
# Java2D runs on its OpenGL pipeline (CGL on Mesa; there is no Metal device).
# SFLayerRendering=0 + SF_CHONK_CPU_LAYER=1: the fill renders Java's CGLLayer
# itself and AppKit draws the picture into the window (see fills.py).
set -u
B=/private/var/db/sfchonkcraft
MODE=${1:-game}; SECS=${2:-60}; shift 2 || true
A=$B/ChonkCraft.app/Contents
J=$A/runtime/Contents/Home/bin/java
PACK=$B/data/packs/warcraft-ii-battle-net-edition-usa.chonkpack
RUNTIME=/private/var/run/gpu-desktop
mkdir -p $B/home $B/tmp $B/logs
[ -f $B/pids ] && kill $(cat $B/pids) 2>/dev/null; sleep 0.5
COMMON=(-XX:ErrorFile=$B/logs/hs_err_%p.log -Xms256m -Xmx2g -Dchonkcraft.version=0.1.1-beta22
  --add-opens=java.desktop/com.apple.eawt=ALL-UNNAMED
  -Dchonkcraft.packaged.native.dir=$A/app -Djna.boot.library.path=$A/app -Djna.nounpack=true
  -Dchonkcraft.pack=$PACK -Dswing.defaultlaf=javax.swing.plaf.metal.MetalLookAndFeel)
if [ "$MODE" = probe ]; then
  ARGS=(-cp $B/probe "${COMMON[@]}" -Dsun.java2d.opengl=true -Dsun.java2d.metal=false "$@" AwtProbe $B/logs/probe-java.png)
elif [ "$MODE" = launcher ]; then
  ARGS=(-cp $A/app/chonkcraft-launcher.jar:$A/app/bootstrap-game.jar "${COMMON[@]}" "$@" net.chonkbase.chonkcraft.launcher.Main)
else
  ARGS=(-cp $A/app/bootstrap-game.jar "${COMMON[@]}" "$@" net.chonkbase.chonkcraft.desktop.Main)
fi
env -i PATH=/usr/bin:/bin HOME=$B/home CFFIXED_USER_HOME=$B/home TMPDIR=$B/tmp/ USER=root LOGNAME=root \
  XDG_RUNTIME_DIR=$RUNTIME WAYLAND_DISPLAY=wayland-0 SF_METAL_ENABLE_REAL_DEVICE=0 SF_LOG_EXC=1 LANG=en_US.UTF-8 \
  SEVEN_JAVA2D_PIPELINE=opengl SFLayerRendering=0 SF_CHONK_CPU_LAYER=1 \
  CHONKCRAFT_ASSET_PACK=$PACK DYLD_LIBRARY_PATH=$B/fwlib DYLD_FRAMEWORK_PATH=$B/fw${SF_EXTRA_FW:+:$SF_EXTRA_FW} ${SF_EXTRA_ENV:-} \
  $J "${ARGS[@]}" </dev/null >$B/logs/$MODE.out 2>$B/logs/$MODE.err &
PID=$!; echo $PID > $B/pids; echo PID $PID
for i in $(seq 1 $SECS); do sleep 1; kill -0 $PID 2>/dev/null || break; done
if kill -0 $PID 2>/dev/null; then echo ALIVE after ${SECS}s; else wait $PID; echo EXITED rc=$?; fi
XDG_RUNTIME_DIR=$RUNTIME WAYLAND_DISPLAY=wayland-0 /usr/bin/chonkstep-darwin-desktop --screencapture $B/logs/desk-$MODE.png >/dev/null 2>&1; echo SHOT $?
echo ---out; tail -c 3000 $B/logs/$MODE.out; echo ---err; tail -c 5000 $B/logs/$MODE.err
