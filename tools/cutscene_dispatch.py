#!/usr/bin/env python3
"""Which authored cutscenes can the game actually reach, and by which door?

WHY THIS IS IN THE REPO
-----------------------
On 2026-09-12 this lane reported "126 of 197 cutscenes unreachable" to itself, caught it on
implausibility (it included world1_chapter2 and every boss intro), and re-derived 34 with a
wider reader. The number that survived — 23 masterite intro/encounter scenes, 3,349 words —
went to struktured from a throwaway heredoc in a gitignored tmp/. Nobody but that session
could re-derive it. Same defect pck_budget.py was written for: the instrument behind a
decision was not in the record.

cowir-sfx needs the same answer from the other side (a cue named only by an undispatched
scene is not reachable, and their orphan audit scores it green). Two lanes, one question,
and the last five instruments this fleet rebuilt independently were each wrong differently.

THE ONE RULE THAT MAKES THE ANSWER TRUE
---------------------------------------
COUNT THE DOORS, NOT THE MENTIONS. A scene id appearing in src/ proves nothing: the
completion-flag table names scenes it does not dispatch, and _epilogue_done_or_unwired names
the four epilogues precisely because nothing plays them. There are SEVEN dispatch forms and a
reader that knows three reports the other four as dead:

    return "id"                     _get_pending_story_cutscene, the story spine      63
    _FRAGMENT_GATES key             a loop returns its own loop variable              20
    _FRAGMENT_GATES "after"         the chain AFTER a fragment reveal                 19
    <node>.cutscene_id = "id"       boss AND village encounters, before the fight     12
    cutscene_on_complete            quest JSON, on turn-in                             6
    PartyChatSystem.REGISTRY key    player-initiated, via PartyChatMenu               44
    play_cutscene("id" | CONST)     map and prop scripts, literal or by constant       5

The "after" chain is the one that matters most and is easiest to miss: it alone routes all 19
masterite DEFEAT scenes. A reader without it reports them dead and buries the real finding,
which is that not one masterite INTRO scene is routed by anything.

THE EIGHTH DOOR, AND HOW IT WAS FOUND (2026-09-12, same day)
------------------------------------------------------------
cowir-story routed three village masterite beats and this tool reported NO CHANGE: 34 before,
34 after. Their fix was real — `MasteriteEncounter` gained an `@export cutscene_id` awaited
before the fight, and three villages set it. The reader only knew `boss_cutscene_id`, the
DragonCave spelling, so a second property name for the same mechanism read as no door at all.

It failed toward NOT ROUTED, which is the safe direction for a death claim and the reason it
was caught in one run instead of quietly crediting a fix that had not landed. But a new door
is exactly what this tool cannot see by construction: it enumerates forms, and a form nobody
has written yet is absent from the list. **When a lane adds a dispatch path, this file is part
of the change.** The controls cannot catch it either — every control names a door that exists.

WHAT THIS DOES NOT ANSWER
-------------------------
ROUTED IS NOT REACHED. A door exists; whether its flag conditions ever open is a different
question and this tool has nothing to say about it. Comment-stripped, so a commented-out
dispatch does not count as a door.

Usage:
    tools/cutscene_dispatch.py                # report, unrouted scenes listed
    tools/cutscene_dispatch.py --json         # machine-readable, for other lanes' guards
    tools/cutscene_dispatch.py --selftest     # prove the reader answers both ways
Exit: 0 report produced · 2 a control failed (result withheld) · 3 nothing scanned
"""

import glob
import json
import os
import re
import sys

# Scenes that MUST read routed, one per form — a reader that loses a form is otherwise silent.
# Each is reachable ONLY by the form named, so a broken form flips exactly its own control, and
# the selftest proves that by deleting each form in turn. SINGLE-FORM IS THE WHOLE POINT: the
# first draft used world1_prologue for "return" and it is ALSO play_literal, so dropping the
# return reader left it routed and the control passed a reader that had lost a door.
CONTROLS_ROUTED = {
    "world1_chapter3": "return",
    "world1_fragment_arbiter": "fragment_loop",
    "world1_arbiter_defeat": "fragment_after",
    "world1_pyrroth_intro": "cutscene_id_property",
    "world1_orrery": "quest",
    "world1_chapter5": "party_chat",
    "world1_rat_king_intro": "play_literal",
    "world1_throne_room_approach": "play_const",
}
# Documented non-doors. Each names a scene in src/ WITHOUT dispatching it; if the reader
# counts any of these the mention/door distinction has collapsed and every verdict is noise.
CONTROLS_UNROUTED = ["world2_epilogue", "world1_warden_intro"]
# Lives in data/cutscenes/ and is NOT a scene — it must not appear in the corpus at all.
# Without this the directory is the definition, and a persona table reads as unreached content.
CONTROL_NOT_A_SCENE = "npc_showcase_personas"


