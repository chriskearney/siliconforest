# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
#
# The SiliconForest release for the 13-inch M1 MacBook Pro (J293), built from this tree:
#
#   rootfs     siliconforest-root.ext4   the root filesystem, sized to its contents plus slack;
#                                        the installer writes it into the target's partition and
#                                        grows it there (resize2fs) before the first start
#              root.manifest.tsv         every entry of that root: path, type, mode, owner, size, sha256
#              image.json                the layers used, their store paths, sizes, ext4 parameters
#   bootfiles  the boot files: sf/boot.bin as it is (stage 2 for this release's root UUID), and what
#              sf_personalize.py needs to pack sf/kernel.bin for one machine at install time (the
#              target's partition identifiers never exist in a release file)
#   release    the files of a GitHub release: compressed root in parts below 2 GiB, the boot
#              archive, MANIFEST.tsv and SHA256SUMS (signed afterwards by the owner, see
#              docs/release/IMAGE.md "Signing"); nothing in it is published by this recipe
#   qemu       a disk for QEMU's arm64 virt machine: the QEMU base's EFI partition and collection
#              with this root, for the equivalence run (docs/release/IMAGE.md, "Proof")
#
# What a release does not contain, and how it arrives instead (docs/release/IMAGE.md):
# Wi-Fi firmware (extracted by the installer from the target's own Linux install), Mozilla's
# Firefox bundle (downloaded at first run), Apple's applications (copied by the user from
# their own macOS), Homebrew bottles (poured at install time by homebrew/hb_pour.py).
#
#   pkgs       nixpkgs of the pinned base
#   base       upstream's arm64 virt image (the minimal release variant), whose ext4 root is the base
#   qemuBase   the QEMU desktop loop's disk image (qemu-dev/build-image.nix), for `qemu` only
#   kernel     the kernel collection (m1-kernel50/build-kc.nix): $out/kernel
#   boot       { stage1 = <sf-stage1.bin>; stage2 = <stage 2 built for identity.rootUUID> }
#   pieces     name -> build output laid out at installed paths (release/packages.nix)
{ pkgs, base, kernel, boot, pieces ? { }, qemuBase ? null, version ? "0.1.0"
, identity ? import ./identity.nix { inherit version; }, slackPercent ? 25 }:
let
  lib = pkgs.lib;
  here = ./image;
  tree = ../integrations/siliconforest;
  spec = import (here + "/layers.nix");
  # Firefox's runtime is assembled here unless the set brings it (./image/firefox-runtime.nix):
  # its providers are built from firefox/*.nix with release.json's arguments, the three selected
  # overrides are these pieces' outputs
  allPieces0 = pieces // lib.optionalAttrs (!(pieces ? firefox-runtime) && pieces ? firefox-sc-network) {
    firefox-runtime = import (here + "/firefox-runtime.nix") {
      inherit pkgs;
      overrides = {
        "network-v1" = pieces.firefox-sc-network;
        "audio-clock-v1" = pieces.firefox-clock-family;
        "video-clock-0172-v1" = pieces.firefox-clocked-providers;
      };
    };
  };
  # pieces the recipe builds itself unless the set brings them
  defaults = lib.optionalAttrs (!(pieces ? homebrew)) { homebrew = import (here + "/homebrew.nix") { inherit pkgs tree; }; }
    // lib.optionalAttrs (!(pieces ? activity-monitor)) {
      activity-monitor = import (here + "/activity-monitor.nix") { inherit pkgs tree; linkRoot = rootTree; }; };
  allPieces = allPieces0 // defaults;
  present = l: builtins.hasAttr (l.piece or l.name) allPieces;
  missing = map (l: l.name) (lib.filter (l: !(present l) && !(l.optional or false)) spec);
  layerOf = l: { inherit (l) name; path = "${allPieces.${l.piece or l.name}}"; prefix = l.prefix or "/"; exclude = l.exclude or [ ]; }
    // (if l ? only then { inherit (l) only; } else { });
  layers =
    assert lib.assertMsg (missing == [ ]) "release/image.nix: pieces missing: ${toString missing}";
    map layerOf (lib.filter (l: present l && !(l.late or false)) spec);
  lateLayers = map layerOf (lib.filter (l: present l && (l.late or false)) spec);
  absent = map (l: l.name) (lib.filter (l: !(present l)) spec);

  # The two installers of the tree, run against the staged root exactly as they ran on the M1:
  # m1-storage/system/sf-install.sh (session, halt, clock, boot tools, dock items) and
  # m1-storage/userland/sf-userland-install.sh (SSH, the account sf, environment, Homebrew's links).
  systemSource = pkgs.runCommand "siliconforest-image-system-source" { } ''
    mkdir -p $out/applications
    cp ${allPieces.system-tools}/sbin/sf-halt ${allPieces.system-tools}/usr/sbin/sf-clock $out/
    cp ${tree + "/m1-storage/system"}/{sf-boot,sf-command,sf-session,darwin-desktop-test.disk} $out/
    cp ${tree + "/m1-native-boot/guest"}/org.siliconforest.desktop.plist $out/
    cp ${allPieces.desktop}/usr/bin/chonkstep-dock $out/
    cp ${tree + "/desktop/system"}/applications/org.siliconforest.terminal.desktop $out/applications/
    cp ${tree + "/desktop/system"}/dock-pins $out/
  '';
  userlandSource = pkgs.runCommand "siliconforest-image-userland-source" { } ''
    mkdir -p $out/ssh
    cp ${tree + "/m1-storage/userland"}/{sshd_config,sf-sshd,org.siliconforest.sshd.plist,brew,sf-environment,shasum} $out/
    for d in bin sbin libexec etc; do [ -d ${allPieces.openssh}/$d ] && cp -R ${allPieces.openssh}/$d $out/ssh/; done
    cp ${allPieces.terminal}/usr/bin/chonk-terminal-darwin $out/
  '';
  # files of the tree that go in as they are (installed path <- tree path)
  files = pkgs.runCommand "siliconforest-image-files" { } ''
    put() { mkdir -p "$out/$(dirname "$1")"; cp "$2" "$out/$1"; }
    put usr/share/backgrounds/siliconforest/siliconforest.png ${tree + "/chonkstep-darwin/backgrounds/siliconforest.png"}
    for w in sf-canopy sf-clearing sf-dieshot sf-wafer; do
      put usr/share/backgrounds/siliconforest/$w.jpg ${tree + "/desktop/themes/wallpapers"}/$w.jpg
    done
    # the desktop's font, where the M1 has its copies (DejaVu 2.37, from nixpkgs), with its licence
    for d in usr/share/darwin-desktop System/Library/Fonts usr/share/fonts/TTF; do mkdir -p $out/$d; done
    f=${pkgs.dejavu_fonts}/share/fonts/truetype
    cp $f/DejaVuSans.ttf $f/DejaVuSans-Bold.ttf $out/usr/share/darwin-desktop/
    cp $f/DejaVuSans.ttf $out/System/Library/Fonts/
    cp $f/DejaVuSans.ttf $out/usr/share/fonts/TTF/
    cp ${pkgs.dejavu_fonts.full-ttf.src}/LICENSE $out/usr/share/darwin-desktop/LICENSE-DejaVu.txt
    # first start on its own machine (release/image/firstboot)
    mkdir -p $out/usr/libexec $out/System/Library/LaunchDaemons
    cp ${here}/firstboot/sf-firstboot $out/usr/libexec/sf-firstboot
    chmod 755 $out/usr/libexec/sf-firstboot
    cp ${here}/firstboot/org.siliconforest.firstboot.plist $out/System/Library/LaunchDaemons/
    mkdir -p $out/usr/share/doc/siliconforest
    cp ${../LICENSE} $out/usr/share/doc/siliconforest/LICENSE
    cp ${../NOTICE} $out/usr/share/doc/siliconforest/NOTICE
    cp ${../LICENSING.md} $out/usr/share/doc/siliconforest/LICENSING.md
    cp -R ${../LICENSES} $out/usr/share/doc/siliconforest/LICENSES
  '';
  layersJson = pkgs.writeText "layers.json" (builtins.toJSON layers);
  lateJson = pkgs.writeText "late-layers.json" (builtins.toJSON lateLayers);
  # fixed per release (./identity.nix): two builds give the same bytes, and stage 2 is built
  # for exactly this root (boot.stage2 = release/boot-stages.nix { rootUUID = identity.rootUUID; })
  fsUUID = identity.rootUUID;
  features = "has_journal ext_attr resize_inode dir_index filetype extent 64bit flex_bg metadata_csum_seed sparse_super large_file huge_file dir_nlink extra_isize metadata_csum";

  # the base with every layer but the late ones: what the late pieces link against
  rootTree = pkgs.runCommand "siliconforest-root-tree-${version}" {
    nativeBuildInputs = with pkgs; [ e2fsprogs python3 util-linux jq ];
  } ''
    set -euo pipefail
    mkdir -p work $out
    img=$(echo ${base}/*.img)
    # the base image's second partition is its ext4 root
    read -r start size < <(sfdisk --json "$img" | jq -r '.partitiontable.partitions[1] | "\(.start) \(.size)"')
    dd if="$img" of=work/base.ext4 bs=512 skip=$start count=$size status=none
    debugfs -R "rdump / $out" work/base.ext4 2> work/rdump.log
    python3 -I -B ${here}/assemble.py stage --root $out --layers ${layersJson} \
      --files ${files} --remove ${here}/remove.txt > layers.log
    mkdir -p $out/nix-support; cp layers.log $out/nix-support/layers.log
  '';

  rootfs = pkgs.runCommand "siliconforest-rootfs-${version}" {
    nativeBuildInputs = with pkgs; [ e2fsprogs fakeroot python3 util-linux jq ];
    passthru = { inherit layers lateLayers absent rootTree; };
  } ''
    set -euo pipefail
    mkdir -p $out work
    cp -a ${rootTree} work/root; chmod -R u+w work/root
    cp work/root/nix-support/layers.log $out/layers.log; rm -rf work/root/nix-support
    python3 -I -B ${here}/assemble.py stage --root work/root --layers ${lateJson} | tee -a $out/layers.log
    # Firmware is looked up at /Library/Firmware/{brcm,apple}; the release ships the empty
    # directories, the installer fills them from the target's own firmware (never from here)
    mkdir -p work/root/Library/Firmware/brcm work/root/Library/Firmware/apple
    fakeroot -- sh -euc '
      sh ${tree + "/m1-storage/system"}/sf-install.sh ${systemSource} work/root
      sh ${tree + "/m1-storage/userland"}/sf-userland-install.sh ${userlandSource} work/root
      python3 -I -B ${here}/assemble.py owners --root work/root --perms ${here}/permissions.tsv --manifest '"$out"'/root.manifest.tsv
      bytes=$(du -s --block-size=4096 work/root | cut -f1)
      entries=$(wc -l < '"$out"'/root.manifest.tsv)
      blocks=$(( bytes * (100 + ${toString slackPercent}) / 100 + 16384 ))
      inodes=$(( entries * 3 / 2 + 4096 ))
      E2FSPROGS_FAKE_TIME=1 mke2fs -q -F -t ext4 -b 4096 -I 256 -N $inodes \
        -O ^orphan_file,metadata_csum_seed -L SiliconForest -U ${fsUUID} \
        -E hash_seed=${fsUUID},lazy_itable_init=0,lazy_journal_init=0,root_owner=0:0 \
        -d work/root '"$out"'/siliconforest-root.ext4 $blocks
    ' | tee -a $out/layers.log
    # the filesystem must carry exactly the features the M1's root has (and its ext4 driver reads)
    got=$(dumpe2fs -h $out/siliconforest-root.ext4 2>/dev/null | sed -n 's/^Filesystem features: *//p')
    [ "$got" = "${features}" ] || { echo "ext4 features: $got" >&2; exit 1; }
    e2fsck -fn $out/siliconforest-root.ext4 > work/fsck.log 2>&1 || { cat work/fsck.log >&2; exit 1; }
    python3 -I -B - <<PY > $out/image.json
    import json, os
    print(json.dumps({"version": "${version}", "fs_uuid_placeholder": "${fsUUID}", "features": "${features}",
      "bytes": os.path.getsize("$out/siliconforest-root.ext4"), "layers": json.load(open("${layersJson}")) + json.load(open("${lateJson}")),
      "absent_optional": ${builtins.toJSON absent}}, indent=1))
    PY
  '';

  bootfiles = pkgs.runCommand "siliconforest-bootfiles-${version}" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    set -euo pipefail
    mkdir -p $out
    cp ${boot.stage1} $out/sf-stage1.bin
    cp ${boot.stage2} $out/boot.bin
    cp ${kernel}/kernel $out/kernel.kc
    cp ${here}/bootargs.template $out/bootargs.template
    cp ${tree + "/m1-native-boot/b1"}/pdsf_pack.py $out/pdsf_pack.py
    cp ${here}/sf_personalize.py $out/sf_personalize.py
    n=$(grep -a -c -F ${fsUUID} $out/boot.bin || true)
    [ "$n" = 1 ] || { echo "stage 2: the release root UUID ${fsUUID} found $n times, not once" >&2; exit 1; }
    python3 -I -B - $out <<'PY'
    import hashlib, json, os, sys
    out = sys.argv[1]
    files = {n: {"size": os.path.getsize(os.path.join(out, n)),
                 "sha256": hashlib.sha256(open(os.path.join(out, n), "rb").read()).hexdigest()}
             for n in sorted(os.listdir(out))}
    json.dump({"release": "${version}", "root_uuid": "${fsUUID}", "files": files,
               # install/build.sh, pack(): the configuration record's settings
               "pack_set": ["display=1", "usb-nodes=remove0", "sprr=1", "amx=1", "xnu-base=0x850000000"],
               "kernel_bin_max": 200 << 20}, open(os.path.join(out, "boot.json"), "w"), indent=1, sort_keys=True)
    PY
  '';

  release = pkgs.runCommand "siliconforest-release-${version}" { nativeBuildInputs = with pkgs; [ zstd python3 gnutar ]; } ''
    set -euo pipefail
    mkdir -p $out
    n=siliconforest-${version}
    zstd -q -19 -T4 --long=27 < ${rootfs}/siliconforest-root.ext4 | split -b 1900M -d -a 2 - $out/$n-root.ext4.zst.
    cp ${rootfs}/root.manifest.tsv $out/$n-root.manifest.tsv
    tar --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner -C ${bootfiles} -cf - . | zstd -q -19 > $out/$n-boot.tar.zst
    python3 -I -B - $out ${rootfs}/siliconforest-root.ext4 <<'PY'
    import hashlib, os, sys
    out, ext4 = sys.argv[1:]
    def sha(p):
        h = hashlib.sha256()
        with open(p, "rb") as f:
            for b in iter(lambda: f.read(1 << 20), b""): h.update(b)
        return h.hexdigest()
    names = sorted(os.listdir(out))
    with open(os.path.join(out, "MANIFEST.tsv"), "w") as m:
        m.write("# SiliconForest ${version}: file, size, sha256. The root parts concatenate to the zstd stream of\n")
        m.write("# siliconforest-root.ext4, whose size and sha256 are the line marked 'uncompressed'.\n")
        for n in names: m.write("%s\t%d\t%s\n" % (n, os.path.getsize(os.path.join(out, n)), sha(os.path.join(out, n))))
        m.write("siliconforest-root.ext4\t%d\t%s\tuncompressed\n" % (os.path.getsize(ext4), sha(ext4)))
    with open(os.path.join(out, "SHA256SUMS"), "w") as s:
        for n in names + ["MANIFEST.tsv"]: s.write("%s  %s\n" % (sha(os.path.join(out, n)), n))
    PY
  '';

  qemu = if qemuBase == null then null else pkgs.runCommand "siliconforest-qemu-${version}.img" {
    nativeBuildInputs = with pkgs; [ util-linux jq e2fsprogs mtools ];
  } ''
    set -euo pipefail
    img=$(echo ${qemuBase}/*.img)
    read -r espStart espSize < <(sfdisk --json "$img" | jq -r '.partitiontable.partitions[0] | "\(.start) \(.size)"')
    read -r rootType rootUuid rootName < <(sfdisk --json "$img" | jq -r '.partitiontable.partitions[1] | "\(.type) \(.uuid) \(.name|gsub(" ";"_"))"')
    root=${rootfs}/siliconforest-root.ext4
    rootSectors=$(( $(stat -c %s $root) / 512 ))
    total=$(( espStart + espSize + rootSectors + 2048 + 34 ))
    truncate -s $(( total * 512 )) $out
    # same partition identifiers as the QEMU base: its loader names the root by them
    sfdisk --json "$img" | jq -r '.partitiontable.id' > id
    {
      echo "label: gpt"; echo "label-id: $(cat id)"
      echo "start=$espStart, size=$espSize, type=$(sfdisk --json "$img" | jq -r '.partitiontable.partitions[0].type'), uuid=$(sfdisk --json "$img" | jq -r '.partitiontable.partitions[0].uuid')"
      echo "start=$(( espStart + espSize )), size=$rootSectors, type=$rootType, uuid=$rootUuid, name=\"''${rootName//_/ }\""
    } | sfdisk -q $out
    dd if="$img" of=$out bs=512 skip=$espStart seek=$espStart count=$espSize conv=notrunc status=none
    dd if=$root of=$out bs=512 seek=$(( espStart + espSize )) conv=notrunc,sparse status=none
    # the QEMU loop's boot arguments for an emulated guest (qemu-dev/qd_image.py, debug kernel):
    # no_lock_timeouts=1, or a descheduled vCPU on a busy host reads as a spinlock deadlock
    printf '%s' 'debug=0x218 -nogzalloc_mode keepsyms=1 serial=3 gopconsole=1 serial_video_mirror=0 -noprogress no_interrupt_masked_debug=1 no_lock_timeouts=1' > boot-args.txt
    mcopy -o -i "$out@@$(( espStart * 512 ))" boot-args.txt ::/EFI/BOOT/boot-args.txt
  '';
in { inherit rootfs rootTree bootfiles release qemu layers lateLayers absent; }
