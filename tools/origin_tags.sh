#!/usr/bin/env bash
# The ONE place that asks origin for its newest v3.33.* tag. Sourced by publish_all.sh,
# store_status.sh and reap_release_worktrees.sh; run directly only for --selftest.
#
# WHY THIS EXISTS
# ---------------
# `git ls-remote --tags origin 'refs/tags/v3.33.*'` can answer SHORT with exit code 0.
# Measured 2026-10-23: 978 lines instead of 1160, every tag after .616 (or .674) missing, same
# last line, nothing on stderr. It is bursty, not a steady rate. That one mechanism had three
# separate resolvers, and each was patched apart by whoever was standing there:
#
#   publish_all.sh  .699's first publish aborted "SUPERSEDED ... by v3.33.616-alpha" and the
#                   second split the store. Fixed in .700 by re-asking until $TAG is listed.
#   store_status.sh .701's publish ended ec 1, "BEHIND (v3.33.674-alpha)" on all three channels
#                   while all three were SERVING .701. Not fixed until this file.
#   reap_*.sh       protects the worktree at the newest tag. A short reply moves that guard
#                   onto an older tree, which is the direction a tool that deletes must not go.
#
# Three sites of one mechanism means the fourth gets written next. So the reply is judged
# here, once, against two invariants, and every caller gets the same verdict.
#
# THE TWO INVARIANTS (a reply that breaks either is STALE: re-asked, then UNKNOWN)
#   WANT   a tag the caller knows exists must be listed. Only publish_all has one (its $TAG,
#          which the evidence gate already found on origin), so this covers that caller alone.
#   FLOOR  the newest tag cannot be OLDER than a version the caller has seen shipped. We only
#          publish tags, so a store serving .701 rules out a newest tag of .674. This is the
#          ONLY cover for a standalone store_status run, which has no WANT to pass. It is
#          load-bearing, not belt-and-braces.
#   The FLOOR is why .701's false red was visible at all: the resolver failed silently and the
#   only clue was a verdict contradicting a second, independently obtained fact. A resolver
#   that fails silently is caught by checking it against another source, not by more logging.
#
# ⚠️ KNOWN EDGE, written down so nobody debugs it twice: a tag DELETED from origin while its
#    build is still served makes the FLOOR contradiction PERMANENT (the store legitimately
#    serves a version newer than every tag). It fails toward UNKNOWN, never BEHIND, which is
#    the right direction. We do re-cut tags here (.699's was force-pushed, target unchanged);
#    a re-cut keeps the name, so only an outright delete hits this.
#
# ⛔ THE COMPARATOR IS A HAZARD ON ITS OWN. Versions compare per component, numerically
#    (`sort -V`). A string compare puts v3.33.99 above v3.33.701 and passes every test built
#    from tags that happen to sort both ways alike, so the selftest has arms where lexical and
#    numeric order DISAGREE.
#
# API:   origin_newest_tag LABEL [WANT] [FLOOR]
#        stdout  the newest v3.33.* tag on the success path, nothing otherwise
#        return  0 resolved · 1 origin unreachable · 2 answered, no v3.33.* tag parsed
#                3 STALE: broke an invariant on every one of OT_RETRIES replies (UNKNOWN)
#        The reason goes to STDERR, prefixed "[LABEL]": every caller runs this inside $(...),
#        so a global set here would die with the subshell, and stderr is what reaches the log.
# Env:   OT_GIT (git) · OT_REMOTE (origin) · OT_RETRIES (3)
#        OT_RETRY_DELAY (falls back to PUB_STALE_RETRY_DELAY, then 2s)
#
# Usage: tools/origin_tags.sh --selftest

# Is $1 strictly older than $2? Per-component numeric, never a string compare.
_ot_older() {
    [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]
}

