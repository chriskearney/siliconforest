# mdnsd (the mDNSResponder daemon, mDNSPosix) from the default SiliconForest source with
# mdnsd-debug-quiet.patch (-debug no longer turns on every LogInfo()) and mdnsd-reply-backlog.patch
# (a large answer no longer waits up to a second for the rest to be written). FXNET; see the patches.
# Same upstream CMake target and libSystem as ../../m1-network-native-resolver/build-mdnsd.nix.
let
  pd = (import ../../rebase/pd.nix).pd;
  system = import ../../m1-userspace-diagnostics/build-libsystem-spawnattr.nix;
  selected = pd.packages.${pd.buildSystem}.userland-arm64.override {
    pname = "siliconforest-mdnsd-quiet";
    buildTargets = [ "mdnsd" ];
    prebuiltLibSystem = system;
    xorgDriverIncludes = null;
    installUserlandTargetsOnly = true;
  };
in selected.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./mdnsd-debug-quiet.patch ./mdnsd-reply-backlog.patch ];
  installPhase = ''
    mkdir -p "$out/usr/sbin"
    cp build-nix/src/Userspace/mdnsd/mdnsd "$out/usr/sbin/"
    grep -q 'debug \[-verbose\]' src/Libraries/mDNSResponder/mDNSPosix/PosixDaemon.c
    grep -q 'FXNET: try again in 10 ms' src/Libraries/mDNSResponder/mDNSShared/uds_daemon.c
  '';
  dontFixup = true;
  dontStrip = true;
})
