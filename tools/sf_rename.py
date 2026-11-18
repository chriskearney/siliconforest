#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""The SiliconForest rename: one rule table, applied the same way to this repository, to a
checkout of upstream PureDarwin and to the Chonkstep Darwin checkout.

    tools/sf_rename.py inventory [--tree DIR]     what would change: names by rule, collisions
    tools/sf_rename.py apply                      rename this repository's live files (git mv + contents)
    tools/sf_rename.py tree DIR [--skip P]...     rename the checkout DIR in place (tracked files), or a plain
                                                  copy of a source tree (every file); --skip vendor/ leaves
                                                  a path prefix alone (the compositor and terminal sources)
    tools/sf_rename.py fork DIR REV [--branch B] [--skip P]...
                                                  make the renamed commit of upstream REV in the clone DIR:
                                                  branch B (default siliconforest/<rev8>) = REV + one commit
                                                  with fixed author and date, so the same REV and the same
                                                  rules always give the same commit id
    tools/sf_rename.py check [--tree DIR]         fail when an old name is left outside the allow-list
    tools/sf_rename.py licence-proof BASE [HEAD] [--tree DIR]
                                                  each file of BASE against what it became in HEAD: fail when a
                                                  line that differs is a copyright or licence line
    tools/sf_rename.py safety-proof BASE          the safety-gated files against BASE: names only, same object code
    tools/sf_rename.py classify PATH...           how a path of this repository is treated, and why

Design, the classification of every family of names and the exception list with reasons:
docs/design/siliconforest-naming.md. The vocabularies are in tools/sf_rename_data.json.

