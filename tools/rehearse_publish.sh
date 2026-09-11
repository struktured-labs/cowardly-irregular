#!/usr/bin/env bash
# rehearse_publish.sh — run publish_all against a CANDIDATE tree, before it is merged or tagged.
#
# WHY THIS EXISTS
# ---------------
# publish_all.sh §3 requires HEAD == TAG, because the chains export the WORKING TREE and
# publishing from a tree that is not the tag ships a mislabelled build. That rule is right and
# is not going anywhere. But it has a consequence nobody had written down:
#
#   ⛔ NO CHANGE TO THE PUBLISHER CAN BE TESTED THROUGH THE PUBLISHER UNTIL IT IS MERGED
#      AND A NEW TAG IS CUT AT THAT MERGE.
#
# A lane branch sits ABOVE the newest tag by construction, so `publish_all --check <tag>` from
# it exits 2 at the tree-identity gate. Three blocking gates were added to publish_all this
# week (polling-bounded, publish-is-opt-in, unknown-option rejection). Each was tested in
# isolation, byte-exact. None could be run through publish_all. They would have executed for
# the first time during a real publish — which is the one moment a false positive costs the
# cadence.
#
# This is the composition blind spot stated generally: every piece verified, the assembly
# never, and the assembly only exists after release.
#
# WHAT THIS DOES
# --------------
# Clones the repo into a gitignored tmp/ dir, checks out the candidate ref, moves the newest
# tag onto it (PRESERVING the annotation, because §1 reads the tag message for gate evidence),
# and runs publish_all there. The real repo, the real tags, and origin are never written.
#
# CONTAINMENT, AND WHY IT IS PROVEN RATHER THAN TRUSTED
# -----------------------------------------------------
# This script exists to rehearse the one operation that ships software. So it does not merely
# point butler at a stub — it PROVES the stub is in force before every run:
#
#   * the stub is placed on PATH *and* exported as BUTLER_BIN (both resolution routes)
#   * pre-flight: `butler status` must log and return 0, `butler push` must log and return 97
#   * if either control fails, this script ABORTS without running publish_all
#
# The reason for the pre-flight is specific and was learned the hard way: an empty call log
# after a run is indistinguishable from a stub that was never installed. "No push happened"
# and "the instrument was never live" produce the same evidence. So the instrument is proven
# live BEFORE the measurement, never after.
#
# Usage:  tools/rehearse_publish.sh <ref> [--check|--dry-run]    default --check
#         tools/rehearse_publish.sh --selftest
# Exit:   whatever publish_all exited · 2 unusable setup · 9 CONTAINMENT CONTROL FAILED
set -uo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$PWD"

MODE="--check"
REF=""
for a in "$@"; do
    case "$a" in
        --selftest) SELFTEST=1 ;;
        --check|--dry-run) MODE="$a" ;;
        -*) echo "rehearse_publish: unknown option: $a" >&2
            echo "usage: tools/rehearse_publish.sh <ref> [--check|--dry-run]" >&2
            exit 2 ;;
        *)  REF="$a" ;;
    esac
done

WORK="${REHEARSE_DIR:-$REPO_ROOT/tmp/rehearse}"
STUB="$WORK/bin"
CALLS="$WORK/butler_calls.log"

_make_stub() {
    mkdir -p "$STUB"
    cat > "$STUB/butler" <<'STUBEOF'
#!/usr/bin/env bash
# Logs EVERY invocation, then REFUSES to push. Refusing loudly rather than succeeding quietly
# matters: a leak must surface as a RED, not as a run that looks clean.
printf '%s\n' "$*" >> "${BUTLER_STUB_LOG:?BUTLER_STUB_LOG unset}"
case "${1:-}" in
  push)   echo "STUB REFUSING PUSH: $*" >&2; exit 97 ;;
  status) printf '| CHANNEL | UPLOAD | BUILD | VERSION |\n| rehearsal | #0 | ok | v0.0.0-stub |\n'; exit 0 ;;
  *)      exit 0 ;;
