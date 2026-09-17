#!/usr/bin/env bash
# Derive a release note for a tag from THE REPOSITORY, never from prose.
#
# WHY THIS EXISTS
# ---------------
# Two facts measured 2026-09-16, both of which surprised the fleet:
#
#   1. A release describes itself to nobody. Every GitHub release body we have ever published is
#      one auto-generated line — checked live on .355, .356 and .357, all identical in shape:
#          **Full Changelog**: https://github.com/.../compare/v3.33.356-alpha...v3.33.357-alpha
#      and itch.io receives a VERSION STRING only (butler --userversion). The changelog prose
#      written per tag lives in the annotation and reaches no surface outside the repo.
#
#   2. That prose is not checked against the tree. v3.33.358-alpha's annotation opened with
#      "a costume no longer re-times the character" and the tag contains no such change --
#      `dressed_fps` appears nowhere in src/ or test/ on that tag. Three of its clauses named
#      branches that were announced but never merged. Nothing certified the prose against the
#      tree, because nothing ever had.
#
# So this tool does NOT reproduce the annotation. It lists what actually merged, which is a
# question git can answer and a sentence cannot. If a branch is in the note, its merge commit is
# in the tag; if it is missing, it did not land. That is the property the prose lacked.
#
# The gate evidence line IS taken from the annotation, because that line is machine-written by
# the fold and is the same string tag_gate_evidence.sh parses -- it is data, not prose.
#
# Usage:
#   tools/release_note.sh <tag> [--prev <tag>] [--out <file>]
#   tools/release_note.sh --selftest
#
# Exit: 0 wrote a note · 2 could not evaluate (unknown tag, no history, not a repo)
set -uo pipefail

# Resolved ONCE, before anything cds. The selftest runs the tool from inside a throwaway repo,
# so a relative $BASH_SOURCE resolves against the wrong directory there -- measured: every arm
# that needed the tool to RUN failed, and every arm that checked for the ABSENCE of a string
# PASSED, because absence from empty output is free. That pair is the vacuity trap this file
# warns about elsewhere, sitting in its own selftest.
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

_die() { echo "[relnote] BLOCKED: $*" >&2; exit 2; }

# The previous release tag, by version order rather than by date -- a tag cut out of order would
# otherwise make the range lie about what is new.
# Tags strictly between prev and tag, oldest first. These are the SUPERSEDED releases: this
# lane publishes the NEWEST tag only, so when the store has been held — a courtesy hold while
# struktured is streaming, a RED, a box nobody was at — the release a player receives carries
# every tag in between and the note has always described only the last one.
#
# Measured 2026-09-17, mid-hold: the store sat on v3.33.371-alpha with v3.33.379-alpha tagged.
#
#     note for .379, default prev (.378)   2 branches ·   7 commits ·  4 files
#     note vs what the store actually has  59 branches · 157 commits · 96 files
#
# A 30x under-description, and the direction is the bad one: it tells a reader that a release
# they cannot otherwise inspect is small.
_superseded_tags() {
    local prev="$1" tag="$2"
    [ -n "$prev" ] || return 0
    git tag -l 'v3.33.*' --sort=v:refname \
        | awk -v p="$prev" -v t="$tag" 'f && $0==t{exit} f{print} $0==p{f=1}'
}

_prev_tag() {
    local tag="$1"
    git tag -l 'v3.33.*' --sort=-v:refname \
        | awk -v t="$tag" 'f{print; exit} $0==t{f=1}'
}

