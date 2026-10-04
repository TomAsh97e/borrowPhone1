#!/usr/bin/env bash
# Copies models/range-parser.gguf straight into the installed app's sandbox (emulator/development),
# for HAPs built without the bundled model. Run tools/fetch_model.sh first and launch the app once.
set -euo pipefail

HDC="${HDC:-$HOME/setup-ohos-sdk/linux/23/toolchains/hdc}"
BUNDLE=org.hackyeah.borrowphone
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILES="/data/app/el2/100/base/$BUNDLE/haps/entry/files"

OWNER=$("$HDC" shell "stat -c %u:%g $FILES" | tr -d '\r')
case "$OWNER" in
  *[0-9]:[0-9]*) ;;
  *) echo "App sandbox not found; install and launch $BUNDLE first." >&2; exit 1 ;;
esac
"$HDC" file send "$ROOT/models/range-parser.gguf" "$FILES/range-parser.gguf"
"$HDC" shell "chown $OWNER $FILES/range-parser.gguf && chmod 600 $FILES/range-parser.gguf"
echo "Model pushed to $FILES/range-parser.gguf"
