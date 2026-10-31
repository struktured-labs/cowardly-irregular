#!/usr/bin/env python3
"""Boss difficulty at the level the game actually meets each boss.

WHY THIS EXISTS. On 2026-10-27 I measured three points on the boss ladder, generalised
from them, and told grokbot the unwinnable fights were "the only two monsters that cast
the player's tier-3 shop spells". The full sweep found FOUR unwinnable bosses, and the
one that broke the explanation -- shadow_dragon, 0/20 at level 18 and 20/20 at level 26
-- casts no player spell at all. The table lived in a chat message, so the next lane
would have had to rebuild it to check me. This file is that table, regenerable.

THE MODEL (--model): biggest per-hit damage against the WEAKEST party member's pool.
Above a ratio of 1.0 the boss removes a member per turn, so the party has about five
rounds and then wins or loses on whether it can kill the boss inside that window. That
is why HP and per-hit damage are not interchangeable knobs: ice_dragon survives a ratio
of 1.40 because 10,000 HP dies in 2.05 rounds, while shadow_dragon loses at a LOWER 1.31
because 12,000 HP takes six.

The model is a SCREEN, not a verdict -- `--sweep` runs the real resolver and is the truth.

⛔ THE RATIO IS AN UPPER BOUND AND FAILS TOWARD FALSE ALARM. The party pool here is
derived from jobs.json stat_modifiers, which is the JOB ONLY: it excludes equipment and
passives, both of which ADD. Measured at level 26 the real pools run 1.08x-1.44x the
job-only figure. So `ratio <= 1.0` here means definitely safe, while `ratio > 1.0` means
"ask --sweep", not "this one-shots".

--selftest READS data/monsters.json, data/abilities.json and src/battle/Combatant.gd.
No subprocess, no godot, no writes, no git. (`--sweep` is the opposite and runs godot
once per boss; it is never reached by the selftest.)
"""
import argparse, json, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DUEL_PREFIXES = ("fighter_", "cleric_", "mage_", "rogue_", "bard_")


