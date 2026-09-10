#!/usr/bin/env bash
# Print a real assembled NPC prompt, and optionally what the local model says back.
#
#   tools/llm_prompt_preview.sh                  # opening prompt, full context
#   tools/llm_prompt_preview.sh reply            # the follow-up prompt
#   tools/llm_prompt_preview.sh opening --bare   # no context blocks (the stranger case)
#   tools/llm_prompt_preview.sh opening --ask    # also send it to local Ollama, 3 samples
#
# Exists because unit tests assert that a block is PRESENT and can say nothing
# about whether the assembled whole reads well to a model. Rendering the real
# builders is what caught a run-on between two blocks on 2026-09-10.
set -uo pipefail
cd "$(dirname "$0")/.."

KIND="opening"; ASK=0; PASS=()
for a in "$@"; do
  case "$a" in
    opening|reply|signoff|intent|party) KIND="$a" ;;
    --ask) ASK=1 ;;
    *) PASS+=("$a") ;;
  esac
done

TMP="tmp/llm_prompt_preview.txt"
mkdir -p tmp
rm -f "$TMP"
# The script WRITES $TMP itself. Do not capture stdout: autoload boot logging
# prints after quit() and would land in the capture.
XDG_DATA_HOME="$PWD/tmp/xdg" godot --headless --audio-driver Dummy \
  --script tools/llm_prompt_preview.gd -- "$KIND" ${PASS[@]+"${PASS[@]}"} >/dev/null 2>&1
EC=$?

if [ ! -s "$TMP" ]; then
  echo "llm_prompt_preview: rendered nothing (godot EC=$EC) — the builders may have changed shape." >&2
  exit 3
fi

echo "===== PROMPT ($KIND${PASS[*]+, ${PASS[*]}}) — $(wc -c < "$TMP") bytes ====="
cat "$TMP"

[ "$ASK" -eq 1 ] || exit 0

MODEL="${OLLAMA_MODEL:-llama3:latest}"
if ! curl -sS -m 5 -o /dev/null http://localhost:11434/api/tags; then
  echo "" >&2; echo "--ask: no local Ollama on 11434; prompt printed above only." >&2
  exit 0
fi
echo ""
echo "===== $MODEL SAYS (3 samples) ====="
python3 - "$TMP" "$MODEL" <<'PY'
import json, sys, urllib.request
prompt = open(sys.argv[1]).read(); model = sys.argv[2]
for i in range(3):
    body = json.dumps({"model": model, "prompt": prompt, "stream": False,
                       "options": {"temperature": 0.8}}).encode()
    req = urllib.request.Request("http://localhost:11434/api/generate", body,
                                 {"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            print(f"{i+1}. {json.load(r).get('response','').strip()}")
    except Exception as e:
        print(f"{i+1}. ERROR {e}")
PY
