#!/usr/bin/env python3
"""Audit every input caption in src/ for device truthfulness.

WHY THIS EXISTS
---------------
Between .308 and .334 this lane shipped fixes for fourteen captions that named a control the
player did not have: six frozen face letters, three frozen shoulder names, four dead labels on a
drawn pad, one inverted Back button. Every one was found with a one-off matcher in a gitignored
tmp/ — 54 of them by the end — so the numbers reached the channel and nothing reached the repo.
Nobody but that session could re-derive any of it. This is those matchers, in one place, with
their exclusions and their limits written down.

THE FOUR SHAPES, each learned from a defect that shipped
--------------------------------------------------------
  frozen-letter   "A/Enter: Confirm"              a face letter inside a caption string
  frozen-family   "L1/R1 page" · "[Select] Auto"  one family's button NAME
  bucket-4        if InputProfileManager:         an unsafe helper behind an AUTOLOAD-only
                      glyph_for_action(...)       guard — it answers as xbox with no pad
  diagram         _draw_face_button(pos, "A", …)  a letter as a DRAWING-CALL argument, which
                                                  no caption scan can see

WHY THE LETTER ALPHABET IS EXACTLY {A, B} — measured against the live InputMap, not chosen:
    KEY A -> ui_text_select_all + a macos caret action   (Godot built-ins only)
    KEY B -> nothing at all
    KEY X -> ui_cancel        <- a REAL keyboard binding in this game
    KEY Y -> ui_redo, and read by RAW KEYCODE at BattleScene:4882 / GameLoop:923
    KEY Z -> ui_accept
A bare A or B in a caption can only be a pad letter. X and Y cannot be flagged without reporting
true keyboard captions ("X/Esc") as defects. Re-run --selftest after any project.godot change.

LIMITS, stated so nobody reads a clean run as more than it is
-------------------------------------------------------------
  * SOURCE-level. It cannot see a caption composed at runtime from parts.
  * It says a caption is DERIVED, never that the derivation is CORRECT for that surface —
    a footer can derive ui_accept while describing ui_cancel. Only reading the handler shows that.
  * Reachability is ONE HOP. A finding on a file nothing loads is marked [UNREACHED]; a file whose
    only loader is itself unreachable is NOT. It answers "does anything name this file", never
    "can a player get here" — cross-check before calling a hit player-visible.
  * A shape nobody has written yet cannot be in the list, and the controls cannot help: every
    control names a shape that already exists. Adding a caption form means adding it here.
"""

from __future__ import annotations
import argparse, io, json, os, re, sys

SRC_ROOT = "src"

# Face letters that can never be a keyboard binding in this game. See the docstring.
FACE_LETTERS = ("A", "B")

# A face letter is only a button name in a caption CONTEXT; bare "A" is an article.
LETTER_CONTEXTS = (
    ("bracketed", r'\[{L}\]\s+\w'),      # "[A] Examine" — the trailing word excludes the Auto badge
    ("colon", r'(?<![\w/-]){L}\s*:'),    # "B: Exit"  — the -] excludes "Form 1-A:"
    ("to", r'(?<![\w/-]){L} to\b'),      # "press A to fight"
    ("slash", r'(?<![\w/-]){L}/'),       # "A/Enter/Click"
    ("gloss", r'(?<![\w/-]){L} \('),     # "B (Esc): Stop"  <- the shape the net missed until now
)

# One family's printed button NAME. The BUTTON_NAMES/BUTTON_LABELS tables are the source of
# truth and are excluded by path.
FAMILY_NAMES = {
    "Select": "nintendo/snes", "Start": "xbox", "Plus": "nintendo", "Minus": "nintendo",
    "Back": "xbox", "Share": "playstation", "Options": "playstation",
    "LB": "xbox", "RB": "xbox", "LT": "xbox", "RT": "xbox",
    "L1": "playstation", "R1": "playstation", "L2": "playstation", "R2": "playstation",
}
# "Back" and "Start" are overwhelmingly ordinary English in this codebase, so they are only a
# finding beside a bracket or a slash — the shape a button caption has.
NAME_NEEDS_BRACKET = ("Back", "Start", "Share", "Options", "Select")

UNSAFE_HELPERS = ("glyph_for_action", "face_glyph_for_index", "face_family_for_device")
AUTOLOAD_ONLY_GUARDS = ('if InputProfileManager:', 'has_method("glyph_for_action")',
                        'has_method("face_glyph_for_index")')
PAD_CHECKS = ("get_connected_joypads", "has_pad", "pads.is_empty")

DRAW_CALLS = ("_draw_face_button", "draw_string")

# The input tables themselves are definitions, not captions.
EXCLUDED_PATHS = ("src/input/InputProfileManager.gd", "src/input/ControllerMappings.gd",
                  "src/input/ControllerMappingCapture.gd")


def gd_files(root: str):
    for dirpath, _, names in os.walk(root):
        for n in sorted(names):
            if n.endswith(".gd"):
                p = os.path.join(dirpath, n)
                if not any(p.endswith(x) for x in EXCLUDED_PATHS):
                    yield p


