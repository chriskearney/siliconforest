# Shared inputs for the Mesa asahi port: the SiliconForest flake at the lab's pin, its nixpkgs, and
# the Mesa source the M1's Linux runs (omacom/mesa integration/aurora 147a62f6190, 26.3.0-devel).
let
  pd = (import ../rebase/pd.nix).pd;
  pkgs = pd.buildPkgs;
in rec {
  inherit pd pkgs;
  p = pd.packages.${pd.buildSystem};
  mesaRev = (builtins.fromJSON (builtins.readFile ../../../sources.lock)).auxiliarySources.mesa-gl.revision;
  mesaVersion = "26.3.0-devel-${builtins.substring 0 11 mesaRev}";
  mesaSrc = (import ../../../release/fetch.nix { pkgs = pkgs; }) "mesa-gl";
  pythonEnv = pkgs.python3.withPackages (ps: [ ps.mako ps.pyyaml ps.packaging ps.setuptools ]);
  triple = "arm64-apple-darwin20.4";
  sdkRoot = "${p.apple-sdk}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
}
