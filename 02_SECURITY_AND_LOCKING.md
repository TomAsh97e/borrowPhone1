# BorrowPhone — Security and locking

Status: initial viewer-only MVP implemented and exercised on the Oniro OpenHarmony 6.1 API23 emulator on 3 October 2026. Minimum API: 20; compile API: 23. No physical-device or whole-device-confinement validation has been performed.

## 1. The security promise has two separate requirements

BorrowPhone must enforce both:

1. **Content restriction:** the guest can view only the selected photos and cannot access owner controls without fresh authentication.
2. **Device confinement:** the guest cannot leave BorrowPhone and reach other phone data without owner authorization.

The application can implement the first requirement within its own boundaries. The second requires an independently verified operating-system mechanism. A restricted gallery, fullscreen layout, hidden navigation buttons or an application PIN does not establish device confinement.

**Release rule:** whole-phone handoff stays disabled until confinement is verified on the exact device, system build and installation configuration. An explicitly labelled **preview-only** mode may demonstrate the selected-photo viewer. It **does not satisfy the original promise of safely handing over the phone** and must not display “phone protected”. Use synthetic demonstration photos when that verification is unavailable.

The guest is assumed to know common phone gestures and to try other applications, screenshots, notifications and repeated exit attempts. Root access, a compromised operating system and forensic extraction are outside this MVP's threat model.

## 2. Baseline content boundary

**Proposed design:** the owner selects one to five JPEG or PNG still photos. BorrowPhone prepares normalized still-image `PixelMap` objects in memory and gives the guest viewer an immutable session containing only those objects. No persistent imports, saved session manifests, thumbnails or photo database are created. Video, animated and moving-photo support is deferred; unsupported content prevents that item from entering the session.

The guest cannot reopen the picker, modify the selection, inspect original URIs or metadata, launch an external viewer, share, save, copy or drag content out. Authorization belongs in the session service as well as the screen navigation. Hiding buttons alone is insufficient. Ignore incoming intents that attempt to open owner routes during a guest session.

Close source handles and release original-URI references after preparation. Release images when the session ends. Apply image dimension and memory limits during preparation so oversized inputs cannot crash the viewer easily. A process restart loses the session and begins locked. RAM-only storage reduces retained data; it is not a claim of guaranteed memory zeroization or immunity to crash diagnostics. Never log photo data, original URIs, authentication tokens or credentials.

## 3. Owner authentication

