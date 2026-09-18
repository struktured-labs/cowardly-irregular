#!/usr/bin/env bash
# Cut a release tag so that an UNGATED one cannot reach origin.
#
# WHY THIS EXISTS
# ---------------
# 5 of the 19 tags cut on 2026-09-18 (.411 .416 .419 .420 .421) carry a prose annotation with
# NO `gated:` evidence line. Measured, not recalled: a 40-hex match against each tag's own
# commit across .410-.428.
#
# Nothing was wrong with those builds. The cost is that the evidence line is the only thing
# that lets the publisher SKIP a redundant full suite — `tag_gate_evidence.sh` answers RUN
# without it — so an omission spends ~8 minutes per channel proving something the fold already
# proved, and it does that silently, in a lane that is not the one that dropped the line.
#
# THE ACTUAL DEFECT WAS ORDERING, NOT A MISSING TOOL
# --------------------------------------------------
# Two tools already detect the omission and BOTH read it after the fact: tag_gate_evidence.sh
# at publish time, and release_note.sh, which prints "_no machine-written evidence line in this
# tag's annotation._" into the note. My own flow ran tag_gate_evidence.sh AFTER `git push
# origin <tag>` — so the check was real, and it was downstream of the irreversible step.
# Tags are not re-cut here, so "detected afterwards" and "not detected" cost the same.
#
# That is the commit-before-refusal family aimed at the release flow rather than at GDScript:
# a push is the commit, the evidence check is the refusal, and they were in the wrong order.
#
# WHAT IT DOES
# ------------
#   1. check_version_matches_tag.sh   SEMVER must equal the tag's label
#   2. git tag -a                     LOCAL only — nothing has left the machine yet
#   3. tag_gate_evidence.sh           must answer VERDICT=SKIP
#   4. git push origin <tag>          only now
#
# Step 3's failure path DELETES the local tag, so a refusal leaves the repository exactly as it
# was found. Nothing to undo, which is the property the ordering was missing.
#
# ⚠️ THE MESSAGE FILE MUST LIVE OUTSIDE THE WORKTREE. tag_gate_evidence.sh refuses a dirty tree
# (correctly — the export ships the working tree), and an untracked message file in the repo IS
# a dirty tree. Measured while writing this: the first good-path run blocked on its own argument.
#
# Usage:  tools/cut_tag.sh v3.33.NNN-alpha /path/outside/the/repo/msg.txt
#         tools/cut_tag.sh --selftest
set -uo pipefail

_die() { echo "[cut-tag] BLOCKED: $*" >&2; exit 2; }

cut_tag() {
    local tag="$1" msgfile="$2" sha
    [ -n "$tag" ] || _die "no tag given"
    [ -f "$msgfile" ] || _die "no message file at '$msgfile'"
    git rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1 && _die "$tag already exists locally"
    sha="$(git rev-parse HEAD)"

    ./tools/check_version_matches_tag.sh "$tag" || _die "SEMVER disagrees with the tag label"

    # The evidence line names a SHA; it must be the one being tagged, not merely a 40-hex.
    if ! grep -aqE "gated: ${sha} " "$msgfile"; then
        _die "the message file carries no 'gated: ${sha} ...' line — the fold's evidence for THIS sha"
    fi
    grep -aqE 'failing=0' "$msgfile" || _die "the evidence line does not say failing=0"

    git tag -a "$tag" "$sha" -F "$msgfile" || _die "git tag failed"

    local verdict
    verdict="$(./tools/tag_gate_evidence.sh "$tag" 2>&1)"
    case "$verdict" in
        VERDICT=SKIP*) : ;;
        *)  git tag -d "$tag" >/dev/null 2>&1
            echo "[cut-tag] $verdict" >&2
            _die "tag_gate_evidence did not answer SKIP — local tag deleted, nothing pushed" ;;
    esac

    git push origin "$tag" || _die "push failed (the local tag is kept; re-run the push)"
    echo "[cut-tag] $tag -> ${sha}  evidence verified BEFORE the push"
}