The rules never touch: a line that carries a copyright or licence notice; URLs, e-mail addresses,
Nix store paths and content hashes; the names of the upstream clones (sources/puredarwin-*);
lock files; binary files. In this repository they never touch frozen evidence and history
(FROZEN_* below); those files move with integrations/puredarwin -> integrations/siliconforest and
keep their bytes.
"""
import hashlib
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = json.load(open(os.path.join(HERE, 'sf_rename_data.json')))

# ---------------------------------------------------------------------------------------------
# Rule table
# ---------------------------------------------------------------------------------------------
# R1  product name, in any spelling, wherever it stands (also inside identifiers and bundle ids:
#     org.puredarwin.driver.X -> org.siliconforest.driver.X)
PRODUCT = {'PureDarwin': 'SiliconForest', 'puredarwin': 'siliconforest', 'PUREDARWIN': 'SILICONFOREST',
           'Puredarwin': 'Siliconforest', 'pureDarwin': 'siliconForest'}
# R2  pd_ / PD_ at the start of an identifier (leading underscores allowed) -> sf_ / SF_
# R2c pd_## / PD_## (a prefix pasted onto a macro argument) -> sf_## / SF_##
#     and after one of these prefixes inside an identifier (every other "x_pd_y" is somebody
#     else's: pf_pd_*, kHIDUsage_PD_*, power domains of the Linux drivers)
INNER_PREFIXES = ['virgl', 'VIRGL', 'to', 'ml', 'MTL', 'libVkLayer', 'VkLayer', 'opl', 'OPL', 'I', 'brcmfmac', 'SWC',
                  'SERIAL', 'INDIUM', 'DYLD', 'test', 'F', 'kern', 'lkpi', 'LKPI', 'xnu', 'XNU', 'HAVE', 'CONFIG', 'WITH',
                  'ENABLE', 'USE', 'BUILD', 'NO', 'has', 'is', 'struct', 'enum', 'union', 'include']
# x_pd_y in lower case is renamed too (sysctl__kern_pd_avd is pasted together from kern and pd_avd, so
# half a rename does not compile), except behind these prefixes, which are other people's:
INNER_DENY = {'pf', 'td', 'bmode', 'seg0', 'dyn', 'gpu', 'gcc', '__rtw89_phy_dig_dyn', 'rtw89_phy_dig_dyn', 'ofdm',
              'iwl_mvm_print', 'dynamic', 'DW_AT_VMS_rtnbeg', 'cck', 'wmi_pdev_obss', 'usb', 'typec', 'tcpm', 'tcpci',
              'ucsi', 'genpd', 'dev_pm', 'pm', 'power'}
SNAKE_KEEP = {  # not ours: reason
    'pd_entry_t': 'x86 pmap type of XNU', 'PD_ENTRY_NULL': 'x86 pmap constant of XNU',
    'pd_ylmv1': 'a cycle id in a record', 'PD_low': 'rtw phy table name', 'PD_low_bd': 'rtw phy table name',
    'PD_BASE': 'PowerVR page directory field, pasted into ROGUE_MMUCTRL_PC_DATA_PD_BASE_* (Imagination, Linux)',
}
# R2b the two-prefix names: PD_SF_x was "PureDarwin, SiliconForest"; one prefix is enough
DOUBLE = {'PD_SF_': 'SF_', 'pd_sf_': 'sf_'}
# R3  PD + CamelCase (class, kext, framework and constant names): PDFoo -> SFFoo, also behind
#     the usual one-letter constant prefixes and lib/-l
CAMEL_PREFIX = r'(?:lib|[kgstl])?'
CAPS_PREFIX = r'(?:lib|k|(?<=-)l)?'          # libPDGOP.a, kPDGPU_Present, -lPDGOP
LIB_PREFIX = r'(?:lib|(?<=-)l)?'             # libpdavd.a, -lpdavd, libpd_virgl_shim
CAMEL_KEEP = re.compile(  # Apple's PDFKit API and plurals of PDE/PDEV/PDU: not ours
    r'^(?:lib|[kgstl])?PD(?:F(?:Access|Action|Allows|Annotation|Border|Destination|Display|Document|Kit|Outline|Page|Point|'
    r'Print|Rect|Representation|Selection|Size|Thumbnail|View|Operation|s$)|EVs$|Es$|Us$|Fs$)')
# R4  PD + all capitals (PDGOP, PDM1SPIHID, HAVE_PDGOP, PDAVD_IOC_x) -> SF..., except the names in
#     caps_false: other people's (PDE, PDPT, PDEV, PDM microphones, PowerVR's PDVFS) and on-disk
#     magics that stay (PDAJ, PDHFSRT1, PDAOT003, PDSF)
# R5  pd + lower case in one word: only the names in lower_vocab (boot arguments pdavd=,
#     pdm1kbd=, programs pdplay, pdvideo, ...); lower_false are other people's (pdev, pdata, ...)
# R6  pd-name: only the names in hyphen_vocab (pd-netd, pd-dhcp, ...)
# R7  pdCamel (functions and variables of the Cocoa and compositor patches) -> sfCamel
PDCAMEL_KEEP = set()
# R8  name-pd (packages and libraries built "for PD": metal-pd.nix, libindium-pd) -> name-sf; only these
SUFFIX_VOCAB = ['indium', 'metal', 'libmetal', 'libindium', 'Iindium', 'debugserver', 'kmod', 'gpu', 'glfw', 'swift', 'mslc',
                'corecrypto', 'radeon', 'objc', 'nouveau', 'i915', 'cross', 'output', 'virgl', 'opl']
# R9  NNNN-pd-what.patch (numbered patches "for PD") -> NNNN-sf-what.patch
# R11 a directory named pd (fbsdkpi/pd/, corecrypto's pd/) -> sf, and /pd/ in a path
# R12 PdPascal (Rust types generated from pd_ names: PdWindowPositionV1, PdSpeaker) -> SfPascal

# Lines that are never changed: copyright and licence notices, authorship.
PROTECTED_LINE = re.compile(
    r'copyright|\(c\)\s*(?:19|20)\d\d|©|spdx-license-identifier|licen[sc]e|all rights reserved|@author|^\s*[#/* ]*authors?:|'
    r'signed-off-by|co-authored-by|permission is hereby granted|\bredistribut(?:e|ed|es|ion|ions|ing|able)\b|warranty|'
    r'@apple_.*_header_|portions (?:of|copyright)',
    re.I)
# Spans inside a line that are never changed.
PROTECTED_SPAN = re.compile(
    r'https?://[^\s"\'<>)]+|git\+[a-z]+://[^\s"\'<>)]+|github:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+|[A-Za-z0-9_.+-]+@[A-Za-z0-9-]+\.[A-Za-z0-9.-]+|'
    r'/nix/store/[a-z0-9]{32}-[^\s"\'/)]*|\b[a-z0-9]{32}-puredarwin[A-Za-z0-9_.+-]*|sha(?:1|256|512)-[A-Za-z0-9+/=]+|'
    r'\b[0-9a-f]{40,64}\b|sources/puredarwin-[a-z0-9-]+|puredarwin-(?:baseline|rebase|upstream-next|m1-bringup|m1-desktop|m1-firstboot|ram-probe)(?![A-Za-z0-9-])|/var/folders/[a-z0-9_]{2}/|'
    r'PUREDARWIN_LICENSE(?:_HEADER_[A-Z]+|\.txt)?|puredarwin\.org|\bSF_PD\b|(?<![A-Za-z0-9_-])pd\.nix\b|'
    r'PureDarwin (?:Project|upstream|handbook|developers|contributors|authors)|upstream(?:\'s)? PureDarwin|'
    r'(?:fork|forked|derived|taken|inherited|comes?|came) (?:of|from) PureDarwin|PureDarwin\'s (?:upstream|tip|pin)')
# Whole-file content exemptions by name, anywhere.
SKIP_CONTENT_NAME = re.compile(r'(?:^|/)(?:(?!flake\.lock$|Cargo\.lock$)[^/]*\.lock|[^/]*\.sha256|PUREDARWIN_LICENSE\.txt|'
                               r'APPLE_[A-Z_]*LICENSE\.txt|LICENSE[^/]*|COPYING[^/]*|NOTICE[^/]*|CREDITS[^/]*|AUTHORS[^/]*)$')

# ---------------------------------------------------------------------------------------------
# This repository: what is live and what is frozen
# ---------------------------------------------------------------------------------------------
OLD_ROOT, NEW_ROOT = 'integrations/puredarwin/', 'integrations/siliconforest/'
# Frozen evidence and history: content never changed, file names never changed.
FROZEN_PREFIX = {
    'reports/': 'attempt records and receipts',
    'archive/': 'the preserved audit of 7 November',
    'planning/': 'sprint plans as they were written',
    'docs/roadmap/': 'dated hand-over and research notes: they describe boots and builds by the names those had',
    'AGENTS.md': 'the running record of the work (a note at its top points to the naming map)',
    'integrations/m1-boot-window/': 'hash-bound m1n1 boot window candidate',
    'fixtures/': 'recorded fixtures',
    'tr1.txt': 'a capture',
    # the lab scaffold of 7-9 November: it describes upstream PureDarwin as a source to acquire and
    # verify, its files are hash-bound by the early sprint reports, and the required local
    # checks (AGENTS.md) run over it
    'config/': 'lab scaffold: source registry and target profiles (upstream names and pins)',
    'core/': 'lab scaffold', 'contracts/': 'lab scaffold', 'probe/': 'lab scaffold', 'specs/': 'lab scaffold',
    'userspace/': 'lab scaffold', 'tests/': 'lab scaffold: tests of the scaffold and of the frozen controllers',
    'Makefile': 'lab scaffold', '.github/': 'lab scaffold',
}
FROZEN_DOCS_EXCEPT = ('docs/design/',)       # docs/ is the scaffold's and the sprints' record, except the design notes
FROZEN_TOOLS = '''acquire_sources.py __init__.py lab.py publish_github.py source_inventory.py uapi_contract.py check_mutations.py
check.py cross_abi.py m1_boot_install.py m1_bringup_cycle.py m1_firstboot.py m1_kernel_cycle.py m1_pcie_cycle.py
m1_proxy_preflight.py m1_recovery.py render_boot_framebuffer.py roadmap_create_issues.sh save_research.py stage_puredarwin.py'''.split()
FROZEN_COMPONENT = re.compile(
    r'(?:^|/)(?:before|after|validation[^/]*|revisions?|attempts?|baseline|implementation-revisions|host-revision-[^/]*|'
    r'[0-9]{3}|[^/]*-0[0-9][0-9]|[^/]*_0[0-9][0-9]|target|target-host|results|upstream-ref)/')
FROZEN_SUBTREE = {
    OLD_ROOT + 'chonkstep-darwin/desktop-shell/source/': 'snapshot of the Chonkstep shell source (Chonkstep keeps its names)',
}
# Parked sub-directories of m1-apcie-bridge (AGENTS.md, "Parked")
PARKED = re.compile(r'^' + re.escape(OLD_ROOT) + r'm1-apcie-bridge/(?:private_lifecycle|native_backing|control_protection|owned_[^/]*|'
                    r'native_policy_[^/]*|native_private_[^/]*|native_bootargs[^/]*|native_owned|mcc_[^/]*|bcm4378_fake_[^/]*|'
                    r'leased_fake_effects|adt_source_inventory|identity-reference|register-accessor-revisions|root-build)/')
# Integration directories by class.
#   frozen   hash-bound streams of 7-11 November that nothing in the release reaches
#   closure  older directories of which the release build uses some files: only the files in
#            release_closure (tools/sf_rename_data.json) are renamed, the rest is frozen
#   (anything else under integrations/puredarwin is live)
FROZEN_DIRS = '''m1-gpu-asc-envelope m1-gpu-channel-codec m1-gpu-rtkit-control m1-gpu-uat m1-gpu-uat-builder m1-gpu-uat-codec
m1-gpu-uat-data m1-gpu-uat-private m1-network-resolver-egress m1-session-lifetime m1-desktop-session m1-gpu-preflight
m1-network-default-client m1-network-desktop-service m1-network-resolver-service m1-network m1-network-default-route
m1-network-egress m1-network-egress-guest m1-network-link m1-network-native-resolver m1-network-transport m1-firstboot
m1-dart-survey m1-dart m1-rootfs DLMemoryProbe m1-apcie-bridge m1-apcie-port-packet'''.split()
CLOSURE_DIRS = '''m1-bringup m1-bringup-platform m1-keyboard m1-trackpad-enum m1-trackpad-input-trace m1-native-input m1-display
m1-userspace-diagnostics'''.split()
# Single files that are never edited, with the reason.
EXCEPT_FILES = {
    OLD_ROOT + 'm1-firstboot/host_console.py': 'hash-pinned host-side controller tool; never edited',
    OLD_ROOT + 'm1-bringup/normal_image.py': 'hash-pinned host-side image tool; never edited (its PINS key "puredarwin" names upstream)',
    OLD_ROOT + 'rebase/pd.nix': 'kept by name: it selects the upstream PureDarwin revision (edited by hand for the fork revision)',
    'README.md': 'edited by hand: it says what is SiliconForest and what is upstream PureDarwin',
    'LICENSE_STATUS.md': 'licence statement', 'LICENSING.md': 'licence statement: it names upstream PureDarwin', 'tools/sf_rename.py': 'the rule table', 'tools/sf_rename_data.json': 'the vocabularies',
    'docs/design/siliconforest-naming.md': 'the naming design: it lists the old names',
    'docs/design/siliconforest-naming-m1-install.md': 'the install plan: it describes the installed system by its old names',
    'tools/sf_rename_stage.py': 'the stage builder for the installed system: its example names an old path',
    'tools/test_sf_rename_switch.sh': 'the switch test: its mock root is a system under the old names',
    'tools/sf_rename_scan.sh': 'the scan of an installed system: its pattern is the list of old lookups',
    'tools/sf_rename_switch.sh': "asks the running kernel by the old sysctl name which halt program fits it",
    OLD_ROOT + 'rebase/swift-darwin-module.nix': "names the pattern (`pd_`) that upstream's module-map script kept and the header it missed",
    'NOTICE': 'attribution',
    'integrations/puredarwin': 'a symbolic link to siliconforest: the frozen controllers, tests and records name files by the old path',
}
# Patches against the launcher base tree (host side, outside git, hash-pinned lineage): their
# context is that tree's text, which is not renamed in this phase.
LAUNCHER_PATCH = re.compile(r'^(?:\+\+\+|---) [ab]/(?:integrations/puredarwin/m1-bringup/|integrations/m1-boot-window/|tools/m1_[a-z_]*cycle\.py)', re.M)
# Verbatim third-party files: their SHA-256 is recorded in a provenance manifest.
PROVENANCE_RECORD = re.compile(r'(?:^|/)(?:m1-thunderbolt/.*provenance[^/]*\.json|upstream\.sha256)$')
# Frozen files that the release build reads: the frozen file stays, and a renamed copy of it
# (same rules) is written beside the live recipe that uses it.  frozen path -> live copy
SUCCESSORS = {
    OLD_ROOT + 'm1-native-input/revisions/002/candidate.patch': NEW_ROOT + 'm1-native-input/hid-publication-rev002.patch',
}
# Changes that are not renames, made by `apply` after the rename so that it stays re-runnable:
# (file after the rename, exact old text, new text, why)
EDITS = [
    (NEW_ROOT + 'rebase/pd.nix',
     '    tip = { checkout = "sources/puredarwin-rebase"; rev = "c713d8fb9b048a38e2242d67e29b9957ced8c495"; };',
     '    # The SiliconForest tree: upstream PureDarwin c713d8fb9b048a38e2242d67e29b9957ced8c495 plus one commit,\n'
     '    # the mechanical rename (branch siliconforest/c713d8fb of the clone), made by\n'
     '    #   tools/sf_rename.py fork sources/puredarwin-rebase c713d8fb9b048a38e2242d67e29b9957ced8c495\n'
     '    # The same upstream revision and the same rules give the same commit. A later upstream commit is\n'
     '    # taken the same way: fork it, put the new id here (docs/design/siliconforest-naming.md).\n'
     '    # SF_PD=pin still names upstream\'s own tree; the recipes of this branch carry the SiliconForest\n'
     '    # names and do not build it (build the pin from the commit before the rename).\n'
     '    tip = { checkout = "sources/puredarwin-rebase"; rev = "@FORK@"; };',
     'the default source is the renamed fork commit'),
    (NEW_ROOT + 'm1-native-input/build-hid-rev002.nix',
     'in assert builtins.hashFile "sha256" ./revisions/002/candidate.patch == manifest.patches."candidate.patch";\n',
     '  # SiliconForest names: the patch is ./revisions/002/candidate.patch (frozen, hash-bound by its\n'
     '  # manifest) with the rename applied (tools/sf_rename.py SUCCESSORS). The manifest\'s per-file\n'
     '  # hashes are of upstream\'s text before the rename and are not compared here; the patch must\n'
     '  # still apply exactly.\n'
     '  renamed = ./hid-publication-rev002.patch;\nin\n',
     'the frozen revision keeps its bytes; the build uses its renamed copy'),
    (NEW_ROOT + 'm1-native-input/build-hid-rev002.nix',
     '  patches = (old.patches or []) ++ [ ./revisions/002/candidate.patch ];\n'
     '  prePatch = (old.prePatch or "") + "\\n" + checks "before_sha256";\n'
     '  postPatch = (old.postPatch or "") + "\\n" + checks "after_sha256";\n',
     '  patches = (old.patches or []) ++ [ renamed ];\n',
     'see above'),
    (NEW_ROOT + 'desktop/neofetch/neofetch-7.1.0-siliconforest.patch',
     '# SiliconForest: a SiliconForest fork; take the macOS code paths.',
     '# SiliconForest (a fork of PureDarwin): take the macOS code paths.',
     'the sentence named upstream'),
    (NEW_ROOT + 'desktop/neofetch/neofetch-7.1.0-siliconforest.patch',
     'distro="SiliconForest (SiliconForest $osx_version $osx_build)"',
     'distro="SiliconForest $osx_version $osx_build"',
     'sw_vers now says SiliconForest itself'),
    (NEW_ROOT + 'desktop/neofetch/README.md',
     'names the system "SiliconForest (SiliconForest <version> <build>)"',
     'names the system "SiliconForest <version> <build>"',
     'as the patch'),
]
# The renamed commit of upstream c713d8fb (printed by `fork`).
FORK_REV = 'cd001928e0223fd77a7850f09e43580b51bde239'
# Safety-gated sources: identifier and file-name substitution only; `safety-proof` shows the logic is untouched.
SAFETY_FILES = [OLD_ROOT + 'm1-storage/kernel/pd_nvme_wgate.c', OLD_ROOT + 'm1-storage/kernel/pd_nvme_wgate.h',
                OLD_ROOT + 'm1-storage/kernel-rw/pd_nvme_wring.h', OLD_ROOT + 'm1-native-boot/reboot/pd_halt_gate.h']

# ---------------------------------------------------------------------------------------------
# The transform
# ---------------------------------------------------------------------------------------------
def _alt(words):
    return '|'.join(sorted((re.escape(w) for w in words), key=len, reverse=True))

LOWER = _alt(w[2:] for w in DATA['lower_vocab'])
HYPH = _alt(w[3:] for w in DATA['hyphen_vocab'])
INNER = _alt(INNER_PREFIXES)
START = r'(?:(?<![A-Za-z0-9])|(?<=-[DU]))'    # an identifier may begin with underscores, follow x_, or follow -D/-U
TOKEN = re.compile(
    r'(?P<product>[Pp]ure[Dd]arwin|PUREDARWIN)'
    r'|(?P<double>' + START + r'_*(?:PD_SF_|pd_sf_))'
    r'|(?P<snake>(?:(?<![A-Za-z0-9_])(?:(?:' + INNER + r')_)?_*|(?<![A-Za-z0-9_])_+|(?<=-[DU])_*)(?:pd|PD)_(?=[A-Za-z0-9_]))'
    r'|(?P<inner>(?<![A-Za-z0-9_])_*(?:[A-Za-z0-9]+_+)+?pd_(?=[A-Za-z0-9_]))'
    r'|(?P<camel>' + START + CAMEL_PREFIX + r'PD(?=[A-Z0-9][A-Za-z0-9]*[a-z]))'
    r'|(?P<caps>' + START + CAPS_PREFIX + r'PD(?=[A-Z0-9]{2,}(?![A-Za-z0-9])))'
    r'|(?P<lower>' + START + LIB_PREFIX + r'pd(?=(?:' + LOWER + r')(?![A-Za-z0-9])))'
    r'|(?P<libsnake>(?<![A-Za-z0-9_])' + r'(?:lib|(?<=-)l)pd_(?=[A-Za-z0-9_]))'
    r'|(?P<hyphen>(?<![A-Za-z0-9_-])pd-(?=(?:' + HYPH + r')(?![A-Za-z0-9])))'
    r'|(?P<pdcamel>(?<![A-Za-z0-9])_*pd(?=[A-Z][A-Za-z0-9]*[a-z]))'
    r'|(?P<suffix>(?<![A-Za-z0-9])(?:' + _alt(SUFFIX_VOCAB) + r')[-_]pd(?![A-Za-z0-9_]))'
    r'|(?P<numbered>(?<![A-Za-z0-9])[0-9]{4}-pd-(?=[a-z]))'
    r'|(?P<dir>(?<=/)pd(?![A-Za-z0-9_.-]))'
    r'|(?P<pascal>(?<![A-Za-z0-9])Pd(?=[A-Z][a-z]))')
IDENT = re.compile(r'[A-Za-z0-9_]*')
OPAQUE = re.compile(r'^[A-Za-z0-9+/=]{60,}$')          # base64 / base85 payload lines


def _whole(line, start):
    """The identifier that contains position `start`."""
    a = start
    while a > 0 and (line[a - 1].isalnum() or line[a - 1] == '_'):
        a -= 1
    return line[a:IDENT.match(line, start).end()]


def _garbage(tok):
    """Random text (base64 in an SVG, a test vector): letters and digits alternate many times."""
    return len(re.findall(r'[0-9][A-Za-z]|[a-z][A-Z][a-z]?[A-Z0-9]', tok)) >= 3 and not re.search(r'[A-Z][a-z]{3,}', tok)


PASTE = re.compile(r'(?<![A-Za-z0-9_])(?:pd_|PD_)(?=##)')


def transform_line(line, counts=None):
    if 'pd' not in line and 'PD' not in line and 'Pd' not in line and 'arwin' not in line and 'ARWIN' not in line:
        return line
    if PROTECTED_LINE.search(line) or OPAQUE.match(line.strip()):
        return line
    spans = [m.span() for m in PROTECTED_SPAN.finditer(line)]
    # R2c: a prefix pasted by the preprocessor (`pd_##f`, `PD_##NAME`): the names it makes are used as
    # `sf_...` elsewhere (upstream's CGL.c: `static ... pd_##f` and `sf_eglGetProcAddress`)
    if '##' in line:
        def paste(m):
            if counts is not None:
                counts.setdefault('paste', {}).setdefault(m.group(0), 0)
                counts['paste'][m.group(0)] += 1
            return 'sf_' if m.group(0) == 'pd_' else 'SF_'
        line = PASTE.sub(paste, line)

    def repl(m):
        s = m.start()
        for a, b in spans:
            if a <= s < b:
                return m.group(0)
        kind = m.lastgroup
        text = m.group(0)
        if kind == 'product':
            out = PRODUCT.get(text)
            if out is None:
                return text
        elif kind == 'double':
            out = text[:-6] + DOUBLE[text[-6:]]
        elif kind == 'suffix':
            out = text[:-2] + 'sf'
        elif kind == 'numbered':
            out = text[:-3] + 'sf-'
        elif kind == 'dir':
            out = 'sf'
        elif kind == 'pascal':
            out = 'Sf'
        else:
            tok = _whole(line, m.end() - 1)
            if kind == 'snake':
                if tok.lstrip('_') in SNAKE_KEEP or tok in SNAKE_KEEP:
                    return text
                out = text[:-3] + ('sf_' if text[-3:] == 'pd_' else 'SF_')
            elif kind == 'libsnake':
                out = text[:-3] + 'sf_'
            elif kind == 'inner':
                if text[:-3].strip('_') in INNER_DENY or text[:-3].rstrip('_') in INNER_DENY:
                    return text
                out = text[:-3] + 'sf_'
            elif kind == 'camel':
                if CAMEL_KEEP.match(tok.lstrip('_')) or _garbage(tok):
                    return text
                out = text[:-2] + 'SF'
            elif kind == 'caps':
                run = re.match(r'PD[A-Z0-9]+', line[m.end() - 2:]).group(0)
                if run in CAPS_FALSE or _garbage(tok):
                    return text
                out = text[:-2] + 'SF'
            elif kind == 'pdcamel':
                if tok.lstrip('_') in PDCAMEL_KEEP or _garbage(tok):
                    return text
                out = text[:-2] + 'sf'
            else:  # lower, hyphen
                out = text[:-2 if kind == 'lower' else -3] + ('sf' if kind == 'lower' else 'sf-')
        if counts is not None:
            if kind in ('product', 'suffix', 'numbered', 'dir'):
                key = text
            elif kind == 'hyphen':
                key = re.match(r'[a-z0-9-]*', line[m.start():]).group(0).rstrip('-')
            else:
                key = _whole(line, m.end() - 1)
            counts.setdefault(kind, {}).setdefault(key, 0)
            counts[kind][key] += 1
        return out
    out = TOKEN.sub(repl, line)
    if out != line:
        # R10  "SiliconForest PureDarwin" (our system on upstream's) became the name twice: say it once
        for twice, once in DOUBLED:
            if twice in out and twice not in line:
                out = out.replace(twice, once)
    return out


DOUBLED = [('SiliconForest SiliconForest', 'SiliconForest'), ('SiliconForest/SiliconForest', 'SiliconForest'),
           ('siliconforest-siliconforest-', 'siliconforest-'), ("SiliconForest: SiliconForest's", "SiliconForest's")]
FLAKE_LOCK_LINE = re.compile(r'^\s*"[a-z0-9-]+": (?:\{|"[a-z0-9-]+",?)$')    # input names; never owner, repo, rev, narHash


def transform_text(text, counts=None, path=''):
    out, binary_patch = [], False
    if path.endswith('flake.lock'):
        return '\n'.join(transform_line(l, counts) if FLAKE_LOCK_LINE.match(l) else l for l in text.split('\n'))
    for line in text.split('\n'):
        if line.startswith('GIT binary patch'):
            binary_patch = True
        elif binary_patch and (line.startswith('diff ') or line.startswith('--- ')):
            binary_patch = False
        out.append(line if binary_patch else transform_line(line, counts))
    return '\n'.join(out)


def transform_name(name, counts=None):
    """A file or directory name (no licence-line protection: names are not notices)."""
    if SKIP_CONTENT_NAME.search(name):
        return name
    if name == 'pd':
        return 'sf'
    saved = PROTECTED_LINE
    try:
        globals()['PROTECTED_LINE'] = re.compile(r'(?!x)x')
        return transform_line(name, counts)
    finally:
        globals()['PROTECTED_LINE'] = saved


def residual_line(line):
    """Old names left in a line, after protection: what `check` reports."""
    if 'pd' not in line and 'PD' not in line and 'Pd' not in line and 'arwin' not in line and 'ARWIN' not in line:
        return []
    if PROTECTED_LINE.search(line) or OPAQUE.match(line.strip()):
        return []
    spans = [m.span() for m in PROTECTED_SPAN.finditer(line)]
    found = []
    for m in RESIDUAL.finditer(line):
        if any(a <= m.start() < b for a, b in spans):
            continue
        tok = m.group(0)
        bare = tok.lstrip('_')
        if m.lastgroup == 'r_lower' and bare in LOWER_FALSE:
            continue
        if m.lastgroup == 'r_caps' and (re.sub(r'^(?:lib|k|l)(?=PD)', '', bare) in CAPS_FALSE or _garbage(bare)):
            continue
        if m.lastgroup == 'r_hyphen' and bare in HYPHEN_FALSE:
            continue
        if m.lastgroup == 'r_camel' and (CAMEL_KEEP.match(bare) or _garbage(bare)):
            continue
        if m.lastgroup == 'r_snake' and (bare in SNAKE_KEEP or tok in SNAKE_KEEP):
            continue
        if m.lastgroup == 'r_pdcamel' and _garbage(bare):
            continue
        if m.lastgroup == 'r_inner':
            pre = tok[:tok.index('_pd_')]
            if pre.strip('_') in INNER_DENY or pre in INNER_DENY or any(pre.strip('_').startswith(d + '_') for d in INNER_DENY):
                continue
        found.append(tok)
    return found


LOWER_FALSE, CAPS_FALSE, HYPHEN_FALSE = set(DATA['lower_false']), set(DATA['caps_false']), set(DATA['hyphen_false'])
RESIDUAL = re.compile(
    r'(?P<r_product>[Pp]ure[Dd]arwin|PUREDARWIN)'
    r'|(?P<r_snake>(?:(?<![A-Za-z0-9_])|(?<=-[DU]))_*(?:pd|PD)_[A-Za-z0-9_]+)'
    r'|(?P<r_inner>(?<![A-Za-z0-9_])_*(?:[A-Za-z0-9]+_+)+?pd_[A-Za-z0-9_]+)'
    r'|(?P<r_camel>' + START + CAMEL_PREFIX + r'PD[A-Z0-9][A-Za-z0-9]*[a-z][A-Za-z0-9_]*)'
    r'|(?P<r_caps>' + START + CAPS_PREFIX + r'PD[A-Z0-9]{2,}(?![A-Za-z0-9]))'
    r'|(?P<r_lower>' + START + r'pd[a-z0-9]{2,}(?![A-Za-z0-9]))'
    r'|(?P<r_libsnake>(?<![A-Za-z0-9_])(?:lib|(?<=-)l)pd_[A-Za-z0-9_]+)'
    r'|(?P<r_hyphen>(?<![A-Za-z0-9_-])pd-[a-z][a-z0-9-]*[a-z0-9])'
    r'|(?P<r_pdcamel>(?<![A-Za-z0-9])_*pd[A-Z][A-Za-z0-9]*[a-z][A-Za-z0-9]*)'
    r'|(?P<r_suffix>(?<![A-Za-z0-9])(?:' + _alt(SUFFIX_VOCAB) + r')[-_]pd(?![A-Za-z0-9_]))'
    r'|(?P<r_numbered>(?<![A-Za-z0-9])[0-9]{4}-pd-[a-z])'
    r'|(?P<r_dir>(?<=/)pd(?![A-Za-z0-9_.-]))'
    r'|(?P<r_pascal>(?<![A-Za-z0-9])Pd[A-Z][a-z][A-Za-z0-9]*)')

# ---------------------------------------------------------------------------------------------
# Files
# ---------------------------------------------------------------------------------------------
def git(args, cwd, **kw):
    return subprocess.run(['git'] + args, cwd=cwd, check=True, capture_output=True, **kw).stdout


def tracked(root):
    return [p for p in git(['ls-files', '-z'], root).decode().split('\0') if p]


def is_text(path):
    try:
        with open(path, 'rb') as f:
            head = f.read(8192)
    except OSError:
        return False
    return b'\0' not in head


def read(path):
    with open(path, 'rb') as f:
        return f.read().decode('utf-8', 'surrogateescape')


def write(path, text):
    with open(path, 'wb') as f:
        f.write(text.encode('utf-8', 'surrogateescape'))


class Repo:
    """Classification of this repository's files."""

    def __init__(self, root):
        self.root = root
        self.files = tracked(root)
        self.closure = set(DATA['release_closure'])
        self.closure |= {'/'.join(transform_name(c) for c in p.split('/')) for p in self.closure}   # after the rename
        self.closure_dirs = tuple(p for p in self.closure if p.endswith('/'))
        self._verbatim = None

    def verbatim(self):
        """Files whose SHA-256 a provenance manifest records: third-party text taken as is."""
        if self._verbatim is None:
            recorded = set()
            for p in self.files:
                if PROVENANCE_RECORD.search(p) and os.path.isfile(os.path.join(self.root, p)):
                    recorded |= set(re.findall(r'\b[0-9a-f]{64}\b', read(os.path.join(self.root, p))))
            self._verbatim = set()
            if recorded:
                for p in self.files:
                    full = os.path.join(self.root, p)
                    if (p.startswith(OLD_ROOT) or p.startswith(NEW_ROOT)) and os.path.isfile(full) and not os.path.islink(full):
                        with open(full, 'rb') as f:
                            if hashlib.sha256(f.read()).hexdigest() in recorded:
                                self._verbatim.add(p)
        return self._verbatim

    def classify(self, path):
        """(class, reason). class: live | frozen | except | verbatim | launcher-patch"""
        p = OLD_ROOT + path[len(NEW_ROOT):] if path.startswith(NEW_ROOT) else path
        if p in EXCEPT_FILES:
            return 'except', EXCEPT_FILES[p]
        for pre, why in FROZEN_PREFIX.items():
            if p == pre or p.startswith(pre):
                return 'frozen', why
        if p.startswith('docs/') and not p.startswith(FROZEN_DOCS_EXCEPT):
            return 'frozen', 'the scaffold\'s and the sprints\' documents, as written'
        if p.startswith('tools/') and p[6:] in FROZEN_TOOLS:
            return 'frozen', 'lab scaffold and the frozen recovery controllers (7-9 November, hash-bound)'
        for pre, why in FROZEN_SUBTREE.items():
            if p.startswith(pre):
                return 'frozen', why
        if p.startswith(OLD_ROOT):
            rest = p[len(OLD_ROOT):]
            top = rest.split('/')[0]
            if top in FROZEN_DIRS:
                return 'frozen', 'hash-bound stream of 7-11 November outside the release'
            if PARKED.match(p):
                return 'frozen', 'parked (AGENTS.md)'
            if FROZEN_COMPONENT.search(rest):
                return 'frozen', 'a kept revision, attempt, validation record or build output'
            if top in CLOSURE_DIRS and not (p in self.closure or p.startswith(self.closure_dirs)):
                return 'frozen', 'older stream; not an input of the release build'
        elif FROZEN_COMPONENT.search(p):
            return 'frozen', 'a kept revision, attempt, validation record or build output'
        if path in self.verbatim():
            return 'verbatim', 'third-party file taken as is (SHA-256 in a provenance manifest)'
        full = os.path.join(self.root, path)
        if path.endswith(('.patch', '.diff')) and os.path.isfile(full) and is_text(full) and LAUNCHER_PATCH.search(read(full)):
            return 'launcher-patch', 'patch against the launcher base tree (host side, not renamed in this phase)'
        return 'live', ''

    def new_path(self, path, cls):
        p = NEW_ROOT + path[len(OLD_ROOT):] if path.startswith(OLD_ROOT) else path
        if cls == 'live':
            head, rest = (NEW_ROOT, p[len(NEW_ROOT):]) if p.startswith(NEW_ROOT) else ('', p)
            p = head + '/'.join(transform_name(c) for c in rest.split('/'))
        elif cls in ('verbatim', 'launcher-patch', 'except'):
            # the file keeps its own name and bytes; its directories follow the live files beside it
            head, rest = (NEW_ROOT, p[len(NEW_ROOT):]) if p.startswith(NEW_ROOT) else ('', p)
            parts = rest.split('/')
            p = head + '/'.join([transform_name(c) for c in parts[:-1]] + parts[-1:])
        return p


