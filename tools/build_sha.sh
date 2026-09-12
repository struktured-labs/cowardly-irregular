#!/usr/bin/env bash
# Print the build-SHA label that goes into a butler --userversion, ONE VALUE PER RUN.
#
# WHY THIS EXISTS
# ---------------
# v3.33.312-alpha shipped with TWO labels across three channels, from one script and one line:
#
#     linux     v3.33.312-alpha+befbe408     (8)   <- pushed first
#     windows   v3.33.312-alpha+befbe4083    (9)   <- ~2 min later, SAME LINE
#     web       v3.33.312-alpha+befbe4083    (9)
#
# `git rev-parse --short` returns the shortest length that is unambiguous AT THAT MOMENT, and
# that length scales with the repo's object count. This repo has 125 worktrees with lanes
# pushing continuously, so the length grew 8 -> 9 BETWEEN the linux push and the windows push.
#
# ⛔ The first diagnosis -- "this SHA became ambiguous" -- was wrong: ALL 24 recent tags now
# abbreviate to 9, including .310 and .311, which shipped with 8-char labels. Nothing about the
# SHA is special; the repo-wide default moved. It is self-healing per release and recurs at
# every threshold.
#
# So the fix is not a longer abbreviation (that changes what struktured sees on the store page,
# and is his call). It is: read the value ONCE at the top of a run and pass it down. A value read
# twice from a concurrently-written source is two values.
#
# PUBLISH_BUILD_SHA, when set, is used verbatim -- including any `-dirty` the caller already
# decided on. Unset, this computes it, which is what keeps the documented standalone recovery
# path working:  tools/deploy_web.sh --publish <tag>   (publish_all.sh:281)
#
# Usage:  tools/build_sha.sh            print the label
#         tools/build_sha.sh --selftest
set -uo pipefail

_label() {
    # Caller's value wins whole: if a run already fixed the label, appending to it here would
    # re-introduce exactly the per-step divergence this exists to prevent.
    if [ -n "${PUBLISH_BUILD_SHA:-}" ]; then
        printf '%s' "$PUBLISH_BUILD_SHA"
        return 0
    fi
    local sha
    sha="$(git rev-parse --short HEAD 2>/dev/null)" || return 2
    [ -n "$sha" ] || return 2
    git diff --quiet HEAD -- 2>/dev/null || sha="${sha}-dirty"
    printf '%s' "$sha"
}

case "${1:-}" in
    --selftest) ;;
    "")  _label; exit $? ;;
    *)   echo "usage: $0 [--selftest]" >&2; exit 2 ;;
esac

# ── selftest ─────────────────────────────────────────────────────────────────────────────
pass=0; fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok    %-54s %s\n' "$1" "$2";
        else fail=$((fail+1)); printf '  FAIL  %-54s got %s want %s\n' "$1" "$2" "$3"; fi; }

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
mkdir -p tmp
T="$(mktemp -d "$(pwd)/tmp/buildsha.XXXXXX")"
trap 'rm -rf "$T"' EXIT

# a real repo, so the git arms measure git and not a stub
( cd "$T" && git init -q . && git config user.email t@t && git config user.name t \
  && echo one > a.txt && git add a.txt && git commit -qm one ) >/dev/null 2>&1
REAL="$(cd "$T" && git rev-parse --short HEAD)"

# 1/2 — the env value WINS, and it wins VERBATIM. A helper that always recomputed would pass
#       nothing here; one that always echoed the env would pass arm 1 and fail arm 3.
chk "env value is used verbatim" \
    "$(cd "$T" && PUBLISH_BUILD_SHA=zzz999 "$SELF")" "zzz999"
chk "env value with -dirty is not doubled" \
    "$(cd "$T" && PUBLISH_BUILD_SHA=zzz999-dirty "$SELF")" "zzz999-dirty"

# 3 — unset falls back to git, so the standalone recovery path still works.
chk "unset falls back to this repo's sha" \
    "$(cd "$T" && unset PUBLISH_BUILD_SHA; "$SELF")" "$REAL"

# 4 — EMPTY must behave as unset, not produce an empty label. An empty userversion would push
#     `v3.33.N-alpha+` to the store.
chk "empty env falls back rather than emitting nothing" \
    "$(cd "$T" && PUBLISH_BUILD_SHA= "$SELF")" "$REAL"

# 5/6 — the -dirty suffix, BOTH directions. A helper that never appended would pass 5 alone;
#       one that always appended would pass 6 alone.
chk "clean tree has no -dirty suffix" \
    "$(cd "$T" && unset PUBLISH_BUILD_SHA; "$SELF")" "$REAL"
( cd "$T" && echo two >> a.txt )
chk "dirty tree appends -dirty" \
    "$(cd "$T" && unset PUBLISH_BUILD_SHA; "$SELF")" "${REAL}-dirty"

# 7 — a caller-fixed label is NOT re-dirtied: the run already decided, and a second opinion
#     mid-run is the whole defect.
chk "env value is not re-dirtied in a dirty tree" \
    "$(cd "$T" && PUBLISH_BUILD_SHA=fixed123 "$SELF")" "fixed123"

# 8 — when git cannot resolve HEAD and there is no env value, refuse loudly rather than
#     printing an empty label: `--userversion v3.33.N-alpha+` would reach the store.
#     ⚠️ A temp dir is NOT a repo-free environment -- git walks UP, and the first version of
#     this arm found THIS worktree's repo and passed with a real sha. Deny git a repo instead.
out=$(cd "$T" && unset PUBLISH_BUILD_SHA; GIT_DIR=/nonexistent GIT_WORK_TREE=/nonexistent "$SELF" 2>/dev/null); rc=$?
chk "git cannot resolve HEAD -> exits non-zero" "$rc" "2"
chk "…and prints nothing"                       "$out" ""

echo; echo "selftest: ${pass} passed, ${fail} failed"; [ "$fail" -eq 0 ]
