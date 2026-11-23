#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Host-only tests of the G2 sequence with a fake Air and M5. No network, no device."""
from __future__ import annotations

import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import unittest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import g2  # noqa: E402

CYCLE = HERE / 'launcher/j313_cycle.py'
OK = dict(status='DARWIN_COMMAND_LINE_OBSERVED', command_line_observed=True, reset_attempts=1, reset_ok=True)


def done(code=0, stdout=b''):
    return subprocess.CompletedProcess('fake', code, stdout, b'')


class FakeProcess:
    def __init__(self, lines):
        self.stdout = io.StringIO(''.join(lines))

    def wait(self, timeout=None):
        return 0


class FakeRemote:
    """The Air as a small state machine: which stage 2 is on the ESP and which boot is running."""
    def __init__(self, result=OK, ready=True, returns=True, restore_ok=True, install_ok=True, m5_ok=True,
                 second_return=True, change_default=False):
        self.boot, self.running = 1, g2.ORIGINAL_STAGE2
        self.target, self.kept = 'original', 'absent'
        self.up = True
        self.log, self.m5_log = [], []
        self.result, self.ready, self.returns = result, ready, returns
        self.restore_ok, self.install_ok, self.m5_ok, self.second_return = restore_ok, install_ok, m5_ok, second_return
        self.change_default = change_default
        self.reboots = 0
        self.default = 'default_entry: Omarchy/linux-aurora'

    def linux(self):
        return dict(boot_id=f'boot-{self.boot}', kernel='7.2.11-6-1-ARCH', compatible=['apple,j313', 'apple,t8103'],
                    stage2=self.running, root_rw=True, oneshot=[], default_entry=[self.default])

    def reboot(self):
        self.reboots += 1
        target = {'original': g2.ORIGINAL_STAGE2, 'window build': g2.WINDOW_STAGE2}[self.target]
        if self.reboots == 1 and not self.returns or self.reboots == 2 and not self.second_return:
            self.up = False
            return
        self.boot += 1
        self.running = target
        if self.reboots == 2 and self.change_default:
            self.default = 'default_entry: something else'

    def esp(self, command):
        words = command.split()
        verb = words[5]
        execute = '--execute' in words
        report = dict(command=verb, steps=[], status='DRY_RUN_NOTHING_WRITTEN')
        code = 0
        if verb == 'install':
            report['steps'] = ['keep', 'install']
            if execute:
                if not self.install_ok:
                    return done(2, json.dumps(dict(status='REFUSED', reason='fake')).encode())
                self.target, self.kept = 'window build', 'original'
                report['status'] = 'DONE'
        elif verb == 'restore' and execute:
            if not self.restore_ok:
                return done(2, json.dumps(dict(status='REFUSED', reason='fake')).encode())
            report['status'] = 'DONE' if self.target != 'original' else 'NOTHING_TO_DO'
            self.target = 'original'
        elif verb == 'finalize' and execute:
            self.kept = 'absent'
            report['status'] = 'DONE'
        report.update(boot_bin=self.target, kept=self.kept)
        return done(code, json.dumps(report).encode())

    def air(self, command, stdin=None, timeout=60):
        self.log.append(command)
        if not self.up:
            return done(255)
        if 'python3 -I -c' in command:
            return done(0, json.dumps(self.linux()).encode())
        if 'python3 -I - ' in command:
            return self.esp(command)
        if 'systemctl reboot' in command:
            self.reboot()
            return done(255)
        if '/dev/shm/g2' in command:
            return done(0, g2.esp.CANDIDATE_SHA.encode() + b'  /dev/shm/g2/boot.bin\n')
        raise AssertionError('unexpected Air command: ' + command)

    def m5(self, command, stdin=None, timeout=120):
        self.m5_log.append(command)
        if stdin is not None and b'system_profiler' in stdin:
            value = dict(peers=[['1', 'peer']], rid0_port='1' if self.m5_ok else '2', macvdmtool=g2.PINS['macvdmtool_sha256'],
                         latch=False, handoff=False, packet_r6=True, host_source=True, venv=True, proxy_present=False)
            return done(0, json.dumps(value).encode())
        if ' verify ' in command:
            return done(0, json.dumps(dict(status='INPUTS_VERIFIED_NO_DEVICE_CONTACT')).encode())
        return done(0, b'')

    def m5_upload(self, directory, members, destination):
        self.m5_log.append('upload ' + destination)
        return True

    def m5_start(self, command):
        self.m5_log.append(command)
        if not self.ready:
            return FakeProcess(['refused\n'])
        return FakeProcess(['G2_READY\n', 'G2_RESULT ' + json.dumps(self.result) + '\n'])

    def sleep(self, seconds):
        pass


CONFIG = dict(air_ssh='a', air_known_hosts='k', m5_ssh='m', m5_host_key_alias='h', m5_work='/w', artifacts='/nonexistent',
              m5_thunderbolt_peer='peer')