def cmd_apply(root):
    repo = Repo(root)
    plan, counts, changed, superseded = [], {}, 0, 0
    for path in repo.files:
        cls, _ = repo.classify(path)
        plan.append((path, cls, repo.new_path(path, cls)))
    targets = {}
    for old, cls, new in plan:
        if new in targets and targets[new] != old:
            sys.exit(f'collision: {old} and {targets[new]} both become {new}')
        targets[new] = old
    olds, news = [], []
    for old, cls, new in plan:
        full = os.path.join(root, old)
        if cls == 'live' and os.path.isfile(full) and not os.path.islink(full) and is_text(full) and not SKIP_CONTENT_NAME.search(old):
            text = read(full)
            out = transform_text(text, counts, old)
            if out != text:
                write(full, out)
                changed += 1
                if new == old:
                    news.append(new)
        if new != old:
            os.makedirs(os.path.dirname(os.path.join(root, new)) or root, exist_ok=True)
            os.rename(full, os.path.join(root, new))
            olds.append(old)
            news.append(new)
    for src, dst in SUCCESSORS.items():
        src = src if os.path.exists(os.path.join(root, src)) else NEW_ROOT + src[len(OLD_ROOT):]
        out = transform_text(read(os.path.join(root, src)), counts)
        full = os.path.join(root, dst)
        if not os.path.exists(full) or read(full) != out:
            write(full, out)
        news.append(dst)
    for path, old_text, new_text, _ in EDITS:
        full = os.path.join(root, path)
        text = read(full)
        if '@FORK@' in new_text:       # already edited for another fork commit: only the id changes
            before = re.compile(re.escape(new_text).replace(re.escape('@FORK@'), '[0-9a-f]{40}'))
            new_text = new_text.replace('@FORK@', FORK_REV)
            if before.search(text) and new_text not in text:
                write(full, before.sub(lambda m: new_text, text))
                news.append(path)
                continue
        if new_text in text:
            continue
        if old_text not in text:
            sys.exit(f'{path}: the text an edit expects is not there')
        write(full, text.replace(old_text, new_text))
        news.append(path)
    # the index follows by named paths (never `git add -A`)
    for args, paths in ((['rm', '-q', '--cached', '--pathspec-from-file=-', '--pathspec-file-nul'], olds),
                        (['add', '-f', '--pathspec-from-file=-', '--pathspec-file-nul'], news)):
        if paths:
            subprocess.run(['git', '-c', 'core.quotepath=off'] + args, cwd=root, check=True, input='\0'.join(paths).encode('utf-8', 'surrogateescape'))
    if not os.path.islink(os.path.join(root, OLD_ROOT.rstrip('/'))):      # afterwards a link to the new directory
        for d, _, _ in sorted(os.walk(os.path.join(root, OLD_ROOT)), reverse=True):
            if not os.listdir(d):
                os.rmdir(d)
    moved = sum(1 for o, c, n in plan if o != n)
    by = {}
    for o, c, n in plan:
        by[c] = by.get(c, 0) + 1
    print(json.dumps({'files': len(plan), 'by_class': by, 'moved': moved, 'content_changed': changed,
                      'names_by_rule': {k: len(v) for k, v in counts.items()},
                      'occurrences_by_rule': {k: sum(v.values()) for k, v in counts.items()}}, indent=1))
    return counts


