#!/usr/bin/env python3
"""Refuse, at write time, to overwrite artist-made sprite pixels.

WHY THIS EXISTS
---------------
CLAUDE.md is unambiguous: "AI sprite generation must NEVER overwrite, modify, or degrade
existing artist-made assets without explicit approval." The protection that actually shipped
was an AUDIT, and `tools/audit_sprite_tiers.py:9` says the real state just as plainly:
"regeneration will happily overwrite artist work." An audit reports AFTER the pixels are gone.

Exactly one tool ever refused: `gen_full_sweep.py`, whose `_protected_anims` is the pattern
this module extracts so the other writers can share it. Nothing here is new policy — it is that
function, moved, with a path-shaped entry point added.

THE TWO HALVES, AND WHY BOTH
----------------------------
`_LEGACY_PROTECTED` is a hand-written list that predates the cleric/mage artist drops. It is
stale and it is NOT wrong: someone who knew wrote it down, which is evidence the derivation
does not have. It stays as a FLOOR, unioned, never replaced -- keeping it caught a live
regression, because the git derivation DROPS `rogue/cast`: that file's commit subject is
"rogue + cleric clashing ML-gen anims -> artist idle placeholders", and the classifier reads
"ML-gen" as machine when the arrow means the artist art REPLACED the ML-gen output.

    A derivation is not automatically safer than an enumeration. It fails differently.

So: union, and protection can only ever GROW.

FAIL CLOSED
-----------
If provenance cannot be determined, every call refuses. Unable to tell whose pixels these are
means unable to promise we will not destroy them. That is the one property this module must
never trade for convenience: a guard that passes when it cannot see is worse than no guard,
because the caller believes it ran.

Usage in a generating tool, one line before the write:

    from tools.artist_guard import assert_writable
    assert_writable(out_path, force=args.force)

Exit: refuses via SystemExit, which a tool run from the shell reports as a non-zero exit.
"""
import os
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent

# The legacy floor. See the module docstring: stale, not wrong, never replaced.
_LEGACY_PROTECTED = {
    "fighter": ["idle", "walk", "attack", "hit", "dead", "cast", "defend", "item", "victory",
                "advance", "defer", "cleave", "power_strike", "provoke", "slash"],
    "rogue": ["idle", "attack", "cast"],
}


def _artist_evidence():
    """The provenance oracle, imported late so the failure is a REFUSAL and not an import error."""
    try:
        # BOTH paths. `audit_sprite_tiers` does a bare `from sprite_corpus import ...`, which
        # resolves for a tool RUN as a script (python puts tools/ on the path) and not for one
        # IMPORTED from elsewhere. This module is always the second case.
        for extra in (str(PROJECT), str(PROJECT / "tools")):
            if extra not in sys.path:
                sys.path.insert(0, extra)
        from tools.audit_sprite_tiers import artist_evidence
        return artist_evidence
    except ImportError as exc:
        raise SystemExit(
            f"[artist_guard] REFUSING: cannot import artist_evidence ({exc}). "
            f"Without it every artist animation is unprotected, so this refuses rather than "
            f"proceed blind."
        )



def _sprite_roots() -> list:
    """Every tree a sprite path may legitimately live under.

    ⛔ THE GENERATORS DO NOT WRITE WHERE THIS MODULE LIVES. Traced 2026-09-17: of 19 tools whose
    save target resolves to a jobs sprite path, essentially all write into ANOTHER checkout —
    `cowardly-irregular` or `cowardly-irregular-sprite-gen`, by literal path or by $GAME_REPO.
    Resolving only against this worktree made every EXISTING file out there unknowable, so the
    guard refused T1 regeneration as readily as artist work — correct-by-accident on the artist
    case and useless on the rest, which is how a guard gets switched off.

    The provenance oracle reads `sprite_corpus.default_root()` (the artist-delivery checkout), so
    a path is asked about by its path RELATIVE to whichever sprite root contains it.
    """
    roots = [PROJECT]
    try:
        for extra in (str(PROJECT), str(PROJECT / "tools")):
            if extra not in sys.path:
                sys.path.insert(0, extra)
        from sprite_corpus import default_root
        roots.append(Path(default_root()))
    except Exception:
        pass
    # Sibling checkouts the generators target, discovered rather than listed: any ancestor of the
    # target that itself contains assets/sprites is a sprite root.
    return roots


def _sprite_relative(p: Path):
    """`p` relative to the sprite root that contains it, or None when nothing does."""
    for root in _sprite_roots():
        try:
            return p.relative_to(Path(root).resolve())
        except (ValueError, OSError):
            continue
    # Walk up: a checkout we were not told about still has assets/sprites at its root.
    for anc in p.parents:
        if (anc / "assets" / "sprites").is_dir():
            try:
                return p.relative_to(anc)
            except ValueError:
                return None
    return None


