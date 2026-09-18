#!/usr/bin/env bash
# Retire publish worktrees that can no longer be needed. DRY RUN unless --apply.
#
# WHY THIS EXISTS
# ---------------
# publish_all.sh builds each release in a throwaway worktree (tmp/pub<N>) and nothing ever
# removes it. That is deliberate up to a point — the store read-back runs AFTER the upload and
# needs the local build to compare against — but nothing retires the worktree once the read-back
# has passed and the tag has been superseded.
#
# Measured 2026-09-17, mid-hold, on struktured's box:
#
#     tmp/                       101 GB      27 worktrees at ~3.5 GB, one per release since .302
#     filesystem                 97% full, 131 GB free
#     and he was five hours into recording video to that same disk
#
# A 4-hour OBS capture against 131 GB of headroom is the reason this is a tool and not a note.
# After retiring 24 of them: tmp/ 29 GB, 202 GB free.
#
# ⛔ WHAT IT WILL NOT DO, and each rule is one I had to apply by hand:
#
#   1. the worktree serving the store   its build is the only local copy of what players have
#   2. the newest tag                   the next publish or read-back may still want it
#   3. no archived evidence             tmp/_archive/logs/<tag>/ is where the proof lives; if a
#                                       publish's logs were never archived the worktree IS the
#                                       only record
#   4. tracked changes not on main      39 lines in tools/marketing_shots.gd read as unpushed
#                                       work against the .350 TAG and were already merged. The
#                                       comparison that makes removal safe is against
#                                       origin/main, not against the tag the worktree sits on.
#
# ⚠️ Untracked build output (build/, builds/, tmp/) is expected and is NOT a reason to refuse —
# it is the thing being reclaimed.
#
# Usage:  tools/retire_publish_worktrees.sh                  dry run, says what and why
#         tools/retire_publish_worktrees.sh --apply
#         tools/retire_publish_worktrees.sh --store-version=v3.33.371-alpha   skip butler
#         tools/retire_publish_worktrees.sh --selftest
# Exit:   0 ran · 2 refused (not a repo, store version unknown)
set -uo pipefail

LANE_ROOT="${RETIRE_LANE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
APPLY=0; STORE_VER=""; 
for a in "$@"; do
    case "$a" in
        --apply) APPLY=1 ;;
        --store-version=*) STORE_VER="${a#*=}" ;;
        --selftest) ;;
        *) echo "unknown argument: $a" >&2; exit 2 ;;
    esac
done

_die() { echo "[retire] REFUSED: $*" >&2; exit 2; }

# The store's version decides rule 1. Unreadable -> refuse outright rather than guess, because
# guessing wrong here deletes the only local copy of what players are running.
_store_version() {
    [ -n "$STORE_VER" ] && { printf '%s' "$STORE_VER"; return 0; }
    # ${BUTLER} is a seam: the selftest points it at a missing binary to produce a REAL
    # unreadable-store condition. Breaking PATH instead breaks bash and yields 127, which is a
    # control asserting its own construction rather than the condition.
    "${BUTLER:-butler}" status struktured/cowardly-irregular 2>/dev/null \
        | awk -F'|' '/\| *(linux|windows|web) *\|/ {gsub(/[ \t]/,"",$5); sub(/\+.*$/,"",$5); if ($5 != "") print $5}' \
        | sort -V | head -1
}

