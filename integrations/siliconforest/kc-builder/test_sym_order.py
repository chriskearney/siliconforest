#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Host test of ./kc-tools-sym-order.patch: kc-tools' lib/linker.c (prepared by ./prepare_source.py, or
KC_TOOLS_SOURCE=DIR for an already patched tree) compiled into a harness that fills symbol tables
through the real symtab_add() and sorts them with the real sym_sort(). ASan and UBSan where the
compiler has them.

  test_sym_order.py              run the cases
  test_sym_order.py --digest     also print the digest of a fixed table sequence (CI compares the
                                 Linux and macOS digests: the same order on both C libraries)

Cases: every table of 0..1500 entries drawn from a small name pool (so most names repeat) sorts
to name order with equal names in the order added; the merge pattern kc-builder uses (a sorted
table, a kext's names appended, sorted again) keeps the kernel's copy before every kext's and
earlier kexts before later ones; and symtab_lookup() returns a name's first definition (the
copy added first) for every name, present or not, at every table size. Exit status 0 only if every case passes.
"""
import os, shutil, subprocess, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from prepare_source import prepare  # noqa: E402

HARNESS = r'''
#include "linker.c"

static uint64_t lcg = 0x9e3779b97f4a7c15ull;
static uint32_t rnd(void) { lcg = lcg * 6364136223846793005ull + 1442695040888963407ull; return (uint32_t)(lcg >> 33); }
static int fails = 0;
#define CHECK(c, ...) do { if (!(c)) { fails++; fprintf(stderr, "FAIL: " __VA_ARGS__); fputc('\n', stderr); } } while (0)

static void fill(SymTable *st, size_t n, unsigned pool, uint64_t base) {
  char nm[32];
  for (size_t i = 0; i < n; i++) {
    snprintf(nm, sizeof(nm), "_s%03u", rnd() % pool);
    symtab_add(st, nm, base + st->count);   /* the address records the order added */
  }
}

static int ordered(const SymTable *st) {
  for (size_t i = 1; i < st->count; i++) {
    int c = strcmp(st->syms[i - 1].name, st->syms[i].name);
    if (c > 0 || (c == 0 && st->syms[i - 1].addr >= st->syms[i].addr))
      return 0;
  }
  return 1;
}

static uint64_t digest = 1469598103934665603ull;
static void mix(const void *p, size_t n) { const uint8_t *b = p; while (n--) { digest ^= *b++; digest *= 1099511628211ull; } }

int main(int argc, char **argv) {
  int want_digest = argc > 1 && !strcmp(argv[1], "--digest");
  /* 1: one sort, every size, heavy repetition */
  for (size_t n = 0; n <= 1500; n++) {
    SymTable st = {0};
    fill(&st, n, 1 + n / 7, 0);
    sym_sort(&st);
    CHECK(st.count == n && ordered(&st), "single sort, n=%zu", n);
    symtab_free(&st);
  }
  /* 1b: first definition at every size, including names absent from the table */
  for (size_t n = 0; n <= 600; n++) {
    SymTable st = {0};
    fill(&st, n, 1 + n / 5, 0x100);
    sym_sort(&st);
    char nm[32];
    for (unsigned q = 0; q < 2 + n / 5; q++) {
      snprintf(nm, sizeof(nm), "_s%03u", q);
      uint64_t a = symtab_lookup(&st, nm), first = 0;
      for (size_t i = 0; i < st.count; i++)
        if (!strcmp(st.syms[i].name, nm) && (!first || st.syms[i].addr < first)) first = st.syms[i].addr;
      CHECK(a == first, "first definition, n=%zu %s", n, nm);
    }
    symtab_free(&st);
  }
  /* 2: kc-builder's merge: kernel table, then kexts appended and the whole table sorted again */
  for (int round = 0; round < 40; round++) {
    SymTable st = {0};
    fill(&st, 500 + rnd() % 3000, 400, 0x1000000);
    sym_sort(&st);
    CHECK(ordered(&st), "kernel table, round %d", round);
    for (int k = 0; k < 30; k++) {
      fill(&st, rnd() % 200, 400, 0x1000000);
      sym_sort(&st);
      CHECK(ordered(&st), "after kext %d, round %d", k, round);
    }
    for (size_t i = 0; i < st.count; i++) { mix(st.syms[i].name, strlen(st.syms[i].name) + 1); mix(&st.syms[i].addr, 8); }
    char nm[32];
    for (unsigned q = 0; q < 400; q++) {
      snprintf(nm, sizeof(nm), "_s%03u", q);
      uint64_t a = symtab_lookup(&st, nm), first = 0;
      for (size_t i = 0; i < st.count; i++)
        if (!strcmp(st.syms[i].name, nm) && (!first || st.syms[i].addr < first)) first = st.syms[i].addr;
      CHECK(a == first, "lookup %s gave %llx, first definition %llx", nm, (unsigned long long)a, (unsigned long long)first);
      mix(&a, 8);
    }
    symtab_free(&st);
  }
  if (want_digest)
    printf("sym-order-digest %016llx\n", (unsigned long long)digest);
  if (fails)
    fprintf(stderr, "%d failure(s)\n", fails);
  else
    fprintf(stderr, "sym-order: all cases passed\n");
  return fails != 0;
}
'''


def compilers():
    for cc in (os.environ.get("CC"), "cc", "clang", "gcc"):
        if cc and shutil.which(cc):
            yield cc


def build(src: Path, out: Path) -> Path:
    (src / "lib" / "harness.c").write_text(HARNESS)
    base = ["-std=gnu11", "-O1", "-g", "-w", f"-I{src / 'include'}", str(src / "lib" / "harness.c"),
            str(src / "lib" / "macho_view.c"), str(src / "lib" / "plist.c"), "-o", str(out)]
    cc = next(compilers())
    for extra in (["-fsanitize=address,undefined", "-fno-omit-frame-pointer"], []):
        if subprocess.run([cc, *extra, *base], capture_output=True).returncode == 0:
            if not extra:
                print("test_sym_order: built without sanitizers", file=sys.stderr)
            return out
    r = subprocess.run([cc, *base], capture_output=True, text=True)
    sys.exit(f"test_sym_order: harness does not compile:\n{r.stderr}")


def main() -> int:
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        given = os.environ.get("KC_TOOLS_SOURCE")
        src = td / "src"
        if given:
            shutil.copytree(given, src)
        else:
            prepare(src)
        exe = build(src, td / "harness")
        r = subprocess.run([str(exe), *sys.argv[1:2]])
        return r.returncode


if __name__ == "__main__":
    sys.exit(main())
