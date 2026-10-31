#!/usr/bin/env bash
# check_store_assets.sh -- the itch store material is GITIGNORED, so nothing in the normal
# workflow ever looks at it. Two failure modes, both silent, both observed live:
#
#   1. DRIFT   -- a shipped PNG or doc changes without MANIFEST.txt being regenerated, so the
#                 manifest certifies bytes that are no longer there.
#   2. STALE   -- the on-disk CAPTIONS.md / PROVENANCE.md are an OLD CHECKOUT of the archive
#                 branch. Measured 2026-09-19: the disk held the 2026-09-11 and 2026-09-10
#                 versions, 2 and 4 commits behind, missing the trailing sections that say
#                 "⛔ THE AUDIT ABOVE IS SUPERSEDED -- do not quote its numbers" and
#                 "LAST RE-TAKEN AT v3.33.267 IS WRONG FOR 17 OF 20 SHOTS". The stale copy
#                 therefore presented the RETRACTED figures with the retraction cut off the end
#                 -- strictly worse than having no notes, because it reads as current.
#
# Staleness is invisible by construction here: the file is present, well-formed, and internally
# consistent. Only a comparison against the archive can see it.
#
# ⛔ THE ARCHIVE MOVED AND THIS TOOL DID NOT (fixed 2026-10-24). itch-assets/ has been TRACKED ON
# MAIN since the 2026-09-24 merge (the .549 re-shoot landed on main 09-29), so `origin/store-assets`
# stopped being canonical a month ago. This still compared the docs against it, so on an untouched
# main it printed DIVERGED + REFUSING, and its remedy -- `git show origin/store-assets:<doc> > <doc>`
# -- would have overwritten a month of main's captions with the stale archive copy. The default ref
# is now the checkout's own HEAD: "are the authored docs on disk the ones this commit records?",
# which is the unbacked-prose hazard above, and it reads clean on any tree whose doc edits are
# committed (a lane, a fold). STORE_ASSETS_REF still overrides it.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
DIR="${STORE_ASSETS_DIR:-$ROOT/itch-assets}"
REF="${STORE_ASSETS_REF:-HEAD}"
DOCS="${STORE_ASSETS_DOCS:-CAPTIONS.md PROVENANCE.md}"
REPO="${STORE_ASSETS_REPO:-$ROOT}"
MAN="MANIFEST.txt"
SELF="$(realpath "$0")"

# --- manifest integrity: rows must describe the files that are actually there --------------
# Returns 0 clean; prints one line per problem. Deliberately does NOT use `find -newer*`:
# cksum+size is the whole question, and a timestamp predicate answers a different one.
check_manifest() {
    local dir="$1" bad=0 p c s ac as
    if [ ! -f "$dir/$MAN" ]; then echo "  NO MANIFEST at $dir/$MAN"; return 1; fi
    while read -r p c s; do
        [ -n "${p:-}" ] || continue
        if [ ! -f "$dir/../$p" ]; then echo "  MISSING   $p"; bad=$((bad+1)); continue; fi
        ac="$(cksum < "$dir/../$p" | awk '{print $1}')"
        as="$(stat -c%s "$dir/../$p")"
        if [ "$ac" != "$c" ] || [ "$as" != "$s" ]; then
            echo "  DRIFTED   $p (manifest ${c}/${s}B, disk ${ac}/${as}B)"; bad=$((bad+1))
        fi
    done < "$dir/$MAN"
    # a file on disk that no row covers is uncertified -- the manifest cannot vouch for it
    local listed ondisk
    listed="$(mktemp)"; ondisk="$(mktemp)"
    awk '{print $1}' "$dir/$MAN" | LC_ALL=C sort > "$listed"
    # *.import / *.uid are Godot sidecars, a BUILD artifact rather than store material: main's fold
    # tree held 189 + 4 of them (untracked, all dated 2026-09-19, none newer than itch-assets/.gdignore
    # of 2026-10-03), so that tree read UNLISTED forever and never clean. None is tracked here.
    ( cd "$dir/.." && find "$(basename "$dir")" -type f ! -name "$MAN" ! -name '*.import' ! -name '*.uid' | LC_ALL=C sort ) > "$ondisk"
    local extra; extra="$(command grep -Fxv -f "$listed" "$ondisk" || true)"
    if [ -n "$extra" ]; then
        printf '  UNLISTED  %s\n' $extra; bad=$((bad+$(printf '%s\n' "$extra" | wc -l)))
    fi
    rm -f "$listed" "$ondisk"
    return $([ "$bad" -eq 0 ] && echo 0 || echo 1)
}