**Huawei fact:** UserAuthenticationKit provides the system authentication widget through `getUserAuthInstance`, result subscription and `start()`. Authentication instances are single-use. `start()` and capability checks require `ohos.permission.ACCESS_BIOMETRIC`; supported types include system PIN and fingerprint. The cited Huawei reference is API14 documentation for APIs introduced earlier, so exact API20 declarations and device behavior remain a build-time verification item. [Huawei UserAuth reference](https://developer.huawei.com/consumer/en/doc/harmonyos-references-V14/js-apis-useriam-userauth-V14).

**Proposed default:** an explicit “Owner controls” action requests fingerprint or the **system lock-screen PIN/password**. Do not collect that credential inside BorrowPhone. Face authentication is disabled by default: the owner standing nearby should not unintentionally authorize the guest's exit attempt.

At owner setup, verify a supported, enrolled authentication method at the selected trust level. Prefer ATL3 where supported; do not silently lower the level. If native authentication is unavailable, unconfigured, locked out or unreliable, block protected-session creation. Explain the required device setup while the owner still controls the phone.

Each attempt receives a new random challenge, a new authentication instance and a session/attempt identifier. Only the named `SUCCESS` result for that current attempt can authorize owner controls. Cancel, timeout, errors and partial biometric progress never count as success.

**OpenHarmony evidence:** optional `reuseUnlockResult` defaults to no reuse. BorrowPhone must leave it unset. Reusing the owner's recent device unlock could authorize exit immediately after handoff. [Official OpenHarmony UserAuth](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-user-authentication-kit/js-apis-useriam-userauth.md).

Any credential enrolled for that operating-system user is trusted by native authentication. BorrowPhone does not identify a separate biological “owner”. A custom application PIN is deferred: secure derivation, storage, throttling, recovery and reset behavior would enlarge the MVP substantially, while still failing to stop Home or Recents escape.

## 4. Privacy must precede pixels

**OpenHarmony evidence:** `Window.setWindowPrivacyMode(true)` requires `ohos.permission.PRIVACY_WINDOW`; the documented behavior blocks ordinary capture/recording and masks background task cards. Its promise can fail, including for a missing permission or invalid window state. This is the ordinary Window API, not an extension-content-session substitute. [Official Window reference](https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/reference/apis-arkui/arkts-apis-window-Window.md).

**Proposed design:** create a neutral window, enable privacy, await success, then render photos. Repeat for each recreated app-owned window. Privacy activation failure blocks the protected viewer and shows a neutral error. Keep a neutral overlay available for lifecycle transitions; do not rely solely on an asynchronous background callback to hide a task snapshot.

**OpenHarmony evidence:** ACCESS_BIOMETRIC and PRIVACY_WINDOW are public `normal` permissions with `system_grant`; PRIVACY_WINDOW has been normal since API11. Verify the commercial Huawei API20 permission catalog and installation behavior before accepting the build. [Official permission definitions](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/security/AccessToken/permissions-for-all.md).

Privacy protection concerns app-owned windows. It cannot promise control over the system picker, every projection surface or a second camera photographing the display. RAM-only sessions avoid creating application backup assets; they do not prove every vendor diagnostic or backup behavior.

## 5. Device-confinement options

| Mechanism | Decision |
|---|---|
| Fullscreen, hidden bars, intercepted Back | Useful presentation/navigation behavior; never a device security boundary. |
| Manual system screen pinning | Unverified for the target NEXT device; cannot be assumed available. |
| System App Lock | Optional owner-configured supplement; does not confine the whole phone. |
| API20 kiosk mode | Conditional managed-device evaluation; excluded from ordinary consumer baseline. |
| Accessibility/overlay escape prevention | Rejected: no dependable confinement guarantee. |

**Huawei fact:** API20 `kioskManager` supports Stage applications, but only after allowance through `applicationManager.setAllowedKioskApps`. Huawei explicitly states that terminating the initiating process automatically exits kiosk mode. Therefore, even successful kiosk entry does not justify an unconditional claim that a crash leaves the entire device locked. [Huawei kioskManager](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/js-apis-app-ability-kioskmanager).

**OpenHarmony evidence:** configuring the allowlist requires an activated device-management application and `ohos.permission.ENTERPRISE_SET_KIOSK`. The public `isAppKioskAllowed` check can inspect allowance; it cannot grant it. [Official MDM applicationManager](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-mdm-kit/js-apis-enterprise-applicationManager.md).

A managed demonstration is an optional deployment variant only if the supplied device is already provisioned and its restrictions are tested. Do not implement MDM enrollment, system modifications or privileged signing workarounds in the MVP. Independently test native authentication within kiosk, including cancellation and process death.

Huawei's screen-pinning article applies to named HarmonyOS2/EMUI11 devices; it establishes neither NEXT support nor authentication-gated unpinning. [Legacy screen pinning](https://consumer.huawei.com/uk/support/content/en-gb15805372/). Huawei documents App Lock on named HarmonyOS5.1 phones, including an immediate-relock-after-exit option. That may protect selected other apps, but notifications and uncovered applications remain separate risks. [Huawei App Lock](https://consumer.huawei.com/cn/support/content/zh-cn16053287/).

## 6. Lifecycle and authorization invariants

- Every cold start begins `LOCKED`, with neutral pixels and no restored owner authorization.
- Starting a guest session revokes previous owner authorization and freezes the selected-photo list.
- An explicit exit action enters `AUTH_PENDING`; guest permissions remain restricted throughout authentication.
- Treat the expected system authentication dialog separately from an unrelated app switch. Verify its actual focus/foreground callbacks on the target device. Returning to the foreground is never authentication success.
- Unsolicited backgrounding, session replacement or termination invalidates pending attempts, releases the session and requires owner authentication on return. Cancelling only an exit-authentication attempt preserves the valid guest session if it remains foreground; otherwise stay locked. Discard late callbacks by session/attempt identifier.
- If lifecycle behavior cannot be distinguished reliably, remain locked. A fresh successful attempt may be required; no owner screen should flash during recovery.
- Process death protects the application's next launch through `LOCKED`; it does not establish that the operating system itself remains confined.

## 7. Required acceptance evidence

Test on the actual phone with the intended signed installation:

| Attempt or failure | Required result |
|---|---|
| Swipe past the fifth photo; reopen picker; incoming owner-route intent | Only selected stills remain reachable. |
| Exit immediately after owner unlocked the phone | Fresh native authentication appears. |
| Wrong credential, cancel, timeout, busy service, late callback | No owner controls or picker access. |
| Background/foreground, screen lock, orientation change, cold restart | Neutral/locked transition; no stale owner authorization. |
| Screenshot, recording, task preview | Protected app pixels are hidden; failures block protected mode. |
| Home, Recents, notification/control center, calls, assistant, split screen, keyboard shortcuts | Whole-phone mode remains disabled unless all relevant confinement checks pass. |
| Crash, forced stop or reboot during confinement | Record actual OS behavior; never infer safety from app relaunch alone. |

Keep the device model, OS build, SDK version, signing configuration, test outcomes and known exceptions with the demo evidence. Unknown capability means unavailable protection, not assumed success.
