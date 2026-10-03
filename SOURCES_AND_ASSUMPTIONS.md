# Sources, evidence and assumptions

Research date: **3 October 2026**. Official web documentation was consulted because platform APIs and permission rules change. Evidence describes documentation reviewed, not a running BorrowPhone application.

## 1. Supplied competition documents

| ID | Document | Relevant material |
| --- | --- | --- |
| R1 | `CRITERIA Imagine What_s Next.pdf`, four pages, supplied by the user | p.1 challenge/themes; p.2 API20, platform/toolchain requirements, installable component and AI policy; p.3 deliverables and scoring; p.4 scoring details |
| R2 | `RULES Imagine What_s Next.pdf`, five pages, supplied by the user | p.2 section 4 English materials, development and disclosure; p.3 section 5 weights; p.5 section 9 organizer updates |

The two files were read in full. Their names are retained here without publishing the user's Downloads path. No official deadline time was inferred. The general HackYeah rules and any later organizer announcement were not reviewed by this task.

## 2. Technical source register

| ID | Primary source | Evidence scope and limitation |
| --- | --- | --- |
| S1 | [Huawei Application Models](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V14/application-models-V14) | Archived official guidance for the Stage model; not an installed-SDK check |
| S2 | [Huawei File Picker reference](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-file-picker) | Current retrieved reference distinguishes DocumentViewPicker and deprecated PhotoViewPicker; points photo selection to photoAccessHelper |
| S3 | [Official OpenHarmony PhotoViewPicker](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-media-library-kit/arkts-apis-photoAccessHelper-PhotoViewPicker.md) | Upstream selected-media API family; exact Huawei API20 overload and URI semantics need local SDK verification |
| S4 | [Huawei User Authentication, API14 reference](https://developer.huawei.com/consumer/en/doc/harmonyos-references-V14/js-apis-useriam-userauth-V14) | System authentication widget, PIN/biometric types and permission; current installed declarations still to check |
| S5 | [Official OpenHarmony UserAuth](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-user-authentication-kit/js-apis-useriam-userauth.md) | Upstream authentication details, including optional reuse behavior; not commercial-device validation |
| S6 | [Official OpenHarmony Window reference](https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/reference/apis-arkui/arkts-apis-window-Window.md) | Ordinary Window privacy API behavior; verify on commercial Huawei target |
| S7 | [Official OpenHarmony public permissions](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/security/AccessToken/permissions-for-all.md) | Upstream permission categories; not a guarantee of commercial signing approval |
| S8 | [Huawei kioskManager](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/js-apis-app-ability-kioskmanager) | Retrieved current Chinese official reference, API20 and deployment restrictions |
| S9 | [Official OpenHarmony enterprise applicationManager](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-mdm-kit/js-apis-enterprise-applicationManager.md) | Upstream MDM allowlisting and administrative requirements |
| S10 | [Huawei MDM Kit API20 Beta3 changes](https://developer.huawei.com/consumer/en/doc/harmonyos-releases/js-apidiff-mdmkit-6003) | Historical API20 changes; useful corroboration, not full provisioning instructions |
| S11 | [Huawei App Lock, HarmonyOS5.1 support](https://consumer.huawei.com/cn/support/content/zh-cn16053287/) | Device-specific manual App Lock; not a public whole-device policy API |
| S12 | [Huawei legacy screen pinning](https://consumer.huawei.com/uk/support/content/en-gb15805372/) | Legacy HarmonyOS2/EMUI applicability; does not establish NEXT support |

Direct links in the API/security documents provide additional specific guides. Where a web page was inaccessible, no missing contract has been invented. OpenHarmony `master` can change: at implementation time pin the corresponding SDK/release documentation or record the source revision used.

## 3. Evidence labels

- **Competition requirement:** directly supported by an identified supplied PDF page.
- **Huawei documented:** retrieved official Huawei reference/support material, with its version/applicability stated.
- **OpenHarmony documented:** official upstream documentation; portability to Huawei remains to verify.
- **Design decision:** a proposed BorrowPhone policy, limit or implementation structure.
- **Unverified:** requires inspection of the chosen SDK, signing configuration, emulator or physical device.

Do not translate “API exists” into “ordinary installation can call it”, or “entry call succeeded” into “all escape routes are blocked”.

## 4. Assumptions and unresolved decisions

| Item | Assumption / current evidence | How to resolve |
| --- | --- | --- |
| Target family | MVP built for Oniro/OpenHarmony 6.1.0.31 API23, with minimum API20 | Verify separately on the intended HarmonyOS NEXT hardware/build |
| Development tool | `oniro-app` 0.11.0, OpenHarmony SDK23 and Hvigor 5.18.5 used | Reproduce in DevEco Studio only if that is the submission workflow |
| Primary deployment | Ordinary development-signed HAP installed on the emulator | Reproduce signing/install on the final device without privileged assumptions |
| Whole-phone containment | Not implemented; UI says other apps remain accessible | Test a supported managed mechanism and all failure paths before changing the claim |
| System authentication | API integrated; no enrolled ATL3 PIN on emulator, unavailable state failed closed | Test successful fresh PIN/fingerprint, cancellation, lockout and kiosk coexistence |
| App privacy window | Enabled on emulator; screenshot showed launcher instead of app pixels | Test Recents, recording, casting and commercial hardware separately |
| Selected URI access | API23 picker/read path decoded two selected synthetic JPEGs | Test API20 if claimed, plus PNG, malformed, oversized and cloud-only assets |
| Persistent data | Implementation keeps URI and PixelMap state in memory only | Inspect application files, framework caches and logs after adverse runs |
| Image formats and limits | JPEG path tested; JPEG/PNG and proposed limits enforced in code | Measure memory and orientation on representative edge cases |
| App owner identity | OS user credential holders are trusted | Explain that all enrolled credentials may authorize access |
| Emulator | UI, picker, JPEG import, screenshot masking and background lock tested | Treat hardware, biometric and policy behavior as unverified |
| Portability | Current artifact targets OpenHarmony/Oniro | Do not claim Huawei HarmonyOS binary/API parity without a separate build and tests |

The architecture now has an initial viewer-only implementation. That implementation is not evidence that the strongest whole-device security requirement has been met.