# --- doc staleness: the authored notes must match the archive ------------------------------
check_docs() {
    local dir="$1" ref="$2" bad=0 f o d
    git -C "$REPO" rev-parse --verify -q "$ref" >/dev/null || { echo "  ref $ref not found -- cannot judge staleness"; return 1; }
    for f in $DOCS; do
        [ -f "$dir/$f" ] || { echo "  MISSING   $f"; bad=$((bad+1)); continue; }
        o="$(git -C "$REPO" ls-tree "$ref" -- "itch-assets/$f" | awk '{print $3}')"
        d="$(git -C "$REPO" hash-object -- "$(realpath "$dir/$f")")"
        if [ -z "$o" ]; then
            echo "  UNARCHIVED $f -- not on $ref, so it exists only on this disk"; bad=$((bad+1))
        elif [ "$o" != "$d" ]; then
            # name the age, because "differs" invites a shrug and a date does not
            local at=""
            for c in $(git -C "$REPO" rev-list "$ref" -- "itch-assets/$f"); do
                if [ "$(git -C "$REPO" ls-tree "$c" -- "itch-assets/$f" | awk '{print $3}')" = "$d" ]; then
                    at="$(git -C "$REPO" log -1 --format=%cd --date=short "$c") ($(git -C "$REPO" rev-list --count "$c".."$ref" -- "itch-assets/$f") commits behind)"
                    break
                fi
            done
            if [ -n "$at" ]; then echo "  STALE     $f -- disk is the $at version of $ref"
            else echo "  DIVERGED  $f -- matches no version on $ref; disk may hold unarchived edits"; fi
            bad=$((bad+1))
        fi
    done
    return $([ "$bad" -eq 0 ] && echo 0 || echo 1)
}

verify() {
    local dir="$1" rc=0 out
    if [ ! -d "$dir" ]; then
        echo "[store-assets] no $dir in this checkout -- nothing to verify"
        return 0
    fi
    echo "[store-assets] dir: $dir"
    echo "[store-assets] manifest integrity:"
    if out="$(check_manifest "$dir")"; then echo "  all rows match the files on disk ✅"
    else printf '%s\n' "$out"; rc=3; fi
    echo "[store-assets] authored docs vs $REF:"
    if out="$(check_docs "$dir" "$REF")"; then echo "  CAPTIONS.md and PROVENANCE.md match the archive ✅"
    else printf '%s\n' "$out"; [ "$rc" -eq 0 ] && rc=4; fi
    if [ "$rc" -ne 0 ]; then
        echo "[store-assets] ⛔ REFUSING: the store material does not match its own record."
        echo "[store-assets]   DRIFTED/UNLISTED -> regenerate MANIFEST.txt after checking the change was intended"
        # Never print an overwrite as the fix: the disk copy may be the NEWER one (it was, 2026-10-13).
        echo "[store-assets]   STALE/DIVERGED   -> diff against $REF first; commit the disk copy (git add -f) if it is"
        echo "[store-assets]                       the newer work, restore from $REF only if it is not"
    fi
    return "$rc"
}

