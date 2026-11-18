# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
#
# /opt/homebrew of the SiliconForest root: the bottles of ./homebrew.lock.json (the system's set
# and its dependency closure, pinned by sha256, fetched from Homebrew's public registry) poured
# and relocated by the tree's own homebrew/hb_pour.py, with the brew client (Homebrew/brew at a
# pinned revision) and its portable Ruby. The output is a tree at installed paths:
#   $out/opt/homebrew/...        owner 501:20 in the image (release/image/permissions.tsv)
#   $out/opt/homebrew/.sf-licences.tsv   formula, version, SPDX licence of every keg
# The bottles keep their machine code; hb_pour.py rewrites placeholders in install names and
# text and re-signs the Mach-O files it changed (ad-hoc), as brew does.
{ pkgs, tree ? ../../integrations/siliconforest, lock ? ./homebrew.lock.json }:
let
  lib = pkgs.lib;
  l = builtins.fromJSON (builtins.readFile lock);
  bottle = f: pkgs.fetchurl {
    name = "homebrew-bottle-${lib.replaceStrings [ "@" ] [ "-at-" ] f.name}-${f.version}.tar.gz";
    url = f.url;
    sha256 = f.sha256;
    # Homebrew's own anonymous token for public bottles
    curlOptsList = [ "-H" "Authorization: Bearer QQ==" ];
  };
  brewSrc = pkgs.fetchFromGitHub { inherit (l.brew) owner repo rev sha256; };
  pour = builtins.filter (f: f.name != "portable-ruby") l.formulae;
  closure = pkgs.writeText "closure-${l.tag}.json" (builtins.toJSON (map (f: {
    inherit (f) name version dependencies keg_only;
    bottle_tag = f.bottle_tag;
  }) l.formulae));
  index = pkgs.writeText "formula.json" (builtins.toJSON (map (f: {
    inherit (f) name post_install_steps;
  }) l.formulae));
  licences = pkgs.writeText "licences.tsv" (lib.concatMapStrings (f:
    "${f.name}\t${f.version}\t${if f.license == null then "unknown" else f.license}\n") l.formulae
    + "brew\t${l.brew.rev}\t${l.brew.license}\n");
in pkgs.runCommand "siliconforest-homebrew-prefix" {
  nativeBuildInputs = [ pkgs.python3 pkgs.gnutar pkgs.gzip ];
} ''
  set -euo pipefail
  R=$PWD/runs; mkdir -p $R/api $R/kegs/${l.tag}
  cp ${closure} $R/closure-${l.tag}.json
  cp ${index} $R/api/formula.json
  ${lib.concatMapStrings (f: ''
    tar -xzf ${bottle f} -C $R/kegs/${l.tag}
    [ -d "$R/kegs/${l.tag}/${f.name}/${f.version}" ] || { echo "bottle ${f.name}: no ${f.name}/${f.version} inside" >&2; exit 1; }
  '') l.formulae}
  cp -R ${brewSrc} brew; chmod -R u+w brew
  [ "$(cat brew/Library/Homebrew/vendor/portable-ruby-version)" = "${(lib.findFirst (f: f.name == "portable-ruby") null l.formulae).version}" ]
  cp -R ${tree}/homebrew tools
  SF_HB_RUNS=$R python3 -I -B tools/hb_pour.py --name release --no-image --tag ${l.tag} --brew brew \
    ${lib.concatMapStringsSep " " (f: lib.escapeShellArg f.name) pour} > pour.json
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); e=d["stats"]["errors"]; print(json.dumps(d["stats"])); sys.exit(1 if e else 0)' $R/prefix/release.json
  mkdir -p $out/opt
  cp -a $R/prefix/release $out/opt/homebrew
  cp ${licences} $out/opt/homebrew/.sf-licences.tsv
''
