#!/usr/bin/env bash
# Decide whether a deploy chain may SKIP its own test suite because the tag it is
# publishing was already gated by the fold.
#
# WHY THIS EXISTS
# ---------------
# Every deploy chain used to re-run the full 1319-script suite, UNSANDBOXED, against
# struktured's live user://. run_tests.sh's net snapshots and restores settings.json and
# autobattle/ on that shared path, so each chain opened a window in which a setting or a
# keybind he changed mid-session was silently reverted (measured 2026-08-19: a gate exit
# re-stamped autobattle/profiles.json with mtime backward 25h while he was playing).
# saves/ is excluded and was never at risk. Three chains per tag = three windows, three
# times 45 minutes, for a tree the fold had ALREADY gated on the exact SHA being tagged.
#
# A content hash cannot detect that revert — reverting TO the baseline is what produces the
# matching hash — so "settings cksum unchanged" was never evidence and is not used here.
#
# THE DIRECTION OF FAILURE IS THE WHOLE DESIGN
# --------------------------------------------
# The natural shape is `if evidence_mismatch; then run_suite; fi`, and an ABSENT or
# unparseable marker is not a mismatch, so that shape SKIPS on every malformation: a typo,
# a format drift, a lightweight tag, an unfetched ref. The unsafe path is the quiet one.
#
# So this script never reports a mismatch. It reports PROOF, and proof must be positive:
# it prints the literal token `VERDICT=SKIP` only when all ten checks below pass. Every
# other outcome — including an internal error, an unhandled case, or an early exit — prints
# `VERDICT=RUN` or prints nothing at all. Callers MUST require the literal SKIP token and
# treat silence as RUN. Absence of evidence is never evidence.
#
# THE LIGHTWEIGHT-TAG LEAK (check 3, measured)
# --------------------------------------------
# `git for-each-ref --format='%(contents)'` FALLS THROUGH TO THE COMMIT MESSAGE on a
# lightweight tag. All tags through v3.33.225-alpha are lightweight (`git cat-file -t` ->
# `commit`). Measured in a scratch repo: a marker written into a COMMIT message parsed out
# of `%(contents)` identically to a real annotation —
#     light-tag -> gated: deadbeef…   (this is the commit body)
#     ann-tag   -> gated: bb0f3828…   (the actual annotation)
# The parser cannot tell them apart, so the objecttype is checked FIRST and the tag object
# is read with `git cat-file tag`, which cannot fall through.
#
# The `sha == tag commit` equality in check 7 happens to catch that leak by accident, since
# a commit's message cannot contain its own sha. That protection is subtle and dies the
# moment anyone writes a short sha or `gated: HEAD`, so it is not relied on: 40-hex exact,
# annotated only.
#
# Usage:   tools/tag_gate_evidence.sh <tag>
#          tools/tag_gate_evidence.sh --selftest
# Output:  VERDICT=SKIP <detail>   |   VERDICT=RUN <reason>
# Exit:    always 0 for a decision; the TOKEN is the answer, not the exit code, so a
#          caller that forgets `set -e` semantics still cannot misread a crash as a skip.

set -uo pipefail

# Format fixed with cowir-main (msgs 8514/8519), field order significant:
#   gated: <40-hex sha> scripts=N tests=N passing=N failing=0
# and, ONLY when the tag names a later commit than the one the suite ran on:
#   tagged_delta_from: <40-hex sha>
#
# From .227 the `gated:` sha is the sha the suite ACTUALLY RAN ON, not merely a sha the
# tagger vouches for. v3.33.226-alpha was the one-time case where those differed and the
# annotation explained it in prose; prose is not a check, so this is the mechanism that
# replaces it.
#
# WITHOUT the second line the two shas must be EQUAL. With it, the tag may sit ahead of the
# gated tree provided every changed path is under an allow-listed prefix — deploy tooling
# and documentation, neither of which reaches the exported game. Anything else means the
# suite's evidence does not describe the bits being shipped, and that is a RUN.
MARKER_RE='gated:[[:space:]]+([0-9a-f]{40})[[:space:]]+scripts=([0-9]+)[[:space:]]+tests=([0-9]+)[[:space:]]+passing=([0-9]+)[[:space:]]+failing=([0-9]+)'
DELTA_RE='tagged_delta_from:[[:space:]]+([0-9a-f]{40})'
## Prefixes whose contents cannot reach the exported game. Keep this list short and boring.
DELTA_ALLOWED_PREFIXES='^(tools/|docs/)'

run() { echo "VERDICT=RUN $*"; exit 0; }