# CLAUDE.md's tier table is the whole vocabulary of a write decision.
_WRITABLE_TIERS = frozenset({"T0", "T1"})    # procedural placeholder · AI prototype
_PROTECTED_TIERS = frozenset({"T2", "T3"})   # artist draft · artist final


def tier_refusal(tier, subject: str = "this sheet") -> str:
    """Refuse on an artist tier AND on any tier this table does not recognise.

    `regen_monster_artist_style.artist_write_refusal` tested `tier in ("T2",
    "T3")` — exact match — and fell through to "" for everything else. So the
    one function whose other two branches fail CLOSED on unknown provenance,
    and say so in as many words, failed OPEN on a tier it could not read:
    "t2", "T2 ", "T2_artist_draft" and a missing field all read as permission.

    Not hypothetical spelling. `weapon_sheets.iron_sword` already carries
    "T2_artist_draft", so the habit exists in the file this reads; it is out of
    reach today only because every tier consumer walks monster_sheets. 0
    instances reachable, and the trigger is authored.

    Three answers, not two: known-writable proceeds, known-protected refuses,
    and anything else refuses — an unrecognised tier is unknown provenance, and
    this module's entire stance is that unknown is not permission.
    """
    t = tier if isinstance(tier, str) else ""
    if t in _WRITABLE_TIERS:
        return ""
    if t in _PROTECTED_TIERS:
        return f"{subject} is tier {t} — ARTIST work. Regenerating would overwrite it."
    known = ", ".join(sorted(_WRITABLE_TIERS | _PROTECTED_TIERS))
    shown = repr(t) if t else "no tier at all"
    return (f"{subject} carries {shown}, which is not one of [{known}]. An "
            f"unrecognised tier is unknown provenance, and unknown is not T1.")


def protected_anims(job_id: str, _evidence=None) -> list:
    """Animation names in this job that must survive a regeneration.

    Union of what git can prove and what the legacy list asserts, because the two have
    different blind spots and the cost of missing one is destroying artist work.
    """
    evidence = _evidence or _artist_evidence()
    derived = {line.split(".png")[0] for line in evidence(f"assets/sprites/jobs/{job_id}")}
    return sorted(derived | set(_LEGACY_PROTECTED.get(job_id, [])))


def is_protected(path, _evidence=None) -> bool:
    """Are the pixels currently at `path` artist-made?

    A path that does not exist is NOT protected -- creating new art is the normal case and
    this guard exists to stop destruction, not creation.
    """
    p = Path(path)
    if not p.exists():
        return False
    rel = _sprite_relative(p.resolve())
    if rel is None:
        # No sprite root contains it. Provenance is unknowable, so refuse to bless it.
        return True
    parts = rel.parts
    if len(parts) >= 4 and parts[0] == "assets" and parts[1] == "sprites" and parts[2] == "jobs":
        if p.stem in _LEGACY_PROTECTED.get(parts[3], []):
            return True
    evidence = _evidence or _artist_evidence()
    return bool(evidence(str(rel)))


def assert_writable(path, force: bool = False, _evidence=None) -> None:
    """Refuse to let the caller overwrite artist pixels. `force=True` is the explicit approval.

    Most of these generators have no argparse at all — running the script IS the act — so
    `ARTIST_GUARD_FORCE=1` is the override for them. Setting an environment variable is still an
    explicit decision a person has to make; the default without it is to refuse.
    """
    if force or os.environ.get("ARTIST_GUARD_FORCE") == "1":
        return
    if is_protected(path, _evidence=_evidence):
        raise SystemExit(
            f"[artist_guard] REFUSING to overwrite artist work: {path}\n"
            f"  CLAUDE.md: AI generation must never overwrite artist-made assets without "
            f"explicit approval.\n"
            f"  If that approval is what you are giving, re-run with --force."
        )


