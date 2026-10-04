#!/usr/bin/env bash
# Puts the on-device period model (Qwen2.5-0.5B-Instruct, Q4_K_M GGUF, Apache-2.0) into models/.
# It is downloaded with Ollama (`ollama pull qwen2.5:0.5b`); Ollama stores the weights as a plain
# GGUF blob named after its SHA-256, which is copied here and checked against that hash. Skips
# everything when models/ already holds a GGUF file. With --bundle it is also copied into the
# raw-file resources, so the next build packs it into the HAP (needs ~1.2 GB free on the device
# during install).
set -euo pipefail

TAG='qwen2.5:0.5b'
# The blob checked with tests/ai (31/31 valid requests, 26/26 rejections).
TESTED='c5396e06af294bd101b30dce59131a76d2b773e76950acc870eda801d3ab0515'
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL="$ROOT/models/range-parser.gguf"
RAWFILE="$ROOT/entry/src/main/resources/rawfile/models/range-parser.gguf"

if ! { [ -f "$MODEL" ] && [ "$(head -c 4 "$MODEL")" = GGUF ]; }; then
  if ! command -v ollama >/dev/null; then
    echo "Ollama is not installed. Install it with:" >&2
    echo "  curl -fsSL https://ollama.com/install.sh | sh" >&2
    exit 1
  fi
  ollama pull "$TAG"
  BLOB=$(ollama show --modelfile "$TAG" | sed -n 's|^FROM \(/.*\)$|\1|p' | head -n 1)
  DIGEST="${BLOB##*sha256-}"
  if [ -z "$BLOB" ] || [ "$DIGEST" = "$BLOB" ]; then
    echo "Could not find the GGUF file of $TAG in 'ollama show --modelfile'." >&2
    exit 1
  fi
  if [ "$DIGEST" != "$TESTED" ]; then
    echo "Warning: $TAG has changed since it was checked with tests/ai (expected $TESTED)." >&2
  fi
  mkdir -p "$(dirname "$MODEL")"
  if [ -r "$BLOB" ]; then
    cp "$BLOB" "$MODEL.part"
  else
    # The Ollama service keeps models in its own home; reading it needs the `ollama` group
    # (granted by the installer, active after logging in again) or sudo.
    echo "Copying $BLOB with sudo"
    sudo cat "$BLOB" > "$MODEL.part"
  fi
  if ! echo "$DIGEST  $MODEL.part" | sha256sum --check --status; then
    rm -f "$MODEL.part"
    echo "The copied model does not match its SHA-256 ($DIGEST)." >&2
    exit 1
  fi
  mv "$MODEL.part" "$MODEL"
fi
echo "Model: $MODEL"
if [ "${1:-}" = "--bundle" ]; then
  mkdir -p "$(dirname "$RAWFILE")"
  cp "$MODEL" "$RAWFILE"
  echo "Bundled into $RAWFILE"
fi
