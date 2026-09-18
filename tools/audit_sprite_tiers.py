#!/usr/bin/env python3
"""Catch tier lies in sprite_manifest.json by checking git, not the manifest.

WHY THIS EXISTS
---------------
`tier` is the field that decides what I am allowed to touch. Nothing in the
game reads it — the only consumers are the generation tools in this repo and
one GUT audit. So a wrong tier changes exactly one thing: whether an AI
regeneration will happily overwrite artist work.

On 2026-07-29 `sheets.fighter` was labelled:

    "tier": "T1",
    "generator": "gen_full_sweep.py (v2 jrpg_pixel_style LoRA)"

while being 9/9 artist art — 7 PNGs byte-identical to the v0.15.0 artist
baseline, and idle/attack holding the artist's own drive-archive renders
(4cab90d0). The generator string was true when it was written and described
a directory whose contents were later replaced by 68b049d0 / 4cab90d0. It
rotted in place.

CLAUDE.md names fighter as THE example of artist work to protect. The one
piece of metadata encoding that protection said "AI-generated, safe to
regenerate."

The manifest cannot audit itself: its tier and its generator string agreed
with each other perfectly (0 contradictions across 143 entries). Both were
wrong together, because both were written at the same moment and neither was
revisited. Provenance has to be checked against something outside the file
that claims it — here, git.

WHAT IT CHECKS
--------------
  BASELINE_MATCH  a PNG byte-identical to its v0.15.0 version is artist art
                  by definition (that tag IS the artist baseline). Any sheet
                  containing one must not be T1.
  ARTIST_COMMIT   a PNG whose current content came from a commit that says it
                  imported artist work is artist art. Same rule.

Both are *sufficient* conditions, never necessary — a sheet with no hits is
unproven, not proven-AI. This tool finds tier lies; it cannot certify tiers.
That asymmetry is deliberate: the expensive mistake is treating artist work
as disposable, not the reverse.

Usage:
    uv run python tools/audit_sprite_tiers.py
"""
import json
import subprocess
import sys
from pathlib import Path

from sprite_corpus import banner, default_root

GAME = default_root()
MANIFEST = GAME / "data" / "sprite_manifest.json"

ARTIST_BASELINE_TAG = "v0.15.0"

# Derived, not curated. A curated hash list is the thing that let this rot in
# the first place — it only knows the drops someone remembered to add.
#
# A file's MOST RECENT commit decides what its pixels are now. If that commit
# says it took them from an artist source, they are artist pixels.
ARTIST_SOURCE = (
    ".aseprite", "artist drive archive", "artist-normalized",
    "artist tag-rename", "artist idle placeholder", "artist original",
    "restore artist", "artist sprite",
)
# ...unless the same subject also says a machine made them. This exclusion is
# load-bearing: my first attempt was a bare grep for "artist" and it called
# bard_sdxl "9/9 artist-sourced", because its subject says the LoRA was
# ARTIST-TRAINED. Trained-on-artist-work and drawn-by-the-artist are opposite
# claims about the pixels and share a word.
MACHINE_SOURCE = (
    "lora", "sdxl", "ml-gen", "ip-adapter", "controlnet", "gen_",
    "trained", "sweep", "procedural", "gpt-image", "diffusion",
)


