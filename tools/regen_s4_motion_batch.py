"""Run tools/regen_s4_motion_frames.py for a list of monsters under a spend cap, then build each monster's before/after contact sheet.
Usage: uv run python tools/regen_s4_motion_batch.py --cap 10 --rate-in <$/1M input tok> --rate-out <$/1M output tok> monster [monster ...]
Rates are passed in, never assumed: read them off OpenAI's pricing page for the model on the day. Stops BEFORE a call that could
cross the cap (budgeting each call at the dearest one seen so far, or --first-call-budget for the first).
The spend ledger is tmp/gpt2_trial/out/calls.jsonl and is cumulative across runs, so --cap is the TOTAL, not this run's share.
A ledger row with no usage is priced at the dearest-call budget, never $0. `--selftest` runs the pricing in memory.
Refuses, before any call, every id that is unregistered or whose tier tools/artist_guard.tier_refusal does not allow."""
import glob, json, os, subprocess, sys
from pathlib import Path
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).parent.parent))
from tools.artist_guard import tier_refusal

OUT = "tmp/gpt2_trial/out"; LEDGER = f"{OUT}/calls.jsonl"; ANIMS = ["attack", "hit", "dead", "idle"]; MAX_TRIES = 2
PASS = 0.70   # idle-overlap retry floor for STANDING poses only; a motion pose is judged by eye, so attack/hit get one try


def arg(name, default=None):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


def cost(rec, rin, rout, unknown):
    """A row with no usage was still a paid call; it costs `unknown` (the dearest-call budget), never $0, or the cap goes blind."""
    u = rec.get("usage")
    if not u:
        return unknown
    return (u.get("input_tokens", 0) * rin + u.get("output_tokens", 0) * rout) / 1e6


def spent(rin, rout, unknown):
    return sum(cost(json.loads(l), rin, rout, unknown) for l in open(LEDGER)) if os.path.exists(LEDGER) else 0.0


def selftest():
    """In memory only: no ledger, no subprocess, no network."""
    fails = []
    known = cost({"usage": {"input_tokens": 1_000_000, "output_tokens": 500_000}}, 8.0, 30.0, 0.5)
    if abs(known - 23.0) > 1e-9:   # CONTROL: 1M in at $8 + 0.5M out at $30
        fails.append(f"CONTROL: a row with usage cost ${known}, expected $23.00")
    for rec in ({"usage": None}, {}, {"usage": {}}):
        if cost(rec, 8.0, 30.0, 0.5) != 0.5:
            fails.append(f"a paid row with no usage {rec} cost ${cost(rec, 8.0, 30.0, 0.5)}, expected the $0.50 budget, not $0")
    for f in fails:
        print("SELFTEST FAIL:", f)
    print("selftest:", "FAIL" if fails else "ok (usage priced; a row without usage costs the budget, not $0)")
    return 1 if fails else 0


def contact(monster):
    m = json.load(open("data/sprite_manifest.json"))["monster_sheets"][monster]
    before = Image.open(m["path"].replace("res://", "")).convert("RGBA")
    rows = [("BEFORE (shipped sheet, all 8 frames)", before)]
    for a in ANIMS:
        strips = sorted(glob.glob(f"{OUT}/{monster}__{a}__*__strip.png"))
        if strips: rows.append((f"AFTER {a} ({os.path.basename(strips[-1])})", Image.open(strips[-1]).convert("RGBA")))
    W = max(r[1].width for r in rows); o = Image.new("RGBA", (W, 256 * len(rows)), (90, 40, 120, 255)); d = ImageDraw.Draw(o)
    for i, (label, im) in enumerate(rows):
        o.alpha_composite(im, (0, i * 256)); d.text((4, i * 256 + 4), label, fill=(255, 255, 0, 255))
    o.convert("RGB").save(f"{OUT}/{monster}__contact.png"); return f"{OUT}/{monster}__contact.png"


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    cap, rin, rout = float(arg("--cap")), float(arg("--rate-in")), float(arg("--rate-out"))
    worst = float(arg("--first-call-budget", "0.50")); model = arg("--model", "gpt-image-2.6-sunburst"); quality = arg("--quality", "medium")
    flags = {"--cap", "--rate-in", "--rate-out", "--first-call-budget", "--model", "--quality"}
    monsters = [a for i, a in enumerate(sys.argv[1:], 1) if not a.startswith("--") and sys.argv[i - 1] not in flags]
    sheets = json.load(open("data/sprite_manifest.json"))["monster_sheets"]
    refused = {m: ("not a registered monster_sheet" if m not in sheets else tier_refusal(sheets[m].get("tier"), m)) for m in monsters}
    refused = {m: why for m, why in refused.items() if why}
    if refused:   # artist sheets and unknown provenance are never regen targets, even into tmp/
        for m, why in refused.items(): print(f"REFUSED {m}: {why}")
        sys.exit(5)
    os.makedirs(OUT, exist_ok=True)
    for mon in monsters:
        for anim in ANIMS:
            for attempt in range(1, (1 if anim in ("attack", "hit") else MAX_TRIES) + 1):
                now = spent(rin, rout, worst)
                if now + worst > cap:
                    print(f"STOP: spent ${now:.2f}, the next call could cross the ${cap:.2f} cap"); sys.exit(3)
                r = subprocess.run(["uv", "run", "-q", "python", "tools/regen_s4_motion_frames.py", mon, anim, "--model", model, "--quality", quality], capture_output=True, text=True)
                if r.returncode != 0:
                    print(f"STOP: {mon} {anim} call failed: {(r.stderr.strip().splitlines() or ['(no stderr)'])[-1][:200]}"); sys.exit(4)
                rec = json.loads(r.stdout.strip().splitlines()[-1]); worst = max(worst, cost(rec, rin, rout, worst) * 1.2)
                ok = anim == "dead" or all(g["overlap"] >= PASS for g in rec["grade"])
                print(f"{mon} {anim} try {attempt}: {'PASS' if ok else 'FAIL'} {rec['grade']} ${cost(rec, rin, rout, worst):.3f} {rec['seconds']}s")
                if ok: break
        print("contact:", contact(mon), f"| spent so far ${spent(rin, rout, worst):.2f}")
