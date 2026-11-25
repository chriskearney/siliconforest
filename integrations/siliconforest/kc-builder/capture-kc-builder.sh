# SPDX-License-Identifier: MIT
# Stands in for kc-builder inside a collection recipe (./release-inputs.nix): copies every input of the
# link into ./release-inputs (kernel, kexts/<Name>.kext, codeless/<Name>.kext) with the options rewritten
# to those relative paths in release-inputs/link-args.txt (one argument per line, the output as
# @OUTPUT@), then links FROM that copy with those options. So the collection the recipe installs is the
# one the release's separate files and link options produce, not merely one built next to them.
set -euo pipefail
real=@real@/bin/kc-builder
dest=$PWD/release-inputs
rm -rf "$dest"
mkdir -p "$dest/kexts" "$dest/codeless"
args=()
out=
while [ $# -gt 0 ]; do
  case "$1" in
    -kernel)
      cp -L "$2" "$dest/kernel"; args+=(-kernel kernel); shift 2 ;;
    -kext|-codeless)
      kind=kexts; [ "$1" = -codeless ] && kind=codeless
      name=$(basename "$2")
      if [ -e "$dest/$kind/$name" ]; then echo "capture: two $kind named $name" >&2; exit 1; fi
      cp -RL "$2" "$dest/$kind/$name"
      args+=("$1" "$kind/$name"); shift 2 ;;
    -o)
      out=$2; args+=(-o @OUTPUT@); shift 2 ;;
    -kc-base|-kext-vmbase|-prefix)
      args+=("$1" "$2"); shift 2 ;;
    *)
      echo "capture: option $1 is not part of the release link format" >&2; exit 1 ;;
  esac
done
[ -n "$out" ] || { echo "capture: no -o" >&2; exit 1; }
case "$out" in /*) ;; *) out=$PWD/$out ;; esac
chmod -R u+w "$dest"
printf '%s\n' "${args[@]}" > "$dest/link-args.txt"
final=()
for a in "${args[@]}"; do [ "$a" = @OUTPUT@ ] && final+=("$out") || final+=("$a"); done
cd "$dest"
exec "$real" "${final[@]}"