# Branch names from merge commits. The fold writes "Merge remote-tracking branch 'origin/<name>'",
# so the name is recoverable exactly; anything that does not match that shape is reported as a
# raw subject rather than silently dropped -- a merge this cannot parse is still a merge that
# landed, and omitting it would make the note's list read complete when it is not.
_merged_branches() {
    local range="$1"
    git log --merges --format='%h%x09%s' "$range" 2>/dev/null | while IFS=$'\t' read -r sha subj; do
        case "$subj" in
            "Merge remote-tracking branch '"*)
                local name="${subj#Merge remote-tracking branch \'}"
                # ⛔ `${name%\'}` strips a TRAILING apostrophe, and the fold's subject does not
                # end in one: it ends `' (68bcd7a39)`. So 47 of 69 lines in the note for
                # v3.33.383-alpha read
                #     lane/a-theater-verdict-is-guarded-not-measured' (68bcd7a39)
                # A branch name cannot contain an apostrophe, so cutting at the FIRST one is
                # exact and handles both shapes — with the sha suffix and without.
                name="${name%%\'*}"
                name="${name#origin/}"
                printf '%s\t%s\n' "$sha" "$name" ;;
            "Merge branch '"*)
                local name="${subj#Merge branch \'}"
                name="${name%%\'*}"
                printf '%s\t%s\n' "$sha" "$name" ;;
            *) printf '%s\t%s\n' "$sha" "[unparsed] $subj" ;;
        esac
    done
}

# The fold's own machine-written evidence line, if the annotation carries one.
_gate_line() {
    git for-each-ref "refs/tags/$1" --format='%(contents)' 2>/dev/null \
        | command grep -aoE 'scripts=[0-9]+ tests=[0-9]+ passing=[0-9]+ failing=[0-9]+' | head -1
}

note() {
    local tag="$1" prev="$2"
    git rev-parse -q --verify "${tag}^{commit}" >/dev/null 2>&1 || _die "unknown tag ${tag}"
    local range have_prev=1
    if [ -n "$prev" ] && git rev-parse -q --verify "${prev}^{commit}" >/dev/null 2>&1; then
        range="${prev}..${tag}"
    else
        have_prev=0
        range="$tag"
    fi

    local merges commits files
    merges="$(_merged_branches "$range")"
    commits="$(git rev-list --count "$range" 2>/dev/null || echo 0)"
    files="$(git diff --name-only "${prev}" "${tag}" 2>/dev/null | wc -l)"

    printf '## %s\n\n' "$tag"

    local gate; gate="$(_gate_line "$tag")"
    if [ -n "$gate" ]; then
        printf '**Gated at the tag:** `%s`\n\n' "$gate"
    else
        # Never silently omit it: a missing evidence line is a fact about the tag.
        printf '**Gated at the tag:** _no machine-written evidence line in this tag'"'"'s annotation._\n\n'
    fi

    if [ "$have_prev" = "0" ]; then
        printf '_No previous release tag found, so this note covers the whole history and the list below is not a delta._\n\n'
    else
        printf 'Changes since **%s** — %s commit(s), %s file(s) changed.\n\n' "$prev" "$commits" "$files"
        local sup; sup="$(_superseded_tags "$prev" "$tag")"
        local sn; sn="$(printf '%s' "$sup" | command grep -c . || true)"
        if [ "${sn:-0}" -gt 0 ]; then
            printf '**Supersedes %s tag(s) the store never received:** ' "$sn"
            printf '%s' "$sup" | tr '\n' ' ' | sed 's/ $//'
            printf '\n\n'
            printf '_Those are cadence markers, not skipped work — every commit in them is in this release._\n\n'
        fi
    fi

    local n; n="$(printf '%s' "$merges" | command grep -c . || true)"
    if [ "${n:-0}" -eq 0 ]; then
        # A release with no merges is a real thing (a hotfix committed straight to main). Say so,
        # rather than printing an empty list that reads like "nothing landed".
        printf '**Branches merged:** none — this release has no merge commits in range.\n'
        printf 'That is not the same as "no changes": see the %s commit(s) above.\n' "$commits"
    else
        printf '**Branches merged (%s):**\n\n' "$n"
        printf '%s\n' "$merges" | while IFS=$'\t' read -r sha name; do
            [ -n "$name" ] && printf -- '- `%s` %s\n' "$sha" "$name"
        done
    fi
    printf '\n---\n'
    printf '_This note is derived from the tag'"'"'s own merge history by `tools/release_note.sh`._\n'
    printf '_Every branch listed has a merge commit in `%s`; a branch that did not land cannot appear here._\n' "$tag"
}

