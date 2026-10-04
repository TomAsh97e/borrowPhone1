# Run SafeShare on Linux

This guide is for **Ubuntu 24.04 on an x86_64 computer**. It runs the app in an OpenHarmony phone emulator.

You need about **25 GB of free disk space**, an internet connection, and preferably **16 GB of RAM**. Enable CPU virtualization (Intel VT-x or AMD-V) in BIOS/UEFI. The optional AI setup needs a few more GB.

For a new computer, follow steps 1–7. If the tools are already installed, go to [Start the emulator](#4-start-the-emulator). To update an existing clone, see [Update or run an existing clone](#8-update-or-run-an-existing-clone).

You can clone the project into any folder. All project commands below run from the repository root: the folder containing `README.md`, `build-profile.json5`, and `tools/`. `$HOME` and `~` refer to your own home folder; no specific username or project location is required.

## 1. Install system tools

```bash
sudo apt update
sudo apt install -y git curl unzip tar zstd coreutils \
  openjdk-21-jdk-headless \
  qemu-system-x86 qemu-system-gui qemu-utils cpu-checker
sudo usermod -aG kvm "$USER"
```

**Log out and log in again**, then check that hardware acceleration works:

```bash
kvm-ok
```

The result should include `KVM acceleration can be used`.

## 2. Install Node.js and oniro-app

Use **Node.js 22.18 or newer in the 22.x series**. Ubuntu's default Node.js 18 is too old for this setup.

Install [nvm](https://github.com/nvm-sh/nvm/tree/v0.40.3), then Node.js:

```bash
curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
source "$HOME/.nvm/nvm.sh"
nvm install 22
nvm alias default 22
nvm use 22
node --version
```

Install the version of `oniro-app` used for this project. Do not use `sudo` for this command:

```bash
npm install -g @oniroproject/oniro-app@0.11.0
oniro-app --version
```

## 3. Install the OpenHarmony SDK

```bash
oniro-app sdk install 6.1
oniro-app cmdtools install
```

These commands install API 23 in `~/setup-ohos-sdk/linux/23` and build tools in `~/command-line-tools`. Downloads may take several minutes.

Add the device connection tool, `hdc`, to your current terminal:

```bash
export PATH="$HOME/setup-ohos-sdk/linux/23/toolchains:$PATH"
hdc version
```

Also add the `export PATH=...` line above to `~/.bashrc`, or `~/.zshrc` if you use zsh, so it works in new terminals.

## 4. Start the emulator

Install the [OpenHarmony QEMU image](https://github.com/harmony-contrib/ohos-qemu) once:

```bash
curl -fsSL https://raw.githubusercontent.com/harmony-contrib/ohos-qemu/main/scripts/install.sh \
  | bash -s -- --release v20260809
```

In **terminal 1**, start the emulator and leave the terminal open:

```bash
~/.ohos-qemu/openharmony-qemu-x86_64-x86_64_virt-phone/launch/linux.sh -r 720x1280
```

If the emulator is already running, use that instance. Do not start a second one.

In **terminal 2**, connect to it:

```bash
source "$HOME/.nvm/nvm.sh"
nvm use 22
export PATH="$HOME/setup-ohos-sdk/linux/23/toolchains:$PATH"
hdc tconn 127.0.0.1:5555
hdc list targets
hdc shell param get bootevent.boot.completed
```

Wait until the target is `127.0.0.1:5555` and the last command returns `true`. If the target list is empty, wait a little and repeat the connection command.

Run the remaining commands in terminal 2.

## 5. Get the project and run it

For a new clone, open a terminal in any folder where you want to keep the project, then run:

```bash
git clone https://github.com/TomAsh97e/borrowPhone1.git
cd borrowPhone1
```

For an existing clone, open a terminal inside it. This command moves to its root from any subfolder:

```bash
cd "$(git rev-parse --show-toplevel)"
```

Create the signing files, build, install, and launch:

```bash
oniro-app sign . --bootstrap --acls ohos.permission.READ_IMAGEVIDEO
oniro-app build .
oniro-app app install .
oniro-app app launch .
```

`--bootstrap` keeps existing signing files. On a fresh clone, it creates them with the gallery permission. Keep these files for future builds: generating new keys can prevent updates to an installed app. Do not commit the generated signing files or the local signing changes in `build-profile.json5`.

The first build can take several minutes. The app package is saved as `entry/build/default/outputs/default/entry-default-signed.hap`.

When the app asks for access to photos, choose **Allow**. It asks you to create a four-digit PIN when you first enter guest mode.

## 6. Add demo files

From the project folder, with the emulator running:

```bash
tools/push_demo_data.sh
oniro-app app stop org.hackyeah.borrowphone
oniro-app app launch .
```

This adds photos to the system gallery and copies notes and PDFs to **Download**. Existing demo photos are skipped.

In the app, open **Notes** or **PDF**, tap **Import**, and choose files from **Download**.

The demo files are dated around **4 October 2026**. If Today or Yesterday shows no files, choose a custom date range that includes those dates.

## 7. Enable AI (optional)

The app works without AI. To select a period using text such as `photos from the last 3 days`, you need the model.

**The model is not included in `git clone`.** The project scripts download it through Ollama. The model runs inside the app; Ollama is only used to download it on your computer.

Install [Ollama](https://docs.ollama.com/linux) once:

```bash
curl -fsSL https://ollama.com/install.sh | sh
sudo systemctl start ollama
ollama --version
```

The app must already be installed and have been opened once. With the emulator connected, run this from the project folder:

```bash
tools/push_model.sh
oniro-app app stop org.hackyeah.borrowphone
oniro-app app launch .
```

`push_model.sh` automatically runs `fetch_model.sh` if needed. It downloads `qwen2.5:0.5b` (about 400 MB), copies it to `models/range-parser.gguf`, then sends it to the app. Copying from Ollama's storage may ask for your `sudo` password. An existing local GGUF file is reused.

After uninstalling the app, run `tools/push_model.sh` again to restore the model.

For a compatible physical OpenHarmony device with enough storage, you can include the model in the app package:

```bash
tools/fetch_model.sh --bundle
oniro-app build .
```

Do not use `--bundle` for this emulator: its data partition is too small for installation with the extra model copies.

## 8. Update or run an existing clone

Start the emulator as shown in step 4. Open another terminal inside your existing clone and prepare it:

```bash
cd "$(git rev-parse --show-toplevel)"
source "$HOME/.nvm/nvm.sh"
nvm use 22
export PATH="$HOME/setup-ohos-sdk/linux/23/toolchains:$PATH"
hdc tconn 127.0.0.1:5555
```

To download the latest code and run it:

```bash
git pull --ff-only
oniro-app sign . --bootstrap --acls ohos.permission.READ_IMAGEVIDEO
oniro-app build .
oniro-app app install .
oniro-app app launch .
```

If `git pull` fails, resolve the reported Git issue before continuing. Keep your local signing files and signing configuration; do not discard them to force an update.

`--bootstrap` reuses your signing files. Updating the app with the same signature keeps its data and model. After editing code locally, use the same build, install, and launch commands without `git pull`.

To open the already installed app without updating or rebuilding:

```bash
oniro-app app launch .
```

## Optional checks

Run the logic checks without the emulator:

```bash
node tests/session_rules_test.mjs
node tests/text_range_test.mjs
node tests/documents_test.mjs
```

To test the AI on your computer, install the extra build tools and download the model first:

```bash
sudo apt install -y build-essential cmake ninja-build
tools/fetch_model.sh
cmake -S tests/ai -B /tmp/range-eval -G Ninja
cmake --build /tmp/range-eval
node tests/ai/run_eval.mjs /tmp/range-eval/range_eval models/range-parser.gguf
```

## Common problems

| Problem | What to do |
| --- | --- |
| `nvm: command not found` | Run `source "$HOME/.nvm/nvm.sh"`, then `nvm use 22`. |
| `oniro-app: command not found`, or Node.js errors | Run `nvm use 22` and check `node --version`. If needed, install `oniro-app` again under Node.js 22 using step 2. |
| KVM permission denied | Log out and back in after step 1. Check that `groups` includes `kvm`. |
| KVM is unavailable | Enable virtualization in BIOS/UEFI. Without it, the emulator may be very slow. |
| Port 5555 is already in use | An emulator may already be running. Connect to it instead of starting another. |
| The emulator window fails to open | Try a normal desktop terminal instead of the VS Code terminal, or use VNC below. |
| `hdc list targets` shows `[Empty]` | Wait for the emulator to start, then run `hdc tconn 127.0.0.1:5555` again. |
| Install fails with `sign info inconsistent` | Uninstall with `oniro-app app uninstall org.hackyeah.borrowphone`, then install again. **This deletes the app's PIN, settings, imported files, and model.** |
| Install fails with `grant request permissions failed` | Regenerate the signature with `oniro-app sign . --acls ohos.permission.READ_IMAGEVIDEO` (without `--bootstrap`), rebuild, then uninstall the old app and install again. Uninstalling deletes app data. |
| AI is unavailable | Complete step 7 and restart the app. |
| Ollama connection refused | Run `sudo systemctl start ollama`, then retry. |
| The model script warns that the model has changed | The downloaded version differs from the tested one. Run the optional AI checks above. |
| Demo photos are missing from Today or Yesterday | Use a custom date range around 4 October 2026. |
| Not enough disk space | Free space before retrying. For build-tool downloads, you can choose another disk with `oniro-app cmdtools install --tmp-dir /path/with/free/space`. |

For a computer without a working emulator window, start it with VNC:

```bash
QEMU_EXTRA_ARGS='-vga none' \
  ~/.ohos-qemu/openharmony-qemu-x86_64-x86_64_virt-phone/launch/linux.sh \
  -r 720x1280 --display vnc
```

Connect a VNC viewer to `127.0.0.1:5921`. This replaces the normal emulator launch command.

## Known limits

- PDF preview is unavailable on the tested x86_64 emulator. Rendering on an ARM64 device still needs verification.
- Guest mode protects this app only. It does not stop the guest from opening other apps.
- The app blocks system screenshots and screen recordings of its content.
