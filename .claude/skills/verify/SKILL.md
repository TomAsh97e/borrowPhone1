---
name: verify
description: Build, install and drive SafeShare on the local OpenHarmony 7.0 QEMU emulator, capturing the real display over VNC.
---

# Verify SafeShare on the OpenHarmony QEMU emulator

## Toolchain (already installed on this laptop)
- `export PATH=~/.local/share/oniro-cli/bin:$PATH` — Node 22 + `oniro-app` 0.11.
- SDK API 23 in `~/setup-ohos-sdk/linux/23`; slim cmdtools in `~/command-line-tools`
  (its `sdk/` is a placeholder + symlink to the API 23 toolchains, needed by hvigorw and hdc lookup).
- hdc: `~/setup-ohos-sdk/linux/23/toolchains/hdc -t 127.0.0.1:5555 …`

## Emulator for automated checks
Start with VNC on the phone display (q35's default VGA would otherwise be the VNC console):
```bash
QEMU_EXTRA_ARGS='-vga none' sg kvm -c "QEMU_EXTRA_ARGS='-vga none' ~/.ohos-qemu/openharmony-qemu-x86_64-x86_64_virt-phone/launch/linux.sh -r 720x1280 --display vnc"
hdc tconn 127.0.0.1:5555   # boot ≈ 15 s; check: hdc shell param get bootevent.boot.completed
```
Stop it cleanly with `hdc shell reboot shutdown`.

## Build / install
```bash
oniro-app build .                     # signing is already in build-profile.json5
oniro-app app install . && oniro-app app launch .
```
Re-running `oniro-app sign . --acls ohos.permission.READ_IMAGEVIDEO` makes new keys → uninstall first.

## Drive and capture
- Tap: `hdc shell uitest uiInput click X Y`; swipe: `… swipe x1 y1 x2 y2 1500`; keys: `… keyEvent Back|Home`;
  text: `… inputText X Y 1234`. Layout/bounds: `oniro-app dump layout --device 127.0.0.1:5555`.
- `oniro-app screenshot` shows only the launcher: the app window is in privacy mode. Grab the real display
  from QEMU's VNC (127.0.0.1:5921) with a minimal RFB client (raw encoding, BGRX 32 bpp).
- Overlays and dialogs take 1.5–3 s to appear on first open; wait before concluding something did not render.
- Seed photos with EXIF DateTimeOriginal: `hdc file send dir /data/local/tmp/seed` then `hdc shell mediatool send /data/local/tmp/seed`.
- Device time zone is Asia/Shanghai; "Today"/"Yesterday" follow device local time.

## Flows worth driving
Permission prompt → grid; presets + custom range; detail (EXIF camera); hand-off → PIN create (mismatch, then match);
guest swipe/boundaries/zoom/filmstrip; Back → PIN pad; Home + return → panic lock; force-stop + relaunch → resume lock;
5 wrong PINs → 30 s lockout; Settings PIN change.
