#!/usr/bin/env python3
"""Find signal connections whose HANDLER is exercised by tests while the CONNECTION is pinned by none.

WHY THIS EXISTS. Four instances of one defect class landed or were found in a single shift
(2026-10-28/29), and in every one the mechanism was correct and the thing that INVOKES it was the gap:

  _record_first_damage            3 call sites, all correct; 9 enemy take_damage sites in the pooled
                                  paths recorded nothing. Shipped for months. Found by a LOG
                                  contradicting a number, not by any test.
  _on_hp_changed_for_low_water    handler correct, nothing asserted the connection. The runtime arm
                                  called it DIRECTLY, so it passed whether or not anything invoked it.
  _update_danger_music            14 guards pin the envelope's behaviour, 0 pin its single caller.
                                  Delete that caller and party HP stops moving the music, all green.
  VictoryOverlay.fight_shape_chip helper correct; _build_loot_strip early-returned before rendering it,
                                  so the chip was invisible on exactly the fights it exists for.

A test that DRIVES a handler is not evidence the handler RUNS, and the tests exercising a mechanism are
precisely why nobody looks at its wiring. This ranks that gap so it can be looked at deliberately.

⚠️ SCOPE, STATED SO A CLEAN RUN IS NOT OVERREAD: signal `.connect(...)` only. A mechanism reached by a
plain call with one caller -- which is what `_update_danger_music` is -- is NOT in this corpus. A green
here says nothing about that shape. Two of the four instances above are outside this tool by
construction; it is deliberately the precise subset rather than a vague sweep.

⚠️ A REPORT, NOT A GATE. It prints a ranking and exits 0 whatever it finds. An allowlist of
pre-existing entries would be rot arriving dressed as diligence -- 40 suppressions on day one, and the
41st never gets read. Whoever wants a specific connection defended writes an arm for it.

`--selftest` runs the classifier over in-memory strings ONLY: no file opened, no directory walked, no
subprocess, no git, nothing written.
"""
import os
import re
import sys

SRC_DIRS = ("src",)
TEST_DIR = os.path.join("test", "unit")

## `<something>.<signal>.connect(<handler>)` or `<signal>.connect(<handler>)`.
CONNECT_RE = re.compile(r"(?:(\w+)\.)?(\w+)\.connect\(\s*([\w.]+)")
## Bound Callables are stashed in a local first -- `var cb = _on_x.bind(y)` -- which is the shape
## BattleManager uses for every per-combatant signal, so the raw handler token is a local name.
BIND_RE = re.compile(r"var\s+(\w+)\s*(?::\s*\w+\s*)?=\s*(\w+)\.bind\(")
## Handlers WE define. Anything else a connect names is an engine method, not a mechanism of ours.
FUNC_RE = re.compile(r"^func\s+(\w+)", re.M)
## Godot calls these itself, so "how many callers in src/" is not a question about them. A fixed list
## is honest here where a derived rule is not: these are engine API, the set is documented and stable,
## and a wrong entry only skips a row rather than inventing one.
ENGINE_VIRTUALS = {
    "_ready", "_init", "_process", "_physics_process", "_input", "_unhandled_input",
    "_unhandled_key_input", "_shortcut_input", "_gui_input", "_draw", "_notification",
    "_enter_tree", "_exit_tree", "_to_string", "_get", "_set", "_get_property_list",
    "_can_drop_data", "_drop_data", "_get_drag_data", "_integrate_forces", "_value_changed",
}
CLASSNAME_RE = re.compile(r"^class_name\s+(\w+)", re.M)
CALL_RE = re.compile(r"(?<!\w)(\w+)\s*\(")
## Names inside a `.connect(...)` or `.is_connected(...)` argument list. @cowir-music's class-A audit:
## 5 of 94 rows were pinned by arms my substring test could not see, for two reasons BOTH present in a
## correctly written assertion -- the arm says `<signal>.is_connected(` where a `.connect(` pattern
## cannot match, and the Callable is receiver-qualified (`is_connected(SoundManager.set_save_corruption)`)
## so `connect(<handler>` cannot match either, because the receiver sits between them.
## ⚠️ NO LEADING DOT REQUIRED. The two rows that survived the first fix are pinned by a SOURCE READ --
## `assert_true(body.contains("is_connected(_on_party_leveled_up)"))` -- so the character before the
## call is a QUOTE, not a dot. Requiring `\.` missed the single most common way this codebase asserts
## a wiring guard. `disconnect(` matches too, which is correct: an arm naming the symmetric disconnect
## is also defending the wiring.
CONNECT_ARGS_RE = re.compile(r"(?:is_connected|connect)\(([^)\n]*)")
WORD_RE = re.compile(r"[A-Za-z_]\w*")


