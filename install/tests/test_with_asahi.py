#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""The Asahi Linux installer's OWN code, behind our gate, against the FakeMac disk model.

    SF_ASAHI_SRC=<asahi-installer checkout at v0.9.2> python3 -I install/tests/test_with_asahi.py

Not part of CI (CI fetches no sources). It copies the checkout's src/ and asahi_firmware/ as
the published package lays them out, lets sf_engine.AsahiEngine patch the modules (diskutil,
subprocess, open, os.system), and then runs Asahi's DiskUtil (reading FakeMac's plists with
Asahi's parser), resizeContainer, addPartition, OSInstaller.partition_disk and
OSInstaller.install (FAT format, esp tree, boot object) exactly as sf_engine does, followed by
our finish() (root image from its xz parts, release personalisation, firmware slot). What it cannot run here: SystemInfo (ioreg/nvram of a
real Mac), the stub's contents (Apple's restore image), firmware collection, bless and step 2.
"""
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import types
import unittest

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path[:0] = [str(HERE), str(ROOT / 'install' / 'engine')]
import fakemac  # noqa: E402
import sf_engine  # noqa: E402
import sf_gate  # noqa: E402
import sf_kernelcfg  # noqa: E402
import sf_manifest  # noqa: E402
import sf_plan  # noqa: E402

SRC = os.environ.get('SF_ASAHI_SRC')
MODELS = sf_plan.load_models((ROOT / 'install' / 'models.tsv').read_text())


@unittest.skipUnless(SRC, 'set SF_ASAHI_SRC to an asahi-installer checkout at v0.9.2')
class RealAsahiBehindTheGate(unittest.TestCase):
    def test_partitions_and_files_with_asahis_code(self):
        tag = subprocess.run(['git', '-C', SRC, 'describe', '--tags'], capture_output=True, text=True).stdout.strip()
        changed = subprocess.run(['git', '-C', SRC, 'diff', '--stat', 'v0.9.2', 'HEAD', '--', 'src', 'asahi_firmware'], capture_output=True, text=True).stdout
        self.assertEqual(changed, '', 'the checkout\'s Python differs from v0.9.2')
        tmp = tempfile.mkdtemp()
        eng = os.path.join(tmp, 'engine')
        shutil.copytree(os.path.join(SRC, 'src'), eng, symlinks=False, ignore=shutil.ignore_patterns('asahi_firmware'))
        shutil.copytree(os.path.join(SRC, 'asahi_firmware'), os.path.join(eng, 'asahi_firmware'))
        pathlib.Path(eng, 'version.tag').write_text('v0.9.2\n')
        rel = os.path.join(tmp, 'rel')
        os.makedirs(rel)
        m, _, _ = fakemac.make_release(rel)
        boot = sf_engine.unpack_boot(m, rel)
        os.makedirs(os.path.join(eng, 'boot'))
        shutil.copy(os.path.join(boot, 'sf-stage1.bin'), os.path.join(eng, 'boot', sf_engine.STAGE1_NAME))
        package = sf_engine.os_package(boot, rel)
        os.environ.update(REPO_BASE=rel, DISTRO='SiliconForest')

        mac = fakemac.FakeMac(name='asahi')
        reader = lambda: sf_plan.gather(mac).layout
        plan = sf_plan.plan_install(sf_plan.gather(mac), MODELS, m)
        gate = sf_gate.Gate(plan, reader, execute=mac, log=lambda *a: None)
        cwd, real_system = os.getcwd(), os.system
        try:
            ae = sf_engine.AsahiEngine(eng, gate)
            du = ae.diskutil.DiskUtil()
            du.get_info()                                    # Asahi's parser reads FakeMac's plists
            disk = du.find_system_disk()
            self.assertEqual(disk, 'disk0')
            r = plan['resize']
            du.resizeContainer(r['store'], r['to_bytes'])
            du.get_info()
            parts = du.get_partitions(disk)
            free = [p for p in parts if p.free and p.name == plan['after'] and p.offset == plan['gap_offset']]
            self.assertEqual(len(free), 1, 'Asahi sees the gap where the plan put it')
            stub_part = du.addPartition(free[0].name, 'apfs', 'SiliconForest', plan['stub_bytes'])
            self.assertEqual(stub_part.name, 'disk0s4')
            ae.stub.StubInstaller(None, du, None).prepare_volume(stub_part)    # Data/System/Preboot/Recovery volumes
            template = sf_engine.installer_template(m, plan, package)
            osins = ae.osinstall.OSInstaller(du, {'os_list': [template]}, template)
            osins.load_package()
            osins.name = 'SiliconForest'
            osins.partition_disk(stub_part.name, plan['boot_bytes'] + plan['root_bytes'])
            fw = os.path.join(tmp, 'vendorfw')
            os.makedirs(fw)
            osins.firmware_package = types.SimpleNamespace(path=fw)
            stub_ins = types.SimpleNamespace(icon_path=os.path.join(tmp, 'VolumeIcon.icns'), boot_obj_path=os.path.join(tmp, 'boot.bin'))
            osins.install(stub_ins)
            efi, root = osins.efi_part, osins.part_info[1]
            mount = du.mount(efi.name)
            fwtar = os.path.join(tmp, 'firmware.tar')
            fakemac.firmware_tar(fwtar)
            sf_engine.finish(gate, m, rel, mount, root.name, root.uuid, root.offset // 4096, root.size // 4096, root.size, fwtar, None)
        finally:
            os.chdir(cwd)
            os.system = real_system
        ours = reader().find_ours()
        self.assertTrue(ours.complete, ours.problems)
        self.assertEqual(mac.part(efi.name)['label'], 'SFBOOT - Si')            # newfs_msdos -v, as Asahi names it
        self.assertEqual(ours.root.size, plan['root_bytes'])                     # expand: the root takes the rest
        boot_obj = pathlib.Path(stub_ins.boot_obj_path).read_bytes()
        self.assertIn(('chosen.asahi,efi-system-partition=%s\nchainload=%s;sf/boot.bin\n' % (efi.uuid.lower(), efi.uuid.lower())).encode(), boot_obj)
        self.assertEqual(sorted(os.listdir(os.path.join(mount, 'sf'))), ['boot.bin', 'kernel.bin'])
        self.assertIn('sfnvme_part=%s ' % root.uuid.lower(), sf_kernelcfg.bootargs(pathlib.Path(mount, 'sf', 'kernel.bin').read_bytes()))
        with open(mac.device_file(root.name), 'rb') as fd:
            self.assertEqual(fd.read(16), b'SYNTHETIC ROOT\n\0')
        changing = [c for c in gate.calls if gate.classify(c) is not None]
        print('\nchanging commands issued by Asahi\'s code, all allowed by the gate:')
        for c in changing:
            print('  ' + ' '.join(c))
        rec = HERE / 'fixtures' / 'asahi-v0.9.2-commands.txt'
        text = ''.join(' '.join(c) + '\n' for c in changing)
        if os.environ.get('SF_RECORD'):
            rec.write_text(text)
        self.assertEqual(rec.read_text(), text, 'Asahi issued other commands than recorded (SF_RECORD=1 to re-record)')
        shutil.rmtree(tmp)


if __name__ == '__main__':
    unittest.main(verbosity=2)
