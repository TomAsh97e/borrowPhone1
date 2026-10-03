# AI-assisted development workflow

## Status and scope

Last updated: 3 October 2026. AI assistance was used for architecture planning and the first runnable BorrowPhone MVP. The product itself performs no AI inference and sends no photo, credential or application data to an AI service.

This is a sanitized development record, not a verbatim prompt transcript. It must be extended if later implementation, debugging or submission work uses AI.

## Planning stage

The earlier planning session used an OpenAI Codex desktop assistant, a GPT-6-based Codex agent identifier reported by that session, three delegated research agents, PDF extraction/rendering tools, web research and local file tools. It reviewed the supplied competition PDFs and official Huawei/OpenHarmony material, then produced the architecture, security, API, implementation and compliance documents in this repository.

The planning request, paraphrased in English, was:

> Plan a small HarmonyOS application named BorrowPhone. An owner selects a few gallery photos and hands the phone to a guest who should not see other data without owner authentication. Read the supplied rules, use meaningful platform APIs, document the architecture and do not implement code yet.

Important planning corrections were retained in the delivered UI: an app-only viewer is not whole-device confinement, a private window is not kiosk mode, and a recent phone unlock must not replace fresh owner authentication.

## MVP implementation stage

The implementation request was made in Polish. Paraphrased in English:

> Implement the HarmonyOS application according to the Markdown files. For now, produce the minimum that can run on Oniro and demonstrate the MVP.

| Tool or capability | Actual use |
| --- | --- |
| Pi coding agent | Read every project Markdown file, inspect the local toolchain/SDK, edit code and run validation commands |
| AI model | `openai/gpt-5.6-sol`, reported by the implementation session environment |
| Ponytail coding skill | Enforced a minimal native implementation without backend, database, DI, event bus or new dependencies |
| `@oniroproject/oniro-app` 0.11.0 | Scaffold, sign, build, install, launch, inspect layout, inject input, capture screenshots and read logs |
| Installed OpenHarmony SDK 6.1 / API 23 | Checked exact picker, image, file, authentication and privacy-window declarations |
| Hvigor 5.18.5 | Compiled and signed the entry HAP |
| Oniro emulator | Ran OpenHarmony 6.1.0.31 API 23 and exercised the actual UI flow |
| Node.js standard library | Runs the small `SessionRules` check without a test framework |

No external account connector, MCP server, cloud backend, analytics SDK or product AI library was added.

## Generated and implemented material

The `oniro-app` EmptyAbility template supplied the initial Stage-project structure and generated image resources. AI assistance then replaced the sample UI and lifecycle code with:

- a privacy-protected one-ability ArkUI application;
- selected-photo picker integration without broad media permission;
- sequential bounded JPEG/PNG decoding into RAM-only `PixelMap` objects;
- review, removal and immutable guest-viewer flow;
- system-PIN authentication integration with a random challenge and no unlock-result reuse;
- fail-closed lifecycle invalidation;
- explicit viewer-only disclosure and an unprotected emulator demo path;
- a lightweight pure-logic check and reproducible commands.

No third-party application runtime dependency was introduced. Local development signing material and generated build files are excluded from source control.

## Commands and observed results

The implementation session actually performed the following classes of checks:

```bash
node tests/session_rules_test.mjs
oniro-app sign .
oniro-app build . --json
oniro-app app install .
oniro-app app launch .
oniro-app dump layout --bundle org.hackyeah.borrowphone
oniro-app screenshot -o <temporary-file>
oniro-app input ...
oniro-app watch ...
```

Observed on the Oniro emulator:

- OpenHarmony reported `6.1.0.31`, API 23.
- The signed HAP built, installed and launched.
- A source-only copy also passed the documented `sign` and `build` sequence.
- The native picker opened and showed three harmless generated JPEG test images imported with the emulator's `mediatool`.
- Two selected images decoded, appeared in review and entered the guest viewer.
- Screenshot capture did not expose the privacy-window pixels; it showed the launcher instead.
- Pressing Home during a guest session and relaunching returned to the locked screen with no restored session.
- The emulator had no enrolled ATL3 PIN, so native owner authentication failed closed as intended.
- Code lint reported no findings, but also reported that the installed command-line linter type did not match the project and its report could be incomplete; this is not counted as strong lint evidence.

## Failed approaches and corrections

- The first ArkTS build used an enum named `Screen` inside ArkUI builder conditions. That collided with an ArkUI class and failed compilation. Screen checks were moved behind ordinary component methods; the next build succeeded.
- The generated Hypium local-test path compiled but the command-line `hvigorw test` run did not finish in the available environment. The test framework dependencies were removed and replaced with the dependency-free Node check in `tests/session_rules_test.mjs`, which passed.
- Initial emulator gallery state contained no photos. Three synthetic JPEGs were transferred and registered with `mediatool`; no personal media was used.

## Human review and remaining limits

The delivered build is an MVP feasibility result, not a security certification. Human review and physical-device validation remain required. In particular:

- whole-device containment is not implemented or claimed;
- native PIN success and fresh authentication after handoff were not observed because the emulator had no enrolled PIN;
- fingerprint, PNG, malformed/oversized files, cloud-only assets, rotation/orientation edge cases, Recents, recording, casting, calls, split-screen and process-kill behavior still need focused tests;
- API 20 compatibility is declared, while this session compiled and ran only API 23;
- an independent reviewer has not yet reproduced the clean build.

Use synthetic media on non-sensitive test devices until those gaps are closed. Do not replace pending evidence with assumptions in submission materials.