def _git(*args: str) -> str:
    r = subprocess.run(["git", *args], cwd=GAME, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


def _blob_hash(path: Path) -> str:
    return _git("hash-object", str(path)).strip()


def artist_evidence(rel_path: str) -> list[str]:
    """Sufficient evidence that this entry's pixels are artist-made.

    Accepts BOTH manifest path shapes. The first version handled only
    directories, so it silently examined 13 of 143 entries — every
    monster_sheets and overworld_npc_sheets path is a single PNG — and then
    printed "No T1 entry contains provable artist pixels", a claim about all
    of them. The sentence was true about what it checked and false about
    what it implied. That is why main() now reports coverage and refuses to
    conclude anything if it collapses.
    """
    out = []
    p = GAME / rel_path
    if p.is_file() and p.suffix == ".png":
        pngs = [p]
    elif p.is_dir():
        pngs = sorted(p.glob("*.png"))
    else:
        return out
    for png in pngs:
        rel = png.relative_to(GAME)
        baseline = _git("rev-parse", f"{ARTIST_BASELINE_TAG}:{rel}").strip()
        if baseline and baseline == _blob_hash(png):
            out.append(f"{png.name}: byte-identical to {ARTIST_BASELINE_TAG}")
            continue
        # Walk newest -> oldest and take the FIRST DECISIVE commit. Using
        # only the newest is a false negative in the dangerous direction:
        # mage/idle's last commit is "strip purple canvas bg from mage
        # idle/attack/cast", a cleanup that says nothing about who drew the
        # pixels, and its parent is "artist tag-rename" over an artist drive
        # import. Neutral operations must not erase provenance — they are
        # the normal fate of shipped artist art.
        verdict = None
        for subj in _git("log", "--format=%s", "--", str(rel)).splitlines():
            s = subj.strip().lower()
            machine = any(w in s for w in MACHINE_SOURCE)
            artist = any(w in s for w in ARTIST_SOURCE)
            if machine and not artist:
                verdict = None
                break
            if artist and not machine:
                verdict = f"{png.name}: artist-source commit ({s[:56]})"
                break
        if verdict:
            out.append(verdict)
    return out


# FLOOR, unioned with the derived corpus so coverage can only grow — the same
# shape as gen_full_sweep's legacy protection floor, and for the same reason.
#
# @cowir-battle's distinction, measured on this tool: `examined < t1_total`
# proves the buckets PARTITION the corpus, never that the corpus was fully
# READ. Truncate the read and both sides shrink together — "examined 12 of 12"
# balances exactly as "288 of 288" does. The tell is that the two numbers AGREE
# while being wrong, which is what a shared denominator looks like on screen.
#
# So the floor is checked against a raw `in manifest` — a DIFFERENT read from
# the one that builds the corpus. A section deleted from the manifest outright
# is not flagged (the floor must not fight a real removal); a section still in
# the file but dropped by the corpus read is.
_REQUIRED_SECTIONS = (
    "sheets", "party_sheets", "weapon_sheets", "overworld_monster_sheets",
    "monster_sheets", "npc_sheets", "overworld_npc_sheets",
    "overworld_player_sheets", "battle_effects", "tile_sheets",
)


def missing_sections(manifest: dict) -> list[str]:
    """Required sections the manifest still declares but the corpus did not reach."""
    reached = set(_tier_sections(manifest))
    return [s for s in _REQUIRED_SECTIONS if s in manifest and s not in reached]


def _tier_sections(manifest: dict) -> list[str]:
    """Every entry-declaring section, DERIVED from the manifest, never listed.

    The hardcoded triple this replaced was both the corpus and the denominator,
    so `examined < t1_total` could not fire for a missing SECTION — the two
    sides moved together and the run printed "examined 129 of 129" while 31 T1
    entries in four other sections were never opened. This tool already records
    a PATH-shape version of that bug; it had a section-shape twin one level up,
    invisible for the same reason: a floor derived from what it checks agrees
    with it by construction.
    """
    return [s for s, body in manifest.items()
            if isinstance(body, dict) and not s.startswith("_")]


def _entry_paths(val: dict) -> list[str]:
    """Every path an entry declares, across all THREE declaration shapes.

    A top-level `path` covers two of them (a directory for jobs, a single PNG
    for monsters and NPCs). weapon_sheets is the third: one nested dict per
    animation, each carrying its own path, with no top-level path at all — so
    the old single `val.get("path")` read it as pathless. An entry declaring
    none is returned empty, and the caller records it SKIPPED rather than
    counting it clean.
    """
    top = str(val.get("path", "")).replace("res://", "")
    if top:
        return [top]
    return [str(sub["path"]).replace("res://", "")
            for sub in val.values()
            if isinstance(sub, dict) and sub.get("path")]


def malformed_entries(manifest: dict) -> list[str]:
    """Entries whose SHAPE makes their tier unknowable.

    @cowir-music's variant of the shared-denominator bug, one level below the
    section list: a non-dict entry cannot carry a tier, so it vanishes from any
    `isinstance(val, dict)` filter — out of the corpus AND out of its total at
    once, leaving every count balanced. The section floor cannot see it,
    because the section is present and readable.

    Reported rather than skipped because UNKNOWN IS NOT T1. This file already
    refuses to write over a sheet whose provenance it cannot read; an entry it
    cannot parse is the same situation, and concluding "no tier lies" over a
    corpus that quietly lost a member is the failure it exists to prevent.

    (Unlike music's jukebox, a bare entry is not a supported shape here: the
    overworld readers absorb it into a convention default, but
    `HybridSpriteLoader.monster_frame_texture` assigns it to a typed
    `Dictionary` with no guard, which aborts the function. Malformed, not
    legal — and an audit must say so either way.)
    """
    out = []
    for section in _tier_sections(manifest):
        for key, val in sorted(manifest[section].items()):
            if not isinstance(val, dict):
                out.append(f"{section}/{key} ({type(val).__name__})")
    return out


def _t1_entries(manifest: dict) -> list[tuple[str, str, dict]]:
    """Every T1 entry the manifest declares, in every section it declares one.

    This is the DENOMINATOR: what exists. `examined` counts what was opened.
    The two must be able to disagree — that gap is the whole coverage control,
    and it was dead while both sides read one hardcoded section list.
    """
    out = []
    for section in _tier_sections(manifest):
        for key, val in sorted(manifest.get(section, {}).items()):
            if isinstance(val, dict) and val.get("tier") == "T1":
                out.append((section, key, val))
    return out


def self_check() -> bool:
    """Controls. A classifier nobody has tried to fool is a guess.

    Both directions matter and they fail differently: a false negative
    silently un-protects artist work (the bug this tool exists for), while a
    false positive would have me relabel machine sheets as artist and refuse
    to regenerate my own output.
    """
    must_be_artist = ["assets/sprites/jobs/fighter"]
    must_not_be = [
        "assets/sprites/jobs/bard_sdxl",     # subject says "artist-trained LoRA"
        "assets/sprites/jobs/mage_sdxl",
        "assets/sprites/jobs/guardian",      # v3 LoRA sweep, no artist source
        "assets/sprites/jobs/summoner",
    ]
    ok = True
    for d in must_be_artist:
        if not artist_evidence(d):
            print(f"CONTROL FAILED: {d} must read as artist and did not")
            ok = False
    for d in must_not_be:
        ev = artist_evidence(d)
        if ev:
            print(f"CONTROL FAILED: {d} must NOT read as artist — got {ev[:2]}")
            ok = False
    return ok


def main() -> int:
    print(banner(GAME))
    print()
    if not self_check():
        print("\nControls failed — the classifier is wrong, so every result "
              "below is untrustworthy. Fix it before believing any of this.")
        return 2
    m = json.loads(MANIFEST.read_text())
    findings = []
    examined = 0
    skipped: list[str] = []
    # COVERAGE FLOOR, before anything is counted. Everything below is a claim
    # about the corpus; if the corpus is short, the claim is void rather than
    # clean, and no count on screen would say so.
    gone = missing_sections(m)
    if gone:
        print(f"\nCORPUS SHORT — the manifest declares {len(gone)} section(s) this "
              f"run never read: {', '.join(gone)}. Every result above is VOID, "
              f"not clean.")
        return 2

    bad = malformed_entries(m)
    if bad:
        print(f"\nCORPUS UNREADABLE — {len(bad)} entr(ies) are not dictionaries, so "
              f"their tier cannot be read and they left the corpus silently: "
              f"{', '.join(bad[:6])}{' …' if len(bad) > 6 else ''}. Unknown is not "
              f"T1; every result above is VOID, not clean.")
        return 2

    t1 = _t1_entries(m)
    t1_total = len(t1)
    for section, key, val in t1:
        rels = _entry_paths(val)
        if not rels:
            skipped.append(f"{section}/{key} (declares no path)")
            continue
        missing = [r for r in rels if not (GAME / r).exists()]
        if missing:
            skipped.append(f"{section}/{key} (path missing: {missing[0]})")
            continue
        examined += 1
        ev = []
        for rel in rels:
            ev.extend(artist_evidence(rel))
        if ev:
            findings.append((section, key, ev))

    for section, key, ev in findings:
        print(f"\nTIER LIE  {section}/{key} is T1 but holds artist pixels:")
        for e in ev[:6]:
            print(f"    {e}")
        if len(ev) > 6:
            print(f"    … +{len(ev)-6} more")

    # COVERAGE CONTROL. Without this the tool once examined 13 of 143 entries
    # and reported a clean sweep — a vacuous pass is indistinguishable from a
    # clean corpus unless the count is stated. Every number below is what was
    # actually looked at, never what was intended.
    by_section: dict[str, int] = {}
    for section, _k, _v in t1:
        by_section[section] = by_section.get(section, 0) + 1
    print(f"\nexamined {examined} of {t1_total} T1 entries across "
          f"{len(_tier_sections(m))} sections")
    for s, n in sorted(by_section.items()):
        print(f"    {n:4d}  {s}")
    for s in skipped[:5]:
        print(f"  SKIPPED {s}")
    if len(skipped) > 5:
        print(f"  SKIPPED … +{len(skipped)-5} more")
    if examined < t1_total:
        print(f"\n{t1_total - examined} T1 entr(ies) could not be examined — "
              f"this run is INCOMPLETE and its clean result means nothing "
              f"for them.")
        return 2
    print(f"{len(findings)} tier lie(s) found")
    if not findings:
        print("No T1 entry contains provable artist pixels. One-way check: "
              "it proves lies, never innocence.")
    return 1 if findings else 0


def selftest() -> int:
    """Controls for the CORPUS, beside the ones self_check() has for the classifier.

    A classifier nobody tried to fool is a guess; so is a denominator. The bug
    these defend was not a wrong answer, it was a right answer about a corpus
    three sections wide reported as if it were the manifest.
    """
    fails = []
    real_m = json.loads(MANIFEST.read_text())

    def check(name: str, cond: bool, detail: str = "") -> None:
        print(f"  {'ok  ' if cond else 'FAIL'}  {name}{(' — ' + detail) if detail and not cond else ''}")
        if not cond:
            fails.append(name)

    print("corpus discovery")
    synthetic = {
        "_comment": "underscore sections are prose, not entries",
        "a_section_this_tool_has_never_heard_of": {
            "newcomer": {"tier": "T1", "path": "res://assets/sprites/x.png"},
        },
        "monster_sheets": {"known": {"tier": "T1", "path": "res://assets/sprites/y.png"}},
    }
    secs = _tier_sections(synthetic)
    check("an unknown section is discovered",
          "a_section_this_tool_has_never_heard_of" in secs, str(secs))
    check("an underscore section is not an entry section", "_comment" not in secs, str(secs))

    # THE arm. A hardcoded section list passes every other check in this file
    # and fails this one, which is the only reason the list can stay derived.
    keys = {k for _, k, _ in _t1_entries(synthetic)}
    check("a T1 entry in an unknown section is COUNTED", keys == {"newcomer", "known"}, str(keys))

    print("declaration shapes")
    check("top-level path (monster/NPC single png)",
          _entry_paths({"path": "res://assets/sprites/m.png"}) == ["assets/sprites/m.png"])
    check("top-level path (job directory)",
          _entry_paths({"path": "res://assets/sprites/jobs/fighter", "animations": ["idle"]})
          == ["assets/sprites/jobs/fighter"])
    check("nested per-animation paths (weapon_sheets)",
          _entry_paths({"tier": "T1", "notes": "x",
                        "idle": {"path": "res://a/idle.png"},
                        "attack": {"path": "res://a/attack.png"}})
          == ["a/idle.png", "a/attack.png"])
    check("an entry declaring NO path yields none, so the caller skips it loudly",
          _entry_paths({"tier": "T1", "notes": "x"}) == [])

    print("coverage floor (the arm the balance check cannot be)")
    # A corpus read that drops a section keeps `examined == t1_total`, so the
    # floor is the only arm that can say VOID rather than clean.
    narrowed = {"sheets": {}, "monster_sheets": {}, "tile_sheets": {}}
    check("a manifest missing required sections is reported short",
          missing_sections(narrowed) == [], "floor must not invent absent sections")
    real = real_m
    check("the real manifest reaches every required section it declares",
          missing_sections(real) == [], str(missing_sections(real)))
    declared = [s for s in _REQUIRED_SECTIONS if s in real]
    check("the floor is not vacuous — it names sections that exist",
          len(declared) >= 8, f"only {len(declared)} required sections present")
    print(f"        floor covers {len(declared)} of {len(_REQUIRED_SECTIONS)} "
          f"required sections, all present in the manifest")

    print("malformed entries (invisible to the section floor)")
    with_bad = {"monster_sheets": {"ok": {"tier": "T1", "path": "res://a.png"},
                                   "zz_bare": "res://assets/sprites/monsters/x.png"}}
    check("a non-dict entry is REPORTED, not filtered away",
          malformed_entries(with_bad) == ["monster_sheets/zz_bare (str)"],
          str(malformed_entries(with_bad)))
    check("it is invisible to the section floor, which is why it needs its own arm",
          missing_sections(with_bad) == [])
    check("the real manifest has none", malformed_entries(real_m) == [],
          str(malformed_entries(real_m)[:4]))

    print("wiring against the real manifest")
    m = json.loads(MANIFEST.read_text())
    old_triple = ("sheets", "monster_sheets", "overworld_npc_sheets")
    found = _t1_entries(m)
    outside = [(s, k) for s, k, _ in found if s not in old_triple]
    # Compared against a FIXED reference, not against itself. The obvious
    # phrasing — "every entry outside the triple is in `found`" — derives
    # `outside` FROM `found` and is true however narrow the corpus gets.
    old_count = sum(1 for s in old_triple
                    for v in m.get(s, {}).values()
                    if isinstance(v, dict) and v.get("tier") == "T1")
    check("the corpus is WIDER than the three sections this tool used to read",
          len(found) > old_count,
          f"{len(found)} found vs {old_count} in the old triple — re-hardcoded?")
    print(f"        {len(found)} T1 entries manifest-wide, {len(outside)} of them "
          f"outside the sections this tool used to read")
    if not outside:
        print("        ⚠️ VACUOUS TODAY: no T1 entry sits outside the old triple, so the "
              "arm above cannot fail — re-check before trusting it")

    print()
    if fails:
        print(f"{len(fails)} control(s) FAILED: {', '.join(fails)}")
        return 1
    print("all corpus controls pass")
    return 0


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    sys.exit(main())