decide() {
    local tag="$1"

    # 1. a tag was actually named
    [ -n "$tag" ] || run "no tag given — nothing to check evidence against"

    # 2. the ref exists locally (an unfetched tag is not evidence)
    git rev-parse -q --verify "refs/tags/${tag}" >/dev/null 2>&1 \
        || run "refs/tags/${tag} not present locally — fetch it or the evidence is unreadable"

    # 3. ANNOTATED ONLY. See the lightweight-tag leak above.
    local otype
    otype="$(git cat-file -t "refs/tags/${tag}" 2>/dev/null)"
    [ "$otype" = "tag" ] \
        || run "refs/tags/${tag} is a ${otype:-unreadable} object, not an annotated tag — a lightweight tag carries no gate evidence (and %(contents) would leak the COMMIT message)"

    # 4. strict marker parse, from the tag object itself
    local body
    body="$(git cat-file tag "refs/tags/${tag}" 2>/dev/null)"
    [ -n "$body" ] || run "tag object for ${tag} unreadable"
    [[ "$body" =~ $MARKER_RE ]] \
        || run "no well-formed 'gated: <40-hex> scripts=N tests=N passing=N failing=N' marker in the ${tag} annotation"
    local gsha="${BASH_REMATCH[1]}" gscripts="${BASH_REMATCH[2]}" gtests="${BASH_REMATCH[3]}"
    local gpassing="${BASH_REMATCH[4]}" gfailing="${BASH_REMATCH[5]}"

    # 5. a red fold is never a licence to skip
    [ "$gfailing" -eq 0 ] \
        || run "the ${tag} marker reports failing=${gfailing} — a red fold cannot authorise skipping the suite"

    # 6. a zero-suite claim is not evidence. `passing` is GUT's own cardinal and prints the
    #    WORD 'none' at zero, so a 0 here means the fold wrote a literal 0, not that it parsed
    #    'none' — either way it describes a run that proved nothing.
    { [ "$gscripts" -gt 0 ] && [ "$gpassing" -gt 0 ]; } \
        || run "the ${tag} marker claims scripts=${gscripts} passing=${gpassing} — a run that asserted nothing is not evidence"

    # 7. the evidence must describe the commit being published — either the same commit, or
    #    one whose entire delta is provably incapable of changing the game.
    local tagsha
    tagsha="$(git rev-parse "refs/tags/${tag}^{commit}" 2>/dev/null)"
    [ -n "$tagsha" ] || run "cannot resolve ${tag} to a commit"

    if [ "$gsha" != "$tagsha" ]; then
        # A bare mismatch is fatal unless the tagger DECLARED it. The declaration is what
        # separates a deliberate tools-only re-tag from a marker pointed at the wrong tree
        # by accident, and an accident must never be the quiet path.
        [[ "$body" =~ $DELTA_RE ]] \
            || run "the ${tag} marker was gated on ${gsha:0:8} but the tag points at ${tagsha:0:8}, and there is no 'tagged_delta_from:' line declaring that gap"
        local declared="${BASH_REMATCH[1]}"
        [ "$declared" = "$gsha" ] \
            || run "${tag} declares tagged_delta_from ${declared:0:8} but was gated on ${gsha:0:8} — the declaration does not match the evidence"

        # THE DIFF MUST BE PROVEN TO HAVE RUN. An empty result from `git diff` means "no
        # changed paths" AND "the command failed" — and read as the former, an unknown sha
        # or a broken invocation yields a clean allow-list and a skip. So: resolve the sha
        # first, then require a zero exit, and only then filter.
        git cat-file -e "${gsha}^{commit}" 2>/dev/null \
            || run "${tag} was gated on ${gsha:0:8}, which is not a commit in this repository — the delta cannot be checked"
        local delta rc
        delta="$(git diff --name-only "$gsha" "$tagsha" 2>/dev/null)"; rc=$?
        [ $rc -eq 0 ] \
            || run "git diff ${gsha:0:8}..${tagsha:0:8} failed (exit ${rc}) — the delta is unverified, which is not the same as empty"

        local offending
        offending="$(printf '%s\n' "$delta" | grep -v '^$' | grep -Ev "$DELTA_ALLOWED_PREFIXES" | head -5)"
        [ -z "$offending" ] \
            || run "${tag} sits ahead of its gated tree ${gsha:0:8} and the delta touches files outside ${DELTA_ALLOWED_PREFIXES}: $(printf '%s' "$offending" | tr '\n' ' ')"
    fi

    # 8-9. THE EXPORT SHIPS THE WORKING TREE, not the tag. Evidence about the tag's tree is
    #      worthless if the tree on disk is not that tree. This is the same subject-of-the-claim
    #      gap GATE_TREE_ID closes between gate 1 and gate 2, one step earlier.
    local head dirty
    head="$(git rev-parse HEAD 2>/dev/null)"
    [ "$head" = "$tagsha" ] \
        || run "HEAD is ${head:0:8} but ${tag} is ${tagsha:0:8} — this worktree is not at the tag, so the fold's evidence does not describe what would be exported"
    dirty="$(git status --porcelain | wc -l)"
    [ "$dirty" -eq 0 ] \
        || run "worktree has ${dirty} uncommitted change(s) — the export ships the WORKING tree, which the fold never gated"

    # 10. the evidence must cover the corpus that exists NOW. GUT omits a script that fails to
    #     PARSE, so a claim of N scripts against a tree holding M is the vacuous-corpus bug
    #     arriving by a different road. Same expression gate.sh uses.
    local ondisk
    ondisk="$(ls test/unit/test_*.gd 2>/dev/null | wc -l)"
    [ "$gscripts" -eq "$ondisk" ] \
        || run "the ${tag} marker covers ${gscripts} scripts but ${ondisk} test files are on disk — the evidence does not cover this corpus"

    echo "VERDICT=SKIP ${tag} @ ${gsha:0:8} already gated by the fold: scripts=${gscripts} tests=${gtests} passing=${gpassing} failing=0; worktree clean and at the tag; corpus matches (${ondisk} on disk)"
    exit 0
}

