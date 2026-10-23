#!/usr/bin/env bash
# Is the store actually current? Answers across ALL THREE channels, not one.
#
# WHY THIS EXISTS
# ---------------
# Every hour on 2026-09-09 I answered "is the store behind?" with:
#
#     LIVE=$(butler status … | grep '^| linux' | grep -oE 'v3\.33\.[0-9]+-alpha')
#     [ "$TAG" = "$LIVE" ] && echo CURRENT
#
# That reads ONE channel and calls it the store. During the .265-.267 window, when web was
# blocked on a RED and sat three tags behind linux for hours, this would have printed CURRENT
# every time. It also printed CURRENT mid-publish, with linux and windows on the new tag and
# web still on the old one — which is how it was finally caught.
#
# The failure direction is the bad one: it under-reports work to be done. A lane whose job is
# "notice the store is behind" had a currency check that could not see two thirds of the store.
#
# THE RULE IT ENCODES
# -------------------
# CURRENT means every channel is on the newest tag. Anything else names the laggards. A
# partial store is a distinct state from a current one and from a behind-one — mid-publish and
# blocked-channel look identical from the outside, so the tool reports the split and lets the
# reader decide.
#
# Usage:  tools/store_status.sh                      query butler and origin live
#         tools/store_status.sh <status-file> <tag>  judge a captured status against a tag
#         tools/store_status.sh --selftest
# Exit:   0 all current · 1 behind with nothing queued · 2 could not determine
#         3 PENDING: every behind channel has OUR build queued, not yet serving

set -uo pipefail

CHANNELS="linux windows web"
TARGET="struktured/cowardly-irregular"

# Overridable so the BLOCKED re-sample path is testable without touching itch.
STORE_BUTLER="${STORE_BUTLER:-butler}"
STORE_RECHECK_DELAY="${STORE_RECHECK_DELAY:-15}"
# How many re-samples a BLOCKED first read gets before it is believed. The budget is
# DELAY x MAX = 120s by default, sized from the queued->serving HANDOFF gap, NOT from itch's
# processing time: three gaps measured 2026-10-14..23 were each >15s and the bounded ones <=60s
# (.700 windows: BLOCKED 21:57:21Z, CURRENT 21:58:21Z), so 120s is twice the worst seen.
# Processing (42-168 min) is irrelevant here -- a processing build is QUEUED, and queued
# already reads PENDING without any re-sample. Counted in SAMPLES, not clock time, so the
# selftest can run it at DELAY=0 and assert an exact butler call count.
STORE_RECHECK_MAX="${STORE_RECHECK_MAX:-8}"

# judge() already fails CLOSED on an empty tag (return 2, "no tag to compare against"), so this
# was never a wrong-verdict defect the way publish_all.sh's was. What it could not do is say
# WHY the tag was empty: an unreachable origin, a dead ssh agent and a genuinely empty tag list
# all produced the same silent empty string, and the operator reading a BLOCKED(2) had nothing
# to act on. CLAUDE.md: don't 2>/dev/null a measurement command -- it deletes the warning and
# keeps the wrong number. Same change as publish_all.sh's resolver, and for the same reason:
# the reason goes to STDERR, which survives the command substitution every caller uses.
_newest_tag() {
    local raw ec t
    raw="$(git ls-remote --tags origin 'refs/tags/v3.33.*' 2>&1)"; ec=$?
    if [ "$ec" -ne 0 ]; then
        echo "[store] origin UNREACHABLE: git ls-remote exited ${ec}: $(printf '%s' "$raw" | head -2 | tr '\n' ' ')" >&2
        return 1
    fi
    t="$(printf '%s\n' "$raw" | grep -v '\^{}' | awk '{print $2}' | sed 's#refs/tags/##' | sort -V | tail -1)"
    if [ -z "$t" ]; then
        echo "[store] origin ANSWERED but no refs/tags/v3.33.* tag parsed from its reply." >&2
        return 2
    fi
    printf '%s' "$t"
}