def _literal_spans(line: str):
    """The double-quoted spans on one line. A line with no quotes holds no caption."""
    if '"' not in line:
        return []
    parts = line.split('"')
    return parts[1::2]


def scan_text(text: str, path: str = "<mem>"):
    """Return findings for one file's source. Three-state over triple-quoted regions:
    free docstring (skip), assigned/returned block (scan whole lines — it is shipping content),
    normal (scan quoted spans)."""
    out, state = [], 0
    for ln, raw in enumerate(text.split("\n"), 1):
        fences = raw.count('"""')
        if state:
            if fences >= 1:
                state = 0
                continue
            if state == 1:
                continue
            spans = [raw]                     # assigned/returned region: content, no quotes of its own
        else:
            if fences == 1:
                state = 1 if raw.strip().startswith('"""') else 2
                continue
            if raw.lstrip().startswith("#") or "print(" in raw:
                continue
            if raw.lstrip().startswith('"""'):
                continue          # a ONE-LINE docstring: two fences, so the state machine never saw it
            spans = _literal_spans(raw)

        for span in spans:
            for letter in FACE_LETTERS:
                for tag, pat in LETTER_CONTEXTS:
                    if re.search(pat.format(L=letter), span):
                        out.append(dict(file=path, line=ln, shape="frozen-letter",
                                        detail=letter, context=tag, text=span.strip()[:70]))
                        break
            # A span naming ALL THREE families is the COMPLETE vocabulary, not a frozen name —
            # "or whatever your pad calls Select. Back. Share." is correct and must not be a
            # finding. Structural, not an allowlist: a caption that names every family has
            # nothing left to be wrong about. Two families is still incomplete and still reported.
            fams = {f for n, f in FAMILY_NAMES.items()
                    if re.search(r'(?<![\w])%s(?![\w])' % n, span)}
            if len({f.split("/")[0] for f in fams}) >= 3:
                continue
            for name, family in FAMILY_NAMES.items():
                if name in NAME_NEEDS_BRACKET:
                    # bracket, slash, or a parenthesised pairing "(Start/F5)" — the three shapes a
                    # button caption takes. Bare prose ("Start the battle") is not a finding.
                    hit = re.search(r'(\[%s\b|/%s\b|\(%s/)' % (name, name, name), span)
                else:
                    hit = re.search(r'(?<![\w])%s(?![\w])' % name, span)
                if hit:
                    out.append(dict(file=path, line=ln, shape="frozen-family",
                                    detail="%s (%s)" % (name, family), context="name",
                                    text=span.strip()[:70]))
        # diagram form: a face letter as a drawing-call ARGUMENT, invisible to a caption scan
        if any(c in raw for c in DRAW_CALLS):
            for letter in FACE_LETTERS:
                if re.search(r'\(\s*[^)]*,\s*"%s"' % letter, raw):
                    out.append(dict(file=path, line=ln, shape="diagram", detail=letter,
                                    context="draw-arg", text=raw.strip()[:70]))
    return out


def scan_bucket4(text: str, path: str = "<mem>"):
    """An unsafe helper within three lines of an AUTOLOAD-only guard. Narrow on purpose: a broad
    'is this call guarded?' heuristic reds other lanes' correct code."""
    out, lines = [], text.split("\n")
    for i, line in enumerate(lines):
        if line.strip().startswith("#"):
            continue
        if not any(g in line for g in AUTOLOAD_ONLY_GUARDS):
            continue
        if any(p in line for p in PAD_CHECKS):
            continue                              # a pad check on the same line is the correct form
        for j in range(i + 1, min(i + 4, len(lines))):
            body = lines[j]
            if body.strip().startswith("#"):
                continue
            for h in UNSAFE_HELPERS:
                if h + "(" in body and ", " not in body:   # an explicit device makes it safe
                    out.append(dict(file=path, line=j + 1, shape="bucket-4", detail=h,
                                    context="autoload-only guard", text=body.strip()[:70]))
    return out


def reachability(root: str):
    """Which .gd files are LOADED by something else. A frozen caption on a screen nothing opens is
    still worth fixing, but it is not PLAYER-VISIBLE — and reporting it as such is a mistake this
    lane made in .318, calling three autogrind fixes player-facing when two sat on MenuScene, the
    dead hub. Counts load()/preload() by res:// path, bare ClassName.new(), and autoload entries.

    LIMIT: ONE HOP, not a transitive closure. A file whose only loader is itself unreachable still
    counts as loaded — it answers "does anything name this file", never "can a player get here"."""
    loaded, bodies = set(), {}
    for p in gd_files(root):
        bodies[p] = io.open(p, encoding="utf-8").read()
    try:
        proj = io.open("project.godot", encoding="utf-8").read()
    except OSError:
        proj = ""
    for p, text in bodies.items():
        for other in bodies:
            if other != p and ("res://" + other.replace(os.sep, "/")) in text:
                loaded.add(other)
            if other != p:
                cname = os.path.basename(other)[:-3]
                if re.search(r'\b%s\.new\(' % re.escape(cname), text):
                    loaded.add(other)
    for other in bodies:
        if ("res://" + other.replace(os.sep, "/")) in proj:
            loaded.add(other)
    return loaded