class Sequence(unittest.TestCase):
    def setUp(self):
        self.verify = g2.verify_local
        g2.verify_local = lambda config: ['fake']
        self.inputs = g2.inputs
        here = Path(__file__)
        g2.inputs = lambda config: dict(raw=here, boot=here, packet=here.parent / 'packet', lab=here.parent / 'lab',
                                        inventory=here)
        self.wait = g2.time.monotonic
        ticks = iter(range(0, 100000, 60))
        g2.time.monotonic = lambda: next(ticks)

    def tearDown(self):
        g2.verify_local, g2.inputs, g2.time.monotonic = self.verify, self.inputs, self.wait

    def run_go(self, remote):
        messages = []
        try:
            return g2.go(CONFIG, remote, say=messages.append), None
        except g2.Stop as error:
            return None, str(error)

    def test_happy_path_restores_and_finalizes(self):
        remote = FakeRemote()
        result, error = self.run_go(remote)
        self.assertIsNone(error)
        self.assertEqual(result['status'], 'BOOT_OBSERVED_LINUX_RESTORED')
        self.assertEqual((remote.target, remote.kept, remote.running), ('original', 'absent', g2.ORIGINAL_STAGE2))
        self.assertEqual(remote.reboots, 2)
        self.assertTrue(any(' clear ' in command for command in remote.m5_log))

    def test_order_install_before_reboot_and_verify_before_install(self):
        remote = FakeRemote()
        self.run_go(remote)
        install = next(i for i, c in enumerate(remote.log) if 'install' in c and '--execute' in c)
        reboot = next(i for i, c in enumerate(remote.log) if 'systemctl reboot' in c)
        self.assertLess(install, reboot)
        self.assertTrue(any(' verify ' in command for command in remote.m5_log))

    def test_no_shell_still_restores(self):
        remote = FakeRemote(result=dict(status='NO_COMMAND_LINE_OBSERVED', command_line_observed=False, reset_attempts=1))
        result, error = self.run_go(remote)
        self.assertIsNone(error)
        self.assertEqual(result['status'], 'NO_SHELL_LINUX_RESTORED')
        self.assertEqual(remote.target, 'original')

    def test_m5_refusal_changes_nothing_on_the_air(self):
        remote = FakeRemote(m5_ok=False)
        result, error = self.run_go(remote)
        self.assertIn('receptacle 1', error)
        self.assertEqual((remote.target, remote.reboots), ('original', 0))

    def test_failed_install_never_reboots(self):
        remote = FakeRemote(install_ok=False)
        _, error = self.run_go(remote)
        self.assertIn('install failed', error)
        self.assertEqual(remote.reboots, 0)

    def test_m5_not_ready_restores_without_reboot(self):
        remote = FakeRemote(ready=False)
        _, error = self.run_go(remote)
        self.assertIn('did not become ready', error)
        self.assertEqual((remote.target, remote.reboots), ('original', 0))

    def test_linux_not_returning_stops_with_recovery_and_no_more_commands(self):
        remote = FakeRemote(returns=False)
        _, error = self.run_go(remote)
        self.assertIn('Do not reset the Air again', error)
        self.assertEqual(remote.target, 'window build')
        self.assertEqual(remote.reboots, 1)
        self.assertFalse(any(' clear ' in command for command in remote.m5_log))

    def test_unknown_worker_state_stops_without_clearing_the_latch(self):
        remote = FakeRemote(result=dict(status='WORKER_STATE_UNKNOWN_NO_RESET', reset_attempts=0))
        _, error = self.run_go(remote)
        self.assertIn('worker may still own', error)
        self.assertFalse(any(' clear ' in command for command in remote.m5_log))

    def test_failed_restore_keeps_the_original_copy(self):
        remote = FakeRemote(restore_ok=False)
        _, error = self.run_go(remote)
        self.assertIn('restore failed', error)
        self.assertEqual(remote.kept, 'original')
        self.assertFalse(any(' clear ' in command for command in remote.m5_log))

    def test_no_return_after_restore_prints_recovery(self):
        remote = FakeRemote(second_return=False)
        _, error = self.run_go(remote)
        self.assertIn('Do not reset the Air again', error)

    def test_a_changed_default_entry_stops_with_stage2_restored(self):
        remote = FakeRemote(change_default=True)
        _, error = self.run_go(remote)
        self.assertIn('default boot entry changed', error)
        self.assertEqual(remote.target, 'original')
        self.assertFalse(any(' clear ' in command for command in remote.m5_log))

    def test_refuses_an_air_that_is_not_in_the_expected_state(self):
        remote = FakeRemote()
        remote.running = 'something-else'
        _, error = self.run_go(remote)
        self.assertIn('not in the expected state', error)
        self.assertEqual((remote.target, remote.reboots), ('original', 0))


class Approval(unittest.TestCase):
    def test_go_and_rollback_need_the_exact_text(self):
        config = HERE / 'test-config-does-not-exist.json'
        for words in (['go'], ['go', '--approval', 'yes'], ['rollback', '--approval', g2.APPROVAL.lower()]):
            original, g2.load_config = g2.load_config, lambda path: CONFIG
            try:
                self.assertEqual(g2.main([*words, '--config', str(config)]), 1)
            finally:
                g2.load_config = original


