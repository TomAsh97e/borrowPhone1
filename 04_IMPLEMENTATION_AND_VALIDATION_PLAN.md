# Implementation and validation plan

This remains the validation backlog. A first viewer-only MVP has now been built and exercised on the Oniro OpenHarmony 6.1 API23 emulator; uncompleted items below remain release gates, especially physical-device authentication and confinement.

## 1. P0: resolve platform feasibility first

Allocate an initial 45-60 minute investigation, then make a scope decision. This is a suggested timebox, not the official competition deadline.

| Check | Evidence to record | Decision |
| --- | --- | --- |
| Environment | DevEco Studio version, SDK release, compile/target/minimum API, hvigor, HDC, emulator image, device model/build and signing method | Use API20 or later; minimum API20 |
| Picker | Choose five out of at least eight local demo photos; read only the returned selection through the chosen API20 path | If this fails, fix the adapter before UI work |
| Authentication | Native PIN and/or fingerprint, fresh prompt immediately after device unlock, cancellation and errors | No protected session without a working credential flow |
| Window privacy | Runtime success, screenshot/recording and Recents results on each claimed target | Do not render protected-session content if policy application fails |
| Containment | Supported feature, actual privileges/provisioning, entry and exit behavior | Classify as unsupported, unverified or verified for a named deployment |
| Containment + authentication | Native owner prompt can work while confinement remains effective | No temporary unprotected escape to authenticate |
| Failure boundary | Kill process, lock/reboot device, interrupt with call, attempt Home/Recents/shade | Record actual device outcome; never infer safety from successful entry |

Do not build an enterprise administration application during the MVP. A mentor-provided, correctly provisioned device could support an optional kiosk demonstration, provided setup is reproducible and its limitations are disclosed. A normal signed HAP alone is not proof of the required provisioning.

If neither a supported credential-protected system feature nor a suitably managed deployment meets the required escape tests, whole-phone handoff remains **blocked by platform feasibility**. Continue with an explicitly limited viewer prototype only after consciously accepting that narrower product scope. Do not implement gesture tricks as a replacement.

### Evidence record template

| Claim | Target and build | API/policy and privilege | Observed result | Remaining limitation |
| --- | --- | --- | --- | --- |
| Selected images only | Oniro emulator, OpenHarmony 6.1.0.31 API23 | System picker + RAM-only PixelMaps | Two of three synthetic JPEGs selected, decoded and viewed | PNG, malformed, cloud and limit cases pending |
| Fresh owner authentication | Same emulator, no enrolled ATL3 PIN | UserAuthenticationKit | Unavailable state failed closed | Successful PIN/fingerprint and return flow pending |
| Capture protection | Same emulator | `setWindowPrivacyMode(true)` | Screenshot showed launcher, not app pixels | Recording, Recents, cast and hardware pending |
| Other apps inaccessible | Same emulator | No containment integration | Explicit viewer-only warning; other apps remain accessible | Whole-device protection unsupported/unverified |

Use “not tested” until an actual observation exists. API documentation is evidence of a contract, not evidence that this application works.

## 2. Ordered implementation slices

| Priority | Deliverable | Completion criterion |
| --- | --- | --- |
| P0 | Capability investigation | Above record filled and product boundary agreed |
| P1 | One native Stage project | Empty installable HAP runs on the recorded API20+ target |
| P1 | Locked start + native owner authentication | No owner screen on cancellation, missing enrollment or cold restart |
| P1 | Picker + bounded importer | One-to-five JPEG/PNG images reviewed without broad gallery permissions |
| P1 | SessionController + guest renderer | Only manifest entries are reachable; owner routes removed |
| P1 | Owner return | Fresh current authentication atomically ends session; no unlock reuse |
| P1 | Privacy and lifecycle integration | Neutral startup/resume, safe callback handling, protection before images |
| P1 conditional | System containment integration | Available only for the tested deployment; failure does not downgrade silently |
| P2 | Error handling and accessibility | Invalid content, service errors and assistive navigation handled clearly |
| P2 | Focused verification | Security-critical tests below recorded with evidence |
| P3 | Submission package | Reproducible build/install/run, English demo and complete disclosure |