def cmd_tree(root, skip=()):
    """Rename a whole tree. A git checkout: its tracked files, moved with git. A plain directory
    (a copy of a source tree without .git): every file. `skip`: path prefixes left alone (vendor/)."""
    counts, changed, moved = {}, 0, 0
    plain = not os.path.exists(os.path.join(root, '.git'))
    if plain:
        files = sorted(os.path.relpath(os.path.join(d, f), root) for d, _, fs in os.walk(root) for f in fs)
    else:
        files = tracked(root)
    files = [f for f in files if not f.startswith(tuple(skip))] if skip else files
    renames = []
    for path in files:
        full = os.path.join(root, path)
        if os.path.isfile(full) and not os.path.islink(full) and is_text(full) and not SKIP_CONTENT_NAME.search(path):
            text = read(full)
            out = transform_text(text, counts, path)
            if out != text:
                write(full, out)
                changed += 1
        new = '/'.join(transform_name(c) for c in path.split('/'))
        if new != path:
            renames.append((path, new))
    seen = set(files)
    for old, new in renames:
        if new in seen:
            sys.exit(f'collision: {old} -> {new} exists')
        seen.add(new)
        os.makedirs(os.path.dirname(os.path.join(root, new)) or root, exist_ok=True)
        if plain:
            os.rename(os.path.join(root, old), os.path.join(root, new))
        else:
            git(['mv', '-k', old, new], root)
        moved += 1
    print(json.dumps({'files': len(files), 'moved': moved, 'content_changed': changed,
                      'names_by_rule': {k: len(v) for k, v in counts.items()},
                      'occurrences_by_rule': {k: sum(v.values()) for k, v in counts.items()}}, indent=1))
    return counts