# ── self-test ────────────────────────────────────────────────────────────────
# A checker whose negative path is never exercised is the thing it is meant to prevent.
# Every case below names its expected verdict, and BOTH verdicts must actually occur —
# a suite of cases that all expect RUN would pass with `decide()` hardwired to run.
selftest() {
    local sandbox pass=0 fail=0 saw_skip=0 saw_run=0
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/taggate_selftest.XXXXXX")"
    # shellcheck disable=SC2064
    trap "rm -rf '$sandbox'" EXIT

    (
        cd "$sandbox" || exit 1
        git init -q .; git config user.email t@t; git config user.name t
        mkdir -p test/unit
        # three scripts on disk; the honest marker must say scripts=3
        for i in 1 2 3; do echo "extends GutTest" > "test/unit/test_${i}.gd"; done
        git add -A; git commit -q -m "base"
    ) || { echo "selftest: sandbox setup failed"; return 1; }

    check() { # name expected tag
        local name="$1" expect="$2" tag="$3" out verdict
        out="$(cd "$sandbox" && decide "$tag")"
        verdict="${out%% *}"; verdict="${verdict#VERDICT=}"
        [ "$verdict" = "SKIP" ] && saw_skip=1
        [ "$verdict" = "RUN" ] && saw_run=1
        if [ "$verdict" = "$expect" ]; then
            pass=$((pass+1)); printf '  ok    %-34s -> %s\n' "$name" "$verdict"
        else
            fail=$((fail+1)); printf '  FAIL  %-34s -> %s (expected %s)\n     %s\n' "$name" "$verdict" "$expect" "$out"
        fi
    }

    local sha; sha="$(cd "$sandbox" && git rev-parse HEAD)"

    (cd "$sandbox" && git tag -a good -m "rel
gated: ${sha} scripts=3 tests=9 passing=9 failing=0")
    check "annotated, honest, clean"        SKIP good

    (cd "$sandbox" && git tag light)
    check "lightweight tag"                 RUN  light

    check "tag absent"                      RUN  nope

    (cd "$sandbox" && git tag -a red -m "rel
gated: ${sha} scripts=3 tests=9 passing=8 failing=1")
    check "failing=1"                       RUN  red

    (cd "$sandbox" && git tag -a empty -m "rel
gated: ${sha} scripts=0 tests=0 passing=0 failing=0")
    check "zero-script claim"               RUN  empty

    (cd "$sandbox" && git tag -a wrongsha -m "rel
gated: 0000000000000000000000000000000000000000 scripts=3 tests=9 passing=9 failing=0")
    check "marker names another commit"     RUN  wrongsha

    (cd "$sandbox" && git tag -a shortsha -m "rel
gated: ${sha:0:8} scripts=3 tests=9 passing=9 failing=0")
    check "short sha in marker"             RUN  shortsha

    (cd "$sandbox" && git tag -a nomarker -m "rel with no marker at all")
    check "no marker"                       RUN  nomarker

    (cd "$sandbox" && git tag -a miscount -m "rel
gated: ${sha} scripts=99 tests=9 passing=9 failing=0")
    check "corpus count mismatch"           RUN  miscount

    # dirty tree — same honest tag that produced SKIP above must now RUN
    echo "scratch" > "$sandbox/test/unit/test_4.gd"
    check "extra untracked test file"       RUN  good
    rm -f "$sandbox/test/unit/test_4.gd"

    echo "dirt" >> "$sandbox/test/unit/test_1.gd"
    check "dirty worktree"                  RUN  good
    (cd "$sandbox" && git checkout -q -- test/unit/test_1.gd)

    # HEAD moved off the tag
    (cd "$sandbox" && echo more > other && git add -A && git commit -q -m next)
    check "HEAD not at the tag"             RUN  good

    # ── declared-delta phase (cowir-main msg 8519) ──────────────────────────
    # Each case resets to the gated base and builds exactly one commit on top, so the diff
    # under test is the ONLY delta. Zeroes are never used as a stand-in for "some other
    # sha": a sha that does not resolve exercises a different branch (the cat-file guard)
    # than a sha that resolves and differs, and conflating them would leave one untested.
    local Z40="0000000000000000000000000000000000000000"
    local F40="ffffffffffffffffffffffffffffffffffffffff"
    dcase() { # tagname, marker-extra-lines, setup-cmd
        ( cd "$sandbox" \
          && git reset -q --hard "$sha" \
          && eval "$3" >/dev/null 2>&1 \
          && git add -A && git commit -q -m "delta-$1" ) || return 1
    }

    dcase delta_tools "" 'mkdir -p tools && echo a > tools/a.sh'
    (cd "$sandbox" && git tag -a delta_tools -m "rel
gated: ${sha} scripts=3 tests=9 passing=9 failing=0
tagged_delta_from: ${sha}")
    check "declared delta, tools/ only"     SKIP delta_tools

    dcase delta_docs "" 'mkdir -p docs && echo a > docs/a.md'
    (cd "$sandbox" && git tag -a delta_docs -m "rel
gated: ${sha} scripts=3 tests=9 passing=9 failing=0
tagged_delta_from: ${sha}")
    check "declared delta, docs/ only"      SKIP delta_docs

    dcase delta_game "" 'echo a > gameplay.gd'
    (cd "$sandbox" && git tag -a delta_game -m "rel
gated: ${sha} scripts=3 tests=9 passing=9 failing=0
tagged_delta_from: ${sha}")
    check "declared delta touches game code" RUN delta_game

    # A real gap with NO declaration — the accident case. Must never be the quiet path.
    dcase delta_undecl "" 'mkdir -p tools && echo a > tools/b.sh'
    (cd "$sandbox" && git tag -a delta_undecl -m "rel
gated: ${sha} scripts=3 tests=9 passing=9 failing=0")
    check "gap present but undeclared"      RUN delta_undecl

    # Declaration that does not match the evidence it claims to explain.
    dcase delta_mism "" 'mkdir -p tools && echo a > tools/c.sh'
    (cd "$sandbox" && git tag -a delta_mism -m "rel
gated: ${sha} scripts=3 tests=9 passing=9 failing=0
tagged_delta_from: ${Z40}")
    check "declaration != gated sha"        RUN delta_mism

    # Gated on a sha this repository does not have: the diff CANNOT be computed, and an
    # uncomputed diff must not read as an empty one.
    dcase delta_unk "" 'mkdir -p tools && echo a > tools/d.sh'
    (cd "$sandbox" && git tag -a delta_unk -m "rel
gated: ${F40} scripts=3 tests=9 passing=9 failing=0
tagged_delta_from: ${F40}")
    check "gated sha absent from repo"      RUN delta_unk

    echo
    echo "selftest: ${pass} passed, ${fail} failed"
    # BOTH verdicts must have occurred. Without this, a decide() that always ran would
    # pass every RUN case and only the single SKIP case would catch it — and a decide()
    # hardwired to SKIP would be caught only by the RUN cases. Requiring both makes the
    # suite unable to pass with either constant stubbed in.
    if [ "$saw_skip" -ne 1 ] || [ "$saw_run" -ne 1 ]; then
        echo "selftest: BROKEN — verdicts observed: SKIP=${saw_skip} RUN=${saw_run}; both are required" >&2
        return 1
    fi
    [ "$fail" -eq 0 ]
}

case "${1:-}" in
    --selftest) selftest ;;
    *)          decide "${1:-}" ;;
esac