run() {
    cd "$LANE_ROOT" || _die "cannot enter ${LANE_ROOT}"
    git rev-parse --git-dir >/dev/null 2>&1 || _die "${LANE_ROOT} is not a git repository"
    local store; store="$(_store_version)"
    [ -n "$store" ] || _die "could not read the store's version. Refusing to retire anything — rule 1 needs it, and guessing wrong deletes the only local copy of what players are running. Pass --store-version=<tag> if butler is unavailable."
    local newest; newest="$(git tag -l 'v3.33.*' --sort=-v:refname | head -1)"
    echo "[retire] store serves ${store} · newest tag ${newest} · ${LANE_ROOT}"
    [ "$APPLY" = "1" ] || echo "[retire] DRY RUN — nothing will be removed. Re-run with --apply."

    local _wtlist; _wtlist="$(git worktree list --porcelain)"
    local kept=0 gone=0 refused=0
    local d b tag
    # DIRECTORIES only. `tmp/pub[0-9]*` also matches archived logs (pub259.log, pub271b.log),
    # which produced eight lines of "not a registered worktree" noise a reader has to scroll
    # past to reach the verdict — and a tool whose output is mostly noise gets skimmed.
    for d in $(ls -d tmp/pub[0-9]*/ 2>/dev/null | sed 's:/*$::' | sort -V); do
        b="$(basename "$d")"; tag="v3.33.${b#pub}-alpha"
        # ⛔ NOT `git worktree list | grep -q`. Under `set -o pipefail` a MATCHING grep -q exits
        # early, git takes SIGPIPE, and the pipeline reports 141 — so a successful match reads
        # as a failure and every registered worktree classifies as "a plain directory". The
        # tool then retires nothing and says so cheerfully. Measured: 141 with pipefail, 0
        # without, 0 when captured first.
        if ! printf '%s' "$_wtlist" | command grep -qa "^worktree .*/${b}$"; then
            printf '  skip     %-10s not a registered worktree (a plain directory)\n' "$b"; continue
        fi
        if [ "$tag" = "$store" ]; then
            printf '  KEEP     %-10s %s — the store serves this; its build is the only local copy\n' "$b" "$tag"
            kept=$((kept+1)); continue
        fi
        if [ "$tag" = "$newest" ]; then
            printf '  KEEP     %-10s %s — the newest tag\n' "$b" "$tag"; kept=$((kept+1)); continue
        fi
        # ⛔ WHERE THE EVIDENCE ACTUALLY IS. publish_all.sh derives the archive root by
        # stripping at the FIRST "/tmp/" in the publish worktree's own path:
        #     */tmp/*) dest="${here%%/tmp/*}/tmp/_archive/logs/${TAG}"
        # This looked under LANE_ROOT instead. Those are the same directory ONLY when the lane
        # worktree is not itself under a /tmp/ path -- and on this box it is
        # (cowir-deploy-wt/tmp/wt-raw), so the archiver wrote one level OUT and this looked one
        # level IN. Measured 2026-09-18 after publishing v3.33.411-alpha: pub409 refused as
        # "no archived evidence" with TEN archived files sitting in the directory it never read.
        # It fails closed, so nothing is ever deleted wrongly -- but nothing is ever reclaimed
        # either, which is the entire purpose of the tool. The disk was 98% full.
        # Derived from the WORKTREE with the archiver's own rule so the two cannot drift apart;
        # the LANE_ROOT-relative path is still accepted so older archives keep working.
        local _abs _eviroot
        _abs="$(cd "$d" && pwd)"
        case "$_abs" in
            */tmp/*) _eviroot="${_abs%%/tmp/*}" ;;
            *)       _eviroot="$LANE_ROOT" ;;
        esac
        if [ ! -d "${_eviroot}/tmp/_archive/logs/${tag}" ] && [ ! -d "tmp/_archive/logs/${tag}" ]; then
            printf '  REFUSE   %-10s %s — no archived evidence; this worktree is the only record\n' "$b" "$tag"
            refused=$((refused+1)); continue
        fi
        # tracked modifications must already be on origin/main
        local dirty stop=0 f
        dirty="$(git -C "$d" status --porcelain 2>/dev/null | command grep -aE '^( M|M |MM|A |D )' | sed 's/^...//')"
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            local here there
            here="$(md5sum < "$d/$f" 2>/dev/null | cut -d' ' -f1)"
            there="$(git show "origin/main:$f" 2>/dev/null | md5sum | cut -d' ' -f1)"
            if [ -z "$there" ] || [ "$here" != "$there" ]; then
                printf '  REFUSE   %-10s %s — %s differs from origin/main; that is unmerged work\n' "$b" "$tag" "$f"
                stop=1
            fi
        done <<< "$dirty"
        [ "$stop" = "1" ] && { refused=$((refused+1)); continue; }

        local sz; sz="$(du -sh "$d" 2>/dev/null | cut -f1)"
        if [ "$APPLY" = "1" ]; then
            if git worktree remove --force "$d" 2>/dev/null; then
                printf '  retired  %-10s %s  (%s reclaimed)\n' "$b" "$tag" "$sz"; gone=$((gone+1))
            else
                printf '  REFUSE   %-10s %s — git declined to remove it\n' "$b" "$tag"; refused=$((refused+1))
            fi
        else
            printf '  would    %-10s %s  (%s)\n' "$b" "$tag" "$sz"; gone=$((gone+1))
        fi
    done
    [ "$APPLY" = "1" ] && git worktree prune
    printf '[retire] %s kept · %s %s · %s refused\n' "$kept" "$gone" \
        "$([ "$APPLY" = "1" ] && echo retired || echo 'would be retired')" "$refused"
    return 0
}

selftest() {
    local pass=0 fail=0
    _eq() {
        if [ "$2" = "$3" ]; then printf '  ok    %-58s %s\n' "$1" "$2"; pass=$((pass+1))
        else printf '  FAIL  %-58s got %s want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
    }
    mkdir -p "$HOME/.cache"
    local d; d="$(mktemp -d "$HOME/.cache/retire.XXXXXX")"
    local origin="$d/origin.git" lane="$d/lane"

    # a real repo with a real origin, because every rule reads git state
    git init -q --bare "$origin"
    git init -q "$lane"; cd "$lane"
    git config user.email t@t; git config user.name t
    mkdir -p tools; echo "ORIGINAL" > tools/f.gd; printf 'tmp/\n' > .gitignore
    git add tools/f.gd .gitignore; git commit -qm one
    git remote add origin "$origin"; git push -q origin HEAD:main
    local t
    for t in 350 351 352; do git tag -a "v3.33.${t}-alpha" -m "v3.33.${t}-alpha" >/dev/null 2>&1; done
    for t in 350 351 352; do git worktree add -q --detach "tmp/pub${t}" "v3.33.${t}-alpha" 2>/dev/null; done
    mkdir -p "tmp/_archive/logs/v3.33.350-alpha" "tmp/_archive/logs/v3.33.351-alpha"
    # 352 deliberately has NO archive

    local out
    out="$(RETIRE_LANE_ROOT="$lane" bash "$SELF" --store-version=v3.33.351-alpha 2>&1)"
    case "$out" in *"KEEP     pub351"*) _eq "the store's worktree is KEPT" yes yes ;; *) _eq "the store's worktree is KEPT" no yes ;; esac
    case "$out" in *"KEEP     pub352"*) _eq "the NEWEST tag is KEPT" yes yes ;; *) _eq "the NEWEST tag is KEPT" no yes ;; esac
    case "$out" in *"would    pub350"*) _eq "a superseded, archived worktree WOULD go" yes yes ;; *) _eq "a superseded, archived worktree WOULD go" no yes ;; esac
    case "$out" in *"DRY RUN"*) _eq "  ...and it is a DRY RUN by default" yes yes ;; *) _eq "  ...and it is a DRY RUN by default" no yes ;; esac
    _eq "  ...so nothing was actually removed" "$([ -d "$lane/tmp/pub350" ] && echo present || echo gone)" "present"

    # rule 3: no archive -> refuse. Make 352 superseded so it is not kept for being newest.
    (cd "$lane" && git tag -a v3.33.353-alpha -m "v3.33.353-alpha" >/dev/null 2>&1)
    out="$(RETIRE_LANE_ROOT="$lane" bash "$SELF" --store-version=v3.33.351-alpha 2>&1)"
    case "$out" in *"REFUSE   pub352"*"no archived evidence"*) _eq "no archived evidence is REFUSED" yes yes ;; *) _eq "no archived evidence is REFUSED" no yes ;; esac

    # rule 3 again, for the shape that broke it: a lane worktree that is ITSELF under a
    # /tmp/ path. The archiver strips at the FIRST "/tmp/", so evidence lands OUTSIDE the lane.
    # Every fixture above has the lane at the top level, where both derivations agree -- which
    # is exactly why the bug survived a selftest that already covered "no archived evidence".
    local nest="$d/outer/tmp/lane"
    mkdir -p "$nest"
    git init -q "$nest"
    (cd "$nest" && git config user.email t@t && git config user.name t \
        && mkdir -p tools && echo ORIGINAL > tools/f.gd && printf 'tmp/\n' > .gitignore \
        && git add tools/f.gd .gitignore && git commit -qm one \
        && git remote add origin "$origin" \
        && git tag -a v3.33.350-alpha -m x >/dev/null 2>&1 \
        && git tag -a v3.33.351-alpha -m x >/dev/null 2>&1 \
        && git tag -a v3.33.352-alpha -m x >/dev/null 2>&1 \
        && git worktree add -q --detach tmp/pub350 v3.33.350-alpha 2>/dev/null)
    # the archiver's location: strip at the first /tmp/ in ".../outer/tmp/lane/tmp/pub350"
    mkdir -p "$d/outer/tmp/_archive/logs/v3.33.350-alpha"
    out="$(RETIRE_LANE_ROOT="$nest" bash "$SELF" --store-version=v3.33.351-alpha 2>&1)"
    case "$out" in *"would    pub350"*) _eq "evidence OUTSIDE a nested lane is found" yes yes ;;
                   *) _eq "evidence OUTSIDE a nested lane is found" no yes ;; esac
    # THE DISCRIMINATING PARTNER: remove that archive and the same nested lane must refuse.
    # Without it, a fix that simply stopped checking would pass the arm above.
    rm -rf "$d/outer/tmp/_archive/logs/v3.33.350-alpha"
    out="$(RETIRE_LANE_ROOT="$nest" bash "$SELF" --store-version=v3.33.351-alpha 2>&1)"
    case "$out" in *"REFUSE   pub350"*"no archived evidence"*) _eq "  ...and its ABSENCE still refuses" yes yes ;;
                   *) _eq "  ...and its ABSENCE still refuses" no yes ;; esac

    # rule 4: a tracked change that is NOT on main -> refuse; one that IS -> allowed.
    echo "UNMERGED" > "$lane/tmp/pub350/tools/f.gd"
    out="$(RETIRE_LANE_ROOT="$lane" bash "$SELF" --store-version=v3.33.351-alpha 2>&1)"
    case "$out" in *"REFUSE   pub350"*"differs from origin/main"*) _eq "an UNMERGED tracked change is REFUSED" yes yes ;; *) _eq "an UNMERGED tracked change is REFUSED" no yes ;; esac
    # ...and the control that makes it mean something: push that same content, now it matches
    (cd "$lane" && cp tmp/pub350/tools/f.gd tools/f.gd && git add tools/f.gd && git commit -qm two && git push -q origin HEAD:main)
    out="$(RETIRE_LANE_ROOT="$lane" bash "$SELF" --store-version=v3.33.351-alpha 2>&1)"
    case "$out" in *"would    pub350"*) _eq "  ...but the SAME change once on main is allowed" yes yes ;; *) _eq "  ...but the SAME change once on main is allowed" no yes ;; esac

    # ⛔ the store version is load-bearing: unknown must refuse EVERYTHING, not default to a guess
    out="$(RETIRE_LANE_ROOT="$lane" BUTLER="$d/no-such-butler" bash "$SELF" 2>&1)"; local ec=$?
    _eq "an unknown store version REFUSES outright" "$ec" "2"
    case "$out" in *"guessing wrong deletes"*) _eq "  ...and says why" yes yes ;; *) _eq "  ...and says why" no yes ;; esac

    # --apply actually removes, and the floor: it must remove the one the dry run named
    out="$(RETIRE_LANE_ROOT="$lane" bash "$SELF" --store-version=v3.33.351-alpha --apply 2>&1)"
    _eq "--apply removes the named worktree" "$([ -d "$lane/tmp/pub350" ] && echo present || echo gone)" "gone"
    _eq "  ...and KEEPS the store's one"     "$([ -d "$lane/tmp/pub351" ] && echo present || echo gone)" "present"
    _eq "  ...and KEEPS the refused one"     "$([ -d "$lane/tmp/pub352" ] && echo present || echo gone)" "present"

    cd /; rm -rf "$d"
    printf '\nselftest: %s passed, %s failed\n' "$pass" "$fail"
    [ "$fail" -eq 0 ]
}

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

case "${1:-}" in
    --selftest) selftest; exit $? ;;
    *) run; exit $? ;;
esac
