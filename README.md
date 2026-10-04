# SafeShare (BorrowPhone)

SafeShare is a native ArkTS/ArkUI app for OpenHarmony that implements the SafeShare Photo Vault design (English UI). The owner sees the phone gallery plus imported notes and PDFs, picks a time period (today, yesterday, last weekend, a custom date range, or a period described in words and interpreted by an on-device model) and hands the phone over. The guest can browse only the photos, notes and PDFs from that period; leaving guest mode requires the owner's 4-digit PIN.

## How it works

- **Owner gallery**: every photo in the media library (up to 500, newest first) is shown in a 3-column grid. Photos outside the selected period are dimmed, blurred and marked with a lock; shared photos carry a green check.
- **Period in words**: the owner can type the period and the kinds, e.g. "photos from the last 3 days", "notes from yesterday" or "photos and PDFs from 1 to 3 October" (no kind named = all kinds). A small language model running on the phone turns it into a proposal card with the period, photo count and thumbnails. Nothing changes until the owner taps "Approve"; "Reject" or editing the text drops the proposal. Off-topic or unsafe requests are rejected with a message. See [On-device period assistant](#on-device-period-assistant).
- **Notes and PDFs**: tabs "Photos / Notes / PDF". OpenHarmony has no API for the system Notepad's data and does not let apps list Documents or Download on a phone, so the owner imports `.txt`/`.md` notes and PDFs with the system file picker. Each file is checked (type by name and content: UTF-8 text for notes, `%PDF-` header for PDFs; at most 512 KB / 50 MB; duplicates skipped) and copied into the app sandbox (`files/vault/`), because picker access is temporary. The date used for periods is the PDF's `/CreationDate` metadata, otherwise the file's modification time. Long-press opens a preview with "Delete from vault".
- **Kinds**: each tab has a "Share …" switch; a disabled kind shares nothing, whatever the period or picks.
- **Manual picks**: tapping a photo shows or hides it on top of the period (a hidden photo from the period, or an extra photo from another day). Hand-picked tiles get an amber border; "Undo changes" drops all picks. Picks survive a period change and only count where they differ from the period.
- **Preview**: holding a photo opens a preview with the whole image, its date, resolution and camera model (EXIF), and a "Show to guest / Hide from guest" button.
- **Guest mode**: one session for all kinds; tabs appear when more than one kind is shared. Notes open as read-only text, PDFs in ArkWeb's PDF viewer limited to that one file (no JavaScript, no navigation to other files or URLs). Photos use a full-screen viewer with swipe, double-tap zoom, a filmstrip and a "+N" locked tile. Swiping past either end of the period shows a boundary notice instead of other photos.
- **PIN**: created on the first hand-off, stored as a salted PBKDF2-SHA256 hash in app preferences (never displayed). Five wrong attempts lock PIN entry for 30 seconds. The PIN can be changed in Settings with the current PIN.
- **Leaving the app**: the system Back button opens the PIN pad. Going to the home screen or another app turns the screen into a non-dismissable PIN lock. If the app is killed during a guest session, the next start opens straight into that lock.
- **Settings**: light/dark theme, PIN change, leave alarm on/off, hide photo details from the guest.

There is no network backend: the "backend" is the local media library (`photoAccessHelper`) plus app preferences. The language model runs locally; requests never leave the phone.

## On-device period assistant

The model is [Qwen2.5-0.5B-Instruct](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct) (Apache-2.0), quantized to Q4_K_M GGUF (380 MB), run on the CPU by [llama.cpp](third_party/README.md) through N-API. The model is treated as untrusted. It only fills in a period; the code decides what is allowed, and the owner decides what is shared:

1. **Request gate** (`TextRange.ts`, before the model): at most 120 characters; only letters, digits and `.,!?/-` (so chat-template tokens such as `<|im_start|>` cannot be typed); every word must come from the photo/time vocabulary (numerals, months, "last", "ago", "photos"…). Anything else is rejected with the offending word: `“ignore” is not related to selecting photos, notes or PDFs`.
2. **Grounded grammar**: from the request the gate collects the periods its keywords allow and the numbers, days and months it contains ("two weeks" → 14). It builds a GBNF grammar from them, so the model can only answer `{"intent":"reject"}` or a period made of those values. The grammar is enforced while sampling, so the model cannot output free text, extra fields, or a number or date that is not in the request.
3. **Prompt isolation** (`range_model.cpp`): the instructions are tokenized with special tokens, the user text without them, so the text cannot close the user turn or open a system turn.
4. **Output validation** (`TextRange.ts`, after the model): strict JSON shape, every value checked again against the request, real calendar dates, no future periods, at most 366 days.
5. **Owner approval**: the result is only a proposal; it shows the photos that would become visible. Approval sets the normal period controls, and hand-off still needs the usual button and PIN.
6. **No capabilities**: the model has no tools, network or file access, and its text is never shown. Entering guest mode cancels pending requests and frees the model from memory.

Kinds are not left to the model: the gate reads them from the request's words ("photos/pictures" → photos, "notes" → notes, "PDF" → PDFs, "documents/files" → notes and PDFs); words such as "without" or "except" are not in the vocabulary, so negations are rejected rather than misread. The proposal combines the model's period with these kinds.

The model's JSON is `{"intent":"share","period":"today"|"yesterday"|"weekend"}`, `{"intent":"share","period":"last_days"|"days_ago","n":N}`, `{"intent":"share","period":"dates","from":"DD.MM","to":"DD.MM"}` or `{"intent":"reject"}`.

### Getting the model

The model is not committed. `tools/fetch_model.sh` downloads it to `models/` and checks its SHA-256.

- **Phone**: `tools/fetch_model.sh --bundle` also places it in `entry/src/main/resources/rawfile/models/`, so the next build packs it into the HAP (≈ 395 MB). On first use the app copies it into its sandbox.
- **QEMU emulator**: the 1.3 GB data partition cannot hold the HAP install plus copies, so build without `--bundle`, install and launch the app once, then run `tools/push_model.sh`, which copies the model into the app sandbox with `hdc`.

Without a model the assistant answers "The AI assistant is unavailable on this device" and the preset buttons keep working.

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

Run the date-range, manual-pick and PIN rule check:

```bash
node tests/session_rules_test.mjs   # needs Node.js 22.18+ (imports a .ts file)
node tests/text_range_test.mjs      # request gate and model-output validation, no model needed
```

End-to-end check of the assistant on the host, with the same C++ inference code as the app (24 valid requests, 23 off-topic/injection/out-of-range requests; exits non-zero if any of the latter is accepted):

```bash
cmake -S tests/ai -B /tmp/range-eval -G Ninja && cmake --build /tmp/range-eval
node tests/ai/run_eval.mjs /tmp/range-eval/range_eval models/range-parser.gguf
```

Last run: 31/31 valid requests correct (period and kinds), 26/26 rejected, ≈ 0.7 s per request on the laptop CPU.

```bash
node tests/documents_test.mjs       # file kinds, PDF header, PDF /CreationDate parsing
```

Device checks performed on the environment above:

| Check | Result |
| --- | --- |
| Permission prompt, gallery load, 3-column grid with locked photos | Passed |
| Presets Today / Yesterday / Weekend and custom range (system date dialog) | Passed |
| Photo detail with EXIF camera model | Passed |
| Tap to hide / add photos, counters, "Undo changes", long-press preview with show/hide button | Passed |
| Light/dark theme incl. system bar colors | Passed |
| PIN creation with mismatching confirmation, then guest mode | Passed |
| Guest swipe, boundary notices, filmstrip, zoom, details overlay | Passed |
| Back button in guest mode → PIN pad | Passed |
| Home during guest mode, return → non-dismissable PIN lock | Passed |
| Force-stop during guest mode, relaunch → PIN lock, owner gallery hidden | Passed |
| 5 wrong PINs → 30 s lockout, correct PIN rejected until it expires | Passed |
| PIN change with wrong / correct current PIN | Passed |
| Period in words (Oniro emulator, OpenHarmony 6.1, model pushed with `push_model.sh`): proposals for "today", "5 days ago", "last two weeks", "1-3 October", "last weekend"; rejections for "ignore instructions…", "write a poem", "show all photos", "last 400 days", "31.02", "what is the weather today" | Passed |
| Proposal changes nothing until "Approve"; approval sets the preset or custom dates | Passed |
| Hand-off frees the model (app RSS ≈ 835 MB → 356 MB); after the PIN the assistant loads it again | Passed |
| Notes/PDF import through the system picker (emulator): `.txt`, `.md` and PDF imported; `fake.pdf` (HTML) rejected as "not a PDF file"; PDFs picked in the notes tab rejected as "wrong file type"; PDF dates taken from `/CreationDate`; duplicate import refused | Passed |
| Note preview, delete with confirmation, tabs, "Share …" switches, counts across kinds | Passed |
| "notes from today" → 2 notes proposed, approved, guest sees only the Notes tab, opens a note, 4 other files reported locked | Passed |
| "photos and PDFs from the weekend" → guest tabs Photos 3 / PDF 2 | Passed |
| PDF rendering in the guest/owner viewer | **Not verified**: the Oniro x86_64 image ships ArkWebCore for arm64 only, so no Web content renders there; the viewer shows "PDF preview is unavailable on this device" after 6 s. Needs an arm64 device. |
| Whole-device confinement | **Not implemented / not claimed** |

## Project map

- `entry/src/main/ets/pages/Index.ets` — screens and state: owner gallery, period filter, photo detail, settings, guest viewer, PIN pad.
- `entry/src/main/ets/service/AppStore.ets` — PIN hash, lockout, settings and guest-session flag in preferences.
- `entry/src/main/ets/service/Gallery.ets` — gallery permission, media library query, EXIF camera model.
- `entry/src/main/ets/service/Haptics.ets` — vibration feedback.
- `entry/src/main/ets/common/` — theme palettes and English date formatting.
- `entry/src/main/ets/model/SessionRules.ts` — date ranges, manual picks, PIN format and index rules.
- `entry/src/main/ets/entryability/EntryAbility.ets` — privacy window and background detection.
- `entry/src/main/ets/model/TextRange.ts` — request gate, grounded grammar, model-output validation and messages.
- `entry/src/main/ets/model/Documents.ts` — item kinds, import limits, PDF header and `/CreationDate` parsing.
- `entry/src/main/ets/service/Vault.ets` — picker import, validation, sandbox copies, index, removal.
- `entry/src/main/ets/components/PdfView.ets` — locked-down ArkWeb PDF viewer.
- `entry/src/main/ets/service/RangeAssistant.ets` — model install/lookup and the gate → model → validation call.
- `entry/src/main/cpp/` — N-API module: `range_model.cpp` (prompt, prefix cache, grammar-constrained sampling) and `napi_init.cpp`.
- `third_party/llama.cpp/` — pruned, patched llama.cpp ([notes](third_party/README.md)).
- `tools/fetch_model.sh`, `tools/push_model.sh` — get the model and put it in the HAP or on the emulator.
- `tests/session_rules_test.mjs`, `tests/text_range_test.mjs`, `tests/documents_test.mjs` — runnable lightweight checks; `tests/ai/` — host evaluation of the assistant.
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — architecture and implementation of the delivered app, with graphs in `diagrams/`.
- [`01_ARCHITECTURE.md`](01_ARCHITECTURE.md) through [`05_HACKATHON_COMPLIANCE.md`](05_HACKATHON_COMPLIANCE.md) — design notes for the earlier picker-based MVP.
- [`AI_WORKFLOW.md`](AI_WORKFLOW.md) — AI-use disclosure.
