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
   read. Found 2026-09-18; cowir-autogrind's fix LANDED and this row now reads `both`, which
   is the prediction this paragraph made coming back true rather than a stale note. The shape is
   kept as the worked example of defect #1 — it is how the category was found, and the tool would
   no longer demonstrate it from live data alone.
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
THE CORPUS IS THE CATALOG ON DISK, AND THERE IS A SECOND CONSTRUCTION PATH
`preset_castable()` reads data/autobattle_rule_templates.json. Two more presets — "Aggressive" and
"Defensive" — are built IN CODE by AutobattleSystem._create_default_scripts, which runs whenever
user://autobattle_scripts.json is absent, i.e. for every new player. They are not in the JSON and
this tool cannot see them. Worse for a reader: they would read as ZERO rather than as an error,
because their actions carry `ability_id` where the catalog carries `id`, and an int ActionType where
the catalog carries a string. A key mismatch is silence, not a crash.

Measured 2026-09-18: those two cast exactly one ability, `power_strike`, which is ALREADY in the
JSON corpus and carries no `effect` — so every number this tool prints is unaffected today. The gap
is in the instrument, not in the answer, and the two are separate claims. If a future in-code preset
casts an ability the catalog does not, this tool goes quietly short by one.

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


def code_only(src):
    """GDScript source with `#` comments and triple-quote regions removed.

    Every lookup here is `"<effect>" in source`, so without this a COMMENT naming an effect
    reports the grind as handling it. Measured 2026-09-18: all 16 preset-castable effects agree
    raw vs stripped, so exposure today is ZERO — and selftest() plants a comment that WOULD fool
    the raw form. Fixed at birth rather than left latent: the resolver is 31% comment by line
    (1986 -> 1365) and an arm drafted as a comment is exactly what would flip a verdict.

    Not a 17th private stripper. `GdSource` is GDScript and unreachable from Python, and the two
    quote-aware readers already in tools/ carry SHELL escaping rules for `.sh` files. This is the
    first GDScript-aware one here. Comments are removed FIRST, because a triple-quote inside a
    `#` comment otherwise flips parity for the rest of the file — GdSource.split()'s documented
    order, and the trap cowir-sprites measured in 26 test files including that helper itself.
    Splitting on the delimiter (rather than toggling per line) also handles a one-line docstring,
    which a parity counter is blind to because its count is 2 and parity stays even.
    """
    out = []
    for line in src.split("\n"):
        if line.strip().startswith("#"):
            continue
        quote, kept, i = "", "", 0
        while i < len(line):
            c = line[i]
            if quote:
                if c == "\\":
                    kept += line[i:i + 2]
                    i += 2
                    continue
                if c == quote:
                    quote = ""
                kept += c
            elif c in "\"'":
                quote = c
                kept += c
            elif c == "#":
                break
            else:
                kept += c
            i += 1
        out.append(kept)
    parts = "\n".join(out).split('\"\"\"')
    return "\n".join(parts[i] for i in range(0, len(parts), 2))


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
    grind_src, live_src = code_only(read(GRIND)), code_only(read(LIVE))
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
    live_src = code_only(read(LIVE))
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

    # The reader must not see a comment, and must not eat real code. Over-stripping and a
    # correct strip are the same green, so both directions are pinned — GdSource's obligation on
    # every caller, which applies to this Python reader for the same reason.
    planted = read(GRIND) + '\n## a future arm will handle "zz_probe_effect" one day\n'
    good = ('"zz_probe_effect"' in planted) and ('"zz_probe_effect"' not in code_only(planted))
    ok &= good
    print(f"  {'PASS' if good else 'FAIL'}  a comment naming an effect is NOT seen as handling it "
          f"(raw would say yes)")

    live_code = code_only(read(LIVE))
    good = 'has_status("barrier")' in live_code and 'func start_battle(' in live_code
    ok &= good
    print(f"  {'PASS' if good else 'FAIL'}  real code survives the strip: has_status(\"barrier\") "
          f"and func start_battle(")

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