origin_newest_tag() {
    local label="${1:-tags}" want="${2:-}" floor="${3:-}"
    local tries="${OT_RETRIES:-3}" delay="${OT_RETRY_DELAY:-${PUB_STALE_RETRY_DELAY:-2}}"
    local raw refs ec t try why
    for try in $(seq 1 "$tries"); do
        raw="$("${OT_GIT:-git}" ls-remote --tags "${OT_REMOTE:-origin}" 'refs/tags/v3.33.*' 2>&1)"; ec=$?
        if [ "$ec" -ne 0 ]; then
            echo "[${label}] origin UNREACHABLE: git ls-remote exited ${ec}: $(printf '%s' "$raw" | head -2 | tr '\n' ' ')" >&2
            return 1
        fi
        # ⛔ SHAPE BEFORE ORDER. `raw` is captured with 2>&1, so a `remote: warning ...` line sits
        # in it beside the refs, and the old parse (`awk '{print $2}' | sort -V | tail -1`) took
        # ANY second field. "warning" sorts above every v3.33 tag, so it came back as the newest
        # with ec 0 -- and neither invariant could see it: WANT found its tag elsewhere in the
        # reply, and FLOOR can only catch junk that sorts BELOW it. Measured by @cowir-main on
        # 5e60cd640, all five WANT/FLOOR combinations. Both invariants judge ORDER and
        # COMPLETENESS (the truncation's axis); this judges SHAPE, a different axis.
        # A ref line is a 40-hex sha and refs/tags/v3.33.<N>-alpha -- every one of origin's
        # 672 tags on 2026-10-24, and the only form butler's versions are read in. The anchored
        # `$` also drops the peeled ^{} lines. WANT is checked against THESE lines, not the raw
        # reply, so a `remote:` line quoting the wanted ref cannot vouch for a short list.
        # ⚠️ THAT COUNT IS 672, NOT 1164/2 = 582 (@cowir-main, re-measured live at the fold). Only
        # 492 of origin's v3.33 tags are ANNOTATED and carry a second ^{} line; the other 180 are
        # lightweight and carry one. 492*2 + 180 = 1164, so halving the line count is wrong by 90.
        # Derive a tag count from DISTINCT NAMES (`sed 's#\^{}$##' | sort -u`), never from lines.
        # The shape claim itself re-verified: 0 exceptions across all 672 names.
        refs="$(printf '%s\n' "$raw" | awk 'length($1) == 40 && $1 ~ /^[0-9a-f]+$/ && $2 ~ /^refs\/tags\/v3\.33\.[0-9]+-alpha$/ { print $2 }')"
        # Split assignment: `local t=$(...)` would discard the status, and the -z test below is
        # what classifies "answered but unparseable" rather than the pipeline's own code.
        t="$(printf '%s\n' "$refs" | sed 's#refs/tags/##' | sort -V | tail -1)"
        if [ -z "$t" ]; then
            echo "[${label}] origin ANSWERED but no line of its reply is a v3.33.<N>-alpha tag ref: $(printf '%s' "$raw" | head -2 | tr '\n' ' ')" >&2
            return 2
        fi
        why=""
        # Exact field match: a grep pattern would read the tag's dots as wildcards.
        if [ -n "$want" ] && ! printf '%s\n' "$refs" | awk -v w="refs/tags/${want}" '$1 == w { f = 1 } END { exit !f }'; then
            why="${want} not among them"
        elif [ -n "$floor" ] && _ot_older "$t" "$floor"; then
            why="its newest ${t} is OLDER than ${floor}, which has already shipped"
        fi
        if [ -z "$why" ]; then
            printf '%s' "$t"
            return 0
        fi
        echo "[${label}] origin reply ${try}/${tries} is STALE: $(printf '%s\n' "$raw" | wc -l) line(s), ${why}." >&2
        [ "$try" -lt "$tries" ] && sleep "$delay"
    done
    echo "[${label}] origin never gave a consistent tag list in ${tries} replies -- newest tag UNKNOWN." >&2
    echo "[${label}]   An inconsistent reply is not a newer tag and not an older store; nothing is concluded from it." >&2
    return 3
}