def cmd_fork(root, rev, branch, skip=()):
    """The renamed commit of REV, made in a temporary worktree of the clone (its own checkout is not touched)."""
    import shutil
    import tempfile
    rev = git(['rev-parse', rev + '^{commit}'], root).decode().strip()
    branch = branch or 'siliconforest/' + rev[:8]
    date = git(['show', '-s', '--format=%cI', rev], root).decode().strip()
    work = tempfile.mkdtemp(prefix='sf-rename-fork-')
    try:
        git(['worktree', 'add', '-f', '--detach', work, rev], root)
        # Submodules (upstream: external/corecrypto) are other repositories whose commits the rename
        # cannot reach. Their files at the recorded commit become ordinary files of the fork commit.
        gitdir = git(['rev-parse', '--git-common-dir'], root).decode().strip()
        gitdir = gitdir if os.path.isabs(gitdir) else os.path.join(root, gitdir)
        for line in git(['ls-files', '-s'], work).decode().split('\n'):
            if line.startswith('160000 '):
                meta, sub = line.split('\t', 1)
                module = os.path.join(gitdir, 'modules', sub)
                tar = subprocess.run(['git', '--git-dir', module, 'archive', meta.split()[1]], check=True, capture_output=True).stdout
                git(['rm', '-q', '--cached', sub], work)
                os.makedirs(os.path.join(work, sub), exist_ok=True)
                subprocess.run(['tar', '-x', '-C', os.path.join(work, sub)], input=tar, check=True)
                git(['config', '-f', '.gitmodules', '--remove-section', 'submodule.' + sub], work)
                if not read(os.path.join(work, '.gitmodules')).strip():
                    git(['rm', '-q', '-f', '.gitmodules'], work)
                else:
                    git(['add', '.gitmodules'], work)
                git(['add', '-f', '--', sub], work)
        cmd_tree(work, skip)
        git(['add', '-u'], work)
        env = dict(os.environ, GIT_AUTHOR_NAME='SiliconForest rename', GIT_AUTHOR_EMAIL='noreply@siliconforest.invalid',
                   GIT_COMMITTER_NAME='SiliconForest rename', GIT_COMMITTER_EMAIL='noreply@siliconforest.invalid',
                   GIT_AUTHOR_DATE=date, GIT_COMMITTER_DATE=date)
        subprocess.run(['git', 'commit', '-q', '--no-gpg-sign', '-m',
                        'SiliconForest names (tools/sf_rename.py tree)\n\n'
                        f'Mechanical rename of upstream PureDarwin {rev}. No other change.\n'
                        'Copyright and licence lines are untouched; PUREDARWIN_LICENSE.txt stays.'],
                       cwd=work, check=True, env=env)
        new = git(['rev-parse', 'HEAD'], work).decode().strip()
        git(['branch', '-f', branch, new], root)
        print(branch, new, 'tree', git(['rev-parse', new + '^{tree}'], root).decode().strip())
    finally:
        subprocess.run(['git', 'worktree', 'remove', '--force', work], cwd=root)
        shutil.rmtree(work, ignore_errors=True)