class Arguments(unittest.TestCase):
    def test_pinned_arguments(self):
        words = g2.PINS['extra_bootargs'].split()
        self.assertEqual(set(words), {'sfsound=0', 'sftouchbar=0', 'sfm1tpmt=0'})
        for word in ('sfnvme=3', 'sfnvme_write=1', 'x sfnvme_part=a', 'pdnvme=1'):
            self.assertIsNotNone(g2.FORBIDDEN_ARGUMENT.search(word), word)
        self.assertIsNone(g2.FORBIDDEN_ARGUMENT.search(g2.PINS['guest_bootargs']))
        for word in ('rd=md0', 'sfsound=0', 'sftouchbar=0', 'sfm1tpmt=0'):
            self.assertIn(word, g2.PINS['guest_bootargs'].split())
        self.assertNotIn('rd=uuid', g2.PINS['guest_bootargs'])


class M5Cycle(unittest.TestCase):
    """j313_cycle.run with fake operations, loaded from the generated tree when it is given."""
    @classmethod
    def setUpClass(cls):
        import os
        lab = os.environ.get('G2_LAB')
        if not lab:
            raise unittest.SkipTest('set G2_LAB to the generated launcher tree')
        spec = importlib.util.spec_from_file_location('j313_cycle_test', Path(lab) / 'tools/j313_cycle.py')
        cls.module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = cls.module
        spec.loader.exec_module(cls.module)
        cls.base = cls.module.base
        cls.cycle = cls.module.cycle

    def make_ops(self, tmp, fail_guest=False, cdc_after=True, unknown=False):
        base = self.base
        class Ops:
            def __init__(self):
                self.resets, self.armed = 0, False
                self.cycle = None
                self.count = 0
                self.events = []
            def start_cycle(self, number):
                self.cycle = Path(tmp) / f'{number:03d}'
                self.cycle.mkdir()
            def save(self, name, data):
                path = self.cycle / name
                path.write_bytes(data if isinstance(data, bytes) else json.dumps(data).encode())
            def arm(self):
                self.armed = True
                self.events.append('arm')
            def clock(self):
                self.count += 1
                return self.count
            def sleep(self, seconds):
                pass
            def discover(self):
                self.events.append('discover')
                if not self.events.count('child-guest'):
                    number = self.events.count('child-bootstrap') + 1
                    return dict(callout=f'/dev/cu.usbmodem{number}', IORegistryEntryID=number, sessionID=number)
                return dict(callout='/dev/cu.usbmodem9', IORegistryEntryID=9, sessionID=9) if cdc_after else None
            def child(self, phase, port):
                self.events.append('child-' + phase)
                directory = self.cycle / phase
                directory.mkdir()
                if phase == 'bootstrap':
                    (directory / 'vector-ack.json').write_text(json.dumps(dict(
                        status='VECTOR_ACKNOWLEDGED_RUNTIME_UNVERIFIED', runtime_verified=False)))
                else:
                    if unknown:
                        raise base.WorkerUnknown('fake')
                    (directory / 'host-result.json').write_text(json.dumps(dict(status='HOST_WORKER_EXITED', worker_returncode=0)))
                return directory
            def reset(self):
                self.events.append('reset')
                self.resets += 1
        return Ops()

    def execute(self, **options):
        import tempfile
        self.cycle.save_inputs = lambda ops, bootstrap, candidate: None
        observed = not options.get('fail_guest')
        self.cycle.console_observation = lambda directory, candidate: observed
        with tempfile.TemporaryDirectory() as tmp:
            ops = self.make_ops(tmp, **options)
            lines = []
            result = self.module.run(ops, {}, {}, say=lambda *words, **kw: lines.append(' '.join(words)))
            return ops, result, lines

    def test_reports_ready_only_after_arming_and_resets_once(self):
        ops, result, lines = self.execute()
        self.assertEqual(lines, ['G2_READY'])
        self.assertLess(ops.events.index('arm'), ops.events.index('child-bootstrap'))
        self.assertEqual((ops.resets, result['status']), (1, 'DARWIN_COMMAND_LINE_OBSERVED'))

    def test_a_guest_that_ran_without_a_shell_still_resets_once(self):
        ops, result, _ = self.execute(fail_guest=True)
        self.assertEqual((result['status'], ops.resets), ('NO_COMMAND_LINE_OBSERVED', 1))

    def test_no_proxy_at_the_end_means_no_reset(self):
        ops, result, _ = self.execute(cdc_after=False)
        self.assertEqual(ops.resets, 0)

    def test_unknown_worker_never_resets(self):
        ops, result, _ = self.execute(unknown=True)
        self.assertEqual((result['status'], ops.resets), ('WORKER_STATE_UNKNOWN_NO_RESET', 0))

    def test_the_m5_cannot_touch_the_airs_linux(self):
        ops = self.module.Ops.__new__(self.module.Ops)
        for call in (lambda: ops.ssh('x'), ops.observe, ops.reboot, ops.refresh_neighbor):
            with self.assertRaises(RuntimeError):
                call()


if __name__ == '__main__':
    unittest.main()
