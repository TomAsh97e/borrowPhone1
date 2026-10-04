# SafeShare (BorrowPhone)

SafeShare is a native ArkTS/ArkUI app for OpenHarmony that implements the SafeShare Photo Vault design (Polish UI). The owner sees the phone gallery, picks a time period (today, yesterday, last weekend or a custom date range) and hands the phone over. The guest can browse only the photos taken in that period; leaving guest mode requires the owner's 4-digit PIN.

## How it works

- **Owner gallery**: every photo in the media library (up to 500, newest first) is shown in a 3-column grid. Photos outside the selected period are dimmed, blurred and marked with a lock. Tapping a photo shows its date, resolution and camera model (EXIF).
- **Guest mode**: full-screen viewer with swipe, double-tap zoom, a filmstrip and a "+N" locked tile. Swiping past either end of the period shows a boundary notice instead of other photos.
- **PIN**: created on the first hand-off, stored as a salted PBKDF2-SHA256 hash in app preferences (never displayed). Five wrong attempts lock PIN entry for 30 seconds. The PIN can be changed in Settings with the current PIN.
- **Leaving the app**: the system Back button opens the PIN pad. Going to the home screen or another app turns the screen into a non-dismissable PIN lock. If the app is killed during a guest session, the next start opens straight into that lock.
- **Settings**: light/dark theme, PIN change, leave alarm on/off, hide photo details from the guest.

There is no network backend: the "backend" is the local media library (`photoAccessHelper`) plus app preferences.

## Security scope

> **Viewer only. Other apps remain accessible.**

OpenHarmony does not let a normal app block the system Home/Recents gestures. A guest can still open other apps (including the system Gallery); SafeShare only locks itself. Whole-device confinement needs an MDM-provisioned device and is not implemented. The window runs in privacy mode, so system screenshots and recordings do not capture its content.

The app requests `ohos.permission.READ_IMAGEVIDEO`. Its level is `system_basic` with `provisionEnable: true`, so the signing profile must list it in `acls.allowed-acls` (see below); the user still has to allow it in the system prompt.

## Tested environment

| Item | Observed value |
| --- | --- |
| Runtime | OpenHarmony QEMU phone image (`~/.ohos-qemu/openharmony-qemu-x86_64-x86_64_virt-phone`), OpenHarmony `7.0.0.39`, API 26 |
| Compile SDK | OpenHarmony API 23 (`oniro-app sdk install 6.1`) |
| Minimum compatible SDK | API 20 |
| CLI | `@oniroproject/oniro-app` 0.11.0 on Node.js 22 |
| Bundle / ability | `org.hackyeah.borrowphone` / `EntryAbility` |

## Build and run

Install Node.js 20+ (22 recommended), a JDK, and `oniro-app`:

```bash
npm install -g @oniroproject/oniro-app
oniro-app sdk install 6.1
oniro-app cmdtools install
```

Start the emulator (use `sg kvm -c "…"` if the session is not yet in the `kvm` group):

```bash
~/.ohos-qemu/openharmony-qemu-x86_64-x86_64_virt-phone/launch/linux.sh -r 720x1280
```

From this repository:

```bash
oniro-app sign . --acls ohos.permission.READ_IMAGEVIDEO   # once; re-signing creates new keys
oniro-app build .
~/setup-ohos-sdk/linux/23/toolchains/hdc tconn 127.0.0.1:5555
oniro-app app install .
oniro-app app launch .
```

Every `oniro-app sign` run generates new signing material, so an already installed copy must be uninstalled first (`oniro-app app uninstall org.hackyeah.borrowphone`), which also deletes the stored PIN.

### Demo photos

The gallery needs photos with dates. Copy JPEG/PNG files (their EXIF `DateTimeOriginal` becomes the photo date) into the media library:

```bash
~/setup-ohos-sdk/linux/23/toolchains/hdc file send ./photos /data/local/tmp/photos
~/setup-ohos-sdk/linux/23/toolchains/hdc shell mediatool send /data/local/tmp/photos
```

## Checks

Run the date-range and PIN rule check:

```bash
node tests/session_rules_test.mjs   # needs Node.js 22.18+ (imports a .ts file)
```

Device checks performed on the environment above:

| Check | Result |
| --- | --- |
| Permission prompt, gallery load, 3-column grid with locked photos | Passed |
| Presets Today / Yesterday / Weekend and custom range (system date dialog) | Passed |
| Photo detail with EXIF camera model | Passed |
| Light/dark theme incl. system bar colors | Passed |
| PIN creation with mismatching confirmation, then guest mode | Passed |
| Guest swipe, boundary notices, filmstrip, zoom, details overlay | Passed |
| Back button in guest mode → PIN pad | Passed |
| Home during guest mode, return → non-dismissable PIN lock | Passed |
| Force-stop during guest mode, relaunch → PIN lock, owner gallery hidden | Passed |
| 5 wrong PINs → 30 s lockout, correct PIN rejected until it expires | Passed |
| PIN change with wrong / correct current PIN | Passed |
| Whole-device confinement | **Not implemented / not claimed** |

## Project map

- `entry/src/main/ets/pages/Index.ets` — screens and state: owner gallery, period filter, photo detail, settings, guest viewer, PIN pad.
- `entry/src/main/ets/service/AppStore.ets` — PIN hash, lockout, settings and guest-session flag in preferences.
- `entry/src/main/ets/service/Gallery.ets` — gallery permission, media library query, EXIF camera model.
- `entry/src/main/ets/service/Haptics.ets` — vibration feedback.
- `entry/src/main/ets/common/` — theme palettes and Polish date formatting.
- `entry/src/main/ets/model/SessionRules.ts` — date ranges, PIN format and index rules.
- `entry/src/main/ets/entryability/EntryAbility.ets` — privacy window and background detection.
- `tests/session_rules_test.mjs` — runnable lightweight check.
- [`01_ARCHITECTURE.md`](01_ARCHITECTURE.md) through [`05_HACKATHON_COMPLIANCE.md`](05_HACKATHON_COMPLIANCE.md) — design notes for the earlier picker-based MVP.
- [`AI_WORKFLOW.md`](AI_WORKFLOW.md) — AI-use disclosure.
