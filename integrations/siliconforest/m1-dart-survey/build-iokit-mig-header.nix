# Export the exact generated MIG header of the already-qualified tiny IOKit.
let base = import ../chonkstep-darwin/build-sfgop.nix;
in base.overrideAttrs (old: {
  pname = "puredarwin-tiny-iokit-mig-header";
  installPhase = (old.installPhase or "") + ''
    test -f build-nix/src/Libraries/IOKit/device_user.h
    cp build-nix/src/Libraries/IOKit/device_user.h "$out/include/"
  '';
})
