# BorrowPhone — HarmonyOS API map

Planning baseline checked 3 October 2026. The first OpenHarmony/Oniro implementation now compiles with API23 and minimum API20; Huawei commercial-device parity remains unverified.

## Platform baseline

Use native ArkTS and ArkUI in DevEco Studio, the Stage model, one UIAbility and one installable `.hap`. Configure target API **20 or later**, with minimum API **20** for this project. A general “HarmonyOS NEXT / 5+” label does not establish the exact API level: record the installed SDK, emulator image and eventual physical device version before implementation. Keep the baseline independent of APIs introduced after 20.

The offline application uses selective media access, native image processing, system authentication and window privacy. No backend, account, analytics, synchronization or gallery index is needed.

## API and verification matrix

“Huawei verified” means documentation content was accessible during research, not that an implementation has passed device tests. “OpenHarmony corroboration” identifies official upstream documentation and is **not** proof of identical Huawei API20 behavior.

| Kit / API | Purpose and permission boundary | Evidence, version and required check |
|---|---|---|
| Media Library Kit: `photoAccessHelper.PhotoViewPicker`, `PhotoSelectOptions`, `select` | Owner selects 1–5 images. Use `IMAGE_TYPE`, maximum 5, and validate the returned list. Do not request `READ_IMAGEVIDEO`, `WRITE_IMAGEVIDEO` or `MEDIA_LOCATION`. | Huawei confirms selective system pickers without broad permissions [H1, H2]. Upstream documents this picker since API10 [O1]. Compile the exact Huawei SDK20 signatures and test cancellation, empty results and unavailable media. |
| Core File Kit: `fileIo` selected-URI adapter | Read only the owner's selected resources; close every file descriptor. No external sharing or directory enumeration. | Huawei's example opens picker URI with `fileIo` [H3]. Upstream specifies read-only access after returning from the picker [O2]. Validate this exact path on API20 before committing implementation. |
| Image Kit: `image.createImageSource`, `ImageSource.createPixelMap`, `PixelMap` | Decode bounded, correctly oriented still previews in RAM; release source and pixel resources. No network or media write permission. | Huawei verifies Image Kit and orientation handling [H4, H5]. Upstream lists resizing and decoding options; SDR selection is marked API12+ [O3]. Confirm signatures and orientation behavior in SDK20. |
| User Authentication Kit: `userAuth.getUserAuthInstance`, `start`, result callback, `cancel` | Explicit owner authentication before protected actions. System PIN and available biometrics; never read/store the system credential. | Huawei marks the instance API10+ and requires `ohos.permission.ACCESS_BIOMETRIC` for start/cancel [H6]. Check capability/enrollment and emulator behavior. An unavailable authenticator must not produce success. |
| Ability Kit: `UIAbility` lifecycle | Invalidate owner access and cover guest content when interrupted; start cold in a locked state. | Lifecycle integration is required. Verify ordering of background/foreground and destruction events on the chosen image; callbacks are not an OS confinement mechanism. Test system dialogs separately from genuine departures. |
| ArkUI Window: `Window.setWindowPrivacyMode` | Reduce screenshots, screen recording and recent-task previews of the app window; requires `ohos.permission.PRIVACY_WINDOW` in the upstream contract. | Verify the permission and method in Huawei SDK20 and test each output channel. API success alone does not prove every surface is protected. See [the security plan](02_SECURITY_AND_LOCKING.md) for official Window and permission sources. |
| Ability Kit: `kioskManager.enterKioskMode` / `exitKioskMode`; MDM allowance | Conditional device-confinement integration for a separately prepared deployment. | Huawei documents API20, Stage and an allowlist prerequisite. MDM administration is a separate privilege. Ordinary installation must not assume it. See [the security plan](02_SECURITY_AND_LOCKING.md) for sources and the process-termination limitation. |
| Core File Kit: `picker.DocumentViewPicker` | Later explicit file selection, followed by an internal allowed-format viewer. | Huawei public documentation; context constructor API12+ [H7]. Test selected URI access separately from photos. No external viewer in guest mode. |

## Selected-photo preparation contract

The owner opens the system picker. After returning, a separate “Prepare” action starts sequential imports. This avoids assuming that a resource can be opened inside the picker callback: upstream documentation explicitly cautions against that sequence [O2].

The adapter accepts only the current selection. The initial supported inputs are JPEG and PNG still images. Check actual format, dimensions and resource limits rather than trusting filenames. Unsupported, corrupted, deleted or cloud-only unavailable media produces an owner-visible error before handoff. Do not silently fall back to an external gallery or original URI.

Read through the validated SDK20 adapter, decode proportionally to a bounded resolution, normalize orientation including mirrored EXIF cases, and retain only the prepared PixelMap. A proposed starting limit is a 1600-pixel longest edge. Five square RGBA previews consume approximately 49 MiB of pixel buffers before additional overhead; measure peak decoding memory on each claimed target and adjust the bound. Release input descriptors and ImageSource objects promptly.

Guest components receive opaque session item IDs and prepared pixels, without source URI, filenames, EXIF, PhotoAsset objects or picker access. Do not persist selected URIs, thumbnails or session state. Release resources on disposal. RAM-only storage avoids application photo files for backup; it does not guarantee forensic memory erasure.

Do not promise that picker permissions expire at a particular lifecycle event. Huawei's general guide describes temporary resource access [H1], while current upstream picker reference describes permanent authorization for a particular `getAssets` route [O1]. The architecture therefore enforces its own session allowlist and discards access handles. Exact URI lifetime and any applicable public revocation API remain SDK/device checks.

## Later extensions and release gates

Files reuse the session policy through a separate DocumentViewPicker adapter and internal renderer. Notes initially mean notes owned by BorrowPhone or explicitly imported text; no assumed general API to the Huawei Notes database. Neither feature belongs in the first photo-only build.

Before declaring the API integration complete, verify real picker selection on API20, prepared-image fidelity, bounded memory, authentication failure/cancellation, process death, and privacy behavior during recent-task view, capture and interruptions. A platform permission denial must remain a denied operation. Full-device protection is a separate decision gate in the security document.

## Primary sources

- [H1 — Huawei: starting system applications and selective pickers](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V14/system-app-startup-V14).
- [H2 — Huawei: Media Library Kit capabilities](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V13/photoaccesshelper-overview-V13).
- [H3 — Huawei: example reading a selected media URI](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/cloudfoundation-storage-upload-file). BorrowPhone does not adopt its cloud upload.
- [H4 — Huawei: Image Kit encoding](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V13/image-picture-encoding-V13).
- [H5 — Huawei: image orientation FAQ](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-arkui-720).
- [H6 — Huawei: User Authentication API](https://developer.huawei.com/consumer/en/doc/harmonyos-references-V14/js-apis-useriam-userauth-V14).
- [H7 — Huawei: Core File Kit pickers and deprecated old photo picker](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-file-picker). Use MediaLibraryKit's photo picker, not deprecated `picker.PhotoViewPicker`.
- [O1 — OpenHarmony: PhotoViewPicker](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-media-library-kit/arkts-apis-photoAccessHelper-PhotoViewPicker.md).
- [O2 — OpenHarmony: selecting and reading media](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/media/medialibrary/photoAccessHelper-photoviewpicker.md).
- [O3 — OpenHarmony: image options and version markers](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-image-kit/arkts-apis-image-i.md).

Some current Huawei reference pages returned an empty document or a retrieval error. Older accessible Huawei pages and explicitly identified upstream documentation support planning; final availability and behavior must be checked against the actual Huawei SDK20 and runtime.
