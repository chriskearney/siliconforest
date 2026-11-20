# SPDX-License-Identifier: MIT
# The system Perl of macOS, from Perl's own source: Perl 5.34.1 for arm64 Darwin, laid out as
# macOS has it (/usr/bin/perl, /System/Library/Perl/5.34, libperl.dylib under
# /System/Library/Perl/5.34/darwin-thread-multi-2level/CORE). Programs built on macOS link
# that libperl.dylib by path (Homebrew's vim does: without it dyld refuses vim), and scripts
# name /usr/bin/perl.
#
#   source   perl-5.34.1.tar.gz from CPAN (Artistic licence or GPL 1+), checksum as CPAN publishes it
#   build    perl-cross 1.3.7 (https://github.com/arsv/perl-cross, the cross-compilation
#            build system nixpkgs also uses; same licence as Perl): its configure tests by
#            compiling and linking against our libSystem, nothing is run on a target.
#   ours     cnf/hints/darwin (written below): what Perl's own hints/darwin.sh says about the
#            platform (dylib/bundle, -bundle -undefined dynamic_lookup), and the type sizes,
#            which perl-cross reads from ELF objects only. The sizes are checked here by
#            static assertions with the cross compiler before configure runs.
#   config   threads + multiplicity, shared libperl, 64-bit: the configuration of the macOS
#            system Perl that binaries linking it were compiled against (archname
#            darwin-thread-multi-2level). Perl checks the interpreter's size at every XS
#            boot (Perl_xs_handshake), so a layout that differs from the one a program was
#            compiled against is reported by Perl, not silently used.
#
#   nix-build --extra-experimental-features 'nix-command flakes' --no-out-link build-perl.nix
let
  pd = import ../qemu-dev/sf-userland.nix;
  pkgs = pd.buildPkgs;
  p = pd.packages.${pd.buildSystem};
  libSystem = import ../libsystem-default/build-libsystem.nix;
  pins = (builtins.fromJSON (builtins.readFile ../../../sources.lock)).auxiliarySources;
  fetch = import ../../../release/fetch.nix { inherit pkgs; };
  version = pins.perl-system.revision;
  archname = "darwin-thread-multi-2level";
  privlib = "/System/Library/Perl/5.34";
  archlib = "${privlib}/${archname}";
  perlCross = fetch "perl-cross";
