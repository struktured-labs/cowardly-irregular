#!/usr/bin/env bash
# Ask the reaper whether cleanup in THIS lane could clear a disk shortfall, and report what it
# actually said.
#
# WHY THIS EXISTS
# ---------------
# publish_all.sh refuses a publish below a free-space floor, and rather than offering a
# destructive tool and hoping, it probes the reaper first. That instinct was right and the
# probe was wrong in a way that pointed the reader away from the only space this lane owns.
#
# ⛔ MEASURED 2026-10-12. The probe ran `tools/reap_release_worktrees.sh` with no REAP_ROOT,
# from a publish whose cwd IS a release worktree. The reaper cd's to its own checkout on
# startup, so it rooted itself at `tmp/pub<N>` and scanned THAT TREE'S OWN tmp/:
#
#     REAP_ROOT=…/wt-raw/tmp/pub658   0 of 221 registered worktree(s) are under this root
#     REAP_ROOT=…/cowir-deploy-wt     121 × would remove   (same default prefix)
#
# On 2026-09-19, at 909 MB free against a 5000 MB floor, that zero printed
# "⛔ CLEANUP HERE CANNOT CLEAR THIS FLOOR … the space is held outside this lane", while this
# lane held 123 release worktrees and 443 GiB. The reaper's own usage note names the trap
# ("without it the reaper can only see its own tmp/, HOWEVER THE CALLER INVOKES IT") and the
# probe, written later as a safety improvement, did not set it.
#
# ⛔ AND THE ZERO WAS ALREADY QUALIFIED. The reaper says "0 of 221 registered worktree(s) are
# under this root — if the population you meant lives elsewhere, set REAP_ROOT". An earlier
# fix put that sentence there precisely so a zero would name its population. The caller
# counted `would remove` lines only, so the qualification stayed in the log and the reader got
# certainty instead. A guard that says "I may be looking in the wrong place" must not be
# reported as "the space is not here". [[a-bound-you-cannot-see]]
#
# WHAT IT IS NOT: this probe never removes anything, and nothing here runs --apply. Reaping is
# struktured's call under his standing "no age-based delete in tmp/" rule.
#
# Usage:  tools/reap_probe.sh <shortfall-mb> [reap-log-path] [reap-root]
#         tools/reap_probe.sh --selftest
# Output: advice lines on stdout, unprefixed, for the caller to frame.
# Exit:   0 printed advice · 2 usage
set -uo pipefail

