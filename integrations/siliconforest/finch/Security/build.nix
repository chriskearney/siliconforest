# SPDX-License-Identifier: MIT
# Merge Finch's object/keychain implementation with SiliconForest's Security.
# The retained SiliconForest image supplies constants and the unported API surface.
let
  e = import ../environment.nix;
  inherit (e) pkgs p pd finch libsystem sdk cc ld;
  openssl = import ../corecrypto/openssl.nix;
  publicSource = (import ../../../../release/fetch.nix { pkgs = pkgs; }) "apple-security-oss";
  security = import ../../homebrew/build-security.nix;
in pkgs.stdenv.mkDerivation {
  name = "siliconforest-finch-security-arm64";
  src = finch;
  patches = [ ./patches/0001-core-without-network.patch ];
  nativeBuildInputs = [ pkgs.python3 ];
  dontConfigure = true;
  buildPhase = ''
    export DARWIN_SDK_ROOT=${sdk}
    mkdir -p headers/Security objects
    cp -L ${security}/System/Library/Frameworks/Security.framework/Headers/*.h headers/Security/
    chmod -R u+w headers
    for n in SecKeychainSearch SecIdentitySearch SecAccess SecCertificateOIDs SecPolicySearch SecACL; do
      find ${publicSource} -name "$n.h" -exec cp -f {} headers/Security/ \;
    done
    # The missing search headers are published open-source headers, never SDK bytes.
    cp ${./include-extra.h} headers/Security/FinchExtra.h
    printf '\n#include <Security/FinchExtra.h>\n' >> headers/Security/Security.h
    cp -L ${security}/System/Library/Frameworks/Security.framework/Versions/A/Security Security.pd
    chmod u+w Security.pd
    export PYTHONPATH=${../../homebrew}
    python3 - <<'PY'
from pathlib import Path
from hb_macho import rewrite_names, resign
p=Path('Security.pd')
d=p.read_bytes()
d, count = rewrite_names(d, lambda n: n + '.pd' if n == '/System/Library/Frameworks/Security.framework/Versions/A/Security' else n)
assert count
p.write_bytes(resign(d)[0])
PY
    CF="-isysroot ${sdk} -mmacosx-version-min=26.5 -O2 -fblocks -fno-stack-protector -D_DARWIN_C_SOURCE -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -DFINCH_KEYCHAIN_SERVICE_BACKEND -DFINCH_NONNETWORK_CORE -Wno-deprecated-declarations -Wno-availability -I$PWD/headers -I${libsystem}/usr/include -I${p.coreFoundation-arm64}/include -I${openssl}/include"
    for n in SecObjects SecKeychain SecKeychainCrypto SecTrustSettings SecRevocation SecAccess; do
      ${cc} $CF -c userland/Security/$n.c -o objects/$n.o
    done
    ${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-nm -u objects/*.o > undefined.txt
    python3 - <<'PYCONST'
from pathlib import Path
import re
from hb_macho import MachO
existing=MachO(Path('Security.pd').read_bytes()).exported()[0]
required=set(re.findall(r'_kSec\w+', Path('undefined.txt').read_text()))-existing
headers=Path('constants-headers'); headers.mkdir()
(headers/'constants.h').write_text("".join('extern const CFStringRef '+n[1:]+';\n' for n in sorted(required)))
PYCONST
    python3 userland/Security/gen-constants.py ${publicSource} constants-headers SecConstants.c
    ${cc} $CF -c SecConstants.c -o objects/SecConstants.o
    ${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-nm -g -U objects/*.o | awk '{print $NF}' | sort -u > defined.txt
    python3 - <<'PYEXPORT'
from pathlib import Path
from fnmatch import fnmatchcase
wanted=set(Path('userland/Security/exports.txt').read_text().splitlines())
defined=set(Path('defined.txt').read_text().splitlines())
Path('exports.txt').write_text('\n'.join(sorted(n for n in defined if any(fnmatchcase(n, pattern) for pattern in wanted)))+'\n')
PYEXPORT
    ${cc} -dynamiclib objects/*.o ${openssl}/lib/libcrypto.a ${openssl}/lib/libssl.a \
      --ld-path=${ld} -nostdlib -isysroot ${sdk} \
      -L${libsystem}/usr/lib -L${libsystem}/usr/lib/system \
      -L${p.coreFoundation-arm64}/usr/lib -L${p.libobjc-arm64}/usr/lib \
      -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libsystem}/usr/lib/system/libdyld.dylib \
      -Wl,-platform_version,macos,26.5,26.5 -Wl,-headerpad_max_install_names \
      -Wl,-reexport_library,$PWD/Security.pd -Wl,-exported_symbols_list,exports.txt \
      -install_name /System/Library/Frameworks/Security.framework/Versions/A/Security \
      -compatibility_version 1 -current_version 61901.100.255 \
      -lCoreFoundation -lobjc -lSystem -o Security

    PYTHONPATH=${../../homebrew} python3 - <<'PYREL'
from pathlib import Path
from hb_macho import rewrite_names, resign
p=Path('Security')
d, changed= rewrite_names(p.read_bytes(), lambda n: '@loader_path/Security.pd' if n == '/System/Library/Frameworks/Security.framework/Versions/A/Security.pd' else n)
assert changed
p.write_bytes(resign(d)[0])
PYREL
  '';
  installPhase = ''
    fw=$out/System/Library/Frameworks/Security.framework
    mkdir -p $fw/Versions/A
    cp Security Security.pd $fw/Versions/A/
    mkdir -p $out/usr/share/licenses/finch-security
    cp ${finch}/LICENSE* $out/usr/share/licenses/finch-security/
    cp ${publicSource}/OSX/APPLE_LICENSE $out/usr/share/licenses/finch-security/
    tar -xOf ${openssl.src} openssl-3.5.9/LICENSE.txt > $out/usr/share/licenses/finch-security/OpenSSL-LICENSE.txt
    cp -a headers/Security $fw/Versions/A/Headers
    ln -s A $fw/Versions/Current
    ln -s Versions/Current/Security $fw/Security
    ln -s Versions/Current/Headers $fw/Headers
  '';
  dontFixup = true;
  dontStrip = true;
}