esac
STUBEOF
    chmod +x "$STUB/butler"
}

# Returns 0 only if the stub is genuinely in force. Every failure here is fatal to the run.
_containment_control() {
    local resolved s p before after
    : > "$CALLS"
    before="$(wc -l < "$CALLS")"
    resolved="$(PATH="$STUB:$PATH" command -v butler)"
    if [ "$resolved" != "$STUB/butler" ]; then
        echo "[rehearse] CONTAINMENT FAILED: butler resolves to '$resolved', not the stub." >&2
        return 1
    fi
    # Invoke the stub BY PATH, not through $PATH resolution. Two separate assertions:
    # the check above proves `butler` RESOLVES to the stub; these prove the stub BEHAVES.
    # Routing them through $PATH conflated the two, and it also made this line read to a static
    # scanner as a bare `butler push` — which is exactly what it must not look like.
    BUTLER_STUB_LOG="$CALLS" "$STUB/butler" status probe >/dev/null 2>&1; s=$?
    BUTLER_STUB_LOG="$CALLS" "$STUB/butler" push probe target >/dev/null 2>&1; p=$?
    after="$(wc -l < "$CALLS")"
    if [ "$s" -ne 0 ]; then
        echo "[rehearse] CONTAINMENT FAILED: stub status returned $s, expected 0." >&2
        return 1
    fi
    if [ "$p" -ne 97 ]; then
        echo "[rehearse] CONTAINMENT FAILED: stub push returned $p, expected 97 (refusal)." >&2
        echo "           A stub that does not refuse is a stub that could publish." >&2
        return 1
    fi
    if [ "$((after - before))" -ne 2 ]; then
        echo "[rehearse] CONTAINMENT FAILED: the call log gained $((after - before)) line(s)," >&2
        echo "           expected 2. An unrecording stub makes 'no push happened' unprovable:" >&2
        echo "           it is indistinguishable from a stub that was never installed." >&2
        return 1
    fi
    echo "[rehearse] containment control: butler -> stub · status 0 · push 97 · both logged"
    : > "$CALLS"
    return 0
}

# Same expression as tools/check_version_matches_tag.sh:45, and the control below makes that
# shipped checker ratify the result rather than trusting the two to stay in step.
_semver_of() {
    sed -n 's/^[[:space:]]*const[[:space:]]\+SEMVER[[:space:]]*:=[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$1/src/meta/Version.gd" 2>/dev/null | head -1
}

_newest_tag_local() {
    git -C "$1" for-each-ref --sort=-creatordate --count=1 \
        --format='%(refname:short)' 'refs/tags/v3.33.*'
}

