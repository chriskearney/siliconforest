# SPDX-License-Identifier: MIT
# /usr/share/terminfo: the whole terminal database of ncurses (its misc/terminfo.src compiled by
# its own tic; ncurses' licence, MIT-X11), so that TERM=tmux-256color, screen-256color, vt220,
# linux, foot, alacritty, kitty, ... resolve for the root's libncurses and every program that links
# it (zsh, vim, less, htop, tmux). The root had xterm-256color only.
# Both layouts, as upstream PureDarwin lays its few entries (nix/arm64.nix): the hex directories
# macOS uses (78/xterm-256color) and the letter directories (x/xterm-256color); which one a given
# ncurses reads depends on how it was configured. Each entry is one file with two names.
#
#   nix-build --extra-experimental-features 'nix-command flakes' --no-out-link build-terminfo.nix
let
  pd = (import ../rebase/pd.nix).pd;
  pkgs = pd.buildPkgs;
in pkgs.runCommand "siliconforest-terminfo-${pkgs.ncurses.version}" { } ''
  set -o pipefail
  T=$out/usr/share/terminfo
  mkdir -p $T
  # nixpkgs' ncurses installs the compiled database under share/terminfo in letter directories
  for d in ${pkgs.ncurses}/share/terminfo/*/; do
    c=$(basename $d)
    h=$(printf %s "$c" | od -An -tx1 | tr -d ' \n')
    mkdir -p $T/$h $T/$c
    cp -L $d* $T/$h/
    chmod u+w $T/$h/*
    [ "$c" = "$h" ] || cp -l $T/$h/* $T/$c/
  done
  test -s $T/74/tmux-256color && test -s $T/t/tmux-256color && test -s $T/78/xterm-256color
  echo "terminfo: $(find $T -type f | wc -l) entries from ncurses ${pkgs.ncurses.version}"
''