# A channel's row can WRAP: butler prints a queued build on continuation lines whose channel
# column is blank. Measured on the real v3.33.675-alpha split (2026-10-13):
#
#   | web     | #16306641 | ✓ #2118363 (from #2118252)     | v3.33.674-alpha+bd2bfdee1 |
#   |         |           |   #2118874 (queued) (from      |                           |
#   |         |           | #2118363)                      |                           |
#
# So a LINE-scoped grep for the channel cannot see its own queued build. This takes the channel's
# ROW BLOCK -- its header line plus every following continuation line -- and stops at the next
# channel row or the table rule. Prints the queued build id, or nothing.
_queued_build_for() {
    local status_file="$1" ch="$2"
    awk -v ch="$ch" '
        $0 ~ "^\\| *" ch " "        { inblk = 1; print; next }
        inblk && /^\+/              { exit }
        inblk && /^\| *[A-Za-z]/    { exit }
        inblk                        { print }
    ' "$status_file" | grep -oE '#[0-9]+ \(queued\)' | grep -oE '#[0-9]+' | head -1
}

judge() {
    local status_file="$1" tag="$2"

    if [ -z "$tag" ]; then
        echo "[store] BLOCKED: no tag to compare against — cannot determine currency." >&2
        return 2
    fi
    if [ ! -s "$status_file" ]; then
        echo "[store] BLOCKED: butler status produced nothing (${status_file})." >&2
        echo "        An empty status is not an up-to-date store." >&2
        return 2
    fi

    local behind="" seen=0 ch ver
    for ch in $CHANNELS; do
        # Anchored on the channel column so a version appearing anywhere else in the table —
        # butler's own upgrade banner carries version strings — cannot be mistaken for a build.
        ver="$(grep -aE "^\| *${ch} " "$status_file" | grep -oE 'v3\.33\.[0-9]+-alpha' | head -1)"
        if [ -z "$ver" ]; then
            echo "[store] BLOCKED: channel '${ch}' not found in the status output." >&2
            echo "        A missing channel is not a current one." >&2
            return 2
        fi
        seen=$((seen+1))
        if [ "$ver" = "$tag" ]; then
            printf '[store]   %-8s %s\n' "$ch" "$ver"
        else
            printf '[store]   %-8s %s   <- BEHIND (%s)\n' "$ch" "$ver" "$tag"
            behind="${behind}${behind:+ }${ch}"
        fi
    done

    if [ "$seen" -ne 3 ]; then
        echo "[store] BLOCKED: read ${seen} channels, expected 3." >&2
        return 2
    fi
    if [ -n "$behind" ]; then
        # ⛔ A QUEUED BUILD IS NOT A FAILED ONE. Measured 2026-10-13 on v3.33.675-alpha: the web
        # push SUCCEEDED (butler: "3.28 MiB patch, Build is now processing") and itch took
        # 42 MINUTES to serve it. This check sampled 20 minutes in, said BEHIND, and publish_all
        # exited 1 on a sound build. The old comment at publish_all.sh:1173 claimed immunity to
        # processing lag "because it runs after the last push" -- the lag is ITCH-SIDE and
        # continues long after the push returns.
        #
        # The distinction is in butler's own output and costs nothing to read:
        #   behind + OUR build queued  -> PENDING (3). Pushed, accepted, not yet serving.
        #   behind + nothing queued    -> BLOCKED (1). That channel did not ship.
        # This does NOT loosen the currency rule: PENDING is still not CURRENT, still non-zero,
        # and a caller that treats non-zero as "do not claim success" is unchanged by it.
        local pending="" unqueued="" qb
        for ch in $behind; do
            qb="$(_queued_build_for "$status_file" "$ch")"
            if [ -n "$qb" ]; then
                pending="${pending}${pending:+ }${ch}:${qb}"
            else
                unqueued="${unqueued}${unqueued:+ }${ch}"
            fi
        done
        if [ -z "$unqueued" ]; then
            echo "[store] PENDING at ${tag}: ${pending} — pushed and accepted, not yet serving."
            echo "        itch is still processing. This is NOT a failed upload; re-check before concluding."
            return 3
        fi
        echo "[store] BEHIND at ${tag}: ${behind}"
        [ -n "$pending" ] && echo "[store]   (of these, queued and merely pending: ${pending})"
        echo "[store]   NOT queued, did not ship: ${unqueued}"
        return 1
    fi
    echo "[store] CURRENT: all 3 channels at ${tag}"
    return 0
}

