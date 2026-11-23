#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Host test of kc-tools' import binding (kc-tools-bind.patch): the patched lib/linker.c compiled
into a harness that builds symbol tables and calls bind_lookup() directly, each case in its own
process (the pins are loaded once per process). ASan/UBSan.

  test-bind.py [KC_TOOLS_SOURCE]      default: the source ../m1-bringup/kc-tools-fixed.nix builds

Cases: a declared library wins over the kernel; the kernel wins over a kext the importer does
not declare; a single definition binds as before; two declared libraries with different
addresses, and two undeclared kexts, fail the build (exit 2); a pin chooses its provider, a pin
whose provider has no such definition fails, a pin no import uses is reported; and the choice
does not depend on the order or the number of entries in the table (the old symtab_lookup()
answer does, shown for contrast). Exit status 0 only if every case passes.
"""
import os, subprocess, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
LAB = HERE.parent

HARNESS = r'''
#include "linker.c"
#include <sys/wait.h>
#include <unistd.h>

static SymTable table(const char **names, const char **owners, const uint64_t *addrs, int n, int pad) {
  SymTable st = {0};
  char filler[64];
  for (int i = 0; i < pad; i++) {          /* unrelated names, to move a bisection */
    snprintf(filler, sizeof(filler), "_filler_%05d", i);
    symtab_add(&st, filler, 0x1000 + i, NULL);
  }
  for (int i = 0; i < n; i++)
    symtab_add(&st, names[i], addrs[i], owners[i]);
  qsort(st.syms, st.count, sizeof(Sym), sym_cmp);
  return st;
}

static LinkedKext kext(const char *id, const char *deps) {
  LinkedKext lk;
  memset(&lk, 0, sizeof(lk));
  strncpy(lk.bundle_id, id, sizeof(lk.bundle_id) - 1);
  static char xml[4096];
  snprintf(xml, sizeof(xml), "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict>"
           "<key>CFBundleIdentifier</key><string>%s</string><key>OSBundleLibraries</key><dict>%s"
           "</dict></dict></plist>", id, deps);
  lk.info_plist_xml = strdup(xml);
  lk.info_plist_len = strlen(xml);
  return lk;
}

#define DEP(x) "<key>" x "</key><string>1.0</string>"
static const char *N[] = { "_m_gethdr", "_m_gethdr", "_hz", "_hz", "_only_storage", "_twice", "_twice", "_two_others", "_two_others" };
static const char *O[] = { NULL, "IO80211", NULL, "IO80211", "IOStorage", "LibA", "LibB", "X", "Y" };
static const uint64_t A[] = { 0xk1, 0xa1, 0xk2, 0xa2, 0xs1, 0xb1, 0xb2, 0xc1, 0xc2 };

static int run(int which, int pad) {
  SymTable st = table(N, O, A, 9, pad);
  LinkedKext bwfm = kext("SFBwfm", DEP("IO80211") DEP("com.apple.kpi.bsd"));
  LinkedKext ext4 = kext("ext4", DEP("com.apple.kpi.bsd"));
  LinkedKext usb = kext("IOUSB", DEP("com.apple.kpi.iokit"));
  LinkedKext both = kext("Both", DEP("LibA") DEP("LibB"));
  switch (which) {
  case 1: bind_begin(&bwfm); return bind_lookup(&st, "_m_gethdr") == 0xa1;
  case 2: bind_begin(&ext4); return bind_lookup(&st, "_hz") == 0xk2;
  case 3: bind_begin(&usb); return bind_lookup(&st, "_only_storage") == 0xs1;
  case 4: bind_begin(&both); bind_lookup(&st, "_twice"); return 0;          /* must exit 2 */
  case 5: bind_begin(&ext4); bind_lookup(&st, "_two_others"); return 0;     /* must exit 2 */
  case 6: bind_begin(&bwfm); return bind_lookup(&st, "_m_gethdr") == 0xk1 && kc_bind_unused_pins() == 0;
  case 7: bind_begin(&bwfm); bind_lookup(&st, "_m_gethdr"); return 0;       /* pin to LibA: exit 2 */
  case 8: bind_begin(&ext4); bind_lookup(&st, "_hz"); return kc_bind_unused_pins() == 1;
  case 9: bind_begin(&usb); return bind_lookup(&st, "_nothing") == 0;
  }
  return 0;
}

int main(int argc, char **argv) {
  int which = atoi(argv[1]), pad = argc > 2 ? atoi(argv[2]) : 0;
  if (which == 100) {   /* the old lookup: which copy it returns for 0..63 filler names */
    int kernel = 0, kext = 0;
    for (int p = 0; p < 64; p++) {
      SymTable st = table(N, O, A, 9, p);
      uint64_t v = symtab_lookup(&st, "_m_gethdr");
      kernel += v == 0xk1;
      kext += v == 0xa1;
    }
    printf("old symtab_lookup over 64 table sizes: kernel %d, IO80211 %d\n", kernel, kext);
    return !(kernel && kext);
  }
  return run(which, pad) ? 0 : 1;
}
'''.replace('0xk1', '0x1111').replace('0xk2', '0x2222').replace('0xa1', '0xa111').replace('0xa2', '0xa222') \
   .replace('0xs1', '0x5111').replace('0xb1', '0xb111').replace('0xb2', '0xb222').replace('0xc1', '0xc111').replace('0xc2', '0xc222')


def source_tree():
    if len(sys.argv) > 1:
        return Path(sys.argv[1])
    nix = ['nix-instantiate', '--extra-experimental-features', 'flakes nix-command', '--eval', '--strict', '-E',
           'toString (import %s/m1-bringup/kc-tools-fixed.nix).src' % LAB]
    return Path(subprocess.run(nix, capture_output=True, text=True, check=True).stdout.strip().strip('"'))


def main():
    src = source_tree()
    with tempfile.TemporaryDirectory(prefix='sf-kc-bind-') as tmp:
        tmp = Path(tmp)
        tree = tmp / 'kc-tools'
        subprocess.run(['cp', '-R', str(src), str(tree)], check=True)
        subprocess.run(['chmod', '-R', 'u+w', str(tree)], check=True)
        for p in [LAB / 'm1-bringup' / 'kc-tools-arm64-text.patch', HERE / 'kc-tools-bind.patch']:
            subprocess.run(['patch', '-d', str(tree), '-p1', '--batch', '--forward', '--fuzz=0', '-s', '-i', str(p)], check=True)
        (tmp / 'harness.c').write_text(HARNESS)
        exe = tmp / 't'
        cc = os.environ.get('CC', 'clang')
        subprocess.run([cc, '-std=gnu11', '-O1', '-g', '-w', '-fsanitize=address,undefined', '-fno-sanitize-recover=all',
                        '-I', str(tree / 'include'), '-I', str(tree / 'lib'), str(tmp / 'harness.c'),
                        str(tree / 'lib' / 'macho_view.c'), str(tree / 'lib' / 'plist.c'), str(tree / 'lib' / 'prelink.c'),
                        '-o', str(exe)], check=True)
        pins = tmp / 'pins'
        cases = [
            (1, 'declared library over the kernel', None, 0),
            (2, 'the kernel over an undeclared kext', None, 0),
            (3, 'one definition binds as before (undeclared, noted)', None, 0),
            (4, 'two declared libraries: fails the build', None, 2),
            (5, 'two undeclared kexts, no kernel: fails the build', None, 2),
            (6, 'a pin chooses its provider', 'SFBwfm _m_gethdr kernel\n', 0),
            (7, 'a pin whose provider has no definition fails', 'SFBwfm _m_gethdr LibA\n', 2),
            (8, 'a pin no import uses is reported', 'SFBwfm _m_gethdr kernel\n', 0),
            (9, 'no definition: 0, as before', None, 0),
        ]
        failures = 0
        for which, what, pin, want in cases:
            for pad in (0, 1, 7, 33):
                env = dict(os.environ, ASAN_OPTIONS='detect_leaks=0')   # a one-shot tool
                env.pop('KC_BIND_PINS', None)
                if pin is not None:
                    pins.write_text(pin)
                    env['KC_BIND_PINS'] = str(pins)
                r = subprocess.run([str(exe), str(which), str(pad)], capture_output=True, text=True, env=env, timeout=60)
                ok = r.returncode == want and 'AddressSanitizer' not in r.stderr and 'runtime error' not in r.stderr
                if not ok:
                    failures += 1
                    print('FAIL case %d pad %d (%s): rc %d, want %d\n%s' % (which, pad, what, r.returncode, want, r.stderr[-800:]))
            print('%s case %d: %s' % ('ok  ' if not failures else '....', which, what))
        r = subprocess.run([str(exe), '100'], capture_output=True, text=True, timeout=60,
                           env=dict(os.environ, ASAN_OPTIONS='detect_leaks=0'))
        print(r.stdout.strip() + ('' if r.returncode == 0 else '  (expected both: the old answer depends on the table)'))
        failures += r.returncode != 0
        if failures:
            sys.exit('kc-bind host test: %d failure(s)' % failures)
    print('KC_BIND host: PASS (bind_lookup of the patched linker.c, 9 cases x 4 table sizes)')


if __name__ == '__main__':
    main()