rehearse() {
    local ref="$1" mode="$2"
    [ -n "$ref" ] || { echo "usage: tools/rehearse_publish.sh <ref> [--check|--dry-run]" >&2; return 2; }

    rm -rf "$WORK"; mkdir -p "$WORK"
    _make_stub
    _containment_control || return 9

    echo "[rehearse] cloning $REPO_ROOT -> $WORK/repo"
    git clone -q --no-hardlinks "$REPO_ROOT" "$WORK/repo" || return 2
    # Mirror the real remote refs in, so _newest_tag_on_origin sees what it would really see.
    git -C "$WORK/repo" fetch -q "$REPO_ROOT" 'refs/remotes/origin/*:refs/remotes/origin/*' 2>/dev/null
    # Belt and braces: make any accidental push from inside the rehearsal fail loudly rather
    # than land in the real repo. Nothing here pushes, but "nothing here pushes" is a claim
    # about today's code.
    git -C "$WORK/repo" remote set-url --push origin "no-pushing-from-a-rehearsal" 2>/dev/null

    local sha; sha="$(git -C "$WORK/repo" rev-parse --verify -q "${ref}^{commit}" \
                      || git -C "$WORK/repo" rev-parse --verify -q "origin/${ref}^{commit}")"
    if [ -z "$sha" ]; then
        echo "[rehearse] BLOCKED: '$ref' does not resolve to a commit in the clone." >&2
        return 2
    fi
    git -C "$WORK/repo" checkout -q --detach "$sha" || return 2

    # ── the rehearsal tag NAME comes from the candidate, not from the tag list ──────────
    # First version moved the newest EXISTING tag onto the candidate. That false-blocks on any
    # VERSION-BUMPING fold — i.e. every fold. Measured on 5ff18686 (the 39-branch fold): with
    # v3.33.294-alpha moved on, §2 said "this build calls itself 3.33.295-alpha, but it would
    # publish as 3.33.294-alpha" and the rehearsal exited 2. The guard was right; the premise
    # was supplied by this script. A rig that feeds a guard a false premise reds a healthy tree
    # exactly as easily as it greens a broken one, and the red is more likely to be believed.
    local prev; prev="$(_newest_tag_local "$WORK/repo")"
    [ -n "$prev" ] || { echo "[rehearse] BLOCKED: no v3.33.* tag in the clone." >&2; return 2; }

    local semver; semver="$(_semver_of "$WORK/repo")"
    if [ -z "$semver" ]; then
        echo "[rehearse] BLOCKED: could not read SEMVER from src/meta/Version.gd in the" >&2
        echo "           candidate. An unreadable version is never a matching one." >&2
        return 2
    fi
    local tag="v${semver}"

    # §1 reads the ANNOTATION for gate evidence, so the tag must carry one. The candidate has
    # no real annotation yet — it is not tagged — so the previous tag's message is reused.
    # ⛔ DELIBERATELY NOT SYNTHESISING A `gated:` TOKEN. That line is the fold's evidence that
    # the suite passed on THAT commit; fabricating one here would let a rehearsal clear a gate
    # the real publish might fail, which is the one direction a rehearsal must never err in.
    # tag_gate_evidence correctly notices the mismatch and downgrades to VERDICT=RUN. That is
    # the conservative answer and it is the right one.
    local msgfile="$WORK/tagmsg.txt"
    git -C "$WORK/repo" tag -l --format='%(contents)' "$prev" > "$msgfile"
    git -C "$WORK/repo" tag -a -f -F "$msgfile" "$tag" "$sha" >/dev/null 2>&1 || return 2

    # CONTROL: the shipped version checker must accept the name this script derived. Without
    # this, a drift between my sed and check_version_matches_tag.sh's sed would surface as a
    # confusing §2 block mid-rehearsal, and the obvious reading would be "the candidate is
    # broken" rather than "the rig parsed the version differently from the tool that decides".
    # An audit instrument must not disagree silently with the thing it is auditing.
    # ⛔ NO SILENT SKIP. The first version of this control was `if [ -x … ]; then … fi` with no
    # else, so a candidate missing the checker would have had this control quietly not run —
    # one commit after I wrote "a missing guard is not a passing one" into publish_all and made
    # the same situation exit 4 there. I wrote the rule and then wrote its opposite, inside the
    # control I was adding BECAUSE of a lesson about audit instruments.
    #
    # Blocking is also the consistent answer: publish_all §2 itself refuses to publish when
    # check_version_matches_tag.sh is absent, so a candidate without it cannot ship anyway, and
    # a rehearsal that sailed past would be rehearsing something the real run forbids.
    if [ ! -x "$WORK/repo/tools/check_version_matches_tag.sh" ]; then
        echo "[rehearse] BLOCKED: the candidate has no executable tools/check_version_matches_tag.sh," >&2
        echo "           so nothing can ratify the tag name this script derived from Version.gd." >&2
        echo "           publish_all §2 refuses to publish without it too — this is not a case to" >&2
        echo "           wave through. A missing guard is not a passing one." >&2
        return 2
    fi
    if ! ( cd "$WORK/repo" && ./tools/check_version_matches_tag.sh "$tag" ) >/dev/null 2>&1; then
        echo "[rehearse] BLOCKED: derived tag ${tag} from Version.gd, but the candidate's own" >&2
        echo "           tools/check_version_matches_tag.sh rejects it. This script's parse and" >&2
        echo "           the shipped checker's have diverged — fix the parse, do not proceed." >&2
        return 2
    fi

    # §3b compares the tag against origin's newest. The candidate's tag does not exist on the
    # real origin, so the comparison would report SUPERSEDED and exit 3 — again a false block
    # from the rig. A rehearsal necessarily models "this tag has just been cut and pushed", so
    # origin is pointed at the sandbox.
    # ⚠ CONSEQUENCE, stated because it is a real loss of fidelity: §3b is REHEARSED, NOT PROVEN.
    # It does its real comparison against the real origin on the day.
    git -C "$WORK/repo" remote set-url origin "$WORK/repo"

    # ⛔ AND REMOVE TAGS THAT SORT ABOVE THE CANDIDATE'S. Repointing origin models "this tag was
    # just cut and pushed" only if the sandbox does not still contain a NEWER one. Measured:
    # rehearsing an unmerged lane stack whose Version.gd reads 3.33.294-alpha, while the sandbox
    # carried v3.33.295-alpha, exited 3 SUPERSEDED — a false block from the rig, and the mirror
    # of the false block I fixed this morning when the candidate was AHEAD of the newest tag.
    # Rehearsing my own unmerged branches is this tool's main use case, so the rig blocked
    # exactly what it exists to check.
    #
    # ⚠ This is a real loss of fidelity and it is the second one: §3b supersession is now
    # REHEARSED TWICE OVER — against a sandbox origin, with newer tags removed. It does its real
    # comparison against the real origin on the day. Anything a rehearsal tells you about
    # supersession is worth nothing; everything else in the chain is still faithful.
    local _newer
    _newer="$(git -C "$WORK/repo" for-each-ref --format='%(refname:short)' 'refs/tags/v3.33.*' \
              | sort -V | awk -v t="$tag" 'index($0, t) == 1 {seen=1; next} seen')"
    if [ -n "$_newer" ]; then
        # `wc -l` on a list with no trailing newline reports 0 — it counts newlines, not items.
        # The first version printed "removing 0 tag(s)" while removing one. Count words, and
        # NAME them, so the line reports what happened rather than a number that can be wrong.
        echo "[rehearse] removing $(printf '%s' "$_newer" | wc -w | tr -d ' ') tag(s) newer than" \
             "$tag from the sandbox so §3b sees this tag as the newest: $(printf '%s' "$_newer" | tr '\n' ' ')"
        for _t in $_newer; do git -C "$WORK/repo" tag -d "$_t" >/dev/null 2>&1; done
    fi

    # The clone carries COMMITTED state only. A rehearsal of a dirty worktree is a rehearsal of
    # something other than what you are looking at — the same trap publish_all §3 guards with
    # its own clean-tree rule, one level out.
    local dirty; dirty="$(git -C "$REPO_ROOT" status --porcelain | wc -l)"
    if [ "$dirty" -ne 0 ]; then
        echo "[rehearse] ⚠ the source worktree has ${dirty} uncommitted change(s). This rehearsal" >&2
        echo "             covers the COMMITTED tree at ${sha:0:8} and does NOT include them." >&2
    fi

    echo "[rehearse] candidate  $ref -> ${sha:0:8}"
    echo "[rehearse] tag        $tag  (DERIVED from the candidate's Version.gd; previous was $prev)"
    echo "[rehearse]            created in the clone only · annotation reused from $prev, so §1"
    echo "[rehearse]            will read VERDICT=RUN rather than a real gated: token"
    echo "[rehearse]            origin -> sandbox, so §3b supersession is REHEARSED, not proven"
    echo "[rehearse] mode       $mode"
    echo "[rehearse] ─── publish_all ───"

    ( cd "$WORK/repo" \
      && PATH="$STUB:$PATH" BUTLER_BIN="$STUB/butler" BUTLER_STUB_LOG="$CALLS" \
         ./tools/publish_all.sh "$mode" "$tag" )
    local ec=$?

    echo "[rehearse] ─── result ───"
    # ⚠ NOT `$(grep -c … || echo 0)`. On a file with no matches `grep -c` prints 0 AND EXITS 1,
    # so the fallback fires too and the variable becomes "0\n0" — after which `[ "$pushes" -ne 0 ]`
    # does not return false, it ERRORS ("integer expression expected") and the check is skipped
    # entirely. Measured here on the first live run. A guard whose comparison errors out is not a
    # lenient guard, it is an absent one, and it fails silently on the CLEAN path where nobody
    # looks. Assign on failure instead of appending to the output.
    local pushes
    pushes="$(command grep -ac '^push ' "$CALLS" 2>/dev/null)" || pushes=0
    [ -n "$pushes" ] || pushes=0
    echo "[rehearse] publish_all exit $ec · butler invocations $(wc -l < "$CALLS") · push attempts ${pushes}"
    if [ "${pushes:-0}" -ne 0 ]; then
        echo "[rehearse] ⚠ the rehearsal ATTEMPTED A PUSH. It was refused by the stub, but on a" >&2
        echo "           real run this would have shipped. Inspect $CALLS." >&2
        command grep -a '^push ' "$CALLS" >&2
    fi
    echo "[rehearse] the real repo, the real tags and origin were not written."
    return $ec
}


