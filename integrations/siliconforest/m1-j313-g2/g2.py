#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""The G2 RAM boot of SiliconForest on the M1 MacBook Air (J313), from the builder.

  g2.py plan                      offline: verify every input and print the exact sequence
  g2.py go --approval TEXT        run it: swap stage 2, RAM boot, return to Linux, restore stage 2
  g2.py rollback --approval TEXT  from Linux: put the original stage 2 back and verify it

Only `plan` is safe without Chris's approval. `plan` opens no network connection. The Air's
address, login and pinned host key, and the M5's, are in a private config outside the repository.

The builder owns the Air's SSH session. The M5 owns the proxy and the one possible reset. Once
stage 2 has been swapped, every exit path tries to restore it if the Air's Linux can be reached.
There is never a second reset: if Linux does not return, this stops and prints the recovery steps.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import shlex
import subprocess
import sys
import threading
import time

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / 'esp'))
import j313_esp as esp  # noqa: E402

APPROVAL = 'Chris approves the temporary J313 G2 ESP swap and RAM boot'
PINS = json.loads((HERE / 'g2-pins.json').read_text())
ORIGINAL_STAGE2 = esp.ORIGINAL_STAGE2
WINDOW_STAGE2 = PINS['window_tag']
RUNTIME = PINS['runtime_seconds']
READY_SECONDS = 180
FORBIDDEN_ARGUMENT = re.compile(r'(^|\s)(sfnvme|pdnvme)[a-z_]*=')
ESP_TOOL = HERE / 'esp/j313_esp.py'
RESET_RECOVERY = """
STOP. Linux did not come back. Do not reset the Air again from the M5.
A person at the Air must:
  1. Hold the power button until the Air is off.
  2. Hold it again until "Loading startup options" appears. Choose Options, then Utilities, Terminal.
  3. Run: diskutil list    and find the Linux ESP (about 500 MB, FAT). Do not assume its number.
  4. Mount it, then: cp "<ESP>/m1n1/boot.bin.pre-g2" "<ESP>/m1n1/boot.bin"
  5. Check: shasum -a 256 "<ESP>/m1n1/boot.bin"   must begin 54fa07e4f5cbeecd
  6. Restart. Do not run bputil, csrutil or any other policy command.
"""


class Stop(Exception):
    """The run stops here; the message says what state things are in."""


class LineReader:
    """Lines from a stream with a time limit. None means the stream ended or the limit passed."""
    def __init__(self, stream):
        self.lines = queue.Queue()
        self.finished = False
        threading.Thread(target=self._read, args=(stream,), daemon=True).start()

    def _read(self, stream):
        for line in stream:
            self.lines.put(line)
        self.lines.put(None)

    def next_line(self, seconds):
        try:
            line = self.lines.get(timeout=seconds)
        except queue.Empty:
            return None
        if line is None:
            self.finished = True
        return line


def stop_process(process):
    """End the local ssh client only. A cycle that never reported ready has not touched the Air."""
    try:
        process.terminate()
        process.wait(timeout=10)
    except (AttributeError, OSError, subprocess.TimeoutExpired):
        pass


