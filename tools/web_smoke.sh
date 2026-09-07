#!/usr/bin/env bash
# Web-boot smoke: executes the ACTUAL WASM build in headless chromium.
# Finds a playwright module on the machine (no project-local install needed).
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
PORT="${1:-8371}"
PW_DIR=""
for cand in "$HOME"/projects/*/node_modules/playwright; do
  [ -d "$cand" ] && PW_DIR="$(dirname "$cand")" && break
done
[ -z "$PW_DIR" ] && { echo "[WEB-SMOKE] no playwright module found"; exit 3; }
mkdir -p tmp
python3 tools/web_smoke_server.py "$PORT" builds/web & SERVER=$!
trap 'kill $SERVER 2>/dev/null || true' EXIT
sleep 1
PW_MODULE="file://$PW_DIR/playwright/index.mjs" node tools/web_smoke.mjs "http://127.0.0.1:$PORT"
