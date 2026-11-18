# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""The one door every change to the disk goes through.

Every command that can change the partition table, a filesystem, the boot policy or the power
state, and every raw write to a disk device, is passed to `Gate.run` or `Gate.open`, whether
our code issues it or the Asahi installer's code does (sf_engine.py routes the engine's
`diskutil`, `newfs_msdos`, `bless`, `shutdown` and raw device opens here). The gate

  * refuses anything the confirmed plan does not name: which container may be resized and to
    exactly what size, after which partition new partitions may be added and how much space
    they may take, which devices may be formatted or written raw, which volume may be blessed,
    and in an uninstall which container and partitions may be deleted;
  * after every change, reads the partition table again and stops everything if a partition
    that existed before moved, changed size or identity (other than the planned resize);
  * writes a journal line before and after each change (the log and the resume record);
  * in simulation mode hands the command to a model of the disk instead of running it, which
    is how the tests drive the whole installer on Linux.

Read-only commands (diskutil list/info/mount, hdiutil attach -readonly, ioreg, bputil -d, ...)
pass through unchanged.
"""
import json
import os
import re
import subprocess
import time

READ_ONLY_DISKUTIL = {'list', 'info', 'mount', 'unmount', 'activity'}
READ_ONLY_APFS = {'list', 'listVolumeGroups', 'listSnapshots', 'listUsers', 'listCryptoUsers'}
PASS = {'hdiutil', 'ioreg', 'nvram', 'scutil', 'sw_vers', 'sysctl', 'chflags', 'xattr', 'mount', 'caffeinate',
        'tmutil', 'fdesetup', 'pmset', 'stat', 'dseditgroup', 'id', 'ditto', 'cp', 'sync'}
PART_TYPES = {'apfs': 'apfs', 'APFS': 'apfs', '%EFI%': 'efi', '%Linux%': 'linux'}


class Refused(Exception):
    pass


def _dev(arg):
    return re.sub(r'^/dev/r?', '', arg or '')


def _container_of(dev):
    m = re.match(r'^(disk\d+)', dev)
    return m.group(1) if m else ''


class Gate:
    def __init__(self, plan, reader, journal=None, execute=None, log=print):
        """plan: the confirmed plan (sf_plan); reader(): the current sf_disk.Layout;
        execute(argv, input) -> (rc, output): None = really run it."""
        self.plan, self.reader, self.log = plan, reader, log
        self.journal = journal
        self.execute = execute
        self.simulated = execute is not None
        self.before = {p.dev: (p.offset, p.size, p.uuid) for p in reader().real_parts()}
        self.created = {}           # dev -> kind ('apfs', 'efi', 'linux')
        self.created_containers = set()
        self.after_ok = {plan.get('after')} if plan.get('kind') == 'install' else set()
        self.used = 0
        self.resized = False
        self.grown = False
        self.removed = set()
        self.calls = []
        self._last_uuid = {}
        self.write_dirs = ()

    # ---- journal -------------------------------------------------------------------------
    def note(self, **entry):
        entry['time'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
        if self.journal:
            with open(self.journal, 'a') as fd:
                fd.write(json.dumps(entry, sort_keys=True) + '\n')

    # ---- the rules -----------------------------------------------------------------------
    def classify(self, argv):
        """None if read-only, else the name of the rule that must allow it."""
        prog = os.path.basename(argv[0])
        if prog == 'diskutil':
            verb = argv[1] if len(argv) > 1 else ''
            if verb in READ_ONLY_DISKUTIL:
                return None
            if verb == 'apfs':
                sub = argv[2] if len(argv) > 2 else ''
                if sub in READ_ONLY_APFS or (sub == 'resizeContainer' and 'limits' in argv):
                    return None
                return 'apfs ' + sub
            return verb
        if prog == 'bless':
            return 'setBoot' if '--setBoot' in argv else None
        if prog == 'bputil':
            return None if argv[1:2] == ['-d'] else 'bputil'
        if prog in ('newfs_msdos', 'shutdown', 'reboot', 'kmutil', 'gpt', 'pdisk', 'fdisk', 'dd', 'asr', 'csrutil', 'nvram-write'):
            return prog
        if prog in PASS:
            return None
        return 'unknown:' + prog

    def check(self, rule, argv):
        p, kind = self.plan, self.plan.get('kind')
        a = argv
        if kind == 'install':
            if rule == 'apfs resizeContainer':
                r = p.get('resize')
                if not r or self.resized or _dev(a[3]) != r['store'] or a[4] != str(r['to_bytes']):
                    return 'the plan resizes %s to %s bytes, once' % ((r or {}).get('store'), (r or {}).get('to_bytes'))
                return None
            if rule == 'addPartition':
                after, ptype, size = _dev(a[2]), a[3], int(a[5])
                if after not in self.after_ok:
                    return 'new partitions go after %s only' % ', '.join(sorted(x for x in self.after_ok if x))
                if ptype not in PART_TYPES:
                    return 'partition type %s is not one the plan adds' % ptype
                if self.used + size > p['total_bytes'] + (1 << 20) * 4:
                    return 'the new partitions would take more than the planned %d bytes' % p['total_bytes']
                return None
            if rule in ('apfs addVolume', 'apfs changeVolumeRole', 'rename', 'apfs updatePreboot'):
                target = _container_of(_dev(a[3] if rule.startswith('apfs') else a[2]))
                if rule == 'apfs updatePreboot':
                    # Apple's own maintenance of macOS's Preboot list of administrators (Asahi main.py check_cur_os)
                    return None
                if target not in self.created_containers:
                    return '%s is not a container this installation created' % target
                return None
            if rule == 'newfs_msdos':
                if self.created.get(_dev(a[-1])) != 'efi':
                    return '%s is not the boot partition this installation created' % a[-1]
                return None
            if rule == 'setBoot':
                dev = _dev(a[a.index('--device') + 1]) if '--device' in a else ''
                if _container_of(dev) not in self.created_containers:
                    return 'only the new SiliconForest volume may be blessed'
                return None
            if rule in ('shutdown',):
                return None
        if kind == 'uninstall':
            remove = {r['dev']: r for r in p['remove']}
            if rule == 'apfs deleteContainer':
                ok = [r for r in p['remove'] if r.get('container') == _dev(a[3]) or (r['action'] == 'deleteContainer' and r['dev'] == _dev(a[3]))]
                return None if ok else '%s is not the SiliconForest container' % a[3]
            if rule == 'eraseVolume':
                uuids = {r['uuid'] for r in p['remove'] if r.get('uuid')}
                cur = next((q for q in self.reader().real_parts() if q.dev == _dev(a[4])), None) if len(a) > 4 else None
                if a[2:4] != ['free', 'free'] or cur is None or (cur.dev not in remove and cur.uuid not in uuids):
                    return 'only "eraseVolume free free" of a SiliconForest partition is allowed'
                return None
            if rule == 'apfs resizeContainer':
                g = p.get('grow')
                if not g or _dev(a[3]) != g['store'] or a[4] != '0':
                    return 'only growing macOS (%s) back over the freed space is allowed' % (g or {}).get('store')
                return None
        return 'the plan (%s) does not include %s' % (kind, rule)

    # ---- after a change: nothing that existed may have moved --------------------------------
    def verify(self, what):
        lay = self.reader()
        now = {q.dev: (q.offset, q.size, q.uuid) for q in lay.real_parts()}
        p = self.plan
        for dev, (off, size, uuid) in self.before.items():
            if p.get('kind') == 'uninstall' and dev in {r['dev'] for r in p['remove']} and dev in self.removed:
                continue
            cur = next((v for v in now.values() if v[2] == uuid and uuid), now.get(dev))
            if cur is None:
                raise Refused('STOP after %s: partition %s (%s) has gone' % (what, dev, uuid))
            if cur[0] != off:
                raise Refused('STOP after %s: partition %s moved' % (what, dev))
            if cur[1] != size:
                r, g = p.get('resize'), p.get('grow')
                if r and dev == r['store'] and self.resized and cur[1] == r['to_bytes']:
                    continue
                if g and dev == g['store'] and self.grown and cur[1] > size:
                    continue
                raise Refused('STOP after %s: partition %s changed size (%d -> %d)' % (what, dev, size, cur[1]))
        return lay

    # ---- the door ------------------------------------------------------------------------
    def run(self, argv, why='', input=None):
        argv = [str(x) for x in argv]
        rule = self.classify(argv)
        if rule is None:
            return self._exec(argv, input, quiet=True)
        reason = self.check(rule, argv)
        if reason is not None:
            self.note(step=why, argv=argv, state='refused', reason=reason)
            raise Refused('refused %s: %s' % (' '.join(argv), reason))
        if rule in ('eraseVolume', 'apfs deleteContainer'):
            t = _dev(argv[-1])
            cur = next((q for q in self.reader().real_parts() if q.dev == t or (q.container is not None and q.container.ref == t)), None)
            self._last_uuid = {t: cur.uuid if cur is not None else ''}
        self.note(step=why, argv=argv, state='start')
        self.log('%s %s' % ('SIMULATED:' if self.simulated else 'running:', ' '.join(a if 'pass' not in a.lower() else '***' for a in argv)))
        rc, out = self._exec(argv, input)
        self.note(step=why, argv=argv, state='done' if rc == 0 else 'failed', rc=rc)
        if rc != 0:
            raise subprocess.CalledProcessError(rc, argv, out)
        self._after(rule, argv)
        return rc, out

    def _exec(self, argv, input, quiet=False):
        self.calls.append(argv)
        if self.execute is not None:
            return self.execute(argv, input)
        res = subprocess.run(argv, input=input, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        return res.returncode, res.stdout

    def _after(self, rule, argv):
        if rule == 'apfs resizeContainer':
            if self.plan['kind'] == 'install':
                self.resized = True
            else:
                self.grown = True
            self.verify(rule)
        elif rule == 'addPartition':
            after = _dev(argv[2])
            lay = self.verify(rule)
            prev = next((q for q in lay.parts if q.dev == after), None)
            new = lay.after(prev) if prev is not None else None
            lo, hi = self.plan['gap_offset'], self.plan['gap_offset'] + self.plan['gap_bytes']
            if new is None or new.free or new.dev in self.before or not (lo <= new.offset and new.end <= hi):
                raise Refused('STOP after addPartition: no new partition inside the planned free space after %s' % after)
            self.created[new.dev] = PART_TYPES[argv[3]]
            if new.container is not None:
                self.created_containers.add(new.container.ref)
            elif PART_TYPES[argv[3]] == 'apfs':
                self.created_containers.add(_container_of(new.dev))
            self.after_ok.add(new.dev)
            self.used += new.size
            self.note(step='created', dev=new.dev, kind=self.created[new.dev], uuid=new.uuid, offset=new.offset, bytes=new.size)
        elif rule in ('eraseVolume', 'apfs deleteContainer'):
            target = _dev(argv[-1])
            for r in self.plan['remove']:
                if r['dev'] == target or r.get('container') == target or r['uuid'] == self._last_uuid.get(target):
                    self.removed.add(r['dev'])
            self.verify(rule)

    def write_file(self, path, data):
        """Files on the SFBOOT partition (update): only below a directory the executor opened."""
        real = os.path.realpath(path)
        if not any(real.startswith(os.path.realpath(d) + os.sep) for d in self.write_dirs):
            raise Refused('refused write to %s: not on the SiliconForest boot partition' % path)
        self.note(step='write', path=path, bytes=len(data), state='start')
        with open(path, 'wb') as fd:
            fd.write(data)
            fd.flush()
            os.fsync(fd.fileno())
        self.note(step='write', path=path, state='done')

    def open(self, path, mode='rb', *args, **kw):
        """open() for the engine's modules: raw writes only to a root partition created here."""
        if path.startswith('/dev/') and any(c in mode for c in 'wa+'):
            dev = _dev(path)
            if self.created.get(dev) != 'linux':
                self.note(step='open', argv=[path, mode], state='refused')
                raise Refused('refused raw write to %s: not the root partition this installation created' % path)
            self.note(step='open', argv=[path, mode], state='start')
            self.log('%s raw write to %s' % ('SIMULATED:' if self.simulated else 'opening', path))
            if self.execute is not None and hasattr(self.execute, 'open_device'):
                return self.execute.open_device(path, mode, *args, **kw)
        return open(path, mode, *args, **kw)

    def system(self, command):
        """os.system for the engine (Asahi calls `shutdown -h now` / `shutdown -r now` this way)."""
        argv = command.split()
        self.run(argv, why='shutdown')
        return 0
