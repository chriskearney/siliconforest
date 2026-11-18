#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Pour fetched bottles into a Homebrew prefix the way `brew` does, on the host, and make a
disk image of it for the guest to mount at /opt/homebrew.

For each formula (and its dependency closure, from runs/homebrew/closure-<tag>.json):
  1. copy the unpacked bottle to <prefix>/Cellar/<name>/<version>/
  2. relocate: `@@HOMEBREW_PREFIX@@`, `@@HOMEBREW_CELLAR@@`, `@@HOMEBREW_REPOSITORY@@`,
     `@@HOMEBREW_LIBRARY@@`, `@@HOMEBREW_PERL@@` -> the real paths, in Mach-O install names
     and rpaths (hb_macho.rewrite_names) and in text files
  3. bring the ad-hoc signature of every changed Mach-O back in line (hb_macho.resign)
  4. <prefix>/opt/<name> -> ../Cellar/<name>/<version>; unless keg-only, symlink the keg's
     bin sbin lib include share etc Frameworks entries into the prefix
  5. the declarative post-install steps of the formula index that matter without macOS
     (symlinks; ca-certificates' bundle)
The bottles' machine code is not modified in any other way.

  hb_pour.py --name first jq tree ...     -> runs/homebrew/prefix/first/ (the tree)
                                             runs/homebrew/prefix/first.img (GPT, one ext4
                                             partition with the tree at its root)
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hb_macho  # noqa: E402

LAB = Path(__file__).resolve().parents[3] if len(Path(__file__).resolve().parents) > 3 else Path(__file__).resolve().parent
# SF_HB_RUNS: another working directory of the same layout (the release image's recipe pours in its build directory)
RUNS = Path(os.environ['SF_HB_RUNS']) if os.environ.get('SF_HB_RUNS') else LAB / 'runs/homebrew'
PREFIX = '/opt/homebrew'
PLACEHOLDERS = [('@@HOMEBREW_PREFIX@@', PREFIX), ('@@HOMEBREW_CELLAR@@', PREFIX + '/Cellar'),
                ('@@HOMEBREW_REPOSITORY@@', PREFIX), ('@@HOMEBREW_LIBRARY@@', PREFIX + '/Library'),
                ('@@HOMEBREW_PERL@@', PREFIX + '/opt/perl/bin/perl')]
LINK_DIRS = ('bin', 'sbin', 'lib', 'include', 'share', 'etc', 'Frameworks')


def replace_all(s):
    for a, b in PLACEHOLDERS:
        s = s.replace(a, b)
    return s


def relocate_file(path, stats):
    with open(path, 'rb') as f:
        data = f.read()
    if hb_macho.is_macho(data[:8]) and not path.name.endswith(('.a', '.o')):
        try:
            m = hb_macho.MachO(data)
        except (ValueError, IndexError):
            return
        if m.fat:
            stats['fat-skipped'] += 1
            return
        try:
            new, changed = hb_macho.rewrite_names(data, replace_all)
        except ValueError as e:
            stats['errors'].append('%s: %s' % (path, e))
            return
        # A bottle's own signature must also still hold before we touch it: count the ones
        # that arrive broken (none expected).
        if hb_macho.verify(data):
            stats['arrived-invalid'] += 1
        if changed:
            new, slots, note = hb_macho.resign(new)
            stats['macho-relocated'] += 1
            if note != 'ad-hoc':
                stats['errors'].append('%s: signature %s' % (path, note))
            mode = path.stat().st_mode
            os.chmod(path, mode | 0o200)
            path.write_bytes(new)
            os.chmod(path, mode)
        return
    if b'@@HOMEBREW_' in data and b'\0' not in data[:8192]:
        new = data
        for a, b in PLACEHOLDERS:
            new = new.replace(a.encode(), b.encode())
        if new != data:
            mode = path.stat().st_mode
            os.chmod(path, mode | 0o200)
            path.write_bytes(new)
            os.chmod(path, mode)
            stats['text-relocated'] += 1


def link_tree(src, dst, prefix_root, conflicts):
    """Symlink every file of src into dst (directories are made, not linked), relative."""
    for entry in sorted(os.scandir(src), key=lambda e: e.name):
        s, d = Path(entry.path), dst / entry.name
        if entry.is_dir(follow_symlinks=False):
            d.mkdir(parents=True, exist_ok=True)
            link_tree(s, d, prefix_root, conflicts)
        else:
            if d.is_symlink() or d.exists():
                conflicts.append(str(d.relative_to(prefix_root)))
                continue
            d.parent.mkdir(parents=True, exist_ok=True)
            os.symlink(os.path.relpath(s, d.parent), d)


def expand(template, name, version):
    return (template.replace('{{etc}}', PREFIX + '/etc').replace('{{pkgetc}}', PREFIX + '/etc/' + name)
            .replace('{{pkgshare}}', PREFIX + '/opt/%s/share/%s' % (name, name)).replace('{{prefix}}', PREFIX + '/opt/' + name)
            .replace('{{var}}', PREFIX + '/var').replace('{{version}}', version))


def post_install(root, name, version, steps, notes):
    host = lambda p: root / os.path.relpath(p, PREFIX)      # noqa: E731
    for step in steps or []:
        if step.get('type') == 'symlink' and 'path' in step.get('source', {}) and 'path' in step.get('target', {}):
            src, dst = expand(step['source']['path'], name, version), expand(step['target']['path'], name, version)
            if '{{' in src + dst:
                notes.append('%s: post-install symlink not understood: %s' % (name, json.dumps(step)[:120]))
                continue
            h = host(dst)
            h.parent.mkdir(parents=True, exist_ok=True)
            if h.is_symlink() or h.exists():
                h.unlink()
            os.symlink(src, h)
        elif name == 'ca-certificates' and step.get('type') == 'run':
            # libexec/post-install <bundle> <out>: on macOS it adds the keychain's trusted
            # roots to Mozilla's bundle. There is no keychain here: the bundle alone.
            out = root / 'etc/ca-certificates/cert.pem'
            out.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(root / 'Cellar' / name / version / 'share/ca-certificates/cacert.pem', out)
        elif step.get('type') == 'set_permissions':
            pass
        else:
            notes.append('%s: post-install step skipped: %s' % (name, json.dumps(step)[:160]))


def pour(root, name, rec, tag, steps, stats, notes):
    version = rec['version']
    src = RUNS / 'kegs' / tag / name / version
    keg = root / 'Cellar' / name / version
    keg.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['cp', '-a', '--reflink=auto', str(src), str(keg)], check=True)
    for dirpath, _dirs, files in os.walk(keg):
        for f in files:
            p = Path(dirpath) / f
            if p.is_symlink():
                t = os.readlink(p)
                if '@@HOMEBREW_' in t:
                    p.unlink()
                    os.symlink(replace_all(t), p)
            else:
                relocate_file(p, stats)
    (root / 'opt').mkdir(exist_ok=True)
    os.symlink('../Cellar/%s/%s' % (name, version), root / 'opt' / name)
    if not rec.get('keg_only'):
        conflicts = []
        for d in LINK_DIRS:
            if (keg / d).is_dir():
                (root / d).mkdir(exist_ok=True)
                link_tree(keg / d, root / d, root, conflicts)
        if conflicts:
            notes.append('%s: %d link conflicts (first kept), e.g. %s' % (name, len(conflicts), conflicts[0]))
    post_install(root, name, version, steps, notes)