def resolve_handler(token, source):
    """The method a connect's argument really names, following one `var x = method.bind(...)` hop.

    A DOTTED argument (`BattleJuice.shake`, `popup.hide`) delegates to another object's method, so the
    method is the last segment -- taking the first gave receivers as handler names (`popup`, which is
    not a method at all) and three such rows led this tool's first run.
    """
    if "." in token:
        parts = token.split(".")
        ## An INLINE bind -- `signal.connect(_on_x.bind(y))` -- ends in `.bind`, so the last segment is
        ## the word "bind" and not a handler at all. Ten rows of this tool's second run were `bind`,
        ## "exercised by 187 test files", which is a pure name collision and exactly the kind of
        ## plausible-looking row that gets published as a finding.
        if parts[-1] == "bind" and len(parts) > 1:
            parts = parts[:-1]
        token = parts[-1]
    if token.startswith("_") or token.startswith("on_"):
        return token
    for local, method in BIND_RE.findall(source):
        if local == token:
            return method
    return token


def connections_in(source):
    """[(signal, handler)] for one file's text, with bound locals resolved to their method."""
    out = []
    for _recv, signal, raw in CONNECT_RE.findall(source):
        if signal == "connect" or raw in ("", "self"):
            continue
        handler = resolve_handler(raw, source)
        out.append((signal, handler))
    return out


def spread(conns):
    """How many DISTINCT src files connect each (signal, handler) pair.

    ⛔ THE DISCRIMINATOR THIS TOOL'S FIRST RUN LACKED, AND IT HAS TO BE DERIVED. `_on_body_entered` is
    connected in 27 files and `_on_battle_ended` in 4: those are Godot IDIOMS, not mechanisms, and
    "exercised by 12 test files" was matching a NAME shared by 27 unrelated implementations. Ranking on
    that put framework callbacks nobody needs a wiring pin for above every bespoke connection.

    A pair wired in exactly ONE file is bespoke -- one author, one mechanism, and the only thing that
    would notice its removal is an arm written for it. A hand-list of Godot signal names would have gone
    stale the first time the engine added one; a spread count cannot.
    """
    counts = {}
    for path, signal, handler in conns:
        counts.setdefault((signal, handler), set()).add(path)
    return {k: len(v) for k, v in counts.items()}


def connect_arg_names(src):
    """Every identifier appearing inside a connect/is_connected argument list in one source."""
    out = set()
    for args in CONNECT_ARGS_RE.findall(src):
        out.update(WORD_RE.findall(args))
    return out


