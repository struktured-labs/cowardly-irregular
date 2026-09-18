#!/usr/bin/env bash
# Publish whatever tag is NEWEST on origin, if the store is behind it. DRY RUN unless --go.
#
# WHY THIS EXISTS
# ---------------
# This is the procedure this lane runs by hand every hour: fetch, compare the newest annotated
# tag against what butler serves, create a worktree AT that tag, gate it, launch. Four commands
# and a judgement call, repeated, at whatever hour the store falls behind.
#
# ⛔ THE JUDGEMENT CALL IS WHERE IT WENT WRONG. On 2026-09-17 I staged a worktree at
# v3.33.374-alpha and gated it, ready to launch the moment a courtesy hold cleared. The hold
# lasted nine hours; .375 through .383 tagged while it ran; and the staged, gated, ready
# worktree was for a tag that had become a cadence marker. Supersession says publish the NEWEST
# tag only — and a tag that is newest when you stage it is not newest when you launch.
#
# So this resolves the tag at LAUNCH time, never before, which is the only moment the answer is
# true. Nothing is staged and there is nothing to go stale.
#
# ⚠️ IT ADDS NO AUTHORITY. tag_gate_evidence.sh must say SKIP, and publish_detached.sh still
# applies the courtesy gate — a publish is CPU and I/O that must not land on a machine
# struktured is recording on. This only removes the chance of pointing those gates at the wrong
# tag.
#
# Usage:  tools/publish_newest.sh            dry run: what it WOULD publish, and why or why not
#         tools/publish_newest.sh --go
#         tools/publish_newest.sh --selftest
# Exit:   0 nothing to do, or launched · 3 the store is behind but something refused · 2 usage
set -uo pipefail

LANE_ROOT="${PUBNEW_LANE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
GO=0
for a in "$@"; do
    case "$a" in
        --go) GO=1 ;;
        --selftest) ;;
        *) echo "unknown argument: $a" >&2; exit 2 ;;
    esac
done

_store_version() {
    [ -n "${PUBNEW_STORE_VERSION:-}" ] && { printf '%s' "$PUBNEW_STORE_VERSION"; return 0; }
    "${BUTLER:-butler}" status struktured/cowardly-irregular 2>/dev/null \
        | awk -F'|' '/\| *(linux|windows|web) *\|/ {gsub(/[ \t]/,"",$5); sub(/\+.*$/,"",$5); if ($5 != "") print $5}' \
        | sort -V | head -1
}

run() {
    cd "$LANE_ROOT" || { echo "[pubnew] cannot enter ${LANE_ROOT}" >&2; return 2; }
    [ -n "${PUBNEW_NO_FETCH:-}" ] || git fetch --tags origin >/dev/null 2>&1
    # ⛔ VERSION ORDER, NOT creatordate. `--sort=-creatordate` has one-second granularity, so
    # tags cut in the same second sort arbitrarily — the selftest's three fixture tags made it
    # return v3.33.371-alpha as "newest" while .373 existed, and every downstream answer
    # inverted from that one line. Version order is a TOTAL order on these names and is what
    # publish_all.sh's _newest_tag_on_origin() already uses (`sort -V | tail -1`); the old
    # `:319` pointer was WRONG WHEN WRITTEN — the target was three lines below it on the day,
    # and has since drifted twelve. deploy_web.sh's VERSION= fallback still uses
    # creatordate for its fallback, which is a weaker key for the same question.
    local newest; newest="$(git tag -l 'v3.33.*' --sort=-v:refname | head -1)"
    [ -n "$newest" ] || { echo "[pubnew] no tags on origin" >&2; return 3; }
    local store; store="$(_store_version)"
    [ -n "$store" ] || { echo "[pubnew] could not read the store's version — refusing to decide anything" >&2; return 3; }

    echo "[pubnew] newest tag ${newest} · store serves ${store}"
    if [ "$newest" = "$store" ]; then
        echo "[pubnew] CURRENT — nothing to publish."
        return 0
    fi
    # How far behind, because a wide gap is the case supersession exists for and the reader
    # should see it rather than infer it from two version strings.
    local skipped; skipped="$(git tag -l 'v3.33.*' --sort=v:refname \
        | awk -v p="$store" -v t="$newest" 'f && $0==t{exit} f{print} $0==p{f=1}' | wc -l)"
    echo "[pubnew] BEHIND by $((skipped + 1)) tag(s); ${skipped} of them are cadence markers this will supersede"

    local wt="tmp/pub${newest#v3.33.}"; wt="${wt%-alpha}"
    if [ "$GO" != "1" ]; then
        echo "[pubnew] DRY RUN — would gate and publish ${newest} from ${wt}. Re-run with --go."
        return 0
    fi

    [ -d "$wt" ] || git worktree add --detach "$wt" "$newest" >/dev/null 2>&1 \
        || { echo "[pubnew] could not create ${wt}" >&2; return 3; }

    local ev; ev="$(cd "$wt" && bash tools/tag_gate_evidence.sh "$newest" 2>&1 | tail -1)"
    echo "[pubnew] ${ev}"
    case "$ev" in
        VERDICT=SKIP*) : ;;
        *) echo "[pubnew] REFUSING: the tag gate did not return SKIP. RED is an absolute stop." >&2; return 3 ;;
    esac

    (cd "$wt" && bash tools/publish_detached.sh "$newest")
    return $?
}

