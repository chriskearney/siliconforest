# Shared inputs for the Mesa asahi port: the SiliconForest flake at the lab's pin, its nixpkgs, and
# the Mesa source the M1's Linux runs (omacom/mesa integration/aurora 147a62f6190, 26.3.0-devel).
let
  pd = (import ../rebase/pd.nix).pd;
  pkgs = import pd.inputs.nixpkgs { system = "x86_64-linux"; };
in rec {
  inherit pd pkgs;
  p = pd.packages.x86_64-linux;
  mesaRev = "147a62f619001f5f2588c7417c2b1fac3b0d93ad";
  mesaVersion = "26.3.0-devel-147a62f6190";
  mesaSrc = (import ../../../release/fetch.nix { pkgs = pkgs; }) "mesa-gl";
  pythonEnv = pkgs.python3.withPackages (ps: [ ps.mako ps.pyyaml ps.packaging ps.setuptools ]);
  triple = "arm64-apple-darwin20.4";
  sdkRoot = "${p.apple-sdk}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
}