def classify(signal, handler, test_sources, arg_names=None):
    """PINNED / GAP / UNTESTED for one connection against the test corpus.

    PINNED   some test names this CONNECTION -- the literal `<signal>.connect(` plus the handler, or
             the handler beside the word connect. That is what an arm asserting the wiring looks like.
    GAP      the handler is exercised somewhere but no test mentions the connection: the dangerous
             case, because the mechanism's own tests are green while nothing invokes it.
    UNTESTED the handler appears in no test at all -- a bigger hole, but a different conversation, and
             listing it as a wiring gap would bury the GAPs under it.
    """
    exercised = 0
    pinned = 0
    for i, src in enumerate(test_sources):
        if handler not in src:
            continue
        exercised += 1
        named_in_a_connect = handler in (arg_names[i] if arg_names else connect_arg_names(src))
        if ("%s.connect(" % signal) in src or ("connect(%s" % handler) in src or named_in_a_connect:
            pinned += 1
    if pinned:
        return "PINNED", exercised, pinned
    if exercised:
        return "GAP", exercised, 0
    return "UNTESTED", 0, 0


def single_caller_gaps(files, tests):
    """CLASS C: a function with exactly ONE call site in src/, whose CALL nothing pins.

    Distinct from the connect corpus above, and distinct again from the shape that shipped broken for
    months: `_record_first_damage` had THREE callers, all correct, and its defect was the NINE effect
    sites that never called it. That is not derivable from source without someone first naming the
    effect, so it is deliberately NOT attempted here -- see this tool's module docstring.

    A call is PINNED when some test names the callee AND the caller's own class_name or file, which is
    what an arm asserting "this caller still reaches this callee" looks like in this codebase.

    ⚠️ ONE PASS PER FILE, NOT ONE PER (function, file). The first draft ran a regex per function per
    file -- ~7000 x ~600 -- and took over two minutes, which is a defect in a tool meant to be run by
    hand. Counting every `name(` once per file and looking functions up in that table is the same
    answer in a second.
    """
    defs, names, calls, selfdefs = {}, {}, {}, {}
    for path, src in files:
        for fn in FUNC_RE.findall(src):
            defs.setdefault(fn, []).append(path)
        m = CLASSNAME_RE.search(src)
        names[path] = m.group(1) if m else os.path.basename(path)[:-3]
        c = {}
        for tok in CALL_RE.findall(src):
            c[tok] = c.get(tok, 0) + 1
        calls[path] = c
        d = {}
        for tok in FUNC_RE.findall(src):
            d[tok] = d.get(tok, 0) + 1
        selfdefs[path] = d

    ## Which test files mention each callee, computed once -- the per-function scan over 2850 test
    ## sources was the other half of the two minutes.
    mentions = {}
    for i, t in enumerate(tests):
        for tok in set(CALL_RE.findall(t)) | set(WORD_RE.findall(t)):
            mentions.setdefault(tok, []).append(i)

    out = []
    for fn, where in defs.items():
        if fn in ENGINE_VIRTUALS or len(where) != 1 or fn.startswith("__"):
            continue
        callers = []
        for path, _src in files:
            n = calls[path].get(fn, 0)
            if path == where[0]:
                n -= selfdefs[path].get(fn, 0)
            if n > 0:
                callers.append((path, n))
        if len(callers) != 1 or callers[0][1] != 1:
            continue
        caller_path = callers[0][0]
        if caller_path == where[0]:
            continue  ## called once inside its own file: a private helper, not a crossing
        idxs = mentions.get(fn, [])
        if not idxs:
            continue
        cname, cbase = names[caller_path], os.path.basename(caller_path)
        pinned = sum(1 for i in idxs if cname in tests[i] or cbase in tests[i])

        ## ⛔ THE FALSE-GAP MODE @cowir-music MEASURED, AND IT IS THE STRONGEST FORM OF PINNING.
        ## test_a_jukebox_stinger_does_not_resume_the_bed never names `disarm_stinger_resume`: it
        ## drives `_play_selected()` -- the function CONTAINING the call -- and asserts the bed stayed
        ## gone. Deleting the call reds it (EC=1, Failing 1, by message). A callee-name count cannot
        ## see that by construction, and `disarm_stinger_resume` showed 1 caller / 0 mentions, the
        ## same two numbers as a real gap. So count the DRIVERS OF THE CALLER, not mentions of the
        ## callee: a test that exercises the enclosing function is what actually defends the call.
        enclosing = _enclosing_func(dict(files)[caller_path], fn)
        if enclosing:
            pinned += sum(1 for t in tests if enclosing in t)
        if not pinned:
            out.append((where[0], fn, caller_path, len(idxs)))
    return out