def sha(path):
    with open(path, 'rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def tree_hash(root):
    files = {}
    for path in sorted(Path(root).rglob('*')):
        rel = path.relative_to(root).as_posix()
        if path.is_file() and '__pycache__' not in rel:
            files[rel] = sha(path)
    return hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()


def load_config(path):
    value = json.loads(Path(path).read_text())
    for key in ('air_ssh', 'air_known_hosts', 'm5_ssh', 'm5_host_key_alias', 'm5_work', 'artifacts',
                'm5_thunderbolt_peer'):
        if not value.get(key):
            raise Stop(f'config has no {key}')
    return value


def inputs(config):
    root = Path(config['artifacts'])
    return dict(raw=root / PINS['window_raw']['path'], boot=root / PINS['window_boot']['path'],
                packet=root / PINS['packet_dir'], lab=root / PINS['lab_dir'], inventory=root / 'inventory.json')


def verify_local(config):
    paths = inputs(config)
    checks = []
    def check(name, condition):
        checks.append(name)
        if not condition:
            raise Stop('input check failed: ' + name)
    for key, pin in (('raw', PINS['window_raw']), ('boot', PINS['window_boot'])):
        check(f'window {key} hash', paths[key].is_file() and sha(paths[key]) == pin['sha256'] and
              paths[key].stat().st_size == pin['bytes'])
    check('ESP tool is the reviewed one', sha(ESP_TOOL) == PINS['esp_tool_sha256'])
    check('window build is the one the ESP tool accepts', PINS['window_boot']['sha256'] == esp.CANDIDATE_SHA)
    check('packet manifest hash', sha(paths['packet'] / 'manifest.json') == PINS['manifest_sha256'])
    manifest = json.loads((paths['packet'] / 'manifest.json').read_text())
    for name, item in manifest['artifacts'].items():
        check(f'packet {name}', sha(paths['packet'] / item['path']) == item['sha256'])
    check('kernel is the G1 RAM-boot collection', manifest['artifacts']['kernel']['sha256'] == PINS['kernel_sha256'])
    check('launcher tree hash', tree_hash(paths['lab']) == PINS['lab_tree_sha256'])
    extra = (paths['lab'] / 'integrations/puredarwin/m1-bringup/extra_bootargs.txt').read_text().strip()
    check('boot arguments are the reviewed ones', extra == PINS['extra_bootargs'])
    for word in ('sfsound=0', 'sftouchbar=0', 'sfm1tpmt=0'):
        check('boot arguments carry ' + word, word in extra.split())
    check('boot arguments name no NVMe driver', FORBIDDEN_ARGUMENT.search(extra) is None)
    return checks


class Remote:
    """The real transport. Everything goes through ssh with a pinned host key."""
    def __init__(self, config, log):
        self.config, self.log = config, log
        self.air_options = ['-F', '/dev/null', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
                            '-o', 'UserKnownHostsFile=' + config['air_known_hosts'], '-o', 'ConnectTimeout=8',
                            '-o', 'ServerAliveInterval=5', '-o', 'ServerAliveCountMax=3']
        self.m5_options = ['-o', 'BatchMode=yes', '-o', 'HostKeyAlias=' + config['m5_host_key_alias'],
                           '-o', 'ConnectTimeout=8', '-o', 'ServerAliveInterval=15']

    def note(self, text):
        with open(self.log, 'a') as stream:
            stream.write(f'{time.time():.3f} {text}\n')

    def air(self, command, stdin=None, timeout=60):
        self.note('air: ' + command)
        try:
            return subprocess.run(['ssh', *self.air_options, self.config['air_ssh'], command], input=stdin,
                                  capture_output=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            return subprocess.CompletedProcess(command, 255, b'', b'timeout')

    def m5(self, command, stdin=None, timeout=120):
        self.note('m5: ' + command)
        return subprocess.run(['ssh', *self.m5_options, self.config['m5_ssh'], command], input=stdin,
                              capture_output=True, timeout=timeout)

    def m5_start(self, command):
        self.note('m5 start: ' + command)
        return subprocess.Popen(['ssh', *self.m5_options, self.config['m5_ssh'], command],
                                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, text=True)

    def m5_upload(self, directory, members, destination):
        self.note(f'm5 upload: {members} to {destination}')
        tar = subprocess.Popen(['tar', '-C', str(directory), '-cf', '-', *members], stdout=subprocess.PIPE)
        remote = ('sudo -n sh -c ' + shlex.quote(f'mkdir -p -m 700 {destination} && tar -xf - -C {destination} '
                                                 f'&& chown -R root:staff {destination}'))
        done = subprocess.run(['ssh', *self.m5_options, self.config['m5_ssh'], remote], stdin=tar.stdout,
                              capture_output=True, timeout=600)
        tar.stdout.close()
        return tar.wait() == 0 and done.returncode == 0

    def sleep(self, seconds):
        time.sleep(seconds)


def esp_command(remote, *words, execute=False):
    arguments = list(words) + (['--execute', '--confirm', esp.CONFIRM] if execute else [])
    command = 'sudo -n python3 -I - ' + ' '.join(shlex.quote(word) for word in arguments)
    done = remote.air(command, stdin=ESP_TOOL.read_bytes(), timeout=120)
    if done.returncode not in (0, esp.EXIT_REFUSED):
        raise Stop(f'the ESP tool did not run on the Air: {done.stderr[-300:]!r}')
    report = json.loads(done.stdout.decode().strip().splitlines()[-1])
    return done.returncode, report


LINUX_PROBE = ("import json,os,pathlib as P;d=P.Path('/sys/firmware/devicetree/base');"
               "r=lambda n:(d/n).read_bytes().rstrip(b'\\0').decode();"
               "print(json.dumps(dict(boot_id=P.Path('/proc/sys/kernel/random/boot_id').read_text().strip(),"
               "kernel=os.uname().release,compatible=(d/'compatible').read_bytes().decode().rstrip(chr(0)).split(chr(0)),"
               "stage2=r('chosen/asahi,m1n1-stage2-version'),"
               "root_rw='rw' in next(l.split()[3].split(',') for l in open('/proc/mounts') if l.split()[1]=='/'),"
               "oneshot=[n for n in os.listdir('/sys/firmware/efi/efivars') if n.startswith('LoaderEntryOneShot')],"
               "default_entry=[l.strip() for l in open('/boot/efi/limine.conf',errors='replace') if l.startswith('default_entry:')])))")


def probe(remote):
    done = remote.air('sudo -n python3 -I -c ' + shlex.quote(LINUX_PROBE), timeout=20)
    if done.returncode != 0:
        return None
    try:
        return json.loads(done.stdout)
    except ValueError:
        return None


def wait_linux(remote, old_boot, stage2, seconds=240):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = probe(remote)
        if value and value['boot_id'] != old_boot:
            if 'apple,j313' not in value['compatible']:
                raise Stop('a different machine answered')
            if value['stage2'] != stage2:
                raise Stop(f"Linux booted with stage 2 {value['stage2']}, expected {stage2}")
            if not value['root_rw']:
                raise Stop('Linux came back with a read-only root')
            return value
        remote.sleep(5)
    return None


M5_CHECK = r'''
import json,os,re,subprocess,hashlib,sys
W,peer=sys.argv[1:3]
out={}
t=json.loads(subprocess.run(['system_profiler','-json','SPThunderboltDataType'],capture_output=True,text=True,timeout=30).stdout)
def walk(n,port=None):
    if isinstance(n,dict):
        p=n.get('receptacle_1_tag',{}).get('receptacle_id_key',port) if isinstance(n.get('receptacle_1_tag'),dict) else port
        if n.get('device_name_key') and n.get('_name') and p is not None: found.append((str(p),n.get('device_name_key')))
        for v in n.values(): walk(v,p)
    elif isinstance(n,list):
        for v in n: walk(v,port)
found=[]; walk(t); out['peers']=found
hpm=subprocess.run(['ioreg','-c','AppleHPM','-l','-w','0'],capture_output=True,text=True,errors='replace',timeout=20).stdout
m=re.search(r'"RID" = 0\b.*?\+-o Port-USB-C@(\d+)',hpm,re.S); out['rid0_port']=m.group(1) if m else None
out['macvdmtool']=hashlib.sha256(open(W+'/native-control-src/macvdmtool','rb').read()).hexdigest()
out['latch']=os.path.exists(W+'/m1-kernel-cycle-incomplete.json')
out['handoff']=os.path.exists(W+'/m1-bench-handoff.json')
out['packet_r6']=os.path.exists(W+'/packet-r6/manifest.json'); out['host_source']=os.path.isdir(W+'/m1n1/proxyclient')
out['venv']=subprocess.run([W+'/venv/bin/python','-c','import construct,serial'],capture_output=True).returncode==0
usb=subprocess.run(['ioreg','-p','IOUSB','-l','-w','0'],capture_output=True,text=True,errors='replace',timeout=20).stdout
out['proxy_present']='"idProduct" = 12653' in usb and '"idVendor" = 4617' in usb
print(json.dumps(out))
'''


def check_m5(remote, config):
    done = remote.m5('sudo -n python3 -I - ' + shlex.quote(config['m5_work']) + ' ' +
                     shlex.quote(config['m5_thunderbolt_peer']), stdin=M5_CHECK.encode())
    if done.returncode != 0:
        raise Stop(f'M5 check did not run: {done.stderr[-300:]!r}')
    value = json.loads(done.stdout)
    problems = []
    if value['rid0_port'] != '1':
        problems.append('macvdmtool would not address receptacle 1')
    if not any(port == '1' and name == config['m5_thunderbolt_peer'] for port, name in value['peers']):
        problems.append('the Air is not the peer on M5 receptacle 1')
    if value['macvdmtool'] != PINS['macvdmtool_sha256']:
        problems.append('macvdmtool hash changed')
    for key, label in (('latch', 'an incomplete-cycle latch is set'), ('handoff', 'a bench handoff is pending'),
                       ('proxy_present', 'an m1n1 proxy is already on the M5')):
        if value[key]:
            problems.append(label)
    for key, label in (('packet_r6', 'bootstrap packet missing'), ('host_source', 'm1n1 host source missing'),
                       ('venv', 'Python environment incomplete')):
        if not value[key]:
            problems.append(label)
    if problems:
        raise Stop('M5 preflight: ' + '; '.join(problems))
    return value


def cycle_arguments(config):
    work, run = config['m5_work'], f"{config['m5_work']}/j313-g2"
    return ['--manifest', f'{work}/packet-r6/manifest.json', '--host-source', f'{work}/m1n1',
            '--window-image', f"{run}/window/{Path(PINS['window_raw']['path']).name}",
            '--inventory', f'{run}/inventory.json', '--candidate', f"{run}/{PINS['packet_dir']}/manifest.json",
            '--launcher-sha256', PINS['launcher_sha256'], '--inspector-sha256', PINS['inspector_sha256'],
            '--runtime', str(RUNTIME), '--private-root', f'{work}/j313-g2-cycles']


def cycle_command(config, words):
    run = f"{config['m5_work']}/j313-g2"
    argv = [f"{config['m5_work']}/venv/bin/python", '-B', 'tools/j313_cycle.py', *words]
    return 'sudo -n sh -c ' + shlex.quote(f"cd {run}/lab && exec caffeinate -dimsu " + shlex.join(argv))


def deliver(remote, config):
    paths = inputs(config)
    run = f"{config['m5_work']}/j313-g2"
    done = remote.m5('sudo -n rm -rf ' + shlex.quote(run))
    if done.returncode != 0:
        raise Stop('could not clear the delivery directory on the M5')
    files = ['manifest.json', 'kernel.macho', 'ramdisk.img', 'source.patch', 'build-record.json', 'ramdisk.record.json']
    ok = (remote.m5_upload(paths['lab'].parent, [paths['lab'].name], run) and
          remote.m5_upload(paths['packet'].parent, [f"{paths['packet'].name}/{name}" for name in files], run) and
          remote.m5_upload(paths['raw'].parent, [paths['raw'].name], run + '/window') and
          remote.m5_upload(paths['inventory'].parent, [paths['inventory'].name], run))
    if not ok:
        raise Stop('delivery to the M5 failed; nothing on the Air has changed')
    if paths['lab'].name != 'lab':
        moved = remote.m5('sudo -n mv ' + shlex.quote(f"{run}/{paths['lab'].name}") + ' ' + shlex.quote(f'{run}/lab'))
        if moved.returncode != 0:
            raise Stop('could not place the launcher on the M5')
    done = remote.m5(cycle_command(config, ['verify', *cycle_arguments(config)]), timeout=180)
    report = json.loads(done.stdout.decode().strip().splitlines()[-1]) if done.stdout.strip() else {}
    if done.returncode != 0 or report.get('status') != 'INPUTS_VERIFIED_NO_DEVICE_CONTACT':
        raise Stop(f'the M5 refused the inputs: {report or done.stderr[-300:]}')
    return report


def deliver_candidate(remote, config):
    data = inputs(config)['boot'].read_bytes()
    command = 'umask 077 && mkdir -p /dev/shm/g2 && cat > /dev/shm/g2/boot.bin && sha256sum /dev/shm/g2/boot.bin'
    done = remote.air(command, stdin=data, timeout=180)
    if done.returncode != 0 or not done.stdout.startswith(esp.CANDIDATE_SHA.encode()):
        raise Stop('the window build did not reach the Air intact; the ESP is unchanged')


def restore_and_verify(remote, boot_id, result):
    """From a running Linux: original back, reboot once onto it, then delete the kept copy."""
    code, report = esp_command(remote, 'restore', execute=True)
    result['restore'] = report
    if code != 0 or report.get('boot_bin') != 'original':
        raise Stop(f'restore failed; boot.bin.pre-g2 is still on the ESP: {report}')
    remote.air('sudo -n systemctl reboot', timeout=15)
    remote.sleep(10)
    back = wait_linux(remote, boot_id, ORIGINAL_STAGE2)
    if back is None:
        raise Stop(RESET_RECOVERY)
    result['final_linux'] = {key: back[key] for key in ('kernel', 'stage2')}
    code, report = esp_command(remote, 'finalize', execute=True)
    result['finalize'] = report
    if code != 0:
        raise Stop(f'finalize refused; the original is restored and its copy kept: {report}')
    return back


def clear_latch(remote, config):
    command = cycle_command(config, ['clear', '--execute', '--confirm-recovery', PINS['recovery_confirmation'],
                                     '--linux-verified'])
    done = remote.m5(command, timeout=30)
    if done.returncode != 0:
        raise Stop('Linux is verified but the M5 latch was not cleared; review before the next bench run')


def go(config, remote, say=print):
    result = dict(status='NOT_STARTED', swapped=False, reset_attempts=0)
    verify_local(config)
    say('1/9 local inputs verified')
    baseline = probe(remote)
    if baseline is None:
        raise Stop('the Air is not reachable over SSH; nothing has changed')
    if 'apple,j313' not in baseline['compatible'] or baseline['stage2'] != ORIGINAL_STAGE2 or baseline['oneshot']:
        raise Stop(f'the Air is not in the expected state: {baseline}')
    code, status = esp_command(remote, 'status')
    if code != 0 or status['boot_bin'] != 'original' or status['kept'] != 'absent':
        raise Stop(f'the ESP is not in the expected state: {status}')
    say('2/9 the Air is J313, on the original stage 2, with no one-shot boot pending')
    check_m5(remote, config)
    say('3/9 M5 checked: receptacle 1 is the Air, no bench work pending')
    deliver(remote, config)
    say('4/9 launcher and packet delivered and verified on the M5')
    deliver_candidate(remote, config)
    code, report = esp_command(remote, 'install', '--candidate', '/dev/shm/g2/boot.bin')
    if code != 0 or len(report['steps']) != 2:
        raise Stop(f'install dry run refused: {report}')

    process = None
    try:
        result['swapped'] = True
        code, report = esp_command(remote, 'install', '--candidate', '/dev/shm/g2/boot.bin', execute=True)
        result['install'] = report
        if code != 0 or report.get('boot_bin') != 'window build':
            raise Stop(f'install failed: {report}')
        say('5/9 window build installed on the ESP; the original is kept beside it')
        words = ['run', '--execute', '--confirm-recovery', PINS['recovery_confirmation'], *cycle_arguments(config)]
        process = remote.m5_start(cycle_command(config, words))
        reader = LineReader(process.stdout)
        line = reader.next_line(READY_SECONDS)
        if line is None or not line.startswith('G2_READY'):
            # The Air has not been rebooted, so its Linux is up and stage 2 can go straight back.
            stop_process(process)
            process = None
            raise Stop(f'the M5 cycle did not become ready: {line!r}')
        remote.air('sudo -n systemctl reboot', timeout=15)
        say('6/9 the Air is rebooting; the M5 is waiting for the proxy')
        final = None
        deadline = time.monotonic() + RUNTIME + 600
        while True:
            line = reader.next_line(max(deadline - time.monotonic(), 1))
            if line is None:
                break
            if line.startswith('G2_RESULT '):
                final = json.loads(line[len('G2_RESULT '):])
        if not reader.finished:
            result['status'] = 'M5_CYCLE_DID_NOT_FINISH'
            raise Stop('the M5 cycle is still running past its limit. Do not reset the Air; review on the M5.')
        process.wait(timeout=30)
        process = None
        if final is None:
            raise Stop('the M5 cycle ended without a result; do not reset the Air until it is reviewed')
        result['boot'] = final
        result['reset_attempts'] = final.get('reset_attempts', 0)
        if final.get('status') == 'WORKER_STATE_UNKNOWN_NO_RESET':
            raise Stop('a worker may still own the proxy; no reset was issued; review on the M5')
        say(f"7/9 boot finished: {final.get('status')}")
        back = wait_linux(remote, baseline['boot_id'], WINDOW_STAGE2)
        if back is None:
            result['status'] = 'LINUX_DID_NOT_RETURN'
            raise Stop(RESET_RECOVERY)
        say('8/9 the Air is back in Linux')
        final_linux = restore_and_verify(remote, back['boot_id'], result)
        # The Air rewrites its menu's snapshot entries by itself, so only the default is compared.
        if final_linux['default_entry'] != baseline['default_entry'] or len(baseline['default_entry']) != 1:
            result['default_entry_changed'] = True
            raise Stop('the default boot entry changed during the run; stage 2 is restored, review the menu')
        clear_latch(remote, config)
        result['swapped'] = False
        say('9/9 original stage 2 restored and verified after a reboot')
        result['status'] = 'BOOT_OBSERVED_LINUX_RESTORED' if final.get('command_line_observed') else 'NO_SHELL_LINUX_RESTORED'
        return result
    except (Exception, KeyboardInterrupt) as error:
        result.setdefault('stopped', f'{type(error).__name__}: {error}' if not isinstance(error, Stop) else str(error))
        # With an M5 cycle possibly still running the Air may be rebooting: leave the ESP alone.
        if result['swapped'] and 'restore' not in result and result['status'] != 'LINUX_DID_NOT_RETURN' and process is None:
            try:
                try_restore(remote, baseline, result, say)
            except Exception as failure:
                result['restore_attempt'] = f'failed: {type(failure).__name__}: {failure}'
        raise Stop(json.dumps(result, indent=1) + '\n' + str(error)) from error


def try_restore(remote, baseline, result, say):
    """Called after a failure while the Air's Linux may still be up. Never resets anything."""
    value = probe(remote)
    if value is None:
        result['restore_attempt'] = 'Linux not reachable; nothing was done'
        return
    code, status = esp_command(remote, 'status')
    if status.get('boot_bin') == 'original':
        result['restore_attempt'] = 'already the original'
        return
    code, report = esp_command(remote, 'restore', execute=True)
    result['restore_attempt'] = report
    say('stage 2 restored after the failure; reboot not attempted' if code == 0 else 'RESTORE FAILED')


def rollback(remote, say=print):
    value = probe(remote)
    if value is None:
        raise Stop('the Air is not reachable over SSH. ' + RESET_RECOVERY)
    code, report = esp_command(remote, 'restore', execute=True)
    if code != 0:
        raise Stop(f'restore refused: {report}')
    say(json.dumps(report))
    if report.get('status') == 'DONE':
        result = {}
        restore_after = value['boot_id']
        remote.air('sudo -n systemctl reboot', timeout=15)
        remote.sleep(10)
        back = wait_linux(remote, restore_after, ORIGINAL_STAGE2)
        if back is None:
            raise Stop(RESET_RECOVERY)
        code, report = esp_command(remote, 'finalize', execute=True)
        result['finalize'] = report
        say(json.dumps(result))
    return report


def print_plan(config_path, config, checks):
    say = print
    say('G2 PLAN. Nothing has been contacted or changed.\n')
    say(f'{len(checks)} input checks passed:')
    for name in checks:
        say('  ok  ' + name)
    extra = PINS['extra_bootargs']
    say('\nBoot arguments (launcher base, then):\n  ' + PINS['guest_bootargs'])
    say(f'  (reviewed additions: {extra})')
    say('\nNo sfnvme argument. The collection has no Apple NVMe driver. The guest stops if anything attaches to it.')
    for number, step in enumerate((
        'Builder checks every hash above again.',
        'Air (read only): J313, stage 2 f5a82fdb-dirty, ESP boot.bin is the original, no one-shot boot pending.',
        'M5 (read only): receptacle 1 is the Air, macvdmtool pin, no latch, handoff or proxy.',
        'M5: receive the launcher and packet; verify them with no device contact.',
        'Air: put the window build in /dev/shm. ESP: keep original as m1n1/boot.bin.pre-g2, install window build.',
        'M5: wait for the proxy. Air: systemctl reboot.',
        f'M5: claim the 10 s window, chainload the proxy, load the RAM boot, capture up to {RUNTIME} s, one reset at most.',
        'Air: new Linux boot on the window build. ESP: restore the original, reboot, verify f5a82fdb-dirty.',
        'Air: delete boot.bin.pre-g2. Confirm the default boot entry is unchanged. M5: clear the latch.'), 1):
        say(f'  {number}. {step}')
    say('\nThis needs Chris to approve, in these words:\n  ' + APPROVAL)
    say('\nThen, holding the shared bench of the main checkout:')
    say(f'  BENCH_WHO=CHL-27-G2 /home/chrisk/src/darwin-lab/tools/bench.sh run python3 {Path(__file__).resolve()} go '
        f'--config {config_path} --approval "{APPROVAL}"')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('command', choices=('plan', 'go', 'rollback'))
    parser.add_argument('--config', type=Path, default=Path.home() / 'chl27-g2/config.json')
    parser.add_argument('--approval')
    args = parser.parse_args(argv)
    try:
        config = load_config(args.config)
        if args.command == 'plan':
            print_plan(args.config, config, verify_local(config))
            return 0
        if args.approval != APPROVAL:
            raise Stop('this command needs --approval with the exact text from `g2.py plan`')
        directory = Path(config['artifacts']) / 'runs' / time.strftime('%Y%m%d-%H%M%S')
        directory.mkdir(parents=True, mode=0o700)
        remote = Remote(config, directory / 'commands.log')
        result = go(config, remote) if args.command == 'go' else rollback(remote)
        (directory / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result, indent=1))
        return 0
    except Stop as error:
        print('STOPPED: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