# ── self-test ────────────────────────────────────────────────────────────────────────────────
# Builds a throwaway repository so the arms run against real git objects rather than a mock.
# Both directions are required: a branch that merged must APPEAR, and one that did not must be
# ABSENT -- the second is the whole point, since the defect this replaces was a note naming
# three branches that were never merged.
selftest() {
    local pass=0 fail=0
    _eq() { # label actual expected
        if [ "$2" = "$3" ]; then printf '  ok    %-52s %s\n' "$1" "$2"; pass=$((pass+1))
        else printf '  FAIL  %-52s got %s want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
    }
    _has() { case "$2" in *"$3"*) _eq "$1" yes yes ;; *) _eq "$1" no yes ;; esac; }
    # FLOORED. An absence check over empty output is not a check -- it passes whenever the tool
    # failed to run at all, which is precisely when you most want to know. Every _hasnt asserts
    # the note exists first, and says VOID rather than absent when it does not.
    _hasnt() {
        case "$2" in
            *"## v3.33."*) : ;;
            *) _eq "$1" "VOID (no note produced — absence proves nothing)" absent; return ;;
        esac
        case "$2" in *"$3"*) _eq "$1" present absent ;; *) _eq "$1" absent absent ;; esac
    }

    mkdir -p "$HOME/.cache"
    local d; d="$(mktemp -d "$HOME/.cache/relnote.XXXXXX")"
    (
        cd "$d" || exit 1
        git init -q .; git config user.email t@t; git config user.name t
        echo a > a.txt; git add a.txt; git commit -qm init
        git tag -a v3.33.100-alpha -m "v3.33.100-alpha
gated: deadbeef scripts=10 tests=100 passing=100 failing=0"
        # one branch that lands
        git checkout -qb lane/landed; echo b > b.txt; git add b.txt; git commit -qm b
        git checkout -q master 2>/dev/null || git checkout -q main
        git merge -q --no-ff lane/landed -m "Merge remote-tracking branch 'origin/lane/landed'"
        # one that does NOT land
        git checkout -qb lane/never-landed; echo c > c.txt; git add c.txt; git commit -qm c
        git checkout -q master 2>/dev/null || git checkout -q main
        git tag -a v3.33.101-alpha -m "v3.33.101-alpha
gated: cafe1234 scripts=11 tests=111 passing=111 failing=0"
    ) || { echo "  FAIL  could not build the fixture repo"; return 1; }

    local out
    out="$(cd "$d" && bash "$SELF" v3.33.101-alpha --prev v3.33.100-alpha)"
    _has   "a merged branch APPEARS"                    "$out" "lane/landed"
    # ⛔ THE FIXTURE ABOVE USES A SHAPE MAIN DOES NOT PRODUCE. Its merge subject ends at the
    # closing quote; every real fold ends `' (68bcd7a39)`. The old stripper removed a TRAILING
    # apostrophe, which the real shape does not have — so 47 of 69 lines in v3.33.383-alpha's
    # note read `lane/a-theater-verdict-is-guarded-not-measured' (68bcd7a39)` while this
    # selftest stayed green. A fixture that cannot carry the defect cannot catch it.
    (cd "$d" && git checkout -q main 2>/dev/null || git checkout -q master 2>/dev/null
     git checkout -qb lane/suffixed 2>/dev/null; echo s > s.txt; git add s.txt; git commit -qm s
     git checkout -q - 2>/dev/null
     git merge -q --no-ff lane/suffixed -m "Merge remote-tracking branch 'origin/lane/suffixed' (deadbeef)"
     git tag -a v3.33.104-alpha -m "v3.33.104-alpha" >/dev/null 2>&1) >/dev/null 2>&1
    local outs; outs="$(cd "$d" && bash "$SELF" v3.33.104-alpha --prev v3.33.101-alpha)"
    _has   "the REAL fold subject yields a clean name"  "$outs" "lane/suffixed"
    _hasnt "  ...with no trailing quote"                "$outs" "lane/suffixed'"
    _hasnt "  ...and no merge sha glued to it"          "$outs" "deadbeef)"
    _hasnt "a branch that did NOT merge is ABSENT"      "$out" "never-landed"
    _has   "the gate evidence line is carried"          "$out" "scripts=11 tests=111 passing=111 failing=0"
    _hasnt "...and it is THIS tag's, not the previous"  "$out" "scripts=10"
    _has   "the previous tag is named"                  "$out" "v3.33.100-alpha"
    _has   "the branch count is stated"                 "$out" "Branches merged (1)"

    # vacuity: a range with no merges must SAY so rather than print an empty list.
    local out2
    out2="$(cd "$d" && bash "$SELF" v3.33.100-alpha --prev v3.33.100-alpha)"
    _has   "an empty range says 'none' explicitly"      "$out2" "none — this release has no merge"
    _hasnt "...and does not claim a branch list"        "$out2" "Branches merged ("

    # a tag with no machine-written evidence must not read as gated
    (cd "$d" && git tag -a v3.33.102-alpha -m "v3.33.102-alpha — no evidence line here" >/dev/null 2>&1)
    local out3
    out3="$(cd "$d" && bash "$SELF" v3.33.102-alpha --prev v3.33.101-alpha)"
    _has   "a tag with no evidence line SAYS so"        "$out3" "no machine-written evidence line"
    _hasnt "...and invents no numbers"                  "$out3" "scripts="

    # an unknown tag is BLOCKED, never an empty note
    local ec
    (cd "$d" && bash "$SELF" v9.9.9-nope >/dev/null 2>&1); ec=$?
    _eq    "an unknown tag is BLOCKED (exit 2)"         "$ec" "2"

    # _prev_tag picks the version predecessor, not the newest tag
    local p
    p="$(cd "$d" && git tag -l 'v3.33.*' --sort=-v:refname | awk -v t=v3.33.101-alpha 'f{print; exit} $0==t{f=1}')"
    _eq    "_prev_tag: the VERSION predecessor"         "$p" "v3.33.100-alpha"

    # ── supersession: the case this lane actually publishes in ──────────────────────────────
    # The fixture already has .100, .101 and .102. A note for .102 against .100 SKIPS .101, so
    # the superseded tag must be named; against .101 it skips nothing and the line must be
    # ABSENT. The second arm is the one that matters — a line that always prints would satisfy
    # the first on its own and say nothing.
    local out4 out5
    out4="$(cd "$d" && bash "$SELF" v3.33.102-alpha --prev v3.33.100-alpha)"
    _has   "a skipped tag is NAMED"                     "$out4" "Supersedes 1 tag(s)"
    _has   "  ...and named exactly"                     "$out4" "v3.33.101-alpha"
    _has   "  ...and says they are not lost work"       "$out4" "cadence markers, not skipped work"
    out5="$(cd "$d" && bash "$SELF" v3.33.102-alpha --prev v3.33.101-alpha)"
    _hasnt "an ADJACENT prev names no supersession"     "$out5" "Supersedes"
    # and the endpoints are exclusive: neither prev nor tag may appear in its own list
    _hasnt "  ...the range excludes prev itself"        "$out4" "Supersedes 1 tag(s) the store never received: v3.33.100-alpha"

    rm -rf "$d"
    printf '\nselftest: %s passed, %s failed\n' "$pass" "$fail"
    [ "$fail" -eq 0 ]
}

case "${1:-}" in
    --selftest) selftest; exit $? ;;
    "") echo "usage: $0 <tag> [--prev <tag>] [--out <file>] | --selftest" >&2; exit 2 ;;
esac

TAG="$1"; shift
PREV=""; OUT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --prev) PREV="${2:-}"; shift 2 ;;
        --out)  OUT="${2:-}"; shift 2 ;;
        *) echo "[relnote] BLOCKED: unknown argument '$1'" >&2; exit 2 ;;
    esac
done
git rev-parse --git-dir >/dev/null 2>&1 || _die "not a git repository"
[ -n "$PREV" ] || PREV="$(_prev_tag "$TAG")"

if [ -n "$OUT" ]; then
    note "$TAG" "$PREV" > "$OUT" || exit 2
    echo "[relnote] wrote ${OUT} ($(wc -l < "$OUT") lines)"
else
    note "$TAG" "$PREV"
fi