For a short hackathon, spend roughly one fifth of implementation time on feasibility and setup, two fifths on the complete core interaction, one fifth on adverse-path verification and one fifth on reproducibility/demo. Reduce optional zoom and visual polish before cutting authorization or lifecycle checks.

## 3. Meaningful tests

Automate domain-state and authorization cases. Use a device/emulator for integration and OS behavior. Mocks can exercise error paths but cannot prove containment or hardware authentication. These are planned tests, not a claim of current coverage.

| ID | Scenario | Required result |
| --- | --- | --- |
| T01 | Select photos 1, 3, 4, 6, 8 from an eight-photo test gallery | Those five only; no fetch/decode outside the selected set |
| T02 | Swipe repeatedly beyond both ends; tamper with requested item ID/index | Clamp/reject; no implicit next-gallery-item lookup |
| T03 | Empty/cancelled picker, duplicate item, unsupported MIME, corrupt or oversized image | Clear safe outcome; no guest session from an invalid draft |
| T04 | One of five imports fails or cloud-only asset is offline | Owner explicitly resolves selection; no hidden download/replacement |
| T05 | Guest presses Back, requests picker or owner route, receives an external Want/deep link | No owner operation without a current authentication result |
| T06 | Wrong PIN, cancelled biometric prompt, lockout, timeout or service failure | Guest/locked state remains; no privilege promotion |
| T07 | Owner unlocks phone, starts session, guest immediately requests owner return | Fresh authentication is still required |
| T08 | Old authentication/picker/decode result arrives after a new epoch | Ignored; cannot unlock or repopulate the session |
| T09 | Background, rotation/window recreation, process death and cold restart | No owner-route flash or persisted unlock; no active session restoration |
| T10 | Screenshot, screen recording, task preview, cast and supported assistive surfaces | Record actual behavior; verify each claimed protection |
| T11 | Home, Recents, notifications/control center, assistant, incoming call, split screen, keyboard shortcuts | Separate containment results; any escape defeats the corresponding phone-safety claim |
| T12 | Crash/force termination while kiosk is active | Explicitly document device state after documented kiosk termination behavior |
| T13 | Return to owner while kiosk active, cancel prompt, fail exit policy | No unauthenticated kiosk exit; neutral recovery if authenticated exit fails |
| T14 | End session repeatedly; inspect app files/logs and native resource usage | No image/session files or sensitive logs; handles released; memory settles |
| T15 | Fresh machine/clean checkout and a second tester | Build and launch from recorded instructions without private developer state |
| T16 | OS image/build lacking a capability or enrollment | Accurate unavailable state, no demo bypass or false protected indicator |

Containment tests must check exposure of other apps and notifications, not just whether BorrowPhone returns locked. Use synthetic photos and an otherwise non-sensitive demo device while capabilities are unproven.

## 4. Demonstration proposal, about 90 seconds

1. **0-15 seconds:** show the everyday problem and a gallery of harmless demonstration images; explain that only five should be shared.
2. **15-35 seconds:** authenticate, open the native picker, select five and review them.
3. **35-55 seconds:** show guest browsing, count boundaries and an unsuccessful/cancelled owner-return attempt.
4. **55-70 seconds:** demonstrate the system integration that actually passed testing. State the exact containment scope; if using viewer-only mode, visibly acknowledge other apps remain accessible.
5. **70-85 seconds:** owner uses a fresh system credential, session is destroyed and a new selection requires owner access.
6. **85-90 seconds:** show the API level, available package/repository and concise platform capability summary.

Keep privacy protection enabled. If OS screen recording hides protected windows, record the physical device with an external camera using synthetic content. If only an emulator can be demonstrated, show its actual behavior and disclose hardware-only gaps. Do not quietly disable security in the demonstrated build or substitute a mock auth result.

## 5. Build and submission instructions to capture later

The final repository README must include exact IDE/SDK and build-tool versions, dependency installation, signing setup without secrets, build action/command, HAP location, HDC or IDE installation steps, bundle/ability launch details, demo image setup and any external device-policy prerequisites. Record the successful clean-checkout procedure rather than guessing commands before a project exists.

Keep certificates, signing passwords, personal paths and device secrets out of the public repository. Supply a working signed `.hap` for the intended demo installation method, and explain how reviewers can reproduce signing for their own device. Update the architecture to match the implementation and replace all pending evidence before making a security claim.