def read(path):
    try:
        with open(path, errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def strip_comments(text):
    return "\n".join(l for l in text.split("\n") if not l.strip().startswith("#"))


def scene_ids(root="."):
    """Files in data/cutscenes/ that are SCENES. Directory membership is not the test.

    npc_showcase_personas.json lives there and is not a cutscene: its top-level keys are
    character names, it has no `steps`, and OverworldNPC loads it by a path CONSTANT
    (PERSONA_DATA_PATH). Counting it made the unrouted list one longer than the content it
    described -- a corpus defined by a directory rather than by the shape of its members.
    """
    out = []
    for path in glob.glob(os.path.join(root, "data/cutscenes/*.json")):
        try:
            data = json.loads(read(path))
        except ValueError:
            continue
        if isinstance(data, dict) and isinstance(data.get("steps"), list):
            out.append(os.path.basename(path)[:-5])
    return sorted(out)


def doors(root="."):
    """scene id -> set of forms that dispatch it. The whole tool is this function."""
    src = {p: strip_comments(read(p))
           for p in glob.glob(os.path.join(root, "src/**/*.gd"), recursive=True)}
    blob = "\n".join(src.values())
    out = {}

    def mark(sid, form):
        out.setdefault(sid, set()).add(form)

    for m in re.finditer(r'return\s+"([a-z0-9_]+)"', blob):
        mark(m.group(1), "return")

    gl = src.get(os.path.join(root, "src/GameLoop.gd"), "")
    gates = re.search(r"const _FRAGMENT_GATES := \{(.*?)\n\}", gl, re.S)
    if gates:
        body = gates.group(1)
        for m in re.finditer(r'"([a-z0-9_]+)"\s*:\s*\{', body):
            mark(m.group(1), "fragment_loop")
        for m in re.finditer(r'"after"\s*:\s*"([a-z0-9_]+)"', body):
            mark(m.group(1), "fragment_after")

    # Matches boss_cutscene_id = "x" AND <node>.cutscene_id = "x": one form, two property
    # names. Keyed on the suffix deliberately — see the docstring's eighth-door note.
    for m in re.finditer(r'cutscene_id\s*=\s*"([a-z0-9_]+)"', blob):
        mark(m.group(1), "cutscene_id_property")

    for path in glob.glob(os.path.join(root, "data/quests/*.json")):
        try:
            data = json.loads(read(path))
        except ValueError:
            continue

        def walk(node):
            if isinstance(node, dict):
                for key, val in node.items():
                    if key == "cutscene_on_complete" and isinstance(val, str) and val:
                        mark(val, "quest")
                    else:
                        walk(val)
            elif isinstance(node, list):
                for val in node:
                    walk(val)
        walk(data)

    pcs = src.get(os.path.join(root, "src/cutscene/PartyChatSystem.gd"), "")
    reg = re.search(r"const REGISTRY := \{(.*?)\n\}", pcs, re.S)
    if reg:
        for m in re.finditer(r'"([a-z0-9_]+)"\s*:', reg.group(1)):
            mark(m.group(1), "party_chat")

    for m in re.finditer(r'play_cutscene\(\s*"([a-z0-9_]+)"', blob):
        mark(m.group(1), "play_literal")
    consts = {m.group(1): m.group(2) for m in
              re.finditer(r'const\s+([A-Z_0-9]+)\s*(?::\s*\w+\s*)?=\s*"([a-z0-9_]+)"', blob)}
    for m in re.finditer(r"play_cutscene\(\s*([A-Z_0-9]+)", blob):
        if m.group(1) in consts:
            mark(consts[m.group(1)], "play_const")

    return out


def words_in(path):
    try:
        data = json.loads(read(path))
    except ValueError:
        return 0, 0
    texts = []

    def walk(node):
        if isinstance(node, dict):
            if isinstance(node.get("text"), str):
                texts.append(node["text"])
            for val in node.values():
                walk(val)
        elif isinstance(node, list):
            for val in node:
                walk(val)
    walk(data)
    return len(texts), sum(len(t.split()) for t in texts)


def check_controls(routed, ids):
    bad = []
    for sid, form in CONTROLS_ROUTED.items():
        if sid in ids and form not in routed.get(sid, set()):
            bad.append("%s must be routed via %s" % (sid, form))
    for sid in CONTROLS_UNROUTED:
        if sid in ids and routed.get(sid):
            bad.append("%s must read UNROUTED (it is only MENTIONED in src/) but shows %s"
                       % (sid, ",".join(sorted(routed[sid]))))
    return bad


def run(as_json=False):
    ids = scene_ids()
    if not ids:
        print("no data/cutscenes/*.json — run from the repo root", file=sys.stderr)
        return 3
    routed = {k: v for k, v in doors().items() if k in ids}
    bad = check_controls(routed, ids)
    if bad:
        print("CONTROL FAILED — result withheld:", file=sys.stderr)
        for b in bad:
            print("   ", b, file=sys.stderr)
        return 2

    unrouted = sorted(set(ids) - set(routed))
    if as_json:
        print(json.dumps({"routed": {k: sorted(v) for k, v in routed.items()},
                          "unrouted": unrouted}, indent=2, sort_keys=True))
        return 0

    counts = {}
    for forms in routed.values():
        for f in forms:
            counts[f] = counts.get(f, 0) + 1
    print("cutscenes %d  ·  routed %d  ·  NOT routed %d" % (len(ids), len(routed), len(unrouted)))
    for f in sorted(counts, key=lambda k: -counts[k]):
        print("   %-18s %d" % (f, counts[f]))
    lines = words = 0
    print("\nNOT routed by any of the seven forms:")
    for sid in unrouted:
        l, w = words_in("data/cutscenes/%s.json" % sid)
        lines += l
        words += w
        print("    %-38s %3d lines  %5d words" % (sid, l, w))
    print("\n%d scenes · %d spoken lines · %d words authored and on no route" %
          (len(unrouted), lines, words))
    print("ROUTED IS NOT REACHED: a door exists; whether its flags open is not asked here.")
    return 0


def selftest():
    """Prove the reader answers BOTH ways rather than asserting it does."""
    ids = scene_ids()
    routed = {k: v for k, v in doors().items() if k in ids}
    ok = True
    for sid, form in CONTROLS_ROUTED.items():
        good = form in routed.get(sid, set())
        ok &= good
        print("  %s  routed via %-16s %s" % ("PASS" if good else "FAIL", form, sid))
    for sid in CONTROLS_UNROUTED:
        good = sid not in routed
        ok &= good
        print("  %s  mentioned but NOT a door: %s" % ("PASS" if good else "FAIL", sid))
    good = "zzz_not_a_real_scene" not in routed
    ok &= good
    print("  %s  a fabricated id is not routed" % ("PASS" if good else "FAIL"))

    good = CONTROL_NOT_A_SCENE not in ids
    ok &= good
    print("  %s  a non-scene in data/cutscenes/ is not in the corpus: %s"
          % ("PASS" if good else "FAIL", CONTROL_NOT_A_SCENE))
    good = os.path.exists("data/cutscenes/%s.json" % CONTROL_NOT_A_SCENE)
    ok &= good
    print("  %s  ...and that control file still exists (else it proves nothing)"
          % ("PASS" if good else "FAIL"))

    # Each form must be LOAD-BEARING: drop it and its control must flip. A form that can be
    # deleted with every control still green is a form this tool is not really using.
    import copy
    for sid, form in CONTROLS_ROUTED.items():
        pruned = {k: {f for f in v if f != form} for k, v in copy.deepcopy(routed).items()}
        pruned = {k: v for k, v in pruned.items() if v}
        good = sid not in pruned
        ok &= good
        print("  %s  without '%s' its control reads unrouted — the form is load-bearing"
              % ("PASS" if good else "FAIL", form))
    return 0 if ok else 2


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    sys.exit(run(as_json="--json" in sys.argv))