def scan(root, files, classify=None):
    left = {}
    for path in files:
        if classify and classify(path)[0] != 'live':
            continue
        full = os.path.join(root, path)
        names = residual_line(os.path.basename(path)) if not SKIP_CONTENT_NAME.search(path) else []
        if names:
            left.setdefault(path, []).append((0, names))
        if os.path.isfile(full) and not os.path.islink(full) and is_text(full) and not SKIP_CONTENT_NAME.search(path):
            binary_patch = False
            for n, line in enumerate(read(full).split('\n'), 1):
                if line.startswith('GIT binary patch'):
                    binary_patch = True
                elif binary_patch and (line.startswith('diff ') or line.startswith('--- ')):
                    binary_patch = False
                if binary_patch or (path.endswith('flake.lock') and not FLAKE_LOCK_LINE.match(line)):
                    continue
                r = residual_line(line)
                if r:
                    left.setdefault(path, []).append((n, r))
    return left


def cmd_check(root, tree):
    files = tracked(root)
    left = scan(root, files, None if tree else Repo(root).classify)
    total = sum(len(r) for hits in left.values() for _, r in hits)
    for path in sorted(left)[:200]:
        for n, r in left[path][:5]:
            print(f'{path}:{n}: {" ".join(r[:6])}')
    names = {}
    for hits in left.values():
        for _, r in hits:
            for t in r:
                names[t] = names.get(t, 0) + 1
    if names:
        print('unclassified or unrenamed names:', ' '.join(f'{k}({v})' for k, v in sorted(names.items(), key=lambda kv: -kv[1])[:150]))
    print(f'check: {total} old name(s) in {len(left)} file(s) outside the allow-list' if total else 'check: clean')
    return 1 if total else 0