def make_image(root, image, extra_mb, owner='0:0'):
    """GPT disk, one ext4 partition holding the tree. Files are owned by root in the image."""
    used = int(subprocess.run(['du', '-sm', str(root)], capture_output=True, text=True, check=True).stdout.split()[0])
    size_mb = int(used * 1.25) + extra_mb
    fs = image.with_suffix('.fs')
    fs.unlink(missing_ok=True)
    subprocess.run(['truncate', '-s', '%dM' % size_mb, str(fs)], check=True)
    # Features as the storage stream's working image had them (extents, 64bit, flex_bg,
    # metadata_csum): the defaults of mke2fs, 4096-byte blocks.
    subprocess.run(['fakeroot', 'sh', '-c', 'chown -R "$1" "$2" && mke2fs -q -t ext4 -b 4096 -L homebrew -E root_owner="$1" -d "$2" "$3"',
                    'sh', owner, str(root), str(fs)], check=True)
    image.unlink(missing_ok=True)
    subprocess.run(['truncate', '-s', '%dM' % (size_mb + 2), str(image)], check=True)
    subprocess.run(['sfdisk', '-q', str(image)], input='label: gpt\nstart=2048, size=%d, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=homebrew\n' % (size_mb * 2048),
                   text=True, check=True)
    subprocess.run(['dd', 'if=' + str(fs), 'of=' + str(image), 'bs=1M', 'seek=1', 'conv=notrunc,sparse', 'status=none'], check=True)
    fs.unlink()
    return size_mb


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('formulae', nargs='*')
    p.add_argument('--list', type=Path)
    p.add_argument('--tag', default='arm64_tahoe')
    p.add_argument('--name', required=True)
    p.add_argument('--skip', default='', help='comma-separated formulae to leave out (with what only they need)')
    p.add_argument('--extra', type=Path, action='append', default=[], metavar='DIR', help='directory copied to <prefix>/.sf/ (tests, scripts)')
    p.add_argument('--free-mb', type=int, default=256, help='free space in the image for the guest to write')
    p.add_argument('--no-image', action='store_true')
    p.add_argument('--owner', default='0:0', help='uid:gid that owns the prefix in the image (brew refuses to run as root: give it a user)')
    p.add_argument('--brew', type=Path, metavar='CHECKOUT', help='also install the Homebrew client itself: this checkout of github.com/Homebrew/brew '
                   'becomes the prefix (bin/brew, Library/; on Apple Silicon the repository is the prefix), and the portable-ruby bottle '
                   '(hb_fetch.py portable-ruby) is unpacked where `brew vendor-install ruby` would put it')
    a = p.parse_args()
    import collections
    closure = {r['name']: r for r in json.loads((RUNS / ('closure-%s.json' % a.tag)).read_text())}
    names = list(a.formulae)
    if a.list:
        names += [l.split('#')[0].strip() for l in a.list.read_text().splitlines() if l.split('#')[0].strip()]
    index = {}
    for f in json.loads((RUNS / 'api/formula.json').read_text()):
        index[f['name']] = f
        for al in f.get('aliases', []) + f.get('oldnames', []):
            index.setdefault(al, f)
    skip = set(filter(None, a.skip.split(',')))
    order = []

    def visit(n):
        n = index[n]['name']
        if n in order or n in skip:
            return
        for d in closure[n]['dependencies']:
            visit(d)
        order.append(n)
    for n in names:
        visit(n)
    root = RUNS / 'prefix' / a.name
    if root.exists():
        subprocess.run(['chmod', '-R', 'u+w', str(root)], check=True)
        shutil.rmtree(root)
    root.mkdir(parents=True)
    stats = collections.Counter()
    stats = dict(errors=[], **{k: 0 for k in ('macho-relocated', 'text-relocated', 'fat-skipped', 'arrived-invalid')})
    notes = []
    for n in order:
        pour(root, n, closure[n], a.tag, index[n].get('post_install_steps'), stats, notes)
    if a.brew:
        for item in ('bin/brew', 'Library', 'completions', 'LICENSE.txt', '.git'):
            src = a.brew / item
            if not src.exists() and item == '.git':
                continue      # a source archive of the client (the release image) has no history
            if src.is_dir():
                subprocess.run(['cp', '-a', '--reflink=auto', str(src), str(root / item)], check=True)
            else:
                (root / item).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, root / item)
        want = (a.brew / 'Library/Homebrew/vendor/portable-ruby-version').read_text().strip()
        ruby = RUNS / 'kegs' / a.tag / 'portable-ruby' / want
        if not ruby.is_dir():
            raise SystemExit('portable-ruby %s is not fetched (hb_fetch.py portable-ruby)' % want)
        vendor = root / 'Library/Homebrew/vendor/portable-ruby'
        vendor.mkdir(parents=True, exist_ok=True)
        subprocess.run(['cp', '-a', '--reflink=auto', str(ruby), str(vendor / want)], check=True)
        os.symlink(want, vendor / 'current')
        notes.append('brew client staged with portable-ruby ' + want)
    for d in ('etc', 'var', 'bin', 'lib', 'share'):
        (root / d).mkdir(exist_ok=True)
    for extra in a.extra:
        shutil.copytree(extra, root / '.sf', dirs_exist_ok=True)
    summary = dict(formulae=order, stats=stats, notes=notes)
    if not a.no_image:
        summary['image'] = str(RUNS / 'prefix' / (a.name + '.img'))
        summary['image_mb'] = make_image(root, RUNS / 'prefix' / (a.name + '.img'), a.free_mb, a.owner)
    (RUNS / 'prefix' / (a.name + '.json')).write_text(json.dumps(summary, indent=1) + '\n')
    print(json.dumps(dict(summary, formulae=len(order)), indent=1))
    return 1 if stats['errors'] else 0


if __name__ == '__main__':
    sys.exit(main())