def _json(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        d = json.load(f)
    for key in ("monsters", "abilities", "jobs"):
        if isinstance(d, dict) and key in d and isinstance(d[key], dict):
            return d[key]
    return d


def level_mult_formula():
    """Parsed out of the engine so this tool's curve cannot silently diverge from it."""
    src = open(os.path.join(ROOT, "src/battle/Combatant.gd"), encoding="utf-8").read()
    m = re.search(r"level_mult\s*=\s*1\.0\s*\+\s*\(\s*job_level\s*-\s*1\s*\)\s*\*\s*([0-9.]+)", src)
    if not m:
        raise SystemExit("Combatant.gd no longer carries the 1.0 + (job_level - 1) * K form — "
                         "re-read it before trusting any ratio this tool prints")
    return float(m.group(1))


def bosses():
    """Every boss and the level its own entry declares. The five unlock-duel minibosses are
    excluded: they are forced-manual 1v1 showcases, not ladder rungs."""
    ms = _json("data/monsters.json")
    out = []
    for k, v in ms.items():
        if not v.get("boss"):
            continue
        if str(k).startswith(DUEL_PREFIXES):
            continue
        out.append((str(k), int(v.get("level", 0))))
    return sorted(out, key=lambda r: (r[1], r[0]))


def biggest_hit(entry, abilities):
    """The boss's own stat times its best damage multiplier. Support abilities carry no
    multiplier and are skipped; phase_faces are NOT included (they belong to a later phase
    of the same fight, and mixing them would attribute phase-4 damage to round one)."""
    st = entry.get("stats", {})
    best, which = 0.0, ""
    for aid in (entry.get("abilities") or []):
        a = abilities.get(aid, {})
        mult = float(a.get("damage_multiplier") or 0)
        if not mult:
            continue
        stat = float(st.get("magic", 0)) if a.get("type") == "magic" else float(st.get("attack", 0))
        if stat * mult > best:
            best, which = stat * mult, aid
    return best, which


def weakest_pool(level, k):
    jobs = _json("data/jobs.json")
    pools = [int(j.get("stat_modifiers", {}).get("max_hp", 0)) for j in jobs.values()
             if int(j.get("stat_modifiers", {}).get("max_hp", 0)) > 0]
    return min(pools) * (1.0 + (level - 1) * k)


def cmd_model():
    abilities, ms, k = _json("data/abilities.json"), _json("data/monsters.json"), level_mult_formula()
    print("# ratio = biggest per-hit / weakest JOB-ONLY pool. Upper bound: excludes gear and")
    print("# passives, which measured 1.08x-1.44x at level 26. <=1.0 is safe; >1.0 asks --sweep.")
    print("%-26s %-5s %-8s %-9s %-7s %-8s %s" % ("boss", "lvl", "bigHit", "weakest", "ratio", "bossHP", "via"))
    for name, lvl in bosses():
        hit, which = biggest_hit(ms[name], abilities)
        pool = weakest_pool(lvl, k)
        print("%-26s %-5d %-8d %-9d %-7.2f %-8s %s" % (
            name, lvl, hit, pool, (hit / pool if pool else 0), ms[name].get("stats", {}).get("max_hp"), which))


def cmd_sweep(trials):
    env = dict(os.environ, XDG_DATA_HOME=os.path.join(ROOT, "tmp/xdg"))
    print("%-26s %-5s %-9s %-8s %s" % ("boss", "lvl", "winrate", "rounds", "HP left"))
    for name, lvl in bosses():
        e = dict(env, BAL_LEVEL=str(lvl), BAL_TRIALS=str(trials), BAL_ENEMIES=name, BAL_GEAR="1")
        log = os.path.join(ROOT, "tmp", "ladder_%s.out" % name)
        with open(log, "wb") as fh:
            subprocess.run(["godot", "--headless", "--audio-driver", "Dummy",
                            "-s", "res://tools/balance_harness.gd"],
                           cwd=ROOT, env=e, stdout=fh, stderr=subprocess.STDOUT, timeout=600)
        text = open(log, encoding="utf-8", errors="replace").read()
        def grab(pat, default="?"):
            m = re.search(pat, text)
            return m.group(1) if m else default
        print("%-26s %-5d %-9s %-8s %s" % (name, lvl,
              grab(r"win rate\s+\d+/\d+ = ([\d.]+%)"),
              grab(r"mean rounds\s+([\d.]+)"),
              grab(r"party HP left ([\d.]+%)")))


def cmd_selftest():
    fails = []

    k = level_mult_formula()
    if abs(k - 0.04) > 1e-9:
        print("note: the engine's per-level coefficient is %s, not the 0.04 measured on 2026-10-27" % k)
    for lvl, want in ((20, 1.76), (26, 2.00), (36, 2.40)):
        got = 1.0 + (lvl - 1) * k
        if abs(got - want) > 0.005:
            fails.append("level_mult(%d) = %.3f, but the harness printed %.2f" % (lvl, got, want))

    bs = bosses()
    if len(bs) < 10:
        fails.append("only %d bosses derived; monsters.json carries far more" % len(bs))
    ms = _json("data/monsters.json")
    for name, lvl in bs:
        if int(ms[name].get("level", -1)) != lvl:
            fails.append("%s: derived level %d != its own entry" % (name, lvl))
    for name, _ in bs:
        if name.startswith(DUEL_PREFIXES):
            fails.append("%s is an unlock duel and must not be a ladder rung" % name)
    if not any(n == "chancellor_mordaine" for n, _ in bs):
        fails.append("chancellor_mordaine absent — the derivation is not finding real bosses")

    synthetic = {"stats": {"magic": 100, "attack": 10}, "abilities": ["__m", "__p"]}
    abil = {"__m": {"type": "magic", "damage_multiplier": 3.0},
            "__p": {"type": "physical", "damage_multiplier": 5.0}}
    hit, which = biggest_hit(synthetic, abil)
    if (hit, which) != (300.0, "__m"):
        fails.append("biggest_hit picked %s at %s; magic 100 x 3.0 must beat attack 10 x 5.0" % (which, hit))
    if biggest_hit({"stats": {"magic": 9}, "abilities": ["__s"]}, {"__s": {"type": "support"}})[0] != 0:
        fails.append("a support ability with no multiplier must contribute no damage")

    if fails:
        for f in fails:
            print("FAIL %s" % f)
        return 1
    print("ok boss_ladder_sweep: %d bosses derived, level curve +%.0f%%/level agrees with the "
          "harness at L20/L26/L36, biggest_hit picks by damage not by type" % (len(bs), k * 100))
    return 0


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--list", action="store_true", help="derived boss:level pairs")
    p.add_argument("--model", action="store_true", help="the ratio screen, data only, no godot")
    p.add_argument("--sweep", action="store_true", help="measure each boss with the real resolver (runs godot)")
    p.add_argument("--trials", type=int, default=20)
    p.add_argument("--selftest", action="store_true")
    a = p.parse_args()
    if a.selftest:
        sys.exit(cmd_selftest())
    if a.list:
        for n, l in bosses():
            print("%s:%d" % (n, l))
    elif a.sweep:
        cmd_sweep(a.trials)
    else:
        cmd_model()