def cmd_inventory(root, tree):
    counts = {}
    files = tracked(root)
    repo = None if tree else Repo(root)
    idents, by = set(), {}
    word = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
    for path in files:
        cls = 'live' if tree else repo.classify(path)[0]
        by[cls] = by.get(cls, 0) + 1
        full = os.path.join(root, path)
        if cls != 'live' or not os.path.isfile(full) or os.path.islink(full) or not is_text(full) or SKIP_CONTENT_NAME.search(path):
            continue
        text = read(full)
        transform_text(text, counts)
        if 'sf' in text or 'SF' in text or 'ilicon' in text:
            idents |= {w for w in word.findall(text) if 'sf' in w or 'SF' in w or 'ilicon' in w}
        for c in path.split('/'):
            transform_name(c, counts)
    collisions = []
    for kind, toks in counts.items():
        for t in toks:
            n = transform_name(t)
            if n != t and n in idents:
                collisions.append(f'{t}->{n}')
    print(json.dumps({'files_by_class': by, 'names_by_rule': {k: len(v) for k, v in counts.items()},
                      'occurrences_by_rule': {k: sum(v.values()) for k, v in counts.items()},
                      'collisions': sorted(collisions)}, indent=1))
    if '--names' in sys.argv:
        for kind in sorted(counts):
            print(kind + ':', ' '.join(f'{k}:{v}' for k, v in sorted(counts[kind].items(), key=lambda kv: -kv[1])))


LICENCE_ID = re.compile(r'\b(?:A?L?GPL-[0-9.]+(?:-only|-or-later)?|Apache-2\.0|BSD-[0-9]-Clause|MPL-[0-9.]+|APSL(?:-[0-9.]+)?|ISC|MIT|OFL-[0-9.]+)\b')
LICENCE_LINE = re.compile(r'copyright|\(c\)\s*(?:19|20)\d\d|©|spdx-license-identifier|licen[sc]e|all rights reserved', re.I)


def cmd_licence_proof(root, base, head, tree=False):
    """Every file of BASE against the file it became in HEAD, line by line (the rename keeps the
    number of lines): no line that differs may be a copyright or licence line, on either side.
    Files whose line count changed (the scripted edits) are compared as a diff."""
    import difflib
    base_files = [l.split('\t', 1)[1] for l in git(['ls-tree', '-r', '-z', base], root).decode('utf-8', 'surrogateescape').split('\0')
                  if l and not l.startswith('160000')]         # not submodule links
    if tree:
        class Plain:
            files = base_files
            def classify(self, p): return ('live', '')
            def new_path(self, p, cls): return '/'.join(transform_name(c) for c in p.split('/')) if cls == 'live' else p
        repo = Plain()
    else:
        repo = Repo(root)
        repo.files = base_files
        repo._verbatim = set()      # path mapping only; a verbatim file is compared like any other
    head_files = set(p for p in git(['ls-tree', '-r', '--name-only', '-z', head], root).decode('utf-8', 'surrogateescape').split('\0') if p)

    def blob(rev, path):
        return subprocess.run(['git', 'show', f'{rev}:{path}'], cwd=root, capture_output=True).stdout

    files = changed = lines = mentions = 0
    bad, gone = [], []
    for old in repo.files:
        cls = repo.classify(old)[0]
        new = next((c for c in (repo.new_path(old, 'live'), repo.new_path(old, 'frozen'), repo.new_path(old, 'except'), old) if c in head_files), None)
        if new is None:
            gone.append(old)
            continue
        if new == old and cls != 'live':
            continue
        x, y = blob(base, old), blob(head, new)
        files += 1
        if x == y:
            continue
        changed += 1
        if b'\0' in x[:8192]:
            bad.append(f'{old}: a binary file changed')
            continue
        xs, ys = x.decode('utf-8', 'surrogateescape').split('\n'), y.decode('utf-8', 'surrogateescape').split('\n')
        if len(xs) == len(ys):
            pairs = [(u, v) for u, v in zip(xs, ys) if u != v]
        else:
            pairs = [(l[1:], l[1:]) for l in difflib.unified_diff(xs, ys, lineterm='', n=0) if l[:1] in '+-' and not l.startswith(('+++', '---'))]
        lines += len(pairs)
        for u, v in pairs:
            if LICENCE_LINE.search(u) or LICENCE_LINE.search(v):
                bad.append(f'{new}: {u[:160]}')
            elif LICENCE_ID.search(u) or LICENCE_ID.search(v):
                # a description that names a licence ("GPL-2.0; driver for ... at /dev/sfavd"): the identifiers must be the same
                mentions += 1
                if LICENCE_ID.findall(u) != LICENCE_ID.findall(v):
                    bad.append(f'{new}: licence identifier changed: {u[:160]}')
    for line in bad[:40]:
        print(line)
    if gone:
        print('no counterpart in', head, ':', ' '.join(gone[:10]))
    print(f'licence-proof {base}..{head}: {files} files compared with what they became, {changed} with changed content, '
          f'{lines} changed lines; {len(bad)} of those lines carry a copyright or licence notice; '
          f'{mentions} others name a licence identifier in a description and the identifier is the same before and after')
    return 1 if bad or [g for g in gone if g != '.gitmodules'] else 0


SAFETY_UNITS = [
    # (directory of the unit before the rename, [sources], [compiler flags by old name])
    (OLD_ROOT + 'm1-storage', ['kernel/pd_nvme_wgate.c', 'kernel/pd_nvme_gate.c', 'kernel-rw/pd_nvme_wring.c'],
     [[], ['-DPD_WRING_HOST_TEST']]),
    (OLD_ROOT + 'm1-native-boot/reboot', ['@pd_halt_gate.h'], [[]]),
]