def _enclosing_func(src, callee):
    """The name of the function containing the first call to `callee`, or "" if none found."""
    m = re.search(r"(?<!\w)" + re.escape(callee) + r"\s*\(", src)
    if not m:
        return ""
    before = src[:m.start()]
    hits = FUNC_RE.findall(before)
    return hits[-1] if hits else ""


def _read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def _gd_files(root):
    hits = []
    for base, _dirs, names in os.walk(root):
        for n in sorted(names):
            if n.endswith(".gd"):
                hits.append(os.path.join(base, n))
    return sorted(hits)


def main():
    conns = []
    ours = set()
    files = []
    for root in SRC_DIRS:
        for path in _gd_files(root):
            src = _read(path)
            files.append((path, src))
            ours.update(FUNC_RE.findall(src))
            for signal, handler in connections_in(src):
                conns.append((path, signal, handler))
    tests = [_read(p) for p in _gd_files(TEST_DIR)]

    ## ⛔ ENGINE METHODS ARE NOT OUR MECHANISMS. `close_requested.connect(queue_free)` and
    ## `pressed.connect(hide)` wire a Godot builtin: there is no authored behaviour behind them to
    ## leave stranded, and their names collide with hundreds of unrelated test mentions (`queue_free`
    ## read as "exercised by 171 test files"). A handler we did not define is out of scope, and
    ## "is there a `func <name>` anywhere in src/" derives that without a list to maintain.
    external = [c for c in conns if c[2] not in ours]
    conns = [c for c in conns if c[2] in ours]

    ## CONTROLS FIRST. A zero from an empty corpus is not a clean bill, and both corpora are walked
    ## from disk, so either can silently come back empty (wrong cwd, renamed directory).
    print("corpus: %d connection(s) in %s · %d test file(s) in %s"
          % (len(conns), "/".join(SRC_DIRS), len(tests), TEST_DIR))
    if not conns or not tests:
        print("CONTROL FAILED: a corpus is empty, so every verdict below is vacuous. Run from the repo root.")
        return 0

    arg_names = [connect_arg_names(t) for t in tests]
    buckets = {"GAP": [], "PINNED": [], "UNTESTED": []}
    for path, signal, handler in conns:
        verdict, exercised, pinned = classify(signal, handler, tests, arg_names)
        buckets[verdict].append((path, signal, handler, exercised, pinned))

    print("excluded: %d connection(s) name an engine method we do not define (queue_free, hide, popup...)"
          % len(external))
    print("CONTROL: %d connection(s) classify as PINNED, so the detector can say yes"
          % len(buckets["PINNED"]))
    if not buckets["PINNED"]:
        print("  ^ ZERO PINNED is itself suspicious: no arm anywhere asserts a connection, or the")
        print("    pinning pattern no longer matches how this codebase writes one. Check before")
        print("    believing the GAP list, which is the same measurement one step over.")

    spreads = spread(conns)
    bespoke = [r for r in buckets["GAP"] if spreads[(r[1], r[2])] == 1]
    idiom = [r for r in buckets["GAP"] if spreads[(r[1], r[2])] > 1]

    print("\n%d BESPOKE GAP(s) — wired in exactly ONE file, handler exercised, connection pinned by none."
          % len(set((r[0], r[1], r[2]) for r in bespoke)))
    print("   The actionable list: one author, one mechanism, and nothing else would notice its removal.")
    ## One file can carry the same pair several times (five per-enemy connects in a loop); the gap is
    ## the PAIR, so report it once with its site count rather than five identical rows.
    rolled = {}
    for path, signal, handler, exercised, _p in bespoke:
        key = (path, signal, handler)
        rolled[key] = [exercised, rolled.get(key, [0, 0])[1] + 1]
    for (path, signal, handler), (exercised, sites) in sorted(rolled.items(), key=lambda kv: -kv[1][0]):
        print("  %-50s %-28s %-34s exercised by %2d test file(s)%s"
              % (path, signal, handler, exercised, "" if sites == 1 else "  [%d connect sites]" % sites))

    print("\n%d gap(s) held back as IDIOM — the same signal+handler wired in several files, which is a" % len(idiom))
    print("   Godot callback convention rather than a mechanism; an exercise count there matches a NAME")
    print("   shared by unrelated implementations, not one of them:")
    seen = {}
    for _path, signal, handler, _e, _p in idiom:
        seen[(signal, handler)] = spreads[(signal, handler)]
    for (signal, handler), n in sorted(seen.items(), key=lambda kv: -kv[1])[:8]:
        print("  %-28s %-34s wired in %d files" % (signal, handler, n))

    print("\n%d UNTESTED (handler in no test — a different hole, listed so it is not mistaken for clean):"
          % len(buckets["UNTESTED"]))
    for path, signal, handler, _e, _p in buckets["UNTESTED"][:15]:
        print("  %-52s %-28s %s" % (path, signal, handler))
    if len(buckets["UNTESTED"]) > 15:
        print("  ... and %d more" % (len(buckets["UNTESTED"]) - 15))

    ## CLASS C, a separate corpus with a separate predicate -- printed apart so a clean section above
    ## is never read as covering this one. The classes are not nested.
    solo = single_caller_gaps(files, tests)
    print("\n== CLASS C: ONE plain call site in src/, and nothing pins the call ==")
    print("%d gap(s). A rename or deletion of that one call stops the mechanism with its own tests green."
          % len(solo))
    for defined_in, fn, caller, exercised in sorted(solo, key=lambda r: -r[3])[:20]:
        print("  %-34s defined in %-42s called once by %-38s exercised by %2d test file(s)"
              % (fn, defined_in, caller, exercised))
    if len(solo) > 20:
        print("  ... and %d more" % (len(solo) - 20))
    print("\n⚠️ NOT COVERED BY ANYTHING HERE: a mechanism whose EFFECT sites are incomplete")
    print("   (_record_first_damage had 3 correct callers and 9 silent take_damage sites). That needs")
    print("   the effect NAMED before the question is askable, so no sweep can derive it.")
    return 0