# The lane root is the path before /tmp/ — the SAME derivation _archive_evidence already uses,
# so the two cannot drift. A publish worktree is created as <lane>/tmp/<name>.
# [[pin-the-value-not-the-spelling]]
# The lane root is the path before the FIRST /tmp/ — the same derivation _archive_evidence
# already uses, so the two cannot drift. [[pin-the-value-not-the-spelling]]
#
# ⚠️ `%%` strips at the FIRST /tmp/, not the last, and that is deliberate: this lane nests
# worktrees (cowir-deploy-wt/tmp/wt-raw/tmp/pub658), and the OUTERMOST root is the one whose
# scan covers every release tree. Measured: rooted there the reaper names 121 trees; rooted at
# the inner wt-raw it names the same 121; rooted at pub658 itself, zero.
#
# Takes a path so the rule can be tested as a rule. An absolute path that BEGINS with /tmp/
# leaves nothing before the separator, so the empty result falls back rather than handing a
# caller an empty root that would silently mean "/".
_lane_root() {
    local here="${1:-}" root
    [ -n "$here" ] || here="$(pwd -P)"
    case "$here" in
        */tmp/*) root="${here%%/tmp/*}" ;;
        *)       root="$here" ;;
    esac
    [ -n "$root" ] || root="$here"
    printf '%s\n' "$root"
}

probe() {
    local short_mb="$1" log="${2:-tmp/reap_probe.$$.log}" root="${3:-}" ec=0 cands=0 pop_line pop_total
    # An explicit root is a PARAMETER, not a test seam: the publish path passes none and so
    # exercises the derivation, and the arms that need a controlled population pass one.
    [ -n "$root" ] || root="$(_lane_root)"
    mkdir -p "$(dirname "$log")" 2>/dev/null
    REAP_ROOT="$root" timeout 120 ./tools/reap_release_worktrees.sh > "$log" 2>&1 || ec=$?

    if [ "$ec" -ne 0 ] && [ "$ec" -ne 1 ]; then
        echo "COULD NOT ASK THE REAPER (exit ${ec}) whether cleanup here could help."
        echo "Treat the next two lines as unverified:"
        echo "  tools/reap_release_worktrees.sh            # dry run, names what it would remove"
        echo "  tools/reap_release_worktrees.sh --apply    # only trees rebuildable from a tag on origin"
        return 0
    fi

    # `would remove` is the reaper's CONTRACT — its own arms assert that string both ways.
    # Counted from a real file, never a pipeline: $? across a pipe has bitten this chain.
    [ -f "$log" ] && cands=$(command grep -ac 'would remove' "$log" || true)
    case "$cands" in ''|*[!0-9]*) cands=0 ;; esac

    if [ "$cands" -gt 0 ]; then
        echo "The reaper names ${cands} removable tree(s) against a ${short_mb} MB shortfall,"
        echo "rooted at ${root}. Whether that is ENOUGH is not known until you read the dry"
        echo "run — the count is trees, not megabytes:"
        echo "  cat ${log}"
        echo "  REAP_ROOT=${root} tools/reap_release_worktrees.sh --apply   # trees rebuildable from a tag on origin"
        return 0
    fi

    # A ZERO IS NOT A VERDICT UNTIL IT NAMES THE POPULATION IT IS A ZERO OVER.
    pop_line="$(command grep -a 'registered worktree' "$log" 2>/dev/null | head -1)"
    pop_total="$(printf '%s\n' "$pop_line" | sed -n 's/.*0 of \([0-9]*\) registered.*/\1/p')"
    case "$pop_total" in ''|*[!0-9]*) pop_total=0 ;; esac
    if [ "$pop_total" -gt 1 ]; then
        echo "⛔ THE PROBE COULD NOT SEE THIS LANE'S POPULATION, so it cannot say whether"
        echo "   cleanup would help. The reaper reported:"
        echo "     ${pop_line}"
        echo "   It was rooted at ${root}. If that is a release worktree rather than the lane"
        echo "   checkout, the trees you are looking for are one level up:"
        echo "     REAP_ROOT=<lane checkout> tools/reap_release_worktrees.sh    # dry run"
        echo "   Do NOT read this as 'the space is not in this lane'. It is 'nobody looked'."
        return 0
    fi

    echo "⛔ CLEANUP HERE CANNOT CLEAR THIS FLOOR, SO DO NOT START ONE."
    echo "  The reaper has 0 removable trees over a population it DID scan:"
    echo "    ${pop_line:-(the reaper printed no population line)}"
    echo "  It would free 0 MB against a ${short_mb} MB shortfall, and it is the ONLY cleanup"
    echo "  this lane is permitted to do, so there is nothing here to reclaim. The space is"
    echo "  held outside this lane and freeing it is struktured's call."
    echo "  Probe: ${log}"
    return 0
}

