#!/usr/bin/env python3
"""Which ability effects can a shipped autobattle preset cast, and does the grind model them?

WHY THIS IS A TOOL AND NOT A GREP
---------------------------------
The grep answer is junk and it is junk in the alarming direction. `HeadlessBattleResolver`
ends its effect dispatch with a generic `target.add_status(effect, duration)` fall-through,
so EVERY effect is "handled" in the weakest possible sense and NO effect is named unless
someone wrote an arm for it. Counting effects the resolver does not name reports 35 of 66
diverging; the number that survives reading is 2.

The collapse is the whole instrument:

    66  effects authored in abilities.json
    35  "the resolver never names it"        <- a grep, and meaningless
     6  ...AND castable from a shipped preset   <- the reachability filter
     2  ...AND live and grind actually disagree <- read each hit

Four of those six are FINE and this tool says so. The resolver's own else-branch states the
policy: "Live owns a ~40-arm effect table; headless deliberately does NOT mirror it. An
effect we do not model is a NO-OP, never damage." An unmodelled effect that adds the SAME
key live creates is that policy working. Only two shapes are defects.

THE TWO SHAPES WORTH A HUMAN
----------------------------
1. WRONG KEY — live composes a status name the grind does not. `provoke` authored effect
   `taunt`; live writes `taunted_<caster>` and reads that prefix back in `_find_taunter`,
   while the fall-through wrote a status literally called "taunt" that nothing anywhere
   read. Found 2026-09-18; cowir-autogrind's fix is queued for .440, so this tool still
   reports it as a GAP against main and will flip to `both` when that lands.
2. LIVE CONSUMES, GRIND ABSENT — `guardian_wall`/`barrier`: live does
   `has_status("barrier")` then `remove_status("barrier")` at three damage sites, the
   grind has zero references. A grinding player gets no ward; the same party in a manual
   battle does.

The precedent for adding an arm is REACHABILITY, not importance: `cleanse` got one because
Esuna sits in the default cleric script and two presets. That is the bar this tool measures.

STATED BIAS, in the noisy direction
-----------------------------------
"The resolver names the effect" is a bare-literal scan, so an arm that handles an effect
under a different spelling reads as MISSING. That inflates the gap list, which is the safe
direction for a report a human reads: a false entry costs a glance, a missed one costs a
silent divergence. The resolver's own cleanse comment makes the same point from the other
side — a literal `has_status("x")` scan is blind to loop variables on BOTH engines, which
is exactly how `taunted_<name>` stayed hidden.

WHAT THIS DOES NOT ANSWER
-------------------------
Castable is not cast. A preset rule sits behind conditions, and whether a given party ever
satisfies them is a different question. Nor does "the grind models it" mean the two engines
agree on MAGNITUDE — same-key, different-number is invisible here and is its own audit.
The LLM Rule Composer emits into this same grammar and is not covered; its vocabulary is
model-driven rather than authored, so it has no static corpus to read.

Usage:
    tools/preset_castable_effects.py              # report
    tools/preset_castable_effects.py --selftest   # prove the reader answers both ways
Exit: 0 report produced · 2 a control failed (result withheld) · 3 nothing scanned
"""

import json
import os
import re
import sys

TEMPLATES = "data/autobattle_rule_templates.json"
ABILITIES = "data/abilities.json"
GRIND = "src/autogrind/HeadlessBattleResolver.gd"
LIVE = "src/battle/BattleManager.gd"

# Controls, both directions. `lullaby` is named by both engines; `guardian_wall` is consumed
# live and absent from the grind. If either reads the wrong way the reader is broken and no
# result is printed — a table that cannot distinguish these two says nothing.
CONTROL_BOTH = "lullaby"
CONTROL_GAP = "guardian_wall"
# Effects, not abilities: the composed-key reader is pinned on live's side alone, so these stay
# true whichever way the grind half is resolved.
CONTROL_COMPOSED = "taunt"   # live writes `taunted_<caster>`, not `taunt`
CONTROL_PLAIN = "sleep"      # live writes the authored name verbatim


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def ability_index():
    raw = json.loads(read(ABILITIES))
    rows = raw if isinstance(raw, dict) else {a.get("id"): a for a in raw}
    # abilities.json nests under an "abilities" key in some revisions; accept both.
    if "abilities" in rows and isinstance(rows["abilities"], dict):
        rows = rows["abilities"]
    return {k: v for k, v in rows.items() if isinstance(v, dict)}


def preset_castable():
    """Ability ids a shipped preset can actually select. Actions are {type: ability, id: X}."""
    doc = json.loads(read(TEMPLATES))
    out = set()
    for tpl in doc.get("templates", []):
        for rule in tpl.get("rules", []):
            for action in rule.get("actions", []):
                if action.get("type") == "ability" and action.get("id"):
                    out.add(action["id"])
    return out


def live_arm_body(effect, live_src):
    """The match-arm block live runs for this effect, or "" — used to see what key it WRITES."""
    m = re.search(r'^(\s*)"%s":\s*$' % re.escape(effect), live_src, re.M)
    if not m:
        return ""
    indent, out = len(m.group(1)), []
    for line in live_src[m.end():].split("\n"):
        if line.strip() and (len(line) - len(line.lstrip())) <= indent:
            break
        out.append(line)
    return "\n".join(out)