selftest() {
    local dir pass=0 fail=0 saw0=0 saw1=0 saw2=0 saw3=0 self
    self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    dir="$(mktemp -d "${TMPDIR:-/tmp}/storestatus.XXXXXX")"
    # shellcheck disable=SC2064
    trap "rm -rf '$dir'" EXIT

    # Fixtures carry butler's real furniture — the upgrade banner holds version-shaped strings
    # that a loose grep would happily read as a build version.
    local BANNER='+-----------------------------------+
|       New version available       |
| Current version: 15.24.0 (stable) |
+-----------------------------------+
| CHANNEL  |  UPLOAD   |    BUILD    |   VERSION   |'

    mk() { printf '%s\n%s\n' "$BANNER" "$1" > "$dir/status.txt"; }

    arm() { # name want-exit status-body tag
        local name="$1" want="$2" got
        mk "$3"
        "$self" "$dir/status.txt" "$4" >/dev/null 2>&1
        got=$?
        [ "$got" -eq 0 ] && saw0=1; [ "$got" -eq 1 ] && saw1=1; [ "$got" -eq 2 ] && saw2=1; [ "$got" -eq 3 ] && saw3=1
        if [ "$got" -eq "$want" ]; then pass=$((pass+1)); printf '  ok    %-40s exit %s\n' "$name" "$got"
        else fail=$((fail+1)); printf '  FAIL  %-40s exit %s (wanted %s)\n' "$name" "$got" "$want"; fi
    }

    local ALL279='| linux    | #1 | ✓ #9 | v3.33.279-alpha+aaa |
| web      | #2 | ✓ #9 | v3.33.279-alpha+aaa |
| windows  | #3 | ✓ #9 | v3.33.279-alpha+aaa |'
    local WEBLAGS='| linux    | #1 | ✓ #9 | v3.33.279-alpha+aaa |
| web      | #2 | ✓ #9 | v3.33.276-alpha+bbb |
| windows  | #3 | ✓ #9 | v3.33.279-alpha+aaa |'
    local ONLYLINUX='| linux    | #1 | ✓ #9 | v3.33.279-alpha+aaa |'

    arm "all three current"                 0 "$ALL279"   v3.33.279-alpha
    arm "web behind (the .265-.267 case)"   1 "$WEBLAGS"  v3.33.279-alpha
    arm "all three behind"                  1 "$ALL279"   v3.33.280-alpha
    arm "a channel missing from the table"  2 "$ONLYLINUX" v3.33.279-alpha
    arm "no tag given"                      2 "$ALL279"   ""

    # ── THE THREE VERDICTS, FROM RECORDED BUTLER OUTPUT ──────────────────────────────────
    # Transcribed from the real v3.33.675-alpha split, 2026-10-13, INCLUDING ITS LINE WRAP: butler
    # puts the queued build on continuation rows whose channel column is blank, so a line-scoped
    # grep for "web" cannot see web's own queued build. That wrap is the whole reason the extractor
    # takes a row BLOCK, and a fixture without it would pass a line-scoped implementation.
    local REAL_PENDING='| linux   | #18690458 | ✓ #2118771 (from #2118316)     | v3.33.675-alpha+7411f5eef |
| web     | #16306641 | ✓ #2118363 (from #2118252)     | v3.33.674-alpha+bd2bfdee1 |
|         |           |   #2118874 (queued) (from      |                           |
|         |           | #2118363)                      |                           |
| windows | #18757510 | ✓ #2118809 (from #2118322)     | v3.33.675-alpha+7411f5eef |'
    # The same split with the queued rows removed: the channel is behind and nothing of ours is
    # waiting for it. That is a real failure and must stay a BLOCK.
    local REAL_BLOCKED='| linux   | #18690458 | ✓ #2118771 (from #2118316)     | v3.33.675-alpha+7411f5eef |
| web     | #16306641 | ✓ #2118363 (from #2118252)     | v3.33.674-alpha+bd2bfdee1 |
| windows | #18757510 | ✓ #2118809 (from #2118322)     | v3.33.675-alpha+7411f5eef |'
    # A queued build on a channel that is ALREADY current must not invent a PENDING.
    local QUEUED_BUT_CURRENT='| linux   | #18690458 | ✓ #2118771 (from #2118316)     | v3.33.675-alpha+7411f5eef |
| web     | #16306641 | ✓ #2118874 (from #2118363)     | v3.33.675-alpha+7411f5eef |
|         |           |   #2118999 (queued) (from      |                           |
|         |           | #2118874)                      |                           |
| windows | #18757510 | ✓ #2118809 (from #2118322)     | v3.33.675-alpha+7411f5eef |'

    arm "REAL .675 split, web queued -> PENDING"   3 "$REAL_PENDING"       v3.33.675-alpha
    arm "same split, nothing queued  -> BLOCKED"   1 "$REAL_BLOCKED"       v3.33.675-alpha
    arm "queued on an ALREADY-CURRENT channel"     0 "$QUEUED_BUT_CURRENT" v3.33.675-alpha

    # The PENDING line must NAME the build it is waiting on, or an operator cannot tell which
    # upload to watch. @cowir-main required this explicitly.
    # \u26d4 NOT a pipeline. Under `set -o pipefail` (line 32) the status of
    #   "$self" ... | grep -q X
    # is the FIRST non-zero, which for a PENDING fixture is store_status's own exit 3 -- so the
    # arm read 3, took the else branch, and reported "did not name the build id" while the text
    # was right there. The deliberate non-zero verdict defeated the test OF that verdict.
    # Capture once, match with a herestring, and the exit code cannot drown the grep.
    mk "$REAL_PENDING"
    local _pout; _pout="$("$self" "$dir/status.txt" v3.33.675-alpha 2>&1 || true)"
    # \u26d4 AND IT MUST BE THE *PENDING* LINE THAT NAMES IT. A bare "does the id appear anywhere"
    # arm passes under a mutation that deletes the PENDING branch entirely, because the BLOCKED
    # branch also prints "(of these, queued and merely pending: web:#2118874)". Measured: that
    # mutation red 1 arm instead of 2. Anchoring on the PENDING line makes the pair red together.
    if grep -q '^\[store\] PENDING .*web:#2118874' <<<"$_pout"; then
        pass=$((pass+1)); printf '  ok    %-40s PENDING line names web:#2118874\n' "PENDING names the queued build"
    else
        fail=$((fail+1)); printf '  FAIL  %-40s did not name the build id\n' "PENDING names the queued build"
    fi

    printf '%s\n' "$BANNER" > "$dir/status.txt"   # banner only, no channel rows
    "$self" "$dir/status.txt" v3.33.279-alpha >/dev/null 2>&1
    local g=$?; [ "$g" -eq 2 ] && saw2=1
    if [ "$g" -eq 2 ]; then pass=$((pass+1)); printf '  ok    %-40s exit %s\n' "banner only — versions must not match" "$g"
    else fail=$((fail+1)); printf '  FAIL  %-40s exit %s (wanted 2)\n' "banner only — versions must not match" "$g"; fi

    : > "$dir/status.txt"
    "$self" "$dir/status.txt" v3.33.279-alpha >/dev/null 2>&1
    g=$?; [ "$g" -eq 2 ] && saw2=1
    if [ "$g" -eq 2 ]; then pass=$((pass+1)); printf '  ok    %-40s exit %s\n' "empty status file" "$g"
    else fail=$((fail+1)); printf '  FAIL  %-40s exit %s (wanted 2)\n' "empty status file" "$g"; fi

    # ---- the BLOCKED re-sample path. judge() is a pure function of a captured file and
    # cannot re-sample, so these drive the NO-ARG entry point with a fake butler whose answer
    # CHANGES between calls. That is the only way to stage the pending->serving gap from
    # outside: stagger the FIXTURE, not the subject.
    local fake="$dir/fakebutler" ctr="$dir/calls" _tout _tec _calls
    _mkfake() {   # butler's answer on call 1, 2, ...; the LAST one repeats forever
        : > "$ctr"
        local i=0 body
        rm -f "$dir"/seq.*.txt
        for body in "$@"; do
            i=$((i+1)); printf '%s\n%s\n' "$BANNER" "$body" > "$dir/seq.$i.txt"
        done
        cat > "$fake" <<FAKE
#!/usr/bin/env bash
n=\$(( \$(cat "$ctr" 2>/dev/null || echo 0) + 1 ))
echo "\$n" > "$ctr"
k=\$n; [ "\$k" -gt $i ] && k=$i
cat "$dir/seq.\$k.txt"
FAKE
        chmod +x "$fake"
    }
    _rsarm() {  # name want-ec want-calls must-match must-NOT-match
        local name="$1" wec="$2" wcalls="$3" yes="$4" no="$5"
        _calls="$(cat "$ctr" 2>/dev/null || echo 0)"
        local bad=""
        [ "$_tec" -eq "$wec" ]      || bad="exit $_tec (wanted $wec)"
        [ "$_calls" -eq "$wcalls" ] || bad="${bad}${bad:+; }butler called $_calls (wanted $wcalls)"
        if [ -n "$yes" ] && ! grep -q "$yes" <<<"$_tout"; then bad="${bad}${bad:+; }missing '$yes'"; fi
        if [ -n "$no" ]  &&   grep -q "$no"  <<<"$_tout"; then bad="${bad}${bad:+; }unexpected '$no'"; fi
        [ "$_tec" -eq 0 ] && saw0=1; [ "$_tec" -eq 1 ] && saw1=1
        if [ -z "$bad" ]; then pass=$((pass+1)); printf '  ok    %-40s exit %s, %s butler call(s)\n' "$name" "$_tec" "$_calls"
        else fail=$((fail+1)); printf '  FAIL  %-40s %s\n' "$name" "$bad"; fi
    }
    _rs() {  # MAX, then the butler sequence
        local max="$1"; shift
        _mkfake "$@"
        _tout="$(STORE_BUTLER="$fake" STORE_RECHECK_DELAY=0 STORE_RECHECK_MAX="$max" STORE_TAG="${_rstag:-v3.33.279-alpha}" "$self" 2>&1)"; _tec=$?
    }

    # 1) The transient: sample 1 BLOCKED, sample 2 CURRENT -> report the re-sample.
    _rs 8 "$WEBLAGS" "$ALL279"
    _rsarm "transient BLOCK -> reports re-sample" 0 2 'first sample read BLOCKED' 'past the handoff budget'

    # 2) THE DEFECT THIS POLL EXISTS FOR: the gap outlasts ONE re-sample (the .698/.700 case,
    #    BLOCKED at +0s and +15s, CURRENT at +60s). The old single re-sample exited 1 here
    #    after 2 calls and called it "confirmed by TWO samples".
    _rs 8 "$WEBLAGS" "$WEBLAGS" "$WEBLAGS" "$ALL279"
    _rsarm "gap outlasting one re-sample -> CURRENT" 0 4 'first sample read BLOCKED' 'past the handoff budget'

    # 3+4) THE DEADLINE, PINNED FROM BOTH SIDES with one sequence (3 BLOCKED, then serving):
    #    a budget of 3 re-samples just reaches the serving sample -> CURRENT, 4 calls;
    #    a budget of 2 stops one short                          -> BLOCKED, 3 calls.
    #    An off-by-one in the loop bound reds exactly one of the pair.
    _rs 3 "$WEBLAGS" "$WEBLAGS" "$WEBLAGS" "$ALL279"
    _rsarm "serving ON the last allowed sample" 0 4 'first sample read BLOCKED' 'past the handoff budget'
    _rs 2 "$WEBLAGS" "$WEBLAGS" "$WEBLAGS" "$ALL279"
    _rsarm "serving one sample PAST the budget" 1 3 'past the handoff budget' 'first sample read BLOCKED'

    # 5) A real block survives the whole budget and says how long it waited.
    _rs 3 "$WEBLAGS"
    _rsarm "persistent BLOCK stays BLOCKED" 1 4 'BLOCKED on all 4 samples' 'first sample read BLOCKED'

    # 6) The old wording claimed a gap had been ruled out. It must be gone.
    if grep -q 'confirmed by TWO samples' <<<"$_tout"; then
        fail=$((fail+1)); printf '  FAIL  %-40s still prints it\n' "no 'confirmed by TWO samples' claim"
    else
        pass=$((pass+1)); printf '  ok    %-40s absent\n' "no 'confirmed by TWO samples' claim"
    fi

    # 7) A re-sample that turns PENDING ends the poll and reports PENDING (3), not BLOCKED.
    _rstag=v3.33.675-alpha _rs 8 "$REAL_BLOCKED" "$REAL_PENDING"
    _rsarm "gap then queued -> PENDING" 3 2 '^\[store\] PENDING' 'past the handoff budget'
    [ "$_tec" -eq 3 ] && saw3=1

    # 8) CONTROL -- the poll must be CONDITIONAL on verdict 1. A CURRENT first sample costs
    #    exactly ONE butler call; hoisting the poll above the `[ "$ec" -ne 1 ]` check would
    #    keep every verdict above and change only this count.
    _rs 8 "$ALL279" "$WEBLAGS"
    _rsarm "CURRENT does not re-sample" 0 1 '' 're-sample'

    echo
    echo "selftest: ${pass} passed, ${fail} failed"
    if [ "$saw0" -ne 1 ] || [ "$saw1" -ne 1 ] || [ "$saw2" -ne 1 ] || [ "$saw3" -ne 1 ]; then
        echo "selftest: BROKEN — outcomes seen: current=${saw0} behind=${saw1} undetermined=${saw2} pending=${saw3}; all four required" >&2
        return 1
    fi
    [ "$fail" -eq 0 ]
}