selftest() {
    local pass=0 fail=0
    _eq() {
        if [ "$2" = "$3" ]; then printf '  ok    %-56s %s\n' "$1" "$2"; pass=$((pass+1))
        else printf '  FAIL  %-56s got %s want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
    }
    _has() { case "$2" in *"$3"*) _eq "$1" yes yes ;; *) _eq "$1" no yes ;; esac; }
    mkdir -p "$HOME/.cache"
    local d; d="$(mktemp -d "$HOME/.cache/pubnew.XXXXXX")"
    local lane="$d/lane"
    git init -q "$lane"; cd "$lane"; git config user.email t@t; git config user.name t
    echo x > a.txt; git add a.txt; git commit -qm one
    local t; for t in 371 372 373; do git tag -a "v3.33.${t}-alpha" -m "v3.33.${t}-alpha" >/dev/null 2>&1; sleep 0.05; done

    local out ec
    # 1. store already current -> nothing to do, and it must not create a worktree
    out="$(PUBNEW_LANE_ROOT="$lane" PUBNEW_NO_FETCH=1 PUBNEW_STORE_VERSION=v3.33.373-alpha bash "$SELF" 2>&1)"; ec=$?
    _eq "a CURRENT store does nothing"                  "$ec" "0"
    _has "  ...and says CURRENT"                        "$out" "CURRENT"
    _eq "  ...and creates no worktree"                  "$([ -d "$lane/tmp/pub373" ] && echo present || echo absent)" "absent"

    # 2. behind -> names the newest, and counts the cadence markers between
    out="$(PUBNEW_LANE_ROOT="$lane" PUBNEW_NO_FETCH=1 PUBNEW_STORE_VERSION=v3.33.371-alpha bash "$SELF" 2>&1)"; ec=$?
    _eq "a BEHIND store reports and stops (dry run)"    "$ec" "0"
    _has "  ...and names the NEWEST tag"                "$out" "newest tag v3.33.373-alpha"
    _has "  ...and counts the gap"                      "$out" "BEHIND by 2 tag(s)"
    _has "  ...and names the superseded count"          "$out" "1 of them are cadence markers"
    _has "  ...and is a DRY RUN by default"             "$out" "DRY RUN"
    _eq "  ...so it still creates no worktree"          "$([ -d "$lane/tmp/pub373" ] && echo present || echo absent)" "absent"

    # ⛔ 3. THE ARM THIS TOOL EXISTS FOR: the answer must come from the tag list at CALL time.
    # Staging picked a tag that later stopped being newest; this proves the tool re-resolves.
    (cd "$lane" && sleep 0.05 && git tag -a v3.33.374-alpha -m "v3.33.374-alpha" >/dev/null 2>&1)
    out="$(PUBNEW_LANE_ROOT="$lane" PUBNEW_NO_FETCH=1 PUBNEW_STORE_VERSION=v3.33.371-alpha bash "$SELF" 2>&1)"
    _has "a NEWER tag appearing moves the target"       "$out" "newest tag v3.33.374-alpha"
    _has "  ...and the gap grows with it"               "$out" "BEHIND by 3 tag(s)"

    # 4. an unreadable store decides nothing
    out="$(PUBNEW_LANE_ROOT="$lane" PUBNEW_NO_FETCH=1 BUTLER="$d/no-such-butler" bash "$SELF" 2>&1)"; ec=$?
    _eq "an unreadable store REFUSES to decide"         "$ec" "3"
    _has "  ...and says so"                             "$out" "could not read the store"

    # 5. --go with a gate that does NOT say SKIP must refuse before launching
    (cd "$lane" && mkdir -p tools
     printf '#!/usr/bin/env bash\necho "VERDICT=RUN fixture says red"\n' > tools/tag_gate_evidence.sh
     printf '#!/usr/bin/env bash\necho LAUNCHED > "%s/launched"\n' "$d" > tools/publish_detached.sh
     chmod +x tools/tag_gate_evidence.sh tools/publish_detached.sh
     git add tools; git commit -qm tools >/dev/null
     sleep 0.05; git tag -a v3.33.375-alpha -m "v3.33.375-alpha" >/dev/null 2>&1)
    out="$(PUBNEW_LANE_ROOT="$lane" PUBNEW_NO_FETCH=1 PUBNEW_STORE_VERSION=v3.33.371-alpha bash "$SELF" --go 2>&1)"; ec=$?
    _eq "a gate that is not SKIP REFUSES"               "$ec" "3"
    _has "  ...and calls RED an absolute stop"          "$out" "absolute stop"
    _eq "  ...and nothing was launched"                 "$([ -f "$d/launched" ] && echo launched || echo no)" "no"

    # 6. ...and the floor: with the gate saying SKIP, it DOES launch. Without this the arm
    #    above is satisfied by a tool that never launches anything.
    (cd "$lane" && printf '#!/usr/bin/env bash\necho "VERDICT=SKIP fixture is clean"\n' > tools/tag_gate_evidence.sh
     git add tools; git commit -qm skip >/dev/null; sleep 0.05
     git tag -a v3.33.376-alpha -m "v3.33.376-alpha" >/dev/null 2>&1)
    out="$(PUBNEW_LANE_ROOT="$lane" PUBNEW_NO_FETCH=1 PUBNEW_STORE_VERSION=v3.33.371-alpha bash "$SELF" --go 2>&1)"; ec=$?
    _eq "  ...but a SKIP verdict DOES launch"           "$([ -f "$d/launched" ] && echo launched || echo no)" "launched"

    cd /; rm -rf "$d"
    printf '\nselftest: %s passed, %s failed\n' "$pass" "$fail"
    [ "$fail" -eq 0 ]
}

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

case "${1:-}" in
    --selftest) selftest; exit $? ;;
    *) run; exit $? ;;
esac
