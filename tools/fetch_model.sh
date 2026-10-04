#!/usr/bin/env bash
# Downloads the on-device period model (Qwen2.5-0.5B-Instruct, Q4_K_M GGUF, Apache-2.0) to models/
# and verifies its SHA-256. With --bundle it is also copied into the raw-file resources, so the
# next build packs it into the HAP (needs ~1.2 GB free on the device during install).
set -euo pipefail

URL='https://huggingface.co/bartowski/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf?download=true'
SHA256='6eb923e7d26e9cea28811e1a8e852009b21242fb157b26149d3b188f3a8c8653'
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL="$ROOT/models/range-parser.gguf"
RAWFILE="$ROOT/entry/src/main/resources/rawfile/models/range-parser.gguf"

if ! { [ -f "$MODEL" ] && echo "$SHA256  $MODEL" | sha256sum --check --status; }; then
  mkdir -p "$(dirname "$MODEL")"
  curl -L --fail --retry 3 -o "$MODEL.part" "$URL"
  echo "$SHA256  $MODEL.part" | sha256sum --check
  mv "$MODEL.part" "$MODEL"
fi
echo "Model: $MODEL"
if [ "${1:-}" = "--bundle" ]; then
  mkdir -p "$(dirname "$RAWFILE")"
  cp "$MODEL" "$RAWFILE"
  echo "Bundled into $RAWFILE"
fi