case "${1:-}" in
    --selftest) selftest ;;
    "")         tmp="$(mktemp)"; tmp2="$(mktemp)"; trap 'rm -f "$tmp" "$tmp2"' EXIT
                # The tag is resolved ONCE. Re-resolving it per sample would let a tag cut
                # between the two samples change the SUBJECT of the comparison, so the
                # re-check would answer a different question than the one that failed.
                tag="${STORE_TAG:-$(_newest_tag)}"
                "$STORE_BUTLER" status "$TARGET" > "$tmp" 2>&1
                out="$(judge "$tmp" "$tag" 2>&1)"; ec=$?
                # ⛔ BLOCKED (1) IS THE ONE VERDICT THAT MUST NOT REST ON A SINGLE SAMPLE.
                # Measured 2026-10-14 on v3.33.693-alpha web: at 20:33:12Z this read
                # "NOT queued, did not ship: web" (exit 1); at 20:33:24Z, and twice more,
                # it read CURRENT. There is a window between "queued and pending" and
                # "serving" in which the build is in NEITHER set, and judge() classifies
                # that as "did not ship".
                #
                # The direction is what makes it worth code rather than a note: this is a
                # transient FALSE BLOCK on the ordinary success path, and the documented
                # response to a BLOCK is a repair publish. So a single sample can send the
                # lane to re-publish a channel that was already fine.
                #
                # CURRENT (0), PENDING (3) and UNDETERMINED (2) return immediately: none of
                # them asks the caller to act destructively, and PENDING already tells the
                # reader to re-check.
                if [ "$ec" -ne 1 ]; then printf '%s\n' "$out"; exit "$ec"; fi
                # ⛔ ONE RE-SAMPLE 15s LATER DID NOT COVER THE GAP. It fired falsely three
                # times (.698 web, .700 linux, .700 windows): BLOCKED on both samples, CURRENT
                # a minute later, and the old message called that "confirmed by TWO samples --
                # not the pending->serving gap", which is exactly what it was. So the re-sample
                # is now a bounded poll: the first non-BLOCKED sample is reported, and BLOCKED
                # is believed only once the whole handoff budget has passed without one.
                #
                # butler has no per-build state query (only `status` and `fetch`), so a build
                # in the gap and a channel that was never pushed are indistinguishable from
                # one sample. Both get the same poll; a real BLOCK costs at most the budget in
                # latency, never a different verdict.
                n=0 ec2=1 out2="$out"
                while [ "$ec2" -eq 1 ] && [ "$n" -lt "$STORE_RECHECK_MAX" ]; do
                    sleep "$STORE_RECHECK_DELAY"
                    n=$((n+1))
                    "$STORE_BUTLER" status "$TARGET" > "$tmp2" 2>&1
                    out2="$(judge "$tmp2" "$tag" 2>&1)"; ec2=$?
                done
                printf '%s\n' "$out2"
                waited=$((n * STORE_RECHECK_DELAY))
                if [ "$ec2" -ne 1 ]; then
                    echo "[store] note: a first sample read BLOCKED; re-sample ${n} (~${waited}s later) did not."
                    echo "[store]       Reporting the re-sample. The first sample said:"
                    printf '%s\n' "$out" | sed 's/^/[store]         /'
                    exit "$ec2"
                fi
                echo "[store] BLOCKED on all $((n+1)) samples over ~${waited}s -- past the handoff budget"
                echo "[store]       (gap measured >15s and <=60s), so this channel did not ship."
                exit "$ec2" ;;
    *)          judge "$1" "${2:-}" ;;
esac