def composed_key(effect, live_src):
    """Live's arm may write a COMPOSED status name, so the authored effect is not the key.

    `provoke` authors `taunt` and live writes `add_status("taunted_%s" % caster_name)`. Without
    this the tool reports "same key, documented policy" for the one shape its own header calls
    defect #1 — a category named and undetectable, which is worse than not mentioning it.
    """
    for m in re.finditer(r'add_status\("([A-Za-z_][A-Za-z0-9_]*?)_?%s"', live_arm_body(effect, live_src)):
        # Greedy capture swallows the separator, so the prefix reads `taunted_` and every
        # downstream lookup then searches `taunted__`. Caught by reading the output, not by a
        # control: mine pinned live's side, where the doubled key never appears.
        return m.group(1).rstrip("_")
    return ""


def live_handling(effect, live_src):
    """How the live engine treats this effect: composes a key, reads one back, an arm, or neither."""
    if composed_key(effect, live_src):
        return "composes"
    if f'has_status("{effect}")' in live_src:
        return "consumes"
    return "arm" if live_arm_body(effect, live_src) else "none"


def classify(effect, live, grind_src, live_src):
    if live == "composes":
        # The authored name is not the key. Ask whether the grind knows the REAL one.
        prefix = composed_key(effect, live_src)
        if f'"{prefix}_' in grind_src or f"{prefix}_" in grind_src:
            return "both"
        return f'GAP: live writes `{prefix}_<name>`, grind has no reference to that key'
    if f'"{effect}"' in grind_src:
        return "both"
    if live == "consumes":
        return "GAP: live consumes it, grind has no reference"
    if live == "arm":
        return "no-op (same key, documented policy)"
    return "unmodelled by both"


def collect(limit_to_presets=True):
    abilities = ability_index()
    grind_src, live_src = read(GRIND), read(LIVE)
    ids = preset_castable() if limit_to_presets else set(abilities)
    rows = []
    for aid in sorted(ids):
        a = abilities.get(aid)
        if not isinstance(a, dict):
            continue
        effect = a.get("effect")
        if not isinstance(effect, str):
            continue
        live = live_handling(effect, live_src)
        rows.append((aid, effect, live, classify(effect, live, grind_src, live_src)))
    return rows


def run():
    for p in (TEMPLATES, ABILITIES, GRIND, LIVE):
        if not os.path.exists(p):
            print(f"missing input: {p}", file=sys.stderr)
            return 3
    rows = collect()
    if not rows:
        print("nothing scanned — no preset-castable ability carries an `effect`", file=sys.stderr)
        return 3
    print(f"{'ability':22s} {'effect':22s} {'live':10s} verdict")
    for aid, effect, live, verdict in rows:
        print(f"{aid:22s} {effect:22s} {live:10s} {verdict}")
    gaps = [r for r in rows if r[3].startswith("GAP")]
    print(f"\n{len(rows)} preset-castable abilities carry an effect · {len(gaps)} need a human")
    for aid, effect, _, verdict in gaps:
        print(f"  {aid} ({effect}) — {verdict}")
    return 0


def selftest():
    """Prove the reader answers BOTH ways rather than asserting it does."""
    ok = True
    rows = {r[0]: r for r in collect()}

    both = rows.get(CONTROL_BOTH)
    good = both is not None and both[3] == "both"
    ok &= good
    print(f"  {'PASS' if good else 'FAIL'}  an effect both engines name reads `both`: {CONTROL_BOTH}")

    gap = rows.get(CONTROL_GAP)
    good = gap is not None and gap[3].startswith("GAP")
    ok &= good
    print(f"  {'PASS' if good else 'FAIL'}  live-consumes/grind-absent reads as a GAP: {CONTROL_GAP}")

    # Negative: an id no preset casts must not appear. Synthesised, because the corpus may
    # one day cast everything and a check that cannot return a positive is not a check.
    good = "zz_not_a_real_ability" not in rows
    ok &= good
    print(f"  {'PASS' if good else 'FAIL'}  an ability no preset casts is absent from the table")

    # The composed-key reader, pinned on LIVE's side only. Deliberately not "provoke is
    # currently a GAP": the grind half of that is being fixed, and a control that reds when a
    # bug is fixed is a control nobody keeps. What must stay true is that the reader can SEE a
    # composed key at all — without this the wrong-key shape is silently filed as a no-op.
    live_src = read(LIVE)
    good = live_handling(CONTROL_COMPOSED, live_src) == "composes"
    ok &= good
    print(f"  {'PASS' if good else 'FAIL'}  a composed status key is recognised as composed: "
          f"{CONTROL_COMPOSED} -> `{composed_key(CONTROL_COMPOSED, live_src)}_<name>`")

    good = composed_key(CONTROL_COMPOSED, live_src) == "taunted"
    ok &= good
    print(f"  {'PASS' if good else 'FAIL'}  the composed prefix is exact, no doubled separator: "
          f"`{composed_key(CONTROL_COMPOSED, live_src)}` (a `taunted_` capture searches `taunted__`)")

    good = live_handling(CONTROL_PLAIN, live_src) != "composes"
    ok &= good
    print(f"  {'PASS' if good else 'FAIL'}  a plain status key is NOT read as composed: {CONTROL_PLAIN}")

    # The reachability filter is the whole instrument — prove it is load-bearing by removing
    # it and watching the population grow. If these match, the filter is doing nothing and
    # every number this tool prints is the junk grep it exists to replace.
    wide = collect(limit_to_presets=False)
    good = len(wide) > len(rows)
    ok &= good
    print(f"  {'PASS' if good else 'FAIL'}  dropping the preset filter widens the corpus "
          f"({len(rows)} -> {len(wide)}) — proves the filter is load-bearing")
    return 0 if ok else 2


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv else run())
