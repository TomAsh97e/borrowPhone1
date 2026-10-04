#!/usr/bin/env bash
# Copies demo_data/ to the connected device/emulator: photos into the media library (dated by their
# EXIF DateTimeOriginal), notes and PDFs into the public Download folder, where the app's import
# picker finds them. Notes are dated by their modification time, which neither git nor
# `hdc file send` keeps, so it is set here to the dates listed in demo_data/README.md.
# Photos already in the gallery are skipped, so the script can be run again.
set -euo pipefail

HDC="${HDC:-$HOME/setup-ohos-sdk/linux/23/toolchains/hdc}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=/data/local/tmp/safeshare-demo
DOWNLOAD=/storage/media/100/local/files/Docs/Download

if [ "$("$HDC" shell param get bootevent.boot.completed | tr -d '\r ')" != "true" ]; then
  echo "No booted device; start the emulator and run: hdc tconn 127.0.0.1:5555" >&2
  exit 1
fi

"$HDC" shell "rm -rf $TMP && mkdir -p $TMP"
sent=0
for f in "$ROOT"/demo_data/photos/*; do
  name=$(basename "$f")
  if "$HDC" shell "mediatool query $name" | grep -qi 'find 0 result'; then
    "$HDC" file send "$f" "$TMP/$name" >/dev/null
    sent=$((sent + 1))
  else
    echo "Already in the gallery: $name"
  fi
done
if [ "$sent" -gt 0 ]; then
  "$HDC" shell "mediatool send $TMP" >/dev/null
fi
"$HDC" shell "rm -rf $TMP"
echo "Photos added to the gallery: $sent"

"$HDC" shell "mkdir -p $DOWNLOAD"
while read -r file date; do
  "$HDC" file send "$ROOT/demo_data/$file" "$DOWNLOAD/" >/dev/null
  "$HDC" shell "touch -d $date '$DOWNLOAD/$(basename "$file")'"
done <<'EOF'
notes/Today_Shopping_List.md       2026-10-04T12:00:00
notes/Yesterday_Weekend_Ideas.md   2026-10-03T12:00:00
notes/Private_Demo_Secrets.txt     2026-09-10T12:00:00
pdfs/Today_Travel_Plan.pdf         2026-10-04T12:00:00
pdfs/Yesterday_Concert_Ticket.pdf  2026-10-03T19:30:00
pdfs/Private_Rental_Agreement.pdf  2026-09-10T12:00:00
EOF
echo "Notes and PDFs copied to $DOWNLOAD (import them in the app: Notes / PDF tab)"