selftest() {
    local pass=0 fail=0 T out
    T="$(mktemp -d)"; trap 'rm -rf "$T"' RETURN
    _mk() { mkdir -p "$T/root/itch-assets"; printf 'a\n' > "$T/root/itch-assets/one.png"
            printf 'b\n' > "$T/root/itch-assets/two.png"
            ( cd "$T/root" && for f in itch-assets/one.png itch-assets/two.png; do
                printf '%s %s %s\n' "$f" "$(cksum < "$f" | awk '{print $1}')" "$(stat -c%s "$f")"; done \
              > itch-assets/MANIFEST.txt ); }
    _arm() { local want="$1" got="$2" name="$3"
             case "$got" in *"$want"*) pass=$((pass+1)); printf '  ok    %-52s\n' "$name" ;;
             *) fail=$((fail+1)); printf '  FAIL  %-52s (got: %s)\n' "$name" "$(printf '%s' "$got" | tr '\n' '|')" ;; esac; }

    # ---- manifest half ----
    rm -rf "$T/root"; _mk
    if out="$(check_manifest "$T/root/itch-assets")"; then pass=$((pass+1)); printf '  ok    %-52s\n' "a consistent tree is clean"
    else fail=$((fail+1)); printf '  FAIL  %-52s (got: %s)\n' "a consistent tree is clean" "$out"; fi

    rm -rf "$T/root"; _mk; printf 'CHANGED\n' > "$T/root/itch-assets/one.png"
    _arm "DRIFTED   itch-assets/one.png" "$(check_manifest "$T/root/itch-assets")" "a changed file is named as DRIFTED"

    rm -rf "$T/root"; _mk; rm "$T/root/itch-assets/two.png"
    _arm "MISSING   itch-assets/two.png" "$(check_manifest "$T/root/itch-assets")" "a deleted file is named as MISSING"

    rm -rf "$T/root"; _mk; printf 'c\n' > "$T/root/itch-assets/three.png"
    _arm "UNLISTED  itch-assets/three.png" "$(check_manifest "$T/root/itch-assets")" "an uncertified new file is UNLISTED"

    rm -rf "$T/root"; _mk; rm "$T/root/itch-assets/MANIFEST.txt"
    _arm "NO MANIFEST" "$(check_manifest "$T/root/itch-assets")" "a missing manifest refuses"

    rm -rf "$T/root"; _mk; printf 'x\n' > "$T/root/itch-assets/one.png.import"
    if out="$(check_manifest "$T/root/itch-assets")"; then pass=$((pass+1)); printf '  ok    %-52s\n' "a *.import sidecar is not store material"
    else fail=$((fail+1)); printf '  FAIL  %-52s (got: %s)\n' "a *.import sidecar is not store material" "$out"; fi
    rm -rf "$T/root"; _mk; printf 'uid://x\n' > "$T/root/itch-assets/shot.gd.uid"
    if out="$(check_manifest "$T/root/itch-assets")"; then pass=$((pass+1)); printf '  ok    %-52s\n' "a *.uid sidecar is not store material"
    else fail=$((fail+1)); printf '  FAIL  %-52s (got: %s)\n' "a *.uid sidecar is not store material" "$out"; fi

    # ---- docs half: a real git fixture, three versions on a branch ----
    local R="$T/repo"
    mkdir -p "$R/itch-assets"; git -C "$R" init -q 2>/dev/null
    git -C "$R" config user.email t@t; git -C "$R" config user.name t
    printf 'v1\n' > "$R/itch-assets/CAPTIONS.md";      git -C "$R" add -A; git -C "$R" commit -qm v1
    printf 'v1\nv2\n' > "$R/itch-assets/CAPTIONS.md";  git -C "$R" add -A; git -C "$R" commit -qm v2
    printf 'v1\nv2\nv3\n' > "$R/itch-assets/CAPTIONS.md"; git -C "$R" add -A; git -C "$R" commit -qm v3
    git -C "$R" branch -f archive HEAD
    local SAVE_REPO="$REPO" SAVE_DOCS="$DOCS"; REPO="$R"; DOCS="CAPTIONS.md"
    local W="$T/work"; mkdir -p "$W"

    printf 'v1\nv2\nv3\n' > "$W/CAPTIONS.md"
    if out="$(check_docs "$W" archive)"; then pass=$((pass+1)); printf '  ok    %-52s\n' "a doc matching the archive tip is clean"
    else fail=$((fail+1)); printf '  FAIL  %-52s (got: %s)\n' "a doc matching the archive tip is clean" "$out"; fi

    printf 'v1\n' > "$W/CAPTIONS.md"
    _arm "STALE     CAPTIONS.md" "$(check_docs "$W" archive)" "an OLD version is named as STALE"
    _arm "2 commits behind"      "$(check_docs "$W" archive)" "STALE says HOW FAR behind"

    printf 'unrelated\n' > "$W/CAPTIONS.md"
    _arm "DIVERGED  CAPTIONS.md" "$(check_docs "$W" archive)" "content in no version is DIVERGED, not STALE"

    DOCS="NOT_ON_BRANCH.md"; printf 'x\n' > "$W/NOT_ON_BRANCH.md"
    _arm "UNARCHIVED NOT_ON_BRANCH.md" "$(check_docs "$W" archive)" "a doc absent from the archive is UNARCHIVED"

    REPO="$SAVE_REPO"; DOCS="$SAVE_DOCS"

    # ---- the SHIPPED DEFAULT, end to end: every arm above passes an explicit ref, so a default
    # that still named origin/store-assets would pass them all. A repo whose HEAD tracks the docs,
    # beside a stale `store-assets` branch, must read clean with nothing overridden.
    local M="$T/main"; mkdir -p "$M/itch-assets"; git -C "$M" init -q 2>/dev/null
    git -C "$M" config user.email t@t; git -C "$M" config user.name t
    printf 'old\n' > "$M/itch-assets/CAPTIONS.md"; printf 'old\n' > "$M/itch-assets/PROVENANCE.md"
    git -C "$M" add -A; git -C "$M" commit -qm archive; git -C "$M" branch -f store-assets HEAD
    printf 'new\n' > "$M/itch-assets/CAPTIONS.md"; printf 'new\n' > "$M/itch-assets/PROVENANCE.md"
    printf 'p\n' > "$M/itch-assets/one.png"
    ( cd "$M" && for f in itch-assets/CAPTIONS.md itch-assets/PROVENANCE.md itch-assets/one.png; do
        printf '%s %s %s\n' "$f" "$(cksum < "$f" | awk '{print $1}')" "$(stat -c%s "$f")"; done > itch-assets/MANIFEST.txt )
    git -C "$M" add -A; git -C "$M" commit -qm main
    local ec=0
    out="$(cd "$M" && env -u STORE_ASSETS_REF -u STORE_ASSETS_DIR -u STORE_ASSETS_REPO -u STORE_ASSETS_DOCS bash "$SELF" --verify 2>&1)" || ec=$?
    _arm "ec=0 match the archive ✅" "ec=$ec $(printf '%s' "$out" | command grep -o 'match the archive ✅')" \
         "default ref: committed docs read clean beside a stale branch"
    printf 'uncommitted\n' > "$M/itch-assets/CAPTIONS.md"; ec=0
    out="$(cd "$M" && env -u STORE_ASSETS_REF -u STORE_ASSETS_DIR -u STORE_ASSETS_REPO -u STORE_ASSETS_DOCS bash "$SELF" --verify 2>&1)" || ec=$?
    _arm "DIVERGED  CAPTIONS.md" "$out" "default ref: an uncommitted doc edit is caught"
    _arm "no-overwrite-remedy" "$(printf '%s' "$out" | command grep -q '> <doc>' && echo overwrite-remedy || echo no-overwrite-remedy)" \
         "the refusal never prints an overwrite as the fix"
    echo
    echo "selftest: ${pass} passed, ${fail} failed"
    [ "$fail" -eq 0 ]
}

case "${1:-}" in
    --selftest) selftest ;;
    ""|--verify) verify "$DIR" ;;
    *) echo "usage: $(basename "$0") [--verify|--selftest]"; exit 2 ;;
esac
