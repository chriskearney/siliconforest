<!-- SPDX-License-Identifier: MIT -->
# installer/payload: the shippable release

Tools that turn a SiliconForest release root into a signed installer release, and extract a Mac's
firmware from Apple's restore image. Design and results: [`docs/installer/PAYLOAD.md`](../../docs/installer/PAYLOAD.md).
Files and images only; nothing here opens a device or publishes anything.

| Path | What |
|---|---|
| `image/prepare_root.py` | Release root → installer root: firmware and receipt slots, first-start job, `root.json` |
| `image/grow_check.py` | Proves, with resize2fs as the test oracle, that an offline grow keeps the slots in place |
| `image/synthetic_base.py` | A small stand-in root for tests and CI |
| `image/sf-installer-firstboot`, `sf-boot-receipt`, `sf-unpack-firmware` | Installed into the root |
| `release/make_release.py`, `verify_release.py`, `sfrelease.py` | `install.json` (`siliconforest-install/2`), `SHA256SUMS` and its SSH signature, and verification |
| `release/make_test_key.sh` | A throwaway **TEST-ONLY** key for rehearsals. Not the release key, which only Chris makes |
| `release/receipt.py` | The boot receipt as macOS reads it (reference for the Swift reader) |
| `firmware/extract_firmware.py`, `remote_zip.py`, `wifi.py` | On a Mac: firmware from the 13.5 restore image (Wi-Fi collector ported from Asahi v0.9.2, MIT) |
| `firmware/names/` | Names and SHA-256 of the extracted files. Never the files |
| `rehearse.sh` | The whole chain on a synthetic or real root |

```sh
installer/payload/rehearse.sh /tmp/sf-rehearsal                       # synthetic root, placeholder boot files
python3 -m unittest -v tests.test_installer_payload                   # needs e2fsprogs, xz, perl, ssh-keygen
python3 installer/payload/firmware/extract_firmware.py --profile installer/profiles/J313.json --work ~/sf-fw   # on a Mac
```