in pkgs.stdenv.mkDerivation {
  pname = "siliconforest-system-perl";
  inherit version;
  src = fetch "perl-system";
  hints = ./perl/hints-darwin;
  sizes = ./perl/sizes.c;
  postUnpack = ''
    tar -C $sourceRoot --strip-components=1 -xzf ${perlCross}
  '';
  postPatch = ''
    cp $hints cnf/hints/darwin
    # perl-cross 1.3.7 tests for a libc function by linking a call without a prototype; current
    # compilers make that an error, so every function tested without a header would be "missing"
    sed -i 's|run \$cc \$ccflags -o try\$_e try.c \$\*|run $cc $ccflags -Wno-implicit-function-declaration -Wno-int-conversion -Wno-incompatible-pointer-types -o try$_e try.c $*|' cnf/configure__f.sh
    grep -q 'Wno-implicit-function-declaration -Wno-int-conversion' cnf/configure__f.sh
    # the signals Darwin has and perl-cross's (Linux) list does not ask for
    sed -i 's/^for sig in HUP INT QUIT ILL TRAP ABRT BUS FPE KILL USR1\\$/for sig in HUP INT QUIT ILL TRAP ABRT EMT BUS FPE KILL USR1 INFO\\/' cnf/configure_sigs.sh
    grep -q 'ABRT EMT BUS' cnf/configure_sigs.sh
    # ld64: no -E; libperl is a dylib with the install name macOS programs carry
    sed -i -e '/^perl\$x: LDFLAGS += -Wl,-E$/d' -e '/^perl\$x: LDFLAGS += -Wl,-rpath,/d' \
      -e 's|^\t\$(CC) \$(LDDLFLAGS) -o \$@ \$(filter %\$o,\$^) \$(LIBS)$|\t$(CC) -dynamiclib -install_name ${archlib}/CORE/libperl.dylib -compatibility_version 5.34 -current_version ${version} $(LDFLAGS) -o $@ $(filter %$o,$^) $(LIBS)|' Makefile
    grep -q 'dynamiclib -install_name' Makefile
    # Time::HiRes finds clockid_t by running a test program, which a cross build cannot;
    # Darwin's <time.h> declares it (an enum), and the module's fallback typedef collides with it
    sed -i 's/^    if (has_clockid_t()) {$/    if (has_clockid_t() || $Config{osname} eq "darwin") {/' dist/Time-HiRes/Makefile.PL
    grep -q 'has_clockid_t() || ' dist/Time-HiRes/Makefile.PL
  '';
  configurePhase = ''
    mkdir -p ../tools
    cat > ../tools/arm64-apple-darwin-cc <<EOF
    #!/bin/sh
    exec ${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-clang -isysroot ${p.apple-sdk}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk -Qunused-arguments -Wno-compound-token-split-by-macro --ld-path=${p.native-ld}/bin/ld -nostdlib -L${libSystem}/usr/lib -L${libSystem}/usr/lib/system -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libSystem}/usr/lib/system/libdyld.dylib -Wl,-platform_version,macos,26.5,26.5 "\$@" -lSystem
    EOF
    sed -i 's/^    //' ../tools/arm64-apple-darwin-cc; chmod 755 ../tools/arm64-apple-darwin-cc
    export PATH=$PWD/../tools:$PATH
    arm64-apple-darwin-cc -c -o /dev/null $sizes      # the hinted sizes are this compiler's
    export AR=${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-ar RANLIB=${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-ranlib \
           NM=${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-nm READELF=readelf OBJDUMP=objdump
    # --sysroot: where ext/Errno finds <errno.h> when the build host is not the target
    ./configure --target=arm64-apple-darwin --with-cc=arm64-apple-darwin-cc \
      --sysroot=${p.apple-sdk}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
      -Dosname=darwin -Dosvers=25.5.0 -Darchname=${archname} \
      -Dusethreads -Dusemultiplicity -Duse64bitall -Duseshrplib -Doptimize=-O2 \
      -Dso=dylib -Dcccdlflags=-fno-common -Dccdlflags=-fno-common "-Dlddlflags=-bundle -undefined dynamic_lookup" \
      -Dprefix=/usr -Dprivlib=${privlib} -Darchlib=${archlib} \
      -Dsitelib=/Library/Perl/5.34 -Dsitearch=/Library/Perl/5.34/${archname} \
      -Dman1dir=none -Dman3dir=none
    grep -E "^(sig_name|sig_num|optimize|archname|useithreads|usemultiplicity|useshrplib|libperl|so|dlext|lddlflags|osname|d_newlocale|d_uselocale|use64bitall|ivsize|nvsize|usemymalloc|cc|libs|perllibs)=" config.sh
  '';
  buildPhase = ''
    make -j$NIX_BUILD_CORES
  '';
  installPhase = ''
    make DESTDIR=$out install
    # %Config describes the system Perl runs on, not the build host: no store path, the
    # compiler by the name a system would have it under
    for f in $out${archlib}/Config.pm $out${archlib}/Config_heavy.pl; do
      sed -i -e "s| *--sysroot=/nix/store/[^ '\"]*||g" -e 's|arm64-apple-darwin-cc|cc|g' $f
      ! grep -q '/nix/store' $f
    done
    mkdir -p $out/nix-support
    cp config.sh config.log $out/nix-support/ 2>/dev/null || cp config.sh $out/nix-support/
  '';
  dontFixup = true;
  dontStrip = true;
  enableParallelBuilding = true;
}