def selftest():
    fails = []

    def check(label, got, want):
        if got != want:
            fails.append("%s: got %r want %r" % (label, got, want))

    ## 1. a plain connect
    check("plain connect", connections_in("damage_dealt.connect(_on_damage_dealt_for_party_line)"),
          [("damage_dealt", "_on_damage_dealt_for_party_line")])

    ## 2. the bound-Callable hop, which is how every per-combatant signal in BattleManager is written.
    ##    Without resolution the handler reads as the local `hcb` and matches nothing in any test.
    bound = "var hcb = _on_hp_changed_for_low_water.bind(combatant)\n\tcombatant.hp_changed.connect(hcb)"
    check("bound callable resolves to its method", connections_in(bound),
          [("hp_changed", "_on_hp_changed_for_low_water")])

    ## 3. a typed local, same hop
    typed = "var cb: Callable = _on_combatant_died.bind(c)\n\tc.died.connect(cb)"
    check("typed bound local", connections_in(typed), [("died", "_on_combatant_died")])

    ## 4. an arm asserting the wiring reads as PINNED
    check("pinned", classify("damage_dealt", "_on_x", ['assert_true(code.contains("damage_dealt.connect(_on_x)"))'])[0],
          "PINNED")

    ## 5. THE CASE THE TOOL EXISTS FOR: the handler is driven directly and nothing pins the connection.
    check("gap", classify("hp_changed", "_on_low_water", ["BattleManager._on_low_water(100, 7, pc)"])[0], "GAP")

    ## 6. a handler no test mentions is UNTESTED, not a wiring gap
    check("untested", classify("hp_changed", "_on_nobody", ["unrelated test body"])[0], "UNTESTED")

    ## 7. ⛔ THE NEGATIVE CONTROL ON THE PINNING PATTERN ITSELF. If `classify` returned PINNED for a
    ##    test that merely MENTIONS the handler, every gap would read as covered and the tool would
    ##    report a clean codebase forever. This is the arm that makes a GAP list mean something.
    check("a mention is not a pin", classify("hp_changed", "_on_low_water", ["_on_low_water is nice"])[0], "GAP")

    ## 8. the INLINE bind, which produced ten `bind` rows before it was handled
    check("inline bind", connections_in("died.connect(_on_died.bind(c))"), [("died", "_on_died")])

    ## 9-11. CLASS C. Built from in-memory file tuples, same as every arm above.
    src_files = [
        ("src/A.gd", "class_name A\nfunc _mechanism() -> void:\n\tpass\n"),
        ("src/B.gd", "class_name B\nfunc update() -> void:\n\t_scene._mechanism()\n"),
    ]
    check("one unpinned caller is a gap",
          [r[1] for r in single_caller_gaps(src_files, ["drive _mechanism() directly"])],
          ["_mechanism"])
    ## a test naming the CALLER's class as well is a pin, not a gap
    check("naming the caller pins the call",
          single_caller_gaps(src_files, ["B then _mechanism"]), [])
    ## an engine virtual has no meaningful caller count and must never be listed
    check("engine virtuals excluded",
          single_caller_gaps([("src/C.gd", "func _ready() -> void:\n\tpass\n"),
                              ("src/D.gd", "func go():\n\t_ready()\n")], ["_ready"]), [])

    ## 12. @cowir-music's FALSE-GAP case: the test drives the CALLER's enclosing function and never
    ##      names the callee. Before this, that read as a gap with the same two numbers as a real one.
    jukebox = [
        ("src/A.gd", "class_name A\nfunc disarm() -> void:\n\tpass\n"),
        ("src/B.gd", "class_name B\nfunc _play_selected() -> void:\n\t_sm.disarm()\n"),
    ]
    check("driving the enclosing function is a pin",
          single_caller_gaps(jukebox, ["await menu._play_selected()\nassert_eq(track, \"\")"]), [])
    ## and the same shape WITHOUT a driver is still a gap, or the fix above would pin everything
    check("no driver is still a gap",
          [r[1] for r in single_caller_gaps(jukebox, ["disarm() mentioned only"])], ["disarm"])

    ## 14-15. @cowir-music's class-A audit: the two forms a correct arm actually uses.
    check("is_connected pins it",
          classify("corruption_changed", "set_save_corruption",
                   ["assert_true(GameState.corruption_changed.is_connected(SoundManager.set_save_corruption))"])[0],
          "PINNED")
    check("a receiver-qualified callable pins it",
          classify("leveled_up", "_on_party_leveled_up",
                   ["c.leveled_up.connect(gl._on_party_leveled_up)"])[0], "PINNED")

    ## 16. the SOURCE-READ form, which is how this codebase most often asserts a wiring guard
    check("a source-read assertion pins it",
          classify("leveled_up", "_on_party_leveled_up",
                   ['assert_true(body.contains("is_connected(_on_party_leveled_up)"))'])[0], "PINNED")

    ## 17. a connect with no handler token must not crash or invent a connection
    check("junk is ignored", connections_in("something.connect()"), [])

    if fails:
        for f in fails:
            print("FAIL %s" % f)
        print("wiring_gaps selftest: %d of 17 arms FAILED" % len(fails))
        return 1
    print("wiring_gaps selftest: 17/17 arms ran, every assertion held (in-memory only: no file, walk, subprocess or git)")
    return 0


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    sys.exit(main())
