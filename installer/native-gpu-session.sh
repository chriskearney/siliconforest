# SPDX-License-Identifier: MIT
# Sourced by uwsm. Keep recovery-kernel logins usable after a native-GPU update.
if [ -r /usr/share/siliconforest/native-gpu-session ]; then
    _sf_native_gpu_ok=
    for _sf_native_attempt in 1 2 3 4 5; do
        if /usr/bin/python3 -I /usr/lib/siliconforest/installer.pyz --graphics-admit >/dev/null 2>&1; then
            _sf_native_gpu_ok=1
            break
        fi
        sleep 1
    done
    if [ "$_sf_native_gpu_ok" = 1 ]; then
        if [ "${SILICONFOREST_NATIVE_FALLBACK:-}" = software ]; then
            unset LIBGL_ALWAYS_SOFTWARE SILICONFOREST_NATIVE_FALLBACK
        fi
    else
        export LIBGL_ALWAYS_SOFTWARE=1 SILICONFOREST_NATIVE_FALLBACK=software
        logger -t siliconforest-graphics 'Native GPU pair unavailable; recovery session uses software rendering'
    fi
    unset _sf_native_gpu_ok _sf_native_attempt
fi