# ── self-test ────────────────────────────────────────────────────────────────
# Arms the CONTAINMENT CONTROL both ways, because that control is the only thing standing
# between a rehearsal and a real publish. The clone/tag machinery is exercised by using it.
selftest() {
    local pass=0 fail=0 saved_work="$WORK"
    _arm() {
        local name="$1" want="$2"; shift 2
        "$@" >/dev/null 2>&1; local got=$?
        if [ "$got" -eq "$want" ]; then
            pass=$((pass+1)); printf '  ok    %-52s rc %s\n' "$name" "$got"
        else
            fail=$((fail+1)); printf '  FAIL  %-52s rc %s (wanted %s)\n' "$name" "$got" "$want"
        fi
    }

    WORK="$(mktemp -d)"; STUB="$WORK/bin"; CALLS="$WORK/butler_calls.log"

    _make_stub
    _arm "a correct stub passes the containment control" 0 _containment_control

    # sabotage 1: a stub that SUCCEEDS on push. This is the dangerous shape — it looks like a
    # working rehearsal and would let a real publish through if it were the real binary.
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "${BUTLER_STUB_LOG:?}"\nexit 0\n' > "$STUB/butler"
    chmod +x "$STUB/butler"
    _arm "a stub that does NOT refuse push is rejected" 1 _containment_control

    # sabotage 2: a stub that refuses but does not RECORD. Then "0 pushes" is unprovable.
    printf '#!/usr/bin/env bash\ncase "${1:-}" in push) exit 97 ;; *) exit 0 ;; esac\n' > "$STUB/butler"
    chmod +x "$STUB/butler"
    _arm "a stub that does not record is rejected" 1 _containment_control

    # sabotage 3: no stub at all on PATH -> must not resolve to the real butler.
    rm -f "$STUB/butler"
    _arm "a missing stub is rejected, not ignored" 1 _containment_control

    _make_stub
    _arm "control recovers once the stub is correct again" 0 _containment_control

    _arm "an unresolvable ref is unusable, not clean" 2 rehearse "no-such-ref-xyz" --check

    rm -rf "$WORK"; WORK="$saved_work"
    echo
    echo "selftest: $pass passed, $fail failed"
    [ "$fail" -eq 0 ] || return 1
    return 0
}

if [ "${SELFTEST:-0}" = "1" ]; then
    selftest
    exit $?
fi
rehearse "$REF" "$MODE"
exit $?