# ── self-test ────────────────────────────────────────────────────────────────
# Arms run THIS FILE as a subprocess against REAL fixtures: a real git worktree at a real tag,
# and a real run of the real reaper. A canned reaper would agree with whatever this file
# expects and could not reject it. [[arrival-is-not-effect]]
selftest() {
    local pass=0 fail=0 self dir out
    self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    local repo; repo="$(cd "$(dirname "$0")/.." && pwd)"
    # ⛔ THE FIXTURE MUST LIVE INSIDE THE REPO, AND THIS LINE IS WHY THIS TOOL BLOCKED A PUBLISH.
    # It was `mktemp -d "${TMPDIR:-/tmp}/reapprobe.XXXXXX"`, and I ran the selftest with
    # TMPDIR=<worktree>/tmp. That put the fixture INSIDE a git worktree, so the reaper — which
    # cd's to its own copy's parent — could run `git worktree list` and reported "0 of 221
    # registered worktree(s) are under this root": the blind case the arm below is about.
    # The publish chain sets no TMPDIR, mktemp chose /tmp, which is not a repo, the population was
    # 0 of 0, and the probe correctly took the "nothing to reclaim" branch instead. 14 passed,
    # 3 failed, gate 0d refused the publish, and the store sat at .660 until a new tag.
    #
    # MY OWN PREAMBLE SUPPLIED THE PRECONDITION THE FILE LACKED. The production path always runs
    # inside a worktree, so the repo-local tmp/ is the FAITHFUL location, not merely the one that
    # works. [[the-harness-supplies-what-the-file-lacks]]
    mkdir -p tmp
    dir="$(mktemp -d "$PWD/tmp/reapprobe.XXXXXX")"
    # shellcheck disable=SC2064
    trap "rm -rf '$dir'" EXIT

    chk() { # name pattern want(0 present|1 absent)
        local name="$1" pat="$2" want="$3"
        if printf '%s' "$out" | command grep -aq -- "$pat"; then
            [ "$want" -eq 0 ] && { pass=$((pass+1)); printf '  ok    %-56s\n' "$name"; return; }
        else
            [ "$want" -eq 1 ] && { pass=$((pass+1)); printf '  ok    %-56s\n' "$name"; return; }
        fi
        fail=$((fail+1)); printf '  FAIL  %-56s (/%s/ want %s)\n' "$name" "$pat" "$want"
    }

    local repo_wt; repo_wt="$dir/noworktrees"
    mkdir -p "$repo_wt/tmp" "$dir/caller/tools"
    cp "$self" "$dir/caller/tools/"
    cp "$repo/tools/reap_release_worktrees.sh" "$dir/caller/tools/"
    # ⛔ AND ITS SOURCED RESOLVER. From .702 the reaper does `. <its own dir>/origin_tags.sh`, so a
    # copy of it alone is a reaper that cannot ask origin for a tag. Copied alone, it refused
    # with "tag list contradicts this repo's", this file's three "no population" arms read the
    # wrong message, and gate 0d BLOCKED v3.33.702-alpha's publish (15/18).
    cp "$repo/tools/origin_tags.sh" "$dir/caller/tools/"

    # PRECONDITION, ASSERTED. The blind arm needs a NON-EMPTY registered population — that is what
    # makes "0 of N" different from "0 of 0". If the fixture ever lands outside the repo again, the
    # arm does not fail honestly, it silently starts testing the OTHER branch. So check it, and
    # fail loudly rather than measuring the wrong case.
    local reg; reg="$(cd "$dir" && git worktree list 2>/dev/null | wc -l)"
    if [ "${reg:-0}" -gt 1 ]; then
        pass=$((pass+1)); printf '  ok    %-56s (%s registered)\n' "the fixture sees a non-empty worktree population" "$reg"
    else
        fail=$((fail+1)); printf '  FAIL  %-56s (%s) — the blind arm below is VOID\n' "the fixture must sit inside the repo" "${reg:-0}"
    fi

    # THE CASE THAT PRODUCED THE WRONG VERDICT: a root whose own tmp/ holds no worktrees while
    # the repo's registered population is large. The REAL reaper runs here.
    out="$(cd "$dir/caller" && ./tools/reap_probe.sh 4091 "$dir/p1.log" "$repo_wt" 2>&1)"
    chk "a probe that saw no population says so"      "COULD NOT SEE THIS LANE'S POPULATION" 0
    chk "...and does NOT claim cleanup cannot help"    "CANNOT CLEAR THIS FLOOR"              1
    chk "...and does NOT blame outside this lane"      "space is held outside this lane"      1
    chk "...and quotes the reaper's own population"    "registered worktree"                  0
    chk "...and says nobody looked, not nothing there" "It is 'nobody looked'"                0

    # THE CONTROL: the same zero, over a population that really was scanned, must still refuse.
    # Without it the fix above could simply delete the verdict.
    cat > "$dir/fakelog" <<'LOG'
[reap] no worktrees under /nowhere/tmp/ — 0 of 1 registered worktree(s) are under this root
LOG
    # The REAPER is stubbed here and only here: a population of exactly 1 cannot be built from
    # real worktrees inside a repo that already has 221. The arm above runs the real one.
    mkdir -p "$dir/stub/tools"
    cp "$self" "$dir/stub/tools/"
    printf '#!/usr/bin/env bash\ncat %s\nexit 0\n' "$dir/fakelog" > "$dir/stub/tools/reap_release_worktrees.sh"
    chmod +x "$dir/stub/tools/reap_release_worktrees.sh"
    out="$(cd "$dir/stub" && ./tools/reap_probe.sh 4091 "$dir/p3.log" "$dir/stub" 2>&1)"
    chk "a zero over a SCANNED population still refuses" "CANNOT CLEAR THIS FLOOR"           0
    chk "...and that refusal is not the blind one"        "COULD NOT SEE THIS LANE"           1

    # AND THE AFFIRMATIVE SIDE. The reaper is stubbed again, and deliberately:
    #
    # ⛔ The first version of this arm built a REAL detached worktree at a real tag and
    # asserted /removable tree/. It passed on the WRONG BRANCH — the refusal text says "has 0
    # removable trees", which contains that substring. The fixture was also a single tree, so
    # the reaper's default --keep 2 protected it and there was never a candidate to count; the
    # arm was green over a verdict that said the opposite. Two mistakes, one green tick.
    #
    # ⛔ And it cost a ~2.3 GB checkout ON EVERY PUBLISH, since the chain runs this selftest.
    # What this arm owns is the PROBE'S FORMATTING of the candidate branch. That the reaper
    # really names candidates is the reaper's own selftest's job, and the blind arm above runs
    # the real reaper against the real population.
    mkdir -p "$dir/stubhit/tools"
    cp "$self" "$dir/stubhit/tools/"
    cat > "$dir/stubhit/tools/reap_release_worktrees.sh" <<'STUB'
#!/usr/bin/env bash
echo "  would remove pub600              3.8G"
echo "  would remove pub601              3.7G"
echo "[reap] 2 candidate(s) under tmp/ (release prefix tmp/pub); keep=2; apply=0"
exit 0
STUB
    chmod +x "$dir/stubhit/tools/reap_release_worktrees.sh"
    out="$(cd "$dir/stubhit" && ./tools/reap_probe.sh 4091 "$dir/p5.log" "$dir/stubhit" 2>&1)"
    chk "candidates are COUNTED exactly"               "names 2 removable tree"               0
    chk "...not reported as a zero"                    "has 0 removable"                      1
    chk "...the shortfall is carried through"          "4091 MB shortfall"                    0
    chk "...the apply line carries the root it used"   "REAP_ROOT=$dir/stubhit .*--apply"     0
    chk "...and it still refuses to claim megabytes"   "count is trees, not megabytes"        0

    # THE DERIVATION, AS A RULE RATHER THAN AS WHATEVER THIS DIRECTORY HAPPENS TO BE. The first
    # version of this arm compared _lane_root against the fixture it had just built — and the
    # fixture lived under the lane's OWN tmp/, so the rule returned the real lane root and the
    # arm red on correct behaviour. A derivation is a function of a string: test the string.
    lane_case() { # name input want
        local got; got="$(_lane_root "$2")"
        if [ "$got" = "$3" ]; then pass=$((pass+1)); printf '  ok    %-56s\n' "$1"
        else fail=$((fail+1)); printf '  FAIL  %-56s (got %s, want %s)\n' "$1" "$got" "$3"; fi
    }
    lane_case "a release worktree -> its lane"      /home/x/lane-wt/tmp/pub658            /home/x/lane-wt
    lane_case "a NESTED release worktree -> OUTER"  /home/x/lane-wt/tmp/wt-raw/tmp/pub658 /home/x/lane-wt
    lane_case "a lane checkout -> itself"           /home/x/lane-wt                       /home/x/lane-wt
    lane_case "a path that IS under /tmp -> itself" /tmp/scratch/lane/tmp/pub1            /tmp/scratch/lane/tmp/pub1
    lane_case "no tmp component -> itself"          /home/x/other/tools                   /home/x/other/tools

    echo
    echo "selftest: ${pass} passed, ${fail} failed"
    [ "$fail" -eq 0 ]
}

case "${1:-}" in
    --selftest)    selftest ;;
    --source-only) : ;;
    ''|-*)         echo "usage: $0 <shortfall-mb> [reap-log] | --selftest" >&2; exit 2 ;;
    *)             probe "$1" "${2:-}" "${3:-}" ;;
esac