def cmd_safety_proof(root, base):
    """The safety-gated files after the rename against BASE: names only.
    1. the new text is the old text with the rules applied, and mapping the names back gives the
       old text byte for byte (so every constant and expression is the same);
    2. the numeric literals of old and new are the same list;
    3. compiled with the same compiler and flags, the sections' bytes are identical and the symbol
       and relocation tables are identical once the names are mapped back."""
    import shutil
    import tempfile
    repo = Repo(root)
    ok = True
    work = tempfile.mkdtemp(prefix='sf-safety-')
    try:
        for old in SAFETY_FILES:
            new = repo.new_path(old, 'live')
            a = git(['show', f'{base}:{old}'], root).decode()
            b = read(os.path.join(root, new))
            counts = {}
            step1 = transform_text(a, counts) == b
            pairs = {}
            for toks in counts.values():
                for t in toks:
                    pairs[transform_name(t)] = t
            pairs[os.path.basename(new)] = os.path.basename(old)
            back = b
            for n in sorted(pairs, key=len, reverse=True):
                back = re.sub(r'(?<![A-Za-z0-9_])' + re.escape(n) + r'(?![A-Za-z0-9_])', pairs[n], back)
            if back != a:      # a name inside a longer word (a comment naming a file or boot argument)
                back = b
                for n in sorted(pairs, key=len, reverse=True):
                    back = back.replace(n, pairs[n])
            step1b = back == a
            num = re.compile(r'(?<![A-Za-z_])(?:0[xX][0-9a-fA-F]+|[0-9]+)[uUlL]*')
            step2 = num.findall(a) == num.findall(b)
            pre = [w for w in re.findall(r'[A-Za-z_][A-Za-z0-9_]*', a) if w.startswith(('sf_', 'SF_', '_SF_'))]
            print(f'{old} -> {new}\n  rules applied to old == new: {step1}; names mapped back == old, byte for byte: {step1b}; '
                  f'numeric literals identical ({len(num.findall(a))}): {step2}; names changed: {len(pairs)}; '
                  f'sf names already in the old file: {len(pre)}')
            ok = ok and step1 and step1b and step2 and not pre
        cc = shutil.which('gcc') or shutil.which('cc')
        for unit, sources, flagsets in SAFETY_UNITS:
            od, nd = os.path.join(work, 'old'), os.path.join(work, 'new')
            for d in (od, nd):
                shutil.rmtree(d, ignore_errors=True)
            new_unit = repo.new_path(unit + '/x', 'live')[:-2]
            for f in git(['ls-tree', '-r', '--name-only', base, unit + '/'], root).decode().split('\n'):
                if f.endswith(('.c', '.h')):
                    dst = os.path.join(od, os.path.relpath(f, unit))
                    os.makedirs(os.path.dirname(dst), exist_ok=True)
                    with open(dst, 'wb') as out:
                        out.write(git(['show', f'{base}:{f}'], root))
                    nf = repo.new_path(f, repo.classify(f)[0])
                    dstn = os.path.join(nd, os.path.relpath(nf, new_unit))
                    os.makedirs(os.path.dirname(dstn), exist_ok=True)
                    shutil.copy(os.path.join(root, nf), dstn)
            for src in sources:
                for flags in flagsets:
                    objs = []
                    for d, rename in ((od, False), (nd, True)):
                        name = transform_name(src) if rename else src
                        fl = [x[:2] + transform_name(x[2:]) for x in flags] if rename else flags
                        if name.startswith('@'):      # a header of static inline functions: emit them all
                            tu = os.path.join(d, 'unit.c')
                            write(tu, f'#include "{name[1:]}"\n')
                            name, fl = 'unit.c', fl + ['-fkeep-inline-functions', '-fkeep-static-functions']
                        inc = [x for sub in sorted({os.path.dirname(os.path.join(dp, f)) for dp, _, fs in os.walk(d) for f in fs if f.endswith('.h')}) for x in ('-I', sub)]
                        obj = os.path.join(d, 'unit.o')
                        r = subprocess.run([cc, '-std=gnu11', '-O2', '-g0', '-ffile-prefix-map=' + d + '=.', '-c', os.path.join(d, name), '-o', obj] + inc + fl,
                                           capture_output=True, text=True)
                        if r.returncode:
                            print(f'  {src} {flags}: does not compile on this host: {r.stderr.strip().splitlines()[-1] if r.stderr.strip() else ""}')
                            objs = None
                            break
                        dump = {}
                        for sec in ('.text', '.rodata', '.data', '.bss'):
                            binf = obj + sec
                            subprocess.run(['objcopy', '-O', 'binary', '--only-section=' + sec + '*', obj, binf], check=True)
                            dump[sec] = hashlib.sha256(open(binf, 'rb').read()).hexdigest()[:16] + f'/{os.path.getsize(binf)}'
                        syms = subprocess.run(['nm', '-n', '--defined-only', obj], capture_output=True, text=True).stdout
                        rel = subprocess.run(['readelf', '-rW', obj], capture_output=True, text=True).stdout
                        dis = subprocess.run(['objdump', '-d', '--no-show-raw-insn', obj], capture_output=True, text=True).stdout
                        dis = '\n'.join(l for l in dis.split('\n') if 'file format' not in l)
                        objs.append((dump, syms, rel, dis))
                    if objs is None:
                        ok = False
                        continue
                    (d0, s0, r0, x0), (d1, s1, r1, x1) = objs
                    back = lambda t: '\n'.join(reverse_line(l) for l in t.split('\n'))
                    same = d0 == d1 and s0 == back(s1) and r0 == back(r1) and x0 == back(x1)
                    print(f'  {src} {" ".join(flags)}: sections {d0} == {d1}: {d0 == d1}; symbols equal after mapping back: {s0 == back(s1)} '
                          f'({len(s0.splitlines())}); relocations: {r0 == back(r1)}; disassembly: {x0 == back(x1)}')
                    ok = ok and same
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print('safety-proof:', 'names only; logic and object code identical' if ok else 'FAILED')
    return 0 if ok else 1


def reverse_line(line):
    """sf names of the gated units back to their pd names (symbols in nm/readelf/objdump output)."""
    return re.sub(r'(?<![A-Za-z0-9])(_*)(sf|SF)_', lambda m: m.group(1) + ('pd_' if m.group(2) == 'sf' else 'PD_'), line)


def main():
    a = sys.argv[1:]
    if not a:
        sys.exit(__doc__)
    cmd = a[0]
    root = os.getcwd() if cmd == 'tree' else git(['rev-parse', '--show-toplevel'], os.getcwd()).decode().strip()
    tree = a[a.index('--tree') + 1] if '--tree' in a else None
    if cmd == 'inventory':
        cmd_inventory(os.path.abspath(tree) if tree else root, bool(tree))
    elif cmd == 'apply':
        cmd_apply(root)
    elif cmd == 'tree':
        cmd_tree(os.path.abspath(a[1]), [a[i + 1] for i, x in enumerate(a) if x == '--skip'])
    elif cmd == 'fork':
        cmd_fork(os.path.abspath(a[1]), a[2], a[a.index('--branch') + 1] if '--branch' in a else None,
                 [a[i + 1] for i, x in enumerate(a) if x == '--skip'])
    elif cmd == 'check':
        sys.exit(cmd_check(os.path.abspath(tree) if tree else root, bool(tree)))
    elif cmd == 'licence-proof':
        rest = [x for x in a[1:] if x != '--tree' and x != tree]
        sys.exit(cmd_licence_proof(os.path.abspath(tree) if tree else root, rest[0], rest[1] if len(rest) > 1 else 'HEAD', bool(tree)))
    elif cmd == 'safety-proof':
        sys.exit(cmd_safety_proof(root, a[1]))
    elif cmd == 'classify':
        repo = Repo(root)
        for p in a[1:]:
            c, why = repo.classify(p)
            print(p, c, why, '->', repo.new_path(p, c))
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
