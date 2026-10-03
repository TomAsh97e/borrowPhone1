# BorrowPhone

BorrowPhone is a native ArkTS/ArkUI MVP for Oniro/OpenHarmony. An owner selects one to five photos with the system picker, the app decodes bounded JPEG/PNG previews into RAM, and a guest can browse only that immutable selection.

## Security scope

> **Viewer only. Other apps remain accessible.**

This build does **not** provide whole-device confinement and must not be presented as a safe phone-handoff mode. The UI repeats this limitation. A managed kiosk integration is intentionally not included because the tested Oniro emulator is not provisioned for it.

Implemented protections:

- no broad gallery read/write permission;
- system photo picker limited to five images;
- JPEG/PNG validation, 25 MiB and 50 MP input limits, and proportional decoding to a 1600 px maximum edge;
- RAM-only `PixelMap` session; source handles and URIs are discarded after preparation;
- internal read-only viewer with bounded Previous/Next controls;
- fresh native system-PIN request for authenticated owner entry/return, without unlock-result reuse;
- privacy-window mode before app content is loaded;
- unexpected backgrounding clears the session and returns to a neutral locked screen;
- cold starts never restore photos or authorization.

The **unprotected MVP demo** button exists only so the viewer can be exercised on an emulator without an enrolled PIN. It is visibly labelled and returns to the locked screen rather than granting owner controls.

## Tested environment

| Item | Observed value |
| --- | --- |
| Runtime | Oniro emulator, OpenHarmony `6.1.0.31`, API 23 |
| Compile SDK | OpenHarmony API 23 |
| Minimum compatible SDK | API 20 |
| CLI | `@oniroproject/oniro-app` 0.11.0 |
| Hvigor | 5.18.5 |
| Bundle / ability | `org.hackyeah.borrowphone` / `EntryAbility` |

The project uses one Stage-model entry HAP and no backend or third-party runtime dependency.

## Build and run

Install Node.js 20+, a JDK, and `oniro-app`, then provision its OpenHarmony tools:

```bash
npm install -g @oniroproject/oniro-app
oniro-app sdk install 6.1
oniro-app cmdtools install
oniro-app emulator install
```

From this repository:

```bash
oniro-app sign .
oniro-app build .
oniro-app emulator start --wait-for-hdc 300  # omit if already running
oniro-app app install .
oniro-app app launch .
```

The signed package is written to:

```text
entry/build/default/outputs/default/entry-default-signed.hap
```

`oniro-app sign` generates local development signing material. Signing files, build outputs, IDE state and `local.properties` are ignored by Git.

### Put demo photos in the Oniro emulator

The picker needs media in the emulator library. With one emulator connected:

```bash
oniro-app file send ./demo.jpg /data/local/tmp/demo.jpg
~/setup-ohos-sdk/linux/23/toolchains/hdc shell \
  mediatool send /data/local/tmp/demo.jpg
```

Repeat with up to eight harmless JPEG/PNG files, then open BorrowPhone and choose **Continue with unprotected MVP demo** → **Choose photos**.

To test the real owner-authentication path, first configure a lock-screen PIN in the emulator/device settings. If no ATL3 PIN is enrolled, BorrowPhone fails closed and keeps owner controls locked.

## Checks

Run the pure session-rule check:

```bash
node tests/session_rules_test.mjs
```

Build and device checks performed on the environment above:

| Check | Result |
| --- | --- |
| Session selection/scaling/index rules | Passed |
| Sign/build from a clean source-only copy | Passed |
| Signed HAP build | Passed |
| Install and launch on Oniro | Passed |
| Native picker displays three seeded photos | Passed |
| Select two photos, decode sequentially, review and enter guest viewer | Passed for JPEG |
| Screenshot while protected window is visible | App pixels hidden; capture showed the launcher |
| Home during guest session, then relaunch | Returned locked; session discarded |
| Native PIN with no enrolled emulator PIN | Failed closed with an unavailable message |
| Whole-device confinement | **Not implemented / not claimed** |
| Fingerprint, PNG, corrupt/oversized input, recording/Recents and physical hardware | Not yet tested |

## Project map

- `entry/src/main/ets/pages/Index.ets` — MVP state, picker/import flow, authentication and UI.
- `entry/src/main/ets/entryability/EntryAbility.ets` — privacy-window setup and lifecycle invalidation.
- `entry/src/main/ets/model/SessionRules.ts` — bounded selection, scaling and index rules.
- `tests/session_rules_test.mjs` — runnable lightweight check.
- [`01_ARCHITECTURE.md`](01_ARCHITECTURE.md) through [`05_HACKATHON_COMPLIANCE.md`](05_HACKATHON_COMPLIANCE.md) — design, threat model, API map, validation backlog and contest fit.
- [`AI_WORKFLOW.md`](AI_WORKFLOW.md) — AI-use disclosure.

## MVP limitations

No kiosk/MDM integration, video, zoom, files, notes, persistence, sharing, cloud service, analytics or custom PIN database is included. Add containment only for a named, provisioned device after Home/Recents/notification/call/crash tests pass; until then this remains a selected-photo viewer, not whole-phone protection.