# Every arm drives the real script against a real repository — no replica of the parse.
selftest() {
    local pass=0 fail=0 saw_ok=0 saw_block=0 root sb
    root="$(cd "$(dirname "$0")/.." && pwd)"
    sb="$(mktemp -d)"; trap 'rm -rf "$sb"' RETURN
    # ⛔ AN ARM ASSERTS THE REASON, NOT THE EXIT CODE. Written rc-only first, and BOTH mutants
    # survived: drop the marker pre-check and tag_gate_evidence still refuses a markerless tag;
    # accept any VERDICT and the pre-check still refuses it. Two gates covering each other, so
    # neither was load-bearing and rc=2 could not tell them apart.
    _arm() { # name expected_rc want_text body...
        local name="$1" want="$2" want_text="$3"; shift 3
        local out rc=0
        out="$("$@" 2>&1)" || rc=$?
        if [ "$rc" -ne "$want" ]; then
            fail=$((fail+1)); echo "selftest: FAIL $name — rc=$rc want=$want" >&2; return
        fi
        if [ -n "$want_text" ] && ! printf '%s' "$out" | grep -aqF "$want_text"; then
            fail=$((fail+1))
            echo "selftest: FAIL $name — rc matched but the wrong gate fired; wanted '$want_text' in:" >&2
            printf '%s\n' "$out" | sed 's/^/          /' >&2
            return
        fi
        pass=$((pass+1)); [ "$want" -eq 0 ] && saw_ok=1 || saw_block=1
    }
    git init -q -b main "$sb/repo"
    (cd "$sb/repo" \
        && mkdir -p src/meta tools \
        && printf 'const SEMVER := "9.9.1-alpha"\n' > src/meta/Version.gd \
        && mkdir -p test/unit && printf 'extends GutTest\n' > test/unit/test_one.gd \
        && cp "$root/tools/check_version_matches_tag.sh" "$root/tools/tag_gate_evidence.sh" \
              "$root/tools/cut_tag.sh" tools/ \
        && git add -A && git commit -qm base) || { echo "selftest: setup failed" >&2; return 1; }
    local sha; sha="$(cd "$sb/repo" && git rev-parse HEAD)"

    printf 'v9.9.1-alpha\n\ngated: %s scripts=1 tests=1 passing=1 failing=0\n' "$sha" > "$sb/good.txt"
    printf 'v9.9.1-alpha\n\nprose only, no evidence line\n' > "$sb/nomarker.txt"
    printf 'v9.9.1-alpha\n\ngated: %s scripts=1 tests=1 passing=0 failing=3\n' "$sha" > "$sb/red.txt"
    printf 'v9.9.1-alpha\n\ngated: deadbeefdeadbeefdeadbeefdeadbeefdeadbeef scripts=1 tests=1 passing=1 failing=0\n' > "$sb/wrongsha.txt"
    # right sha, well-formed, but claims a corpus this tree does not have -> evidence answers RUN
    printf 'v9.9.1-alpha\n\ngated: %s scripts=99 tests=99 passing=99 failing=0\n' "$sha" > "$sb/miscount.txt"

    # Each arm names the gate that must fire, so a gate removed cannot be covered by its neighbour.
    _arm "no marker blocks" 2 "carries no 'gated:" env -C "$sb/repo" ./tools/cut_tag.sh v9.9.1-alpha "$sb/nomarker.txt"
    _arm "no marker left no tag" 1 "" env -C "$sb/repo" git rev-parse -q --verify refs/tags/v9.9.1-alpha
    _arm "failing!=0 blocks" 2 "does not say failing=0" env -C "$sb/repo" ./tools/cut_tag.sh v9.9.1-alpha "$sb/red.txt"
    _arm "another sha blocks" 2 "carries no 'gated:" env -C "$sb/repo" ./tools/cut_tag.sh v9.9.1-alpha "$sb/wrongsha.txt"
    _arm "label mismatch blocks" 2 "SEMVER disagrees" env -C "$sb/repo" ./tools/cut_tag.sh v9.9.2-alpha "$sb/good.txt"
    # ISOLATES THE VERDICT GATE: the marker is well-formed and names the right sha, so every
    # pre-check passes and only tag_gate_evidence can refuse. Without this arm, accepting any
    # VERDICT is invisible — the pre-checks alone keep every other arm red.
    _arm "evidence RUN blocks" 2 "did not answer SKIP" env -C "$sb/repo" ./tools/cut_tag.sh v9.9.1-alpha "$sb/miscount.txt"
    _arm "evidence RUN left no tag" 1 "" env -C "$sb/repo" git rev-parse -q --verify refs/tags/v9.9.1-alpha
    # CONTROL: the good message must reach the push attempt. No remote here, so the push fails
    # (rc 2) — but ONLY after the tag exists, which is what separates "passed the gates" from
    # "refused at one of them".
    env -C "$sb/repo" ./tools/cut_tag.sh v9.9.1-alpha "$sb/good.txt" >/dev/null 2>&1
    _arm "CONTROL good message created the tag" 0 "" env -C "$sb/repo" git rev-parse -q --verify refs/tags/v9.9.1-alpha

    echo "selftest: ${pass} passed, ${fail} failed"
    if [ "$saw_ok" -eq 0 ] || [ "$saw_block" -eq 0 ]; then
        echo "selftest: BROKEN — outcomes observed: pass=${saw_ok} block=${saw_block}; both are required" >&2
        return 1
    fi
    [ "$fail" -eq 0 ]
}

case "${1:-}" in
    --selftest) selftest ;;
    "") _die "usage: tools/cut_tag.sh <tag> <message-file> | --selftest" ;;
    *) cut_tag "$1" "${2:-}" ;;
esac
