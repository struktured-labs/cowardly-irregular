#!/usr/bin/env python3
"""Scan the sprite domain for the shipped-unwired / dangling-pointer classes.

Bug-hunt sweep (cowir-main msg 3182): "for each public producer: grep its
name; 1 hit = definition only = DEAD."

The sprite-lane instance of that class is an ASSET that ships but is never
read. `HybridSpriteLoader.load_monster_sprite_frames()` returns null for
any id absent from `monster_sheets` and the caller silently falls back to
procedural — so an unregistered PNG is inert with no warning, a clean
commit, and art visibly present on disk. `chancellor_mordaine` shipped
2026-07-17 and was inert until 2026-07-25.

Five checks, both directions:
  ORPHAN     PNG on disk that no manifest entry and no source file references
  DANGLING   manifest entry pointing at a path that does not exist
  SILENT     monster sheet whose animations dict lacks idle (never renders)
  MISMATCH   manifest frame_width/height disagreeing with the actual PNG
  PLACEMENT  an NPC placed in a map whose archetype resolves to no art

The first four all start from the MANIFEST, which is why none of them could
see Aria (2026-07-30): her frames were on disk since 07-18 and a SECOND
loader refused them. PLACEMENT starts from the consumer instead.

Usage:
    uv run python tools/audit_sprite_wiring.py
    uv run python tools/audit_sprite_wiring.py --section monster_sheets
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

from PIL import Image

GAME = Path("/home/struktured/projects/cowardly-irregular-artist-ship")
MANIFEST = GAME / "data" / "sprite_manifest.json"
SPRITES = GAME / "assets" / "sprites"


def load_manifest() -> dict:
    return json.loads(MANIFEST.read_text())


def referenced_paths(m: dict) -> dict[str, list[str]]:
    """path -> [section/key ...] for every entry that declares one."""
    out: dict[str, list[str]] = {}
    for section, entries in m.items():
        if not isinstance(entries, dict):
            continue
        for key, val in entries.items():
            if not isinstance(val, dict):
                continue
            p = val.get("path")
            if isinstance(p, str) and p.startswith("res://"):
                out.setdefault(p.replace("res://", ""), []).append(
                    f"{section}/{key}")
    return out


def _code_of(src: str) -> str:
    """The CODE half of a .gd file: trailing comments and docstring regions removed.

    ⛔ A REPLICA OF test/unit/helpers/gd_source.gd, AND THAT IS A COST. Two
    instruments for one question drift, and this lane's own memory says a
    replica in another language is another instrument. It is written anyway
    because the alternative was not "no replica" — grep_repo already carried
    one at its `s.startswith("#")` line, just a broken one. This replaces a
    half-stripper, it does not add a stripper. If gd_source gains a case,
    this needs it too; the control below is what makes that discoverable.

    Quote-aware and escape-aware: a `#` inside a string is not a comment.
    `src/exploration/IndustrialOverworld.gd` really does create an NPC named
    "Worker #4471", and a naive `#`-strip eats that placement — measured
    2026-09-16, when it made this very audit report a prose ghost that was
    live code. Comments are stripped BEFORE the `\"\"\"` parity split, or a
    fence hidden in a comment flips parity for the rest of the file.
    """
    out = []
    for line in src.split("\n"):
        quote = ""
        kept = []
        i = 0
        while i < len(line):
            c = line[i]
            if quote:
                kept.append(c)
                if c == "\\" and i + 1 < len(line):
                    kept.append(line[i + 1])
                    i += 2
                    continue
                if c == quote:
                    quote = ""
                i += 1
                continue
            if c in "\"'":
                quote = c
                kept.append(c)
                i += 1
                continue
            if c == "#":
                break
            kept.append(c)
            i += 1
        out.append("".join(kept))
    return "\n".join("\n".join(out).split('\"\"\"')[0::2])


def _strip_control() -> str:
    """The stripper, proven in BOTH directions before anything trusts it.

    An over-strip and a correct strip are the same green — gd_source's rule.
    """
    keep = 'var n = _create_npc("Worker #4471", "villager")  # trailing prose'
    drop = '\t# was _create_npc("ghost_npc", "villager")'
    if 'Worker #4471' not in _code_of(keep):
        return "STRIP CONTROL FAILED: a `#` inside a string literal ate real code"
    if 'trailing prose' in _code_of(keep):
        return "STRIP CONTROL FAILED: a trailing comment survived into the code half"
    if 'ghost_npc' in _code_of(drop):
        return "STRIP CONTROL FAILED: a whole-line comment survived into the code half"
    return ""


def grep_repo(needle: str) -> int:
    """Count files that reference a name in CODE, not in prose.

    A bare `grep -l` counts a file whose only mention is a comment, so a
    sheet nobody loads reads as consumed and the ORPHAN check stays quiet.
    cowir-story hit exactly this (msg 3520) — their passive guard passed
    three unwired keys, each on a single comment naming it, one of them a
    starter-job passive promising a percentage that did nothing.

    Direction matters and this one is safe: a comment inflates the count,
    so the failure is UNDER-reporting — an inert sheet goes unmentioned,
    never a live one wrongly condemned.

    NO LONGER LATENT, and this paragraph used to say it was. It read "there
    are 0 unregistered monster PNGs, so this predicate is unexercised" —
    falsified by this tool's own output, which reports cartographer_wraith
    and dark_knight as ORPHANs with 0 refs. The data landed and the note
    did not move (measured 2026-09-16).

    ⚠️ AND THE PREDICATE WAS STILL WRONG WHILE THE DOCSTRING PROMISED "in
    CODE, not in prose": `s.startswith("#")` skips only a line that BEGINS
    with a comment, so a TRAILING `# was <path>` counted as a reference and
    a triple-quoted region was never touched at all (naming that delimiter
    literally here closes this very docstring — the false fence, in the
    sentence about false fences). Both inflate the count, so
    both fail toward under-reporting — an inert sheet goes unmentioned.
    Measured before the fix across 427 needles: 0 prose-only references, so
    the repo was clean and the promise was not.
    """
    try:
        r = subprocess.run(
            ["grep", "-rIl", "--include=*.gd", "--include=*.json",
             needle, str(GAME / "src"), str(GAME / "data")],
            capture_output=True, text=True, timeout=60)
    except Exception:
        return -1
    hits = 0
    for path in (x for x in r.stdout.splitlines() if x.strip()):
        try:
            with open(path, errors="ignore") as fh:
                body = fh.read()
            # .json has no comments and _code_of leaves it untouched; .gd is the case
            if needle in _code_of(body):
                hits += 1
        except OSError:
            hits += 1  # unreadable: assume referenced, stay under-reporting
    return hits


def placement_gaps() -> list[str]:
    """Archetypes placed in a map that resolve to no sprite art.

    Direction matters: this catches a placement pointing at art that does not
    exist (renders procedural, which is what struktured sees). Its sibling
    failure -- art that exists but no consumer loads -- is what happened to
    the dancer, and no manifest check found that either.

    `villager` and `elder` alias through non-literal expressions (name-hashed
    across young_man/young_woman/old_man/old_woman), so their targets cannot
    be read statically. They are reported as UNVERIFIABLE rather than clean,
    because scoring an unreadable alias as "fine" is how the dancer's
    carve-out survived twelve days.
    """
    src_root = GAME / "src"
    npc_gd = src_root / "exploration" / "OverworldNPC.gd"
    if not npc_gd.exists():
        return ["OverworldNPC.gd absent — cannot resolve placements"]

    text = npc_gd.read_text(errors="ignore")
    m = re.search(r'NPC_TYPE_TO_ARCHETYPE: Dictionary = \{(.*?)\n\}', text, re.S)
    alias: dict[str, str] = {}
    if m:
        for line in m.group(1).splitlines():
            km = re.match(r'\s*"([a-z_]+)"\s*:\s*(.+?),?\s*(#.*)?$', line.strip())
            if km:
                alias[km.group(1)] = km.group(2).rstrip(",")

    placed: dict[str, set[str]] = {}
    for p in src_root.rglob("*.gd"):
        for c in re.finditer(r'_create_npc\(\s*"([^"]+)"\s*,\s*"([^"]+)"',
                             _code_of(p.read_text(errors="ignore"))):
            placed.setdefault(c.group(2), set()).add(c.group(1))

    npcs_dir = SPRITES / "npcs"
    on_disk = {d.name for d in npcs_dir.iterdir() if d.is_dir()} if npcs_dir.exists() else set()
    manifest_keys = set(load_manifest().get("overworld_npc_sheets", {}).keys())

    # SEMANTIC CONTROL, not a count. If the _create_npc regex or the alias parse
    # breaks, `placed` comes back empty and this returns [] -- a clean pass over
    # nothing, indistinguishable from a healthy corpus.
    #
    # cowir-overworld 2026-07-30 ran two sweeps of one question that both printed
    # "0 missing"; the first resolved ZERO targets, so nothing could fail. Their
    # rule, sharpened from cowir-battle's: a control asserting a count is
    # non-zero tests the sweep's PLUMBING, a control asserting a NAMED member
    # resolves tests its SEMANTICS. These four are placed in shipped maps and
    # each has art, so all four must resolve or this sweep is lying.
    #
    # The members were VERIFIED present before being used as controls. My first
    # pick included `innkeeper`, which has art but is not created via
    # _create_npc -- so the control fired on a healthy corpus. A control whose
    # own premise is unchecked is just another guess.
    for known in ("guard", "merchant", "blacksmith", "dancer"):
        if known not in placed:
            return [f"CONTROL FAILED: '{known}' is placed in a shipped map but "
                    f"this sweep did not find it — the _create_npc extraction is "
                    f"broken and every result below would be a false clean "
                    f"(found {len(placed)} archetypes)."]
        if known not in on_disk and known not in manifest_keys:
            return [f"CONTROL FAILED: '{known}' has art on disk but this sweep "
                    f"cannot resolve it — the resolution logic is broken, not "
                    f"the corpus."]

    out = []
    for arch in sorted(placed):
        if arch in on_disk or arch in manifest_keys:
            continue
        if arch in alias:
            targets = re.findall(r'"([a-z_]+)"', alias[arch])
            if not targets:
                out.append(f"{arch}: aliases through a non-literal expression — "
                           f"UNVERIFIABLE statically (placed as "
                           f"{', '.join(sorted(placed[arch])[:3])})")
            else:
                dead = [t for t in targets if t not in on_disk and t not in manifest_keys]
                if dead:
                    out.append(f"{arch}: alias targets missing art {dead}")
            continue
        out.append(f"{arch}: no sprite dir, no manifest entry, no alias — "
                   f"renders PROCEDURAL (placed as "
                   f"{', '.join(sorted(placed[arch])[:3])})")
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--section", default=None)
    args = ap.parse_args()

    # ⛔ THE INSTRUMENT BEFORE THE CORPUS. Every check below reads source
    # through _code_of; an over-strip makes all five report a clean repo.
    bad_strip = _strip_control()
    if bad_strip:
        print(bad_strip)
        return 2

    m = load_manifest()
    refs = referenced_paths(m)
    findings = {"DANGLING": [], "SILENT": [], "MISMATCH": [], "ORPHAN": [],
                "PLACEMENT": []}

    # --- PLACEMENT: an NPC placed in a map whose archetype has no art -------
    # The four checks below all start from the MANIFEST. Aria (2026-07-30)
    # proved that insufficient: her frames were on disk, and a SECOND loader
    # -- OverworldNPC, with its own hardcoded path list -- refused them. A
    # manifest-first audit cannot see a consumer that never consults the
    # manifest, so this check starts from the CONSUMER instead: every
    # archetype actually placed by _create_npc, resolved the way the game
    # resolves it (direct dir, manifest entry, or NPC_TYPE_TO_ARCHETYPE alias).
    findings["PLACEMENT"] = placement_gaps()

    # --- DANGLING: manifest points at a file that isn't there --------------
    for rel, owners in sorted(refs.items()):
        if not (GAME / rel).exists():
            findings["DANGLING"].append(f"{rel}  <- {', '.join(owners)}")

    # --- SILENT + MISMATCH: monster/job sheets that can't render ----------
    for section in ("monster_sheets", "sheets", "overworld_npc_sheets"):
        if args.section and section != args.section:
            continue
        for key, val in sorted(m.get(section, {}).items()):
            if not isinstance(val, dict):
                continue
            anims = val.get("animations")
            # TWO SCHEMAS, and conflating them was this scanner's own first
            # bug (52 false positives). Horizontal STRIP sheets key
            # animations by frame range {"start","end"} and need "idle";
            # GRID sheets (overworld walk cycles) key by {"row","frames"}
            # and legitimately have only walk_<dir> — no idle exists or
            # should. Detect by the value shape, never by section name.
            is_grid = bool(isinstance(anims, dict) and anims and all(
                isinstance(v, dict) and "row" in v for v in anims.values()))
            if isinstance(anims, dict) and not is_grid and "idle" not in anims:
                findings["SILENT"].append(
                    f"{section}/{key}: strip sheet with no 'idle' "
                    f"({', '.join(sorted(anims)) or 'empty'})")
            rel = str(val.get("path", "")).replace("res://", "")
            fp = GAME / rel
            fw, fh = val.get("frame_width"), val.get("frame_height")
            if fp.exists() and fw and fh:
                try:
                    w, h = Image.open(fp).size
                except Exception:
                    continue
                if is_grid:
                    rows = max((v.get("row", 0) for v in anims.values()),
                               default=0) + 1
                    cols = max((v.get("frames", 1) for v in anims.values()),
                               default=1)
                    if h < rows * fh or w < cols * fw:
                        findings["MISMATCH"].append(
                            f"{section}/{key}: grid needs >={cols*fw}x{rows*fh} "
                            f"({cols}x{rows} cells of {fw}x{fh}), PNG is {w}x{h}")
                else:
                    if h != fh:
                        findings["MISMATCH"].append(
                            f"{section}/{key}: manifest frame_height={fh} "
                            f"but PNG is {w}x{h}")
                    elif w % fw != 0:
                        findings["MISMATCH"].append(
                            f"{section}/{key}: PNG width {w} not divisible by "
                            f"frame_width={fw}")

    # --- ORPHAN: monster PNG on disk that nothing points at ---------------
    known = set(refs)
    for png in sorted((SPRITES / "monsters").glob("*.png")):
        rel = str(png.relative_to(GAME))
        if rel in known:
            continue
        if ".pre_" in png.name:
            continue
        hits = grep_repo(png.stem)
        if hits == 0:
            findings["ORPHAN"].append(
                f"{rel}: no manifest entry, 0 refs in src/ or data/ — INERT")

    total = 0
    # COVERAGE CONTROL. Without this the tool prints "0 finding(s)" whether the
    # corpus is clean or the sweep examined nothing — a manifest that failed to
    # load, a glob that matched no files, and a genuinely healthy tree all
    # produce the identical happy line.
    #
    # Added 2026-07-29 after the same shape was found in this tool's sibling
    # audit_sprite_tiers.py, which reported a clean sweep having examined 13 of
    # 143 entries. I fixed that one and did not come back here — which is the
    # error four lanes logged tonight (fix one, leave the siblings), so the
    # floors below are stated as numbers rather than trusted as habits.
    examined = sum(
        len(m.get(s, {}))
        for s in ("monster_sheets", "sheets", "overworld_npc_sheets")
        if not args.section or s == args.section
    )
    on_disk = len(list((SPRITES / "monsters").glob("*.png")))
    print(f"examined {examined} manifest entr(ies), {len(refs)} referenced "
          f"path(s), {on_disk} monster PNG(s) on disk")
    if examined == 0 or len(refs) == 0 or on_disk == 0:
        print("REFUSING TO REPORT: a zero above means this sweep read nothing, "
              "and a clean result over an empty corpus is not a clean corpus.")
        return 2

    for kind in ("DANGLING", "SILENT", "MISMATCH", "ORPHAN", "PLACEMENT"):
        items = findings[kind]
        if items:
            print(f"\n=== {kind} ({len(items)}) ===")
            for i in items:
                print(f"  {i}")
            total += len(items)
    print(f"\n{total} finding(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
