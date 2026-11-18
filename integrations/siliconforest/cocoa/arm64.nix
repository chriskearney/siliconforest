# SPDX-License-Identifier: MIT
# arm64 builds of upstream frameworks that the pinned flake only wires for x86_64, made the
# way upstream's own nix/arm64.nix makes its arm64 set (`mkArm64Build`: the same recipe file,
# the arm64 cross toolchain and libSystem, arm64 dependencies). The flake does not export
# that helper or every arm64 intermediate, so the few that are needed are rebuilt here from
# the exported pieces. Nothing here changes a source file; patched builds are in ./patched.nix.
let
  flake = (import ../../../release/cocoa-base.nix).pd;
  pd = flake.packages.x86_64-linux;
  pkgs = import flake.inputs.nixpkgs { system = "x86_64-linux"; };
  src = flake.outPath;
  common = {
    darwinCrossToolchain = pd."arm64-cross-toolchain";
    targetTriple = "arm64-apple-darwin20.4";
    libSystem = pd."libsystem-arm64";
    libcxxDylib = pd."libcxxDylib-arm64";
    libcxxabiDylib = pd."libcxxabiDylib-arm64";
    nativeLd = pd."native-ld";
    appleSdk = pd."apple-sdk";
  };
  # upstream's mkArm64Build
  mk = file: deps:
    let f = import (src + file);
    in pkgs.callPackage f (builtins.intersectAttrs (builtins.functionArgs f) common // deps);
  # an x86_64 package of the flake with its toolchain and the named dependencies swapped
  toArm64 = pkg: deps: pkg.override ({
    inherit (common) darwinCrossToolchain targetTriple libSystem;
  } // deps);

  base = {
    libobjc = pd."libobjc-arm64";
    corefoundation = pd."coreFoundation-arm64";
    foundation = pd."foundation-arm64";
  };
  mesa = pd."mesa-msm-arm64";
  glu = toArm64 pd.glu { inherit (common) libcxxDylib libcxxabiDylib; inherit mesa; };
  openglFramework = pd."openglFramework-arm64".override {
    withX11 = false; inherit mesa glu;
    libX11 = null; xorgproto = null; libXext = null; libxcb = null; libXau = null; libXdmcp = null;
  };
  iosurface = toArm64 pd.iosurface { corefoundation = base.corefoundation; };
  corevideo = toArm64 pd.corevideo (base // {
    inherit openglFramework mesa glu iosurface;
    coregraphics = pd."coregraphics-arm64";
  });
  # what an AppKit application or framework is compiled and linked against
  appDeps = base // {
    appkit = pd."appkit-msm-arm64";
    onyx2d = pd."onyx2d-arm64";
    coretext = pd."coretext-arm64";
    quartzcore = pd."quartzcore-msm-arm64";
    coregraphics = pd."coregraphics-arm64";
    coreservices = pd."coreServices-arm64";
    windowserver = pd."windowserver-arm64";
    inherit openglFramework mesa;
  };
  # CoreMedia, VideoToolbox, AVFoundation, ImageIO, CFNetwork, WebKit, libcups and the other
  # small frameworks Xcode-built applications link (upstream: nix/pkgs/apple/app-frameworks.nix)
  appFrameworks = toArm64 pd."app-frameworks" (appDeps // {
    inherit corevideo;
    libz = pd."libzDylib-arm64";
  });
in {
  inherit flake pd pkgs src common mk toArm64 base mesa glu openglFramework iosurface corevideo appDeps appFrameworks;
}
