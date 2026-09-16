#!/usr/bin/env python3
"""llm_prompt_bench — measure a prompt change against the live local model.

Every claim this lane made on 2026-09-16 rests on a throwaway harness in tmp/. This
is that harness, kept, so the next person to touch a prompt — or to swap the model —
can reproduce the numbers instead of re-deriving them.

WHAT IT MEASURES
    Renders REAL prompts with tools/llm_prompt_bench.gd (DialoguePrompts, not a copy),
    samples the live model with the SAME request shape HTTPBackend._build_body sends
    (/api/generate, format json, temperature 0.7, num_predict 512), and reports how many
    replies survive validate_rule_composition's own parse.

    Two arms per run: the prompt as shipped, and the prompt with one edit applied. The
    edit is given as a literal find/replace on the rendered text, so exactly one thing
    differs between arms.

THREE THINGS THAT COST THIS LANE A WRONG ANSWER, ENCODED HERE
    1. SEQUENTIAL BY DEFAULT. Concurrency changes the malformed-reply rate: measured
       2026-09-16, same prompt, 30 samples — sequential lost 1, three parallel workers
       lost 4. The game issues one request at a time, so a parallel run understates the
       shipped path. --workers exists, and warns.
    2. BOTH ARMS IN ONE RUN. A comparison against a number from an earlier run is a
       comparison across whatever else changed (model load, machine, my own sampler).
    3. IT PRINTS FISHER'S EXACT p. A 4-in-90 difference looks decisive and is not
       (p=0.12); the same effect over three rounds was (p=0.03). The number is there so
       a ship decision does not rest on eyeballing two fractions.

USAGE
    tools/llm_prompt_bench.py --list
    tools/llm_prompt_bench.py --job mage_nuke --n 30
    tools/llm_prompt_bench.py --job rogue_fast --n 30 \\
        --find "as a JSON string" --replace "as a JSON ARRAY (not a quoted string)"

Requires a local model: see the ollama-status skill, or `ollama serve` + `ollama pull llama3`.
"""
import argparse
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request
from math import comb
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tmp" / "llm_prompt_bench"
RENDERER = "res://tools/llm_prompt_bench.gd"

# The same request HTTPBackend._build_body sends for a json_mode call.
URL = "http://localhost:11434/api/generate"
MODEL = "llama3:latest"
OPTIONS = {"num_predict": 512, "temperature": 0.7}


def render_prompts() -> dict:
    """Render real prompts through DialoguePrompts. Godot writes them; we only read."""
    OUT.mkdir(parents=True, exist_ok=True)
    env_cmd = [
        "godot", "--headless", "--audio-driver", "Dummy", "-s", RENDERER,
    ]
    proc = subprocess.run(
        env_cmd, cwd=ROOT, capture_output=True, text=True,
        env={**__import__("os").environ, "XDG_DATA_HOME": str(ROOT / "tmp" / "xdg")},
    )
    manifest = OUT / "manifest.json"
    if not manifest.exists():
        sys.exit(f"renderer produced no manifest.\n{proc.stdout[-2000:]}\n{proc.stderr[-2000:]}")
    return json.loads(manifest.read_text())


def sample_once(prompt: str) -> bool:
    """True when the reply parses the way validate_rule_composition parses it."""
    body = json.dumps({"model": MODEL, "prompt": prompt, "stream": False,
                       "format": "json", "options": OPTIONS}).encode()
    req = urllib.request.Request(URL, data=body, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            outer = json.loads(r.read())
    except (urllib.error.URLError, TimeoutError) as e:
        sys.exit(f"model unreachable at {URL}: {e}\nStart it, or see the ollama-status skill.")
    try:
        reply = json.loads(outer.get("response", ""))
    except Exception:
        return False
    rules = reply.get("rules_json", "")
    if isinstance(rules, list):          # the validator accepts an array directly
        return True
    try:
        return isinstance(json.loads(rules), list)
    except Exception:
        return False


def run_arm(prompt: str, n: int, workers: int) -> int:
    if workers <= 1:
        return sum(sample_once(prompt) for _ in range(n))
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(max_workers=workers) as ex:
        return sum(ex.map(lambda _: sample_once(prompt), range(n)))


def fisher_two_tailed(a: int, b: int, c: int, d: int) -> float:
    """Exact p for the 2x2 [[a,b],[c,d]]. No scipy in this repo's toolchain."""
    def table_p(w, x, y, z):
        return comb(w + x, w) * comb(y + z, y) / comb(w + x + y + z, w + y)
    observed = table_p(a, b, c, d)
    total = 0.0
    for i in range(a + c + 1):
        j, k = (a + b) - i, (a + c) - i
        l = (c + d) - k
        if j < 0 or k < 0 or l < 0:
            continue
        p = table_p(i, j, k, l)
        if p <= observed + 1e-12:
            total += p
    return total


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--job", help="which rendered prompt to measure")
    ap.add_argument("--n", type=int, default=30, help="samples PER ARM (default 30)")
    ap.add_argument("--find", help="text to replace in the rendered prompt (the variant arm)")
    ap.add_argument("--replace", default="", help="what to replace it with")
    ap.add_argument("--workers", type=int, default=1,
                    help="parallel requests. DEFAULT 1 — concurrency changes the failure rate")
    ap.add_argument("--list", action="store_true", help="list the rendered prompts and exit")
    args = ap.parse_args()

    manifest = render_prompts()
    jobs = {s["key"]: s for s in manifest["scenarios"]}
    if args.list or not args.job:
        print("rendered prompts:")
        for key, s in jobs.items():
            print(f"  {key:16s} {s['domain']:10s} {Path(s['path']).stat().st_size:6d} B")
        return
    if args.job not in jobs:
        sys.exit(f"unknown job '{args.job}'. --list to see them.")
    if args.workers > 1:
        print(f"⚠️  --workers {args.workers}: parallel sampling raises the malformed rate "
              f"(measured 4/30 vs 1/30 sequential). The game issues one request at a time.")

    shipped = Path(jobs[args.job]["path"]).read_text()
    if not args.find:
        ok = run_arm(shipped, args.n, args.workers)
        print(f"{args.job}: {ok}/{args.n} usable (shipped prompt only — pass --find/--replace to compare)")
        return
    if shipped.count(args.find) != 1:
        sys.exit(f"--find matched {shipped.count(args.find)} times; it must match exactly once "
                 f"so only one thing differs between arms.")
    variant = shipped.replace(args.find, args.replace)

    t0 = time.time()
    a_ok = run_arm(shipped, args.n, args.workers)
    b_ok = run_arm(variant, args.n, args.workers)
    p = fisher_two_tailed(args.n - a_ok, a_ok, args.n - b_ok, b_ok)
    print(f"\n{args.job}  n={args.n} per arm  workers={args.workers}  {time.time() - t0:.0f}s")
    print(f"  shipped  {a_ok}/{args.n} usable   ({args.n - a_ok} lost)")
    print(f"  variant  {b_ok}/{args.n} usable   ({args.n - b_ok} lost)")
    print(f"  Fisher exact two-tailed p = {p:.4f}")
    if p >= 0.05:
        print("  NOT significant at p<0.05 — run more rounds before shipping on this.")


if __name__ == "__main__":
    main()
