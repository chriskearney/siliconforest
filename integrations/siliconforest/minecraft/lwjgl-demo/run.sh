#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# Compile and run LwjglDemo on SiliconForest using private JDK 21 and LWJGL 3.3.3 jars.
set -eu

JDK="${SF_MC_JDK:-/private/var/db/sfminecraft/jdk/Contents/Home}"
LWJGL_DIR="${SF_MC_LWJGL:-/private/var/db/sfminecraft/lwjgl-3.3.3}"
DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SF_MC_DEMO_BUILD:-/private/var/db/sfminecraft/demo-build}"

CP=""
for j in "$LWJGL_DIR"/*.jar; do
    CP="${CP:+$CP:}$j"
done

mkdir -p "$BUILD_DIR"
"$JDK/bin/javac" -cp "$CP" -d "$BUILD_DIR" "$DEMO_DIR/LwjglDemo.java"

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/private/var/run/gpu-desktop}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export SF_NSGL_GPU_TRACE="${SF_NSGL_GPU_TRACE:-1}"

exec "$JDK/bin/java" -XstartOnFirstThread \
    -Dorg.lwjgl.util.Debug=true \
    -cp "$BUILD_DIR:$CP" \
    LwjglDemo