def selftest() -> int:
    """Arms run against an INJECTED oracle: no git, no network, no writes outside a temp dir."""
    import tempfile
    ok, bad = 0, 0

    def check(label, got, want):
        nonlocal ok, bad
        if got == want:
            print(f"  ok    {label}")
            ok += 1
        else:
            print(f"  FAIL  {label}: got {got!r} want {want!r}")
            bad += 1

    # TIER DECISION TABLE. The bug was a fallthrough, so every arm that matters
    # here is a value the old `tier in ("T2","T3")` test let through as permission.
    print("  -- tier decisions --")
    check("T0 procedural is writable", tier_refusal("T0"), "")
    check("T1 AI prototype is writable", tier_refusal("T1"), "")
    check("T2 artist draft refuses", bool(tier_refusal("T2")), True)
    check("T3 artist final refuses", bool(tier_refusal("T3")), True)
    check("T2 names ARTIST in the reason", "ARTIST" in tier_refusal("T2"), True)
    # The four shapes that used to return "" and mean "go ahead".
    check("lowercase 't2' refuses", bool(tier_refusal("t2")), True)
    check("trailing space 'T2 ' refuses", bool(tier_refusal("T2 ")), True)
    check("the authored 'T2_artist_draft' refuses", bool(tier_refusal("T2_artist_draft")), True)
    check("a missing tier refuses", bool(tier_refusal("")), True)
    check("a non-string tier refuses", bool(tier_refusal(None)), True)
    check("an unrecognised tier is not called ARTIST work",
          "ARTIST" in tier_refusal("T2_artist_draft"), False)

    with tempfile.TemporaryDirectory() as d:
        real = Path(d) / "idle.png"
        real.write_bytes(b"x")
        missing = Path(d) / "nope.png"

        yes = lambda rel: [f"{Path(rel).name}: byte-identical to v0.15.0"]
        no = lambda rel: []

        # A file outside the checkout is unknowable, so it must refuse rather than bless.
        check("outside the checkout is treated as protected", is_protected(real, _evidence=no), True)
        # Absence is not protection: creating new art must stay possible.
        check("a path that does not exist is writable", is_protected(missing, _evidence=yes), False)

        # The union, with the oracle injected both ways.
        check("git evidence alone protects", protected_anims("mage", _evidence=yes) != [], True)
        check("legacy floor alone protects rogue/cast",
              "cast" in protected_anims("rogue", _evidence=no), True)
        check("legacy floor survives an empty oracle",
              protected_anims("fighter", _evidence=no) == sorted(_LEGACY_PROTECTED["fighter"]), True)
        check("an unknown job with no evidence is empty",
              protected_anims("no_such_job", _evidence=no), [])

        # assert_writable: the refusal, and the explicit override.
        refused = False
        try:
            assert_writable(real, force=False, _evidence=yes)
        except SystemExit:
            refused = True
        check("assert_writable REFUSES protected pixels", refused, True)

        forced = True
        try:
            assert_writable(real, force=True, _evidence=yes)
        except SystemExit:
            forced = False
        check("--force is the explicit approval", forced, True)

    # Cross-checkout resolution. The generators write into sibling checkouts, so a path must be
    # asked about by its path RELATIVE to whichever sprite root holds it — not refused because it
    # is not under this one. Built as a throwaway tree so the arm needs no sibling checkout.
    with tempfile.TemporaryDirectory() as d2:
        fake = Path(d2) / "some-other-checkout"
        art = fake / "assets" / "sprites" / "jobs" / "fighter"
        art.mkdir(parents=True)
        sheet = art / "idle.png"
        sheet.write_bytes(b"x")
        rel = _sprite_relative(sheet.resolve())
        check("a sibling checkout resolves to a repo-relative path",
              str(rel), "assets/sprites/jobs/fighter/idle.png")
        # and the legacy floor still applies out there, with no oracle at all
        check("the legacy floor reaches a sibling checkout",
              is_protected(sheet, _evidence=no), True)
        stray = Path(d2) / "not-a-checkout" / "idle.png"
        stray.parent.mkdir(parents=True)
        stray.write_bytes(b"x")
        check("a path under NO sprite root is refused", is_protected(stray, _evidence=no), True)

    # The env override, for the tools with no CLI to carry a --force.
    with tempfile.TemporaryDirectory() as d3:
        f3 = Path(d3) / "idle.png"
        f3.write_bytes(b"x")
        os.environ["ARTIST_GUARD_FORCE"] = "1"
        allowed = True
        try:
            assert_writable(f3, _evidence=yes)
        except SystemExit:
            allowed = False
        del os.environ["ARTIST_GUARD_FORCE"]
        check("ARTIST_GUARD_FORCE=1 is an explicit approval", allowed, True)
        refused_again = False
        try:
            assert_writable(f3, _evidence=yes)
        except SystemExit:
            refused_again = True
        check("...and unsetting it restores the refusal", refused_again, True)

    # Fail-closed: a broken oracle must refuse, never pass.
    def broken(rel):
        raise SystemExit("oracle unavailable")
    closed = False
    try:
        protected_anims("fighter", _evidence=broken)
    except SystemExit:
        closed = True
    check("a broken oracle REFUSES rather than returning empty", closed, True)

    print(f"\nselftest: {ok} passed, {bad} failed")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    print(__doc__)
    sys.exit(2)
