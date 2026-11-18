# SPDX-License-Identifier: MIT
# One correction of the renamed trees to upstream's Swift runtime recipe (17 November 2026), for both the tip's
# package and the pin's:
#
#   swiftFix = import ../rebase/swift-darwin-module.nix;   swiftFix pd."swift-runtime-arm64"
#
# Upstream's gen-darwin-modulemap.sh keeps kernel-private headers out of Swift's Darwin module with a name
# pattern, `pd_`, that the rename did not follow when pd_pthread_sched.h became sf_pthread_sched.h (the pattern
# stands alone in a regular expression; tools/sf_rename.py has no rule for it). That header defines
# XNU_KERNEL_PRIVATE, so with it in the module <sys/filedesc.h> asks for <kern/locks.h>, which no SDK has, and
# the module does not build ("could not build module 'Darwin'"). The header is taken out of the build's own
# sysroot while the module map is made and put back afterwards, which gives the module map of before the
# rename. Without effect once a fork carries `sf_` in that pattern: the last line then finds nothing to check.
# ld64 also infers an SDK version from the last digits in -syslibroot. Give the
# copied SDK its declared 14.5 version, so a random Nix build-directory number
# cannot become a malformed SDK version during CMake's real compiler probes.
drv: drv.overrideAttrs (old:
  let
    fixed = builtins.replaceStrings
      [ "R=$W/sysroot"
        "> $R/SDKSettings.json\n"
        "cmake -P $S/Runtimes/Resync.cmake > /dev/null" ]
      [ "R=$W/MacOSX14.5.sdk"
        ''
        > $R/SDKSettings.json
            if [ -f $R/usr/include/sf_pthread_sched.h ]; then mv $R/usr/include/sf_pthread_sched.h $W/sf_pthread_sched.h.aside; fi
        ''
        ''
        if [ -f $W/sf_pthread_sched.h.aside ]; then mv $W/sf_pthread_sched.h.aside $R/usr/include/sf_pthread_sched.h; fi
            if grep -q sf_pthread_sched $R/usr/include/module.modulemap; then echo "sf_pthread_sched.h is in the Darwin module"; exit 1; fi
            cmake -P $S/Runtimes/Resync.cmake > /dev/null'' ]
      old.buildPhase;
  in assert builtins.length (builtins.split "R=\\$W/sysroot" old.buildPhase) == 3;
    assert fixed != old.buildPhase; { buildPhase = fixed; })
