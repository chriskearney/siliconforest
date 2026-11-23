#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""One J313 RAM boot from the M5: proxy, guest, capture, and at most one reset.

This runs on the M5 inside the generated launcher tree. It never connects to the Air's Linux: the
builder owns the Air's SSH session (ESP swap, reboot, Linux check). The two sides meet at the line
G2_READY, printed once the inputs are verified and the M5 is waiting for the proxy.

Without --execute it only prints what it would do. The shared controller lock is held throughout,
and the shared incomplete latch stays armed until `clear` runs after the builder has verified a new
Linux boot, so no bench tool can reset the machine on this port while the outcome is unknown.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys

LAB = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(LAB))
from tools import m1_bringup_cycle as cycle  # noqa: E402
from tools import m1_kernel_cycle as base  # noqa: E402

WAIT_FOR_PROXY = 150


class Ops(cycle.Ops):
    """The bring-up operations with every Linux and SSH path removed."""
    def ssh(self, remote, timeout=10):
        raise RuntimeError('the M5 does not connect to the Air')

    def observe(self):
        raise RuntimeError('the builder checks Linux on the Air')

    def reboot(self):
        raise RuntimeError('the builder reboots the Air')

    def refresh_neighbor(self):
        raise RuntimeError('no address is configured for the Air on the M5')


def run(ops, bootstrap, candidate, say=print):
    """Same order and failure rules as m1_bringup_cycle.run_attempt, from the proxy onward."""
    ops.start_cycle(1)
    result = dict(status='NOT_STARTED', command_line_observed=False, reset_attempts=0, reset_ok=None,
                  proxy_seen=False, workers_stopped=True)
    workers_stopped, bootstrap_attempted = True, False
    try:
        cycle.save_inputs(ops, bootstrap, candidate)
        ops.arm()
        say('G2_READY', flush=True)
        initial = base.wait_cdc(ops, WAIT_FOR_PROXY)
        result['proxy_seen'] = True
        ops.save('bootstrap-port.json', initial)
        bootstrap_attempted, workers_stopped = True, False
        directory = ops.child('bootstrap', initial['callout'])
        workers_stopped = True
        ack = base.read_json(directory / 'vector-ack.json')
        base.require(ack.get('status') == 'VECTOR_ACKNOWLEDGED_RUNTIME_UNVERIFIED' and
                     ack.get('runtime_verified') is False, 'Missing bootstrap vector acknowledgement')
        selected = base.wait_cdc(ops, 25, previous=initial)
        ops.save('guest-port.json', selected)
        workers_stopped = False
        guest = ops.child('guest', selected['callout'])
        workers_stopped = True
        host_result = base.read_json(guest / 'host-result.json')
        result['guest_host_status'] = host_result['status']
        result['guest_worker_returncode'] = host_result['worker_returncode']
        result['command_line_observed'] = cycle.console_observation(guest, candidate)
        result['status'] = 'DARWIN_COMMAND_LINE_OBSERVED' if result['command_line_observed'] else 'NO_COMMAND_LINE_OBSERVED'
    except (Exception, KeyboardInterrupt) as error:
        result.update(status='EXPERIMENT_STOPPED', experiment_error=f'{type(error).__name__}: {error}')
    result['workers_stopped'] = workers_stopped
    if not workers_stopped:
        # A worker may still own the device. Never reset under it.
        result['status'] = 'WORKER_STATE_UNKNOWN_NO_RESET'
    elif bootstrap_attempted:
        try:
            present = ops.discover()
            ops.save('recovery-cdc.json', dict(primary_cdc=present))
            if present is not None:
                ops.save('reset-intent.json', dict(attempt=1, workers_stopped=True, primary_cdc=present,
                                                   args=['reboot', 'serial']))
                result['reset_attempts'] = 1
                ops.reset()
                result['reset_ok'] = True
        except Exception as error:
            result['reset_ok'] = False
            result['reset_error'] = f'{type(error).__name__}: {error}'
    ops.save('result.json', result)
    return result


def parser():
    value = base.parser()
    value.description = __doc__
    value.add_argument('command', nargs='?', choices=('run', 'clear', 'verify'), default='run')
    value.add_argument('--candidate', type=Path)
    value.add_argument('--launcher-sha256')
    value.add_argument('--inspector-sha256')
    value.add_argument('--runtime', type=int, default=300)
    value.add_argument('--linux-verified', action='store_true')
    value.set_defaults(private_root=base.WORK / 'j313-g2-cycles', handoff=None)
    return value


def clear(args):
    base.require(args.linux_verified, 'clear needs --linux-verified from the builder')
    if base.INCOMPLETE.exists():
        record = base.read_json(base.INCOMPLETE)
        base.require('j313-g2-cycles' in record.get('run_directory', ''), 'the latch belongs to another cycle')
        base.INCOMPLETE.unlink()
        base.sync_directory(base.INCOMPLETE.parent)
        return dict(status='LATCH_CLEARED')
    return dict(status='NO_LATCH')


def main(argv=None):
    args = parser().parse_args(argv)
    if args.command == 'verify':
        # Every input check the run makes, with no lock, device or network.
        try:
            bootstrap, candidate, module = cycle.verify(args)
            image = candidate['kernel']
            print(json.dumps(dict(status='INPUTS_VERIFIED_NO_DEVICE_CONTACT', members=len(image['members']),
                                  bootargs=module.guest_bootargs(module.verify_inputs(argparse.Namespace(
                                      manifest=args.candidate, bootstrap_manifest=args.manifest,
                                      host_source=args.host_source, inventory=args.inventory))),
                                  artifacts=candidate['artifacts'])))
            return 0
        except Exception as error:
            print(json.dumps(dict(status='INPUTS_REFUSED', error=f'{type(error).__name__}: {error}')))
            return 1
    if not args.execute:
        print(json.dumps(dict(status='OFFLINE_PLAN_ONLY', device_contacted=False, command=args.command)))
        return 0
    try:
        base.require(args.confirm_recovery == base.CONFIRMATION, 'Recovery confirmation required')
        if args.command == 'clear':
            print(json.dumps(clear(args)))
            return 0
        base.require(args.cycles == 1 and args.candidate and 5 <= args.runtime <= 900,
                     'One candidate and a runtime of at most 900 seconds')
        os.umask(0o077)
        with Ops(args) as ops:
            bootstrap, candidate, _ = cycle.verify(args)
            result = run(ops, bootstrap, candidate)
        print('G2_RESULT ' + json.dumps(result), flush=True)
        return 0 if result['status'] == 'DARWIN_COMMAND_LINE_OBSERVED' else 1
    except Exception as error:
        print('G2_RESULT ' + json.dumps(dict(status='CONTROLLER_STOPPED_REQUIRES_REVIEW', error=str(error),
                                             command_line_observed=False, reset_attempts=0)), flush=True)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