def audit(root: str):
    findings, files = [], 0
    for p in gd_files(root):
        text = io.open(p, encoding="utf-8").read()
        files += 1
        findings.extend(scan_text(text, p))
        findings.extend(scan_bucket4(text, p))
    reach = reachability(root)
    for f in findings:
        f["loaded_by_something"] = f["file"] in reach
    return files, findings


def selftest() -> int:
    """Every shape must be DETECTED, and every exclusion must HOLD. Each case is single-shape, so
    a detector that stopped working cannot hide behind a sample that trips another one."""
    must_fire = [
        ('\tx.text = "B: Exit"', "frozen-letter"),
        ('\tx.text = "[A] Examine"', "frozen-letter"),
        ('\tx.text = "A/Enter: Confirm"', "frozen-letter"),
        ('\tx.text = "press A to fight"', "frozen-letter"),
        ('\tx.text = "B (Esc): Stop"', "frozen-letter"),
        ('\tx.text = "L1/R1 page"', "frozen-family"),
        ('\tx.text = "[Select] Auto"', "frozen-family"),
        ('\tx.text = "Start (Plus)  F5  Open Editor"', "frozen-family"),   # TWO families is still incomplete
        ('\tx.text = "the Autobattle Editor (Start/F5) writes rules"', "frozen-family"),
        ('\t_draw_face_button(POS_A, "A", "a")', "diagram"),
    ]
    must_not_fire = [
        '## the old "[B]" named the wrong cap',
        '\t"""Repeat actions (A button)"""',
        '\t"""\n\tpress B to exit\n\t"""',
        '\tvar auto_indicator = " [A]"',
        '\tprint("[BOSS] press A to fight")',
        '\tvar keys := "X/Esc"',
        '\tx.text = "Attack: 12  Block/Parry"',
        '\tx.text = "Back Row"',
        '\tx.text = "Start the battle after dialogue"',                    # bare prose, not a caption
        '\tvar s := "Share code copied"',
        '\t"""Create an action button setting (press A to activate)"""',   # ONE-LINE docstring
        '\tx.text = "Z / Enter   L-Click   Confirm / Select"',            # "Select" the action word
        '\tx.text = "Form 1-A: the incident"',                            # a form number, not a caption
        '\tx.text = "whatever your pad calls Select. Back. Share."',       # ALL THREE = complete vocabulary
    ]
    bad = 0
    for src, shape in must_fire:
        got = {f["shape"] for f in scan_text(src)}
        if shape not in got:
            print("SELFTEST FAIL: %r did not fire %s (got %s)" % (src, shape, got or "nothing"))
            bad += 1
    for src in must_not_fire:
        got = scan_text(src)
        if got:
            print("SELFTEST FAIL: %r fired %s" % (src, [f["shape"] for f in got]))
            bad += 1
    b4_fire = '\tif InputProfileManager:\n\t\tg = InputProfileManager.glyph_for_action("ui_cancel")'
    if not scan_bucket4(b4_fire):
        print("SELFTEST FAIL: the bucket-4 pair did not fire")
        bad += 1
    b4_safe = '\tif Input.get_connected_joypads().is_empty() or not InputProfileManager:\n\t\treturn p'
    if scan_bucket4(b4_safe):
        print("SELFTEST FAIL: a pad-checked call was reported as bucket-4")
        bad += 1
    print("selftest: %d case(s) failed" % bad if bad else "selftest: all %d cases pass"
          % (len(must_fire) + len(must_not_fire) + 2))
    return 1 if bad else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=SRC_ROOT)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if not os.path.isdir(a.root):
        print("no such root: %s" % a.root, file=sys.stderr)
        return 2
    files, findings = audit(a.root)
    if a.json:
        print(json.dumps(dict(root=a.root, files=files, findings=findings), indent=2))
        return 1 if findings else 0
    print("input caption audit — %d .gd files under %s/" % (files, a.root))
    if not findings:
        print("  no frozen captions, no bucket-4 pairs, no welded diagram letters.")
        print("  NOTE: derived is not the same as CORRECT FOR ITS SURFACE — a footer can derive")
        print("        ui_accept while describing Cancel, and this cannot see that. Reachability")
        print("        is one hop. See the module docstring for the full limits.")
        return 0
    for f in sorted(findings, key=lambda x: (x["shape"], x["file"], x["line"])):
        mark = "" if f.get("loaded_by_something", True) else "   [UNREACHED: nothing loads this file]"
        print("  %-14s %-44s:%-5d %-22s %s%s"
              % (f["shape"], f["file"], f["line"], f["detail"], f["text"], mark))
    print("  %d finding(s)" % len(findings))
    return 1


if __name__ == "__main__":
    sys.exit(main())