_ot_selftest() {
    local dir pass=0 fail=0 seen0=0 seen1=0 seen2=0 seen3=0
    dir="$(mktemp -d "${TMPDIR:-/tmp}/origintags.XXXXXX")"
    # shellcheck disable=SC2064
    trap "rm -rf '$dir'" EXIT

    # Replies are built from tag lists the way origin prints them: an annotated tag line plus
    # its peeled ^{} line, so the ^{} filter is exercised and not just the happy shape.
    _reply() { local n; for n in "$@"; do
        printf '%040d\trefs/tags/v3.33.%s-alpha\n%040d\trefs/tags/v3.33.%s-alpha^{}\n' 0 "$n" 1 "$n"
    done; }
    _reply 615 616 673 674 699 700 701 > "$dir/full"
    _reply 615 616 673 674                > "$dir/short674"
    _reply 98 99                          > "$dir/top99"
    _reply 99 674                         > "$dir/mixed"
    _reply 615 616 673 674 700            > "$dir/top700"
    : > "$dir/empty"

    local fake="$dir/git" ctr="$dir/calls"
    _mkgit() {   # each arg: a reply file name, or "fail"; the LAST one repeats forever
        : > "$ctr"
        printf '%s\n' "$@" > "$dir/seq"
        cat > "$fake" <<FAKE
#!/usr/bin/env bash
n=\$(( \$(cat "$ctr" 2>/dev/null || echo 0) + 1 )); echo "\$n" > "$ctr"
k=\$(wc -l < "$dir/seq"); [ "\$n" -lt "\$k" ] && k=\$n
r=\$(sed -n "\${k}p" "$dir/seq")
[ "\$r" = fail ] && { echo "fatal: Could not read from remote repository." >&2; exit 128; }
cat "$dir/\$r"
FAKE
        chmod +x "$fake"
    }
    # name · want-ec · want-stdout · want-calls · WANT · FLOOR · reply sequence...
    _arm() {
        local name="$1" wec="$2" wout="$3" wcalls="$4" want="$5" floor="$6"; shift 6
        _mkgit "$@"
        local out ec calls bad=""
        out="$(OT_GIT="$fake" OT_RETRY_DELAY=0 origin_newest_tag selftest "$want" "$floor" 2>"$dir/err")"; ec=$?
        calls="$(cat "$ctr")"
        [ "$ec" -eq "$wec" ]       || bad="exit $ec (wanted $wec)"
        [ "$out" = "$wout" ]       || bad="${bad}${bad:+; }stdout '$out' (wanted '$wout')"
        [ "$calls" -eq "$wcalls" ] || bad="${bad}${bad:+; }ls-remote called $calls (wanted $wcalls)"
        # Every non-zero verdict must say why, on stderr, or the operator reads a bare exit code.
        if [ "$ec" -ne 0 ] && ! [ -s "$dir/err" ]; then bad="${bad}${bad:+; }no reason on stderr"; fi
        case "$ec" in 0) seen0=1 ;; 1) seen1=1 ;; 2) seen2=1 ;; 3) seen3=1 ;; esac
        if [ -z "$bad" ]; then pass=$((pass+1)); printf '  ok    %-46s exit %s, %s call(s)\n' "$name" "$ec" "$calls"
        else fail=$((fail+1)); printf '  FAIL  %-46s %s\n' "$name" "$bad"; fi
    }
    local T=v3.33.701-alpha

    _arm "full reply, no invariants"                 0 "$T" 1 ""  ""                full
    _arm "unreachable origin"                        1 ""   1 ""  ""                fail
    _arm "answered, no v3.33 tag"                    2 ""   1 ""  ""                empty
    # WANT, the publish_all invariant
    _arm "WANT: short then full -> re-asked"         0 "$T" 2 "$T" ""               short674 full
    _arm "WANT: short x3 -> UNKNOWN"                 3 ""   3 "$T" ""               short674
    # FLOOR, the only cover for a standalone store_status run
    _arm "FLOOR: short then full -> re-asked"        0 "$T" 2 ""  "$T"              short674 full
    _arm "FLOOR: short x3 -> UNKNOWN"                3 ""   3 ""  "$T"              short674
    _arm "FLOOR equal to newest is consistent"       0 "$T" 1 ""  "$T"              full
    # THE TWIN THAT KEEPS A TRUE 'BEHIND' POSSIBLE: a genuinely newer tag over an older floor
    # is the ordinary case store_status exists to report. An eager FLOOR would re-ask it.
    _arm "FLOOR below newest: no re-ask"             0 "$T" 1 ""  v3.33.700-alpha   full
    # LEXICAL vs NUMERIC DISAGREE: as strings ".99" > ".674"; as versions it is far older.
    _arm "FLOOR .674 vs top .99 -> STALE (numeric)"  3 ""   3 ""  v3.33.674-alpha   top99
    _arm "FLOOR .99 vs top .674 -> consistent"       0 v3.33.674-alpha 1 "" v3.33.99-alpha short674
    _arm "newest of {.99,.674} is .674"              0 v3.33.674-alpha 1 "" ""      mixed
    # WANT is checked by exact field match, not by the reply's top: a reply topping out ABOVE
    # the floor but missing the wanted tag is still stale.
    _arm "WANT missing though top >= FLOOR"          3 ""   3 "$T" v3.33.673-alpha  short674
    _arm "WANT present, FLOOR satisfied"             0 v3.33.700-alpha 1 v3.33.700-alpha v3.33.674-alpha top700
    # SHAPE: junk that sorts ABOVE every tag, in the merged 2>&1 capture. The old parse returned
    # "warning" / "zzz" / a quoted ref as the newest with ec 0, past both invariants.
    { echo "remote: warning: the remote end hung up on a slow client"; cat "$dir/full"; } > "$dir/warnfull"
    # SECOND fields: the old parse read only $2, so single-word junk lines never reached it and
    # an arm built from them passes with the filter removed (measured: it did).
    { cat "$dir/full"; echo "hint: zzz"; echo "remote: v9.9.9-alpha"; } > "$dir/zzzfull"
    { echo "remote: refs/tags/v3.33.999-alpha is being mirrored"; cat "$dir/full"; } > "$dir/quoted999"
    { echo "remote: refs/tags/v3.33.701-alpha is being mirrored"; cat "$dir/short674"; } > "$dir/quotedwant"
    { echo "remote: warning: nothing to see"; } > "$dir/onlyjunk"
    _arm "junk 'warning' above every tag is ignored"   0 "$T" 1 ""  ""              warnfull
    _arm "  ...with WANT and FLOOR set"                0 "$T" 1 "$T" v3.33.700-alpha warnfull
    _arm "'zzz' and 'v9.9.9-alpha' are ignored"        0 "$T" 1 ""  ""              zzzfull
    _arm "a remote: line quoting a ref is no tag"      0 "$T" 1 ""  ""              quoted999
    # ...and it cannot VOUCH for a short list by naming the wanted tag.
    _arm "quoted WANT does not vouch for a short list" 3 ""   3 "$T" ""             quotedwant
    _arm "only junk -> no tag (2), not a junk tag"     2 ""   1 ""  ""              onlyjunk
    # The retry budget is the env's, not a constant.
    _mkgit short674
    OT_GIT="$fake" OT_RETRY_DELAY=0 OT_RETRIES=5 origin_newest_tag selftest "$T" "" >/dev/null 2>&1
    if [ "$(cat "$ctr")" -eq 5 ]; then pass=$((pass+1)); printf '  ok    %-46s 5 call(s)\n' "OT_RETRIES=5 is honoured"
    else fail=$((fail+1)); printf '  FAIL  %-46s %s call(s)\n' "OT_RETRIES=5 is honoured" "$(cat "$ctr")"; fi

    echo
    echo "selftest: ${pass} passed, ${fail} failed"
    if [ "$seen0" -ne 1 ] || [ "$seen1" -ne 1 ] || [ "$seen2" -ne 1 ] || [ "$seen3" -ne 1 ]; then
        echo "selftest: BROKEN — verdicts seen: resolved=${seen0} unreachable=${seen1} none=${seen2} stale=${seen3}; all four required" >&2
        return 1
    fi
    [ "$fail" -eq 0 ]
}

# Sourced: define the functions and stop. Executed: the only supported entry is --selftest.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    case "${1:-}" in
        --selftest) _ot_selftest; exit $? ;;
        *)          echo "usage: $0 --selftest   (otherwise source it and call origin_newest_tag)" >&2; exit 2 ;;
    esac
fi
