#!/usr/bin/env bash
# deploy_desktop.sh — build, verify and (only when explicitly told) publish a
# native DESKTOP build. Platform comes from $PLAT; tools/deploy_linux.sh and
# tools/deploy_windows.sh are thin wrappers that set it.
#
# WHY LINUX IS FIRST-CLASS HERE
#   It is struktured's own platform and his dev cycle. Not a market tier — the
#   build he actually plays. Web stays the portability/collaboration channel
#   (phone, laptops, friends, and the artist's sprite review). Windows is a real
#   target because most players are on it; macOS is NOT wired in here because it
#   cannot be boot-gated from this box (see docs/DEPLOYMENT_PLATFORMS.md).
#
# HOW THIS DIFFERS FROM deploy_web.sh
#   * No pck size gate. That limit is itch's HTML5 *embed* cap; a downloadable
#     build is not subject to it. A 300+ MB desktop binary is unremarkable.
#   * A BOOT gate instead of a render/WASM smoke. The exported binary is run
#     headless and must reach the title screen. Web cannot do this; desktop can,
#     and it is the cheapest possible proof the artifact is not merely large.
#     Windows gets the identical assertion via wine, so it is not a blind ship.
#   * Gating is delegated to tools/gate.sh rather than re-rolled. deploy_web.sh
#     used to decide "did the suite pass?" by counting lines containing
#     [Failed], which is 2x failing ASSERTS — a quantity GUT never prints — and
#     which reads 0 for a suite that CRASHED or ran nothing. Measured: point that
#     command at a nonexistent -gdir and you get exit 0, zero [Failed], zero
#     Totals blocks, and the gate passes straight into a publish. Never re-roll a
#     weaker copy of a checker that already exists.
#
# PUBLISHING IS OPT-IN, BY CONSTRUCTION
#   Standing rule: never push to itch.io without explicit per-deploy approval
#   from struktured. This script therefore BUILDS AND VERIFIES by default and
#   refuses to publish unless --publish is passed. Forgetting the flag cannot
#   ship anything; that is the intended asymmetry.
#
# Usage:
#   tools/deploy_linux.sh                      build + verify only  (default)
#   tools/deploy_linux.sh --publish [version]  build + verify + butler push
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

PUBLISH=0
[ "${1:-}" = "--publish" ] && { PUBLISH=1; shift; }

# ── platform table ───────────────────────────────────────────────────────────
# One implementation, N platforms. deploy_linux.sh and deploy_windows.sh are
# thin wrappers over this file. NOT a copy each: gate 0b alone has taken four
# correctness fixes (overwrite coverage, a duplicate `trap` that silently
# disarmed the drift report, one-sided enumeration blind to file creation, and a
# partial-snapshot control). A forked copy would have to re-earn every one, and
# would not — that is how deploy_web.sh's gate 1 stayed vacuous while this file
# was being hardened.
#
# BOOT_RUNNER is the whole reason Windows is shippable from a Linux box: wine
# runs the exported .exe headless, so Windows gets the SAME positive-marker boot
# assertion Linux does. A platform with no runner has no boot gate and must not
# be published from here — see macOS in docs/DEPLOYMENT_PLATFORMS.md.
PLAT="${PLAT:-linux}"
case "$PLAT" in
  linux)
    PRESET="Linux";           OUT_DIR="build/linux"
    ARTIFACT="cowardly-irregular.x86_64"; CHANNEL="linux";  BOOT_RUNNER=() ;;
  windows)
    PRESET="Windows Desktop"; OUT_DIR="build/windows"
    ARTIFACT="cowardly-irregular.exe";    CHANNEL="windows"; BOOT_RUNNER=(wine) ;;
  *)
    echo "[deploy] unknown platform '$PLAT' (linux|windows)" >&2; exit 2 ;;
esac
# NO PIPE, deliberately. `git tag --sort=-creatordate | head -1` dies here:
# `head` closes the pipe after one line, `git tag` keeps writing into it and takes
# SIGPIPE, and `set -o pipefail` makes 141 the status of the whole pipeline — fatal
# under `set -e`, at the very first statement, BEFORE any echo. The symptom is an
# empty log and exit 141, which reads like nothing ran, because nothing did.
# Measured here: 507 tags emit 7453 bytes and it failed 20/20. It is buffer-bound,
# so it was silent while the repo had fewer tags and became reliable as they piled
# up — the same producer-speed pipe class the fleet hit in `comm` tonight.
# deploy_web.sh already carries this fix; I copied its pre-fix shape.
VERSION="${1:-$(git for-each-ref --sort=-creatordate --count=1 --format='%(refname:short)' refs/tags)}"

# ── version identity ─────────────────────────────────────────────────────────
# The label this build publishes under and the version it will SHOW A PLAYER must agree.
# v3.33.247-alpha shipped to all three channels on 2026-09-09 with Version.gd still reading
# 3.33.246-alpha — a tools-only re-cut whose semver bump was missed. Nothing in this chain
# looked, so it published three times. The fold's test_version_display_regression protects
# the REPOSITORY at merge time; this protects the PUBLISH, and a tag can be cut and pushed
# between those two moments — which is exactly what happened.
#
# First gate deliberately: it costs milliseconds and the alternative is finding out after a
# 15-minute build, or not at all. Blocks on mismatch AND on any failure to read the version;
# an unreadable version is never a matching one.
if [ -x tools/check_version_matches_tag.sh ]; then
    ./tools/check_version_matches_tag.sh "$VERSION" || exit 5
else
    echo "BLOCKED: tools/check_version_matches_tag.sh missing — refusing to publish a label" >&2
    echo "        nothing has checked against the build's own version string." >&2
    exit 5
fi

# THE VERSION LABEL DOES NOT IDENTIFY THE BUILD, AND UNTIL NOW NOTHING DID.
# This script EXPORTS THE WORKING TREE. The tag is a string passed to --userversion; it
# is never checked out. So the tag and the bits can be arbitrarily far apart, and the
# published label reads as if it were the built commit.
#
# Measured on the 2026-08-05 Linux publish, which is live right now:
#   userversion shown on itch   v3.33.205-alpha   -> a 2026-07-25 commit, 740 behind main
#   the tree actually exported  6dd69779          -> 2026-08-05 06:43, 146 behind main
# The label overstates the build's age by 594 commits. Nobody could have told which
# number was real from anything itch displays, and I quoted the wrong one to struktured
# for a day — from the tag, because that is what the deploy prints.
#
# So publish the built SHA alongside the tag. `+` is semver build metadata and butler
# takes the string verbatim. `-dirty` when the tree has uncommitted changes, because an
# export of a dirty tree is not reproducible from any SHA and saying so is the point.
# Was two lines computing this locally. `git rev-parse --short` picks the shortest length
# unambiguous AT THAT MOMENT, so two channels of ONE publish disagreed (v3.33.312-alpha:
# +befbe408 vs +befbe4083). publish_all fixes the label once and exports it; standalone runs
# still derive their own, which is what keeps the recovery path in publish_all.sh:281 working.
_BUILD_SHA_TOOL="$(cd "$(dirname "$0")" && pwd)/build_sha.sh"
[ -x "$_BUILD_SHA_TOOL" ] || {
    echo "BLOCKED: ${_BUILD_SHA_TOOL} missing or not executable — refusing to guess a version label." >&2
    exit 2; }
BUILD_SHA="$("$_BUILD_SHA_TOOL")" || {
    echo "BLOCKED: could not determine a build label." >&2; exit 2; }
USERVERSION="${VERSION}+${BUILD_SHA}"

ITCH_TARGET="struktured/cowardly-irregular:${CHANNEL}"
BIN="${OUT_DIR}/${ARTIFACT}"
# Overridable so the post-push confirmation path is testable without touching itch.
BUTLER_BIN="${BUTLER_BIN:-$(command -v butler || echo ./butler-bin/butler)}"

mkdir -p tmp "$OUT_DIR"
echo "[${PLAT}] target ${VERSION}  publish=${PUBLISH}"

# ⚠️ WHY THESE RUN BACKGROUNDED + `wait` RATHER THAN IN THE FOREGROUND.
# bash DEFERS a signal trap until the current foreground command finishes.
# Measured: TERM during a foreground `sleep 8` -> handler ran 8s later; the same
# work backgrounded with `wait` -> handler ran in 1s. Gate 1 is a 9-11 minute
# suite, so a foreground kill would leave the export dir clobbered for the whole
# remaining run. Trapping the signal is only half the fix; being interruptible is
# the other half.
#
# `EC=0; wait $! || EC=$?` and not `cmd; EC=$?`: under `set -e` a failing command
# exits the script BEFORE its status can be read, so every "BLOCKED: ..." message
# below was unreachable on the exact failure it describes. The deploy still failed
# safely (non-zero), it just never said why.

# ── marker staleness guard ──────────────────────────────────────────────────
# Gates 3 and 3b assert a literal log line. That is a positive marker, which is
# right — but it is also a coincidental-value pin: change the log line and the
# gate goes RED on a correct build, and whoever hits it edits the string. That
# is how the WEB gate spent three days blocked on a hardcoded menu row index
# (2026-07-27 -> 2026-07-30) while reporting "failed to boot in chromium" for a
# build that booted perfectly.
#
# So before believing a missing marker means a broken build, check the marker
# still EXISTS in src/. If it doesn't, the gate is stale and says so, rather
# than blaming the artifact. This is the expiry condition a comment can't be.
_require_marker_live() {
    grep -rqF "$1" src/ && return 0
    echo "[${PLAT}] BLOCKED: gate marker '$1' no longer exists in src/." >&2
    echo "        This gate is STALE — the game changed its log line. The build is" >&2
    echo "        NOT necessarily broken. Re-derive the marker before touching it," >&2
    echo "        and do not simply edit the string until it passes." >&2
    exit 3
}

# ── gate 0: import prewarm ───────────────────────────────────────────────────
# A fresh worktree has no .godot cache, so res:// paths resolve to nothing while
# the files sit right there on disk. A test run in that state exits 0 having run
# NOTHING, which is indistinguishable from success. Cheap and idempotent once warm.
echo "[${PLAT}] gate 0/4: import prewarm"
godot --headless --audio-driver Dummy --import --quit > tmp/${PLAT}_import.log 2>&1 &
EC=0; wait $! || EC=$?
test $EC -eq 0 || { echo "[${PLAT}] BLOCKED: asset import failed — see tmp/${PLAT}_import.log" >&2; exit 1; }

# ── gate 0b: protect the player's exported scripts ──────────────────────────
# The suite DELETES user://script_exports/. Verified with a canary against
# origin/main: plant a file no test knows about, run the share suite, it is gone.
# Since gate 1 runs the suite, a deploy destroys any autobattle script struktured
# has exported from the grid editor — the storage for a shipped pillar.
#
# The upstream fix (a per-process export dir) exists on a branch and is not merged.
# This does NOT wait for it: a publish path must not be able to eat player data
# regardless of what another lane has folded.
#
# Snapshot/restore rather than refuse-to-run, because refusing would make the
# deploy un-runnable whenever the directory is non-empty, and the directory is
# non-empty precisely when there is something worth protecting.
#
# Why a snapshot is the only safe option and not merely the tidy one: tests and
# players write the SAME FILENAMES to this directory — a test writes
# autogrind_rules.json, and so does the game. So a clobbered export cannot be
# detected after the fact, let alone recovered. There is no "is this mine?" check
# available, which is why the answer is to copy first and ask nothing.
USERDATA="${HOME}/.local/share/godot/app_userdata/Cowardly Irregular"
EXPORT_DIR_REAL="${USERDATA}/script_exports"
SNAP_DIR="tmp/script_exports_snapshot"
# SNAPSHOT BROAD, RESTORE NARROW, REPORT THE REST.
#
# The census predicate that settled the fleet's audit asked "does any test write
# to the EXPORT dir" — so it could not see user://autogrind/, which is 13 days
# older than script_exports/ and had all three of its files rewritten during a
# test window. Content there turned out intact (an internal 07-14 timestamp
# inside a file written at 23:05 proves re-serialization, not replacement), but
# the check never covered it and neither did this gate.
#
# Widening the SNAPSHOT is free insurance: the whole profile is well under a MiB.
# Widening the RESTORE is NOT free and is deliberately not done. struktured may
# be playing while a deploy runs — a .recovery_mode_lock appeared mid-window
# tonight — and blanket-restoring user:// would revert live progress made during
# the deploy. That trades a silent overwrite for a silent rollback, which is
# worse: the overwrite hits data a test also writes, the rollback hits anything.
#
# So: copy everything, put back only the paths TESTS write and the player does
# not continuously write, and for the remainder report what changed so a loss is
# detectable rather than either silently kept or silently reverted.
#
# user://autogrind/ IS NOT RESTORED — but NOT for the reason I first wrote here.
#
# ⚠️ MY ORIGINAL JUSTIFICATION WAS FALSE. It read: "tests CANNOT write there —
# every save path in AutogrindSystem.gd opens with `if _test_disable_persistence:
# return`, set by 24 test files." Every clause is individually true and the
# conclusion does not follow. The guard is present in every WRITER; that says
# nothing about whether every CALLER sets the flag. cowir-autogrind measured it
# (2026-08-06): 48 tests touch AutogrindSystem, 19 do not set the flag, and 4 of
# those reach a write path. I counted the files that DO set it and generalised to
# the ones that don't — a correct count of the wrong predicate, again.
#
# THE DECISION IS UNCHANGED; ONLY ITS BASIS IS. Both writers are real:
#   * the GAME writes here live — restoring would revert an in-progress session
#   * the SUITE writes here too, and gate 1 above runs the full suite, so THIS
#     SCRIPT is one of the writers it is reporting drift for
# Neither restore nor keep is safe, so we do the third thing: report it, name
# both possible authors, and keep the pre-image. The snapshot is taken at gate 0b
# BEFORE gate 1, so it is a genuine pre-suite copy — which is why it can serve as
# an independent restore source (verified 2026-08-06: my Aug-5 snapshot and
# cowir-autogrind's separate restore agree at b5bfef1c).
#
# The generalisable rule survives intact and is what I got wrong: a path may be
# put back only if ONLY tests write it. That must be established by driving the
# tests, not inferred from a guard's presence in the writer.
FULL_SNAP="tmp/userdata_snapshot"
RESTORE_PATHS=(script_exports)
# Paths excluded from the DRIFT REPORT (not from the snapshot — they are still
# copied, they just don't get reported). Engine logs only.
#
# user://logs/ gets a fresh file on EVERY native godot invocation, and a deploy
# makes three (import, suite, export). So it would drift on every single run,
# unconditionally. A report that always fires is a report nobody reads, and the
# whole point of this one is that "drift: none" carries information. Excluding a
# guaranteed-noisy path is what keeps the remaining lines meaningful.
#
# Deliberately narrow: ONLY logs. Anything under saves/ or autogrind/ still
# reports, because those are the paths where a change might be his.
DRIFT_IGNORE=(logs)
_restore_exports() {
    [ -d "$SNAP_DIR" ] || return 0
    mkdir -p "$EXPORT_DIR_REAL"
    # `cp -a src/. dst/` REPLACES existing files, and that is load-bearing — do not
    # "optimise" this into a copy-only-if-missing. There are TWO exposures here, and
    # only one is deletion:
    #   DELETE    test_autobattle_grid_share_regression.gd purges the dir
    #   OVERWRITE test_script_share.gd calls export_autogrind_rules() with NO
    #             EXPORT_DIR override, writing test data over the FIXED production
    #             filename autogrind_rules.json — a shipped player action
    #             (AutogrindUI.gd:1687). Same path, same name, someone else's
    #             contents, nothing loud. A copy-if-missing restore would "pass"
    #             while leaving that substitution in place.
    # Measured, sandboxed (never probe the live dir — planting a canary there is a
    # destructive act, not a read): original 95e34427 -> clobbered 4947f406 ->
    # restored 95e34427, with plain deletion as the control. Both axes recover.
    #
    # NOTE the declaration form is NOT the discriminator. `static var EXPORT_DIR`
    # only makes the path assignable; the writer never assigns it, so a "fixed"
    # tree overwrites production exactly like an unfixed one. An override nobody
    # sets is a default. This snapshot is a net, not a scope — it does not replace
    # scoping the writer, it only makes gate 1 non-destructive until that lands.
    cp -a "$SNAP_DIR/." "$EXPORT_DIR_REAL/" 2>/dev/null || true
    echo "[${PLAT}] restored $(find "$SNAP_DIR" -type f | wc -l) exported script(s)"
}
# Report-only drift check over everything OUTSIDE RESTORE_PATHS. Detection, never
# reversion — see the RESTORE_PATHS note above for why reverting here is worse.
_report_userdata_drift() {
    [ -d "$FULL_SNAP" ] || return 0
    local rel top a b changed=0
    while IFS= read -r a; do
        rel="${a#"$FULL_SNAP"/}"
        top="${rel%%/*}"
        case " ${RESTORE_PATHS[*]} " in *" $top "*) continue ;; esac
        case " ${DRIFT_IGNORE[*]} " in *" $top "*) continue ;; esac
        b="$USERDATA/$rel"
        if [ ! -e "$b" ] || ! cmp -s "$a" "$b"; then
            changed=$(( changed + 1 ))
            echo "[${PLAT}]   drift: $rel"
        fi
    done < <(find "$FULL_SNAP" -type f | sort)
    # Second pass, from the OTHER side. The loop above walks the SNAPSHOT, so it
    # sees modifications and deletions and is structurally blind to CREATIONS — a
    # file a test invents was never in the snapshot to be iterated over. That is
    # the enumerate-from-one-side hole: a sweep's silence is only as wide as its
    # shape, and this one's shape was "things that already existed."
    while IFS= read -r b; do
        rel="${b#"$USERDATA"/}"
        top="${rel%%/*}"
        case " ${RESTORE_PATHS[*]} " in *" $top "*) continue ;; esac
        case " ${DRIFT_IGNORE[*]} " in *" $top "*) continue ;; esac
        [ -e "$FULL_SNAP/$rel" ] && continue
        changed=$(( changed + 1 ))
        echo "[${PLAT}]   new: $rel"
    done < <(find "$USERDATA" -type f | sort)
    case $changed in
        0) echo "[${PLAT}] userdata drift outside ${RESTORE_PATHS[*]}: none" ;;
        *) echo "[${PLAT}] NOTE: ${changed} user:// file(s) changed during this deploy." >&2
           # This used to read "if you were playing, that is your own save" — which
           # named the wrong author for autogrind/. Gate 1 runs the full suite and the
           # suite writes user://autogrind/ (cowir-autogrind, 2026-08-06), so THIS
           # SCRIPT is a writer. Attributing its own drift to the player is worse than
           # saying nothing: it invites him to keep a test fixture as if it were a save.
           # Post-C1 (main 4dda6dfb) run_tests.sh carries its own net over
           # script_exports/autogrind/autobattle/input/ + root *.json, restoring them on
           # EXIT INT TERM — verified, including the signal cases this script had to learn.
           # So for a NETTED path (b) now means the suite ALSO died by SIGKILL or its
           # restore failed, which is worth knowing rather than assuming (a).
           # For saves/ and screenshots/ nothing is netted by anyone, deliberately.
           echo "        NOT reverted. TWO possible authors and this report cannot tell" >&2
           echo "        them apart: (a) your live session, or (b) gate 1's test suite —" >&2
           echo "        user:// is ONE path shared by every cowir-* checkout on this" >&2
           echo "        machine. For netted dirs (autogrind/ autobattle/ input/" >&2
           echo "        script_exports/ root *.json) the suite restores its own writes," >&2
           echo "        so drift there points at (a) or at a net that did not run." >&2
           echo "        Pre-deploy copy at ${FULL_SNAP}/ is from BEFORE gate 1, so it is" >&2
           echo "        a true pre-suite pre-image — diff against it before keeping either." >&2 ;;
    esac
}
# ONE trap, both handlers. `trap X EXIT` followed by `trap Y EXIT` does not add a
# second handler — the second REPLACES the first, silently. I wrote both and the
# restore would have won, leaving the drift report defined and never called: a
# handler that looks installed and isn't, which is this evening's whole theme.
# ⚠️ AN EXIT TRAP DOES NOT RUN WHEN THE SHELL IS KILLED. bash runs EXIT on a
# normal exit, on `set -e`, and on `exit N` — but a SIGTERM/SIGINT kills the shell
# outright and the handler never fires. @cowir-story found this in tools/gate.sh
# with physical evidence: FOUR orphaned snapshot dirs in /tmp, three of them 13
# hours old, from gates that were killed and silently never restored. Nobody
# noticed, because a net that fails open is invisible exactly when it matters.
#
# This script had the identical hole. Ctrl-C on a long deploy — or any lane
# killing a stuck gate — would skip both the restore and the drift report, which
# is the worst moment to lose them: an interrupted run is when the suite is most
# likely to have left the export dir mid-write.
#
# _EXIT_DONE makes it idempotent: the signal handler exits, which re-fires the
# EXIT trap, and without the guard the drift report would print twice.
_EXIT_DONE=0
_on_exit() {
    [ "$_EXIT_DONE" = "1" ] && return 0
    _EXIT_DONE=1
    _restore_exports
    _report_userdata_drift
}
# 128+signo, the conventional status for a signal death.
_on_signal() { echo "[${PLAT}] interrupted — running restore before exiting" >&2; _on_exit; exit $((128 + $1)); }
trap _on_exit EXIT
trap '_on_signal 2'  INT
trap '_on_signal 15' TERM
trap '_on_signal 1'  HUP
if [ -d "$USERDATA" ]; then
    rm -rf "$FULL_SNAP"; mkdir -p "$FULL_SNAP"
    cp -a "$USERDATA/." "$FULL_SNAP/" 2>/dev/null || true
    # POSITIVE CONTROL on the snapshot itself. The cp above suppresses its errors
    # (some godot userdata is unreadable sockets/locks), so a PARTIAL copy would be
    # silent — and every later "drift: none" would inherit that silence and read as
    # a clean deploy. Counting both sides makes the snapshot a measurement rather
    # than a claim: a sweep reporting 0 problems is only meaningful if you have
    # shown the sweep can see anything at all.
    SNAP_N=$(find "$FULL_SNAP" -type f | wc -l)
    LIVE_N=$(find "$USERDATA" -type f | wc -l)
    echo "[${PLAT}] gate 0b: userdata snapshot ${SNAP_N}/${LIVE_N} file(s), $(du -sh "$FULL_SNAP" 2>/dev/null | cut -f1)"
    if [ "$SNAP_N" -ne "$LIVE_N" ]; then
        echo "[${PLAT}] BLOCKED: snapshot captured ${SNAP_N} of ${LIVE_N} user:// files." >&2
        echo "        Refusing to run the suite behind a partial backup — an" >&2
        echo "        uncaptured file cannot be restored and its loss would not" >&2
        echo "        even be reported. Fix the copy, or move the unreadable file." >&2
        exit 1
    fi
fi
if [ -d "$EXPORT_DIR_REAL" ] && [ -n "$(ls -A "$EXPORT_DIR_REAL" 2>/dev/null)" ]; then
    rm -rf "$SNAP_DIR"; mkdir -p "$SNAP_DIR"
    cp -a "$EXPORT_DIR_REAL/." "$SNAP_DIR/"
    echo "[${PLAT}] gate 0b: snapshotted $(find "$SNAP_DIR" -type f | wc -l) exported script(s)"
    # The EXIT trap is installed ONCE, above, as _on_exit — do not re-arm it here.
    # A second `trap ... EXIT` REPLACES the first rather than adding to it, and
    # this line used to do exactly that: it silently disarmed the drift report,
    # which then existed, was correct, and never ran. Caught by a sandbox test
    # that asserted the report's OUTPUT rather than that the code was present.
else
    echo "[${PLAT}] gate 0b: no exported scripts to protect"
fi

# ── gate 1: test suite ───────────────────────────────────────────────────────
# gate.sh checks Totals-present, scripts-run == test files on disk, reports
# tests that asserted NOTHING, and returns a real exit code. Consult it; do not
# parse its output.
# NON-BLOCKING. A pattern that matches nothing means an exclusion silently stopped
# happening — the direction that SHIPS content you meant to drop, and pck size cannot
# see it (bigger reads as "we added content"). Reported, never enforced: a prophylactic
# *.jpg legitimately matches nothing and refusing over it would be worse than the bug.
./tools/check_exclude_patterns.sh || true

# TREE IDENTITY — bind the gate's evidence to the bits that get exported.
#
# THE GAP THIS CLOSES, measured on a real attempt (cowir-main, 2026-08-08, 3 tries):
# this script EXPORTS THE WORKING TREE. Gate 1 reads src/ at time T; gate 2 exports src/
# at T+8min. NOTHING connected the two. A concurrent edit — another lane, a rebase, a fold
# landing, or the same operator editing GameLoop.gd while their own publish chain ran —
# silently changes WHAT SHIPS after the evidence for shipping it was collected.
# "The gate was green" is a claim with no subject unless the subject is recorded.
#
# This is the label-vs-build defect one turn worse. There, the published label failed to
# identify the bits; here the GATE failed to identify them, and the gate is what authorises
# a public push.
#
# Discipline ("publish from a quiescent tree") is what failed three times today with
# `git checkout --`. A mechanism does not need anyone to remember.
_tree_id() { printf '%s %s' "$(git rev-parse HEAD)" "$(git status --porcelain | sort | md5sum | cut -d' ' -f1)"; }
GATE_TREE_ID="$(_tree_id)"

# GATE 1 RUNS AT MOST ONCE PER TAG, AND NEVER AGAINST HIS LIVE user://.
#
# Two changes, both agreed with cowir-main (msgs 8510/8512/8513/8514):
#
#  (a) SKIP when the fold already gated this exact tree. The tag's annotation carries
#      `gated: <40-hex> scripts=N tests=N passing=N failing=0`, and tools/tag_gate_evidence.sh
#      demands POSITIVE PROOF before it will authorise a skip — annotated tag, full-length
#      sha, sha == the tag's own commit, HEAD at the tag, clean tree, corpus count matching
#      disk. Silence, malformation, or a lightweight tag all mean RUN. Read that script's
#      header for why the failure direction is the entire design.
#
#  (b) When it does run, it runs SANDBOXED. Previously each chain re-ran the full
#      1319-script suite against the shared user://, and run_tests.sh's net restores
#      settings.json and autobattle/ there — so a deploy silently reverted any setting or
#      keybind struktured changed while it ran. Measured 2026-09-07: he played 20 minutes
#      (save_98 playtime +1200s) straight through a linux chain. saves/ is excluded from the
#      net so his progress was safe; his SETTINGS were not.
#
# The suite is NOT weakened — it is the same tools/gate.sh with the same exit code. Only its
# user:// moves. Tests that read his real saves self-skip under the sandbox; per cowir-main
# that is the fold's problem to cover, not a reason to keep writing to a live profile.
_SUITE_STAMP="tmp/suite_ok_$(printf '%s' "$GATE_TREE_ID" | md5sum | cut -d' ' -f1)"

echo "[${PLAT}] gate 1/4: test suite"
_EVIDENCE="$(./tools/tag_gate_evidence.sh "${VERSION}" 2>/dev/null)"
# The literal token is required. An empty or unrecognised value falls through to the RUN
# branch, which is why this is a prefix match on SKIP and not a test for a mismatch.
case "${_EVIDENCE}" in
    "VERDICT=SKIP "*)
        echo "[${PLAT}] gate 1: SKIPPED — ${_EVIDENCE#VERDICT=SKIP }"
        ;;
    *)
        if [ -f "$_SUITE_STAMP" ]; then
            # Same tag, same tree, earlier chain in this batch already ran it. The three
            # chains export ONE tree, so a second full run is redundant by construction —
            # this needs no marker and no trust in anyone's claim.
            echo "[${PLAT}] gate 1: already run for this exact tree by an earlier chain ($(cat "$_SUITE_STAMP"))"
        elif [ -x tools/gate.sh ]; then
            [ -n "${_EVIDENCE}" ] && echo "[${PLAT}] gate 1: running the suite — ${_EVIDENCE#VERDICT=RUN }"
            mkdir -p tmp/gate_xdg
            XDG_DATA_HOME="$PWD/tmp/gate_xdg" ./tools/gate.sh > tmp/${PLAT}_gate.log 2>&1 &
            EC=0; wait $! || EC=$?
            tail -12 tmp/${PLAT}_gate.log
            test $EC -eq 0 || { echo "[${PLAT}] BLOCKED: suite gate failed (exit ${EC}) — tmp/${PLAT}_gate.log" >&2; exit 1; }
            echo "${PLAT} $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$_SUITE_STAMP"
        else
            echo "[${PLAT}] BLOCKED: tools/gate.sh missing. Refusing to substitute a weaker check —" >&2
            echo "        a hand-rolled [Failed] count is what let a vacuous run reach a publish." >&2
            exit 1
        fi
        ;;
esac

# ── gate 2: export ───────────────────────────────────────────────────────────
# TREE IDENTITY RE-CHECK — the gate's evidence must describe the bits about to be exported.
# Deliberately BEFORE the export, not before the push: an export from a changed tree has
# already produced an artifact nothing vouches for, and the useful place to stop is before
# the expensive step rather than after it.
GATE_TREE_ID_NOW="$(_tree_id)"
if [ "$GATE_TREE_ID_NOW" != "$GATE_TREE_ID" ]; then
    echo "[${PLAT}] BLOCKED: the working tree CHANGED between the suite gate and the export." >&2
    echo "        at gate 1: ${GATE_TREE_ID}" >&2
    echo "        now:       ${GATE_TREE_ID_NOW}" >&2
    echo "        This script exports the WORKING TREE, so what would ship is not what" >&2
    echo "        gate 1 tested. The suite result is void — it describes a tree that no" >&2
    echo "        longer exists. Causes seen in practice: another lane editing a shared" >&2
    echo "        file, a fold landing on this checkout, a rebase, or concurrent work by" >&2
    echo "        the same operator who launched the deploy." >&2
    echo "        Re-run from a quiescent tree." >&2
    exit 1
fi
echo "[${PLAT}] gate 2/4: export (tree unchanged since gate 1)"
godot --headless --audio-driver Dummy --export-release "$PRESET" "$BIN" > tmp/${PLAT}_export.log 2>&1 &
EC=0; wait $! || EC=$?
test $EC -eq 0 || { echo "[${PLAT}] BLOCKED: export failed — see tmp/${PLAT}_export.log" >&2; exit 2; }
[ -s "$BIN" ] || { echo "[${PLAT}] BLOCKED: export reported success but produced no binary" >&2; exit 2; }
echo "[${PLAT}] binary: $(( $(stat -c%s "$BIN") / 1048576 )) MiB"

# ── does the binary CONTAIN what the export owed? ───────────────────────────
# Until now this gate checked the exit code and that the binary is non-empty. Neither can see
# content silently dropped: a desktop build that lost every sprite still exits 0 and still has
# a non-empty binary, and there is deliberately no pck size gate here (that limit is itch's
# HTML5 embed cap, irrelevant to a download) — so nothing looked at the payload at all.
# check_exclude_patterns.sh above guards the opposite direction, an exclusion that silently
# stopped matching. This one guards the dropout direction, and the two second each other.
if [ -f tools/check_pck_complete.py ]; then
    if ! python3 tools/check_pck_complete.py . "tmp/${PLAT}_export.log" "$PRESET"; then
        echo "[${PLAT}] BLOCKED: the export is missing content it owed — see above." >&2
        exit 2
    fi
else
    echo "[${PLAT}] BLOCKED: tools/check_pck_complete.py missing. Refusing to ship a binary" >&2
    echo "        whose payload nothing has checked." >&2
    exit 2
fi

# ── gate 3: does it actually boot? ───────────────────────────────────────────
# The gate web cannot have. An export can succeed and still produce something
# that dies on startup — a missing autoload, an unresolved class_name, a broken
# manifest entry. Asserting a POSITIVE marker rather than the absence of errors:
# "no errors" is also what an empty log looks like.
echo "[${PLAT}] gate 3/4: boot smoke"
# ⛔ THE TWO BOOT LOGS WERE INDISTINGUISHABLE BY CONTENT. Measured on v3.33.316-alpha's archive:
# both carry "[GAME] Started", both carry a byte-identical "Godot Engine v4.4.1.stable..." banner,
# and neither carries a wine/drive-letter path. The platform identity of this evidence lived
# ENTIRELY IN THE FILENAME. The chain is correct -- `cd build/windows` and the Linux binary is
# not in that directory -- but the Windows boot smoke is the ONLY thing proving the .exe runs at
# all, and if BOOT_RUNNER or ARTIFACT were ever mis-wired the logs would look exactly the same.
# So record the subject INSIDE the log: what was run, and the magic bytes of the thing run.
_ARTID="$(cd "$(dirname "$0")" && pwd)/artifact_identity.sh"
[ -x "$_ARTID" ] || {
    echo "[${PLAT}] BLOCKED: ${_ARTID} missing or not executable — refusing to record an unidentified boot." >&2
    exit 2; }
_RUNNER="${BOOT_RUNNER[*]+${BOOT_RUNNER[*]}}"
[ -n "$_RUNNER" ] || _RUNNER="<native>"
{
    echo "[${PLAT}] boot subject: runner=${_RUNNER} path=${OUT_DIR}/${ARTIFACT}"
    echo "[${PLAT}] boot subject: $("$_ARTID" "${OUT_DIR}/${ARTIFACT}" 2>&1)"
    ( cd "$OUT_DIR" && timeout 240 ${BOOT_RUNNER[@]+"${BOOT_RUNNER[@]}"} "./${ARTIFACT}" \
        --headless --quit )
} > "tmp/${PLAT}_boot.log" 2>&1 || true
_require_marker_live "[GAME] Started"
if ! grep -q "\[GAME\] Started" tmp/${PLAT}_boot.log; then
    echo "[${PLAT}] BLOCKED: exported binary did not reach '[GAME] Started'" >&2
    # `|| true` is load-bearing: a diagnostic grep that finds NOTHING exits 1,
    # and under `set -e` that pre-empts the `exit 3` below — so the gate would
    # report 1 instead of 3 exactly when there is no error to print. Caught by a
    # control that asserted the exit CODE, not merely that the gate failed.
    grep -iE "SCRIPT ERROR|Failed to load|Parse Error" tmp/${PLAT}_boot.log | head -5 >&2 || true
    exit 3
fi
BOOT_ERRS=$(grep -icE "SCRIPT ERROR|Failed to load script" tmp/${PLAT}_boot.log || true)
echo "[${PLAT}] booted to title screen · script errors during boot: ${BOOT_ERRS}"
[ "$BOOT_ERRS" = "0" ] || echo "[${PLAT}] WARNING: booted, but with ${BOOT_ERRS} script error(s) — see tmp/${PLAT}_boot.log"

# ── gate 3b: COMBAT smoke, in an isolated profile (linux only) ──────────────
# Gate 3 proves the binary reaches the title screen. It says nothing about the
# battle system — and on 2026-07-30 four BattleManager fixes landed (burn damage,
# blocked-Defer, an empty-party victory guard and a selection guard, the last two
# running on every action of every turn) with no execution in a booted build on
# any platform.
#
# GameLoop.gd:382 has accepted `--battle-smoke` all along and NOTHING used it:
# 0 references in tools/, .github/ or CLAUDE.md. It fights a real battle in the
# exported build and writes screenshots.
#
# WHY THIS IS SAFE TO RUN AND GATE 3 IS NOT EXTENDED INSTEAD:
# a desktop binary resolves user:// from $HOME, so redirecting HOME relocates the
# ENTIRE profile. The smoke then plays a real battle against a throwaway
# directory and cannot reach struktured's saves — which is the only reason this
# is allowed to do more than boot. Measured on the first run: his profile held
# 141 files before and 141 after, and all 63 writes landed in the sandbox.
#
# That isolation is ASSERTED below, not trusted. If it ever stops holding, this
# gate must fail rather than quietly play the game against real save data.
if [ "$PLAT" = "linux" ] || [ "$PLAT" = "windows" ]; then
    if ! command -v xvfb-run >/dev/null; then
        # Loudly skipped, never silently: a smoke that does not run must not look
        # like a smoke that passed.
        echo "[${PLAT}] gate 3b: SKIPPED — xvfb-run absent, combat is UNVERIFIED" >&2
    elif [ "$PLAT" = "windows" ] && ! command -v wine >/dev/null; then
        echo "[${PLAT}] gate 3b: SKIPPED — wine absent, combat is UNVERIFIED" >&2
    else
        echo "[${PLAT}] gate 3b: combat smoke (isolated profile)"
        # THE ISOLATOR DIFFERS BY PLATFORM, and that is the whole reason windows was skipped.
        # A linux build resolves user:// from $HOME, so redirecting HOME relocates the profile.
        # A wine build resolves it through %APPDATA% INSIDE THE WINEPREFIX, so HOME redirection
        # is the wrong lever there — a throwaway prefix is the right one, and it is stricter:
        # the sandbox is a whole fake Windows, not just a relocated directory.
        SMOKE_HOME="$(pwd)/tmp/smoke_home"
        rm -rf "$SMOKE_HOME"; mkdir -p "$SMOKE_HOME"
        # CONTENT, not a count. The previous baseline was `find | wc -l`, which cannot see a
        # save OVERWRITTEN IN PLACE — the exact shape of a partially-failed HOME redirect,
        # where the game finds an existing profile and rewrites slot files already there.
        # Measured: a slot overwritten in place leaves the count at 2 -> 2, so the old check
        # printed "profile untouched" and published.
        if [ ! -x tools/check_profile_untouched.sh ]; then
            echo "[${PLAT}] BLOCKED: tools/check_profile_untouched.sh missing. Refusing to run" >&2
            echo "        the game against a redirected HOME without a way to prove his saves" >&2
            echo "        survived it." >&2
            exit 3
        fi
        REAL_SIG_BEFORE="$(./tools/check_profile_untouched.sh --sig "$USERDATA")"
        REAL_N_BEFORE=$(find "$USERDATA" -type f 2>/dev/null | wc -l)
        if [ "$PLAT" = "windows" ]; then
            # 900s, not 600: creating a fresh WINEPREFIX dominates the first minutes and is
            # not the game being slow. Measured 2026-09-10 — prefix creation, then engine
            # banner, [GAME] Started, Battle commenced, and a clean exit 0.
            ( cd "$OUT_DIR" && WINEPREFIX="$SMOKE_HOME" timeout 900 xvfb-run -a \
                wine "./${ARTIFACT}" -- --battle-smoke ) > "tmp/${PLAT}_battle.log" 2>&1 &
        else
            HOME="$SMOKE_HOME" timeout 600 xvfb-run -a "$BIN" -- --battle-smoke \
                > "tmp/${PLAT}_battle.log" 2>&1 &
        fi
        SEC=0; wait $! || SEC=$?
        # Isolation first: a leak matters more than a failed battle. The sandbox is passed so
        # the RED can distinguish "he was playing during the deploy" from "the redirect did
        # not work" — a battle that ran and left an EMPTY sandbox did not have a working HOME.
        if ! ./tools/check_profile_untouched.sh --verify "$USERDATA" "$REAL_SIG_BEFORE" "$SMOKE_HOME"; then
            echo "[${PLAT}] BLOCKED: refusing to keep running the game against real save data." >&2
            exit 3
        fi
        # Positive marker, not absence-of-error: an empty log has no errors either.
        _require_marker_live "Battle commenced"
        if ! grep -aq "Battle commenced" "tmp/${PLAT}_battle.log"; then
            echo "[${PLAT}] BLOCKED: combat smoke never reached a battle (exit ${SEC})" >&2
            grep -aiE "SCRIPT ERROR|Failed to load|Parse Error" "tmp/${PLAT}_battle.log" | head -5 >&2 || true
            exit 3
        fi
        # Scoped to the game's own user:// tree so the number means the same thing on both
        # platforms: screenshots THIS RUN wrote. An unscoped find over a WINEPREFIX counts
        # whatever wine ships as well — measured 0 on wine-10.0, which is a fact about this
        # wine build and not a property to rely on.
        SHOTS=$(find "$SMOKE_HOME" -ipath '*app_userdata*' -name '*.png' 2>/dev/null | wc -l)
        # SAY WHAT WAS CHECKED. "fought a real battle" overstated a marker test: the gate
        # greps for "Battle commenced", which proves combat STARTED, not that it ran to a
        # conclusion. And "profile untouched" is now a signature comparison rather than a
        # count, so it is finally the claim it always read as.
        # The count and the verified set are NOT the same set, so do not print one and claim
        # the other. ${REAL_N_BEFORE} counts every file including user://logs/; the signature
        # covers the profile MINUS logs, which is what was actually compared. Printing "176
        # files, signature matched" attaches a verified verb to an unverified number — the
        # same substitution this whole gate was rewritten to remove.
        echo "[${PLAT}] reached a battle ('Battle commenced') · ${SHOTS} screenshot(s) in the sandbox"
        echo "[${PLAT}] his profile: ${REAL_N_BEFORE} files total; signature verified unchanged over all of them except user://logs/ (see [profile] line above for the covered count)"
    fi
else
    echo "[${PLAT}] gate 3b: SKIPPED — no combat smoke defined for platform '${PLAT}'"
fi

# ── gate 4: publish, only if explicitly asked ───────────────────────────────
if [ "$PUBLISH" != "1" ]; then
    echo "[${PLAT}] gate 4/4: SKIPPED — build verified, nothing published."
    echo "[${PLAT}] run it: ${BIN}"
    echo "[${PLAT}] to publish: tools/deploy_${PLAT}.sh --publish ${VERSION}"
    exit 0
fi

echo "[${PLAT}] gate 4/4: pushing to ${ITCH_TARGET} (userversion ${USERVERSION})"
echo "[${PLAT}]   tag ${VERSION} is a LABEL; ${BUILD_SHA} is the tree that was exported"
"${BUTLER_BIN}" push "$OUT_DIR" "$ITCH_TARGET" --userversion "$USERVERSION"
# Bounded wait. deploy_web.sh's equivalent loop has no timeout, so a version that
# never registers hangs the deploy forever instead of reporting anything.
CONFIRM_BUDGET="${CONFIRM_BUDGET:-900}"   # seconds; itch's processing queue is not ours
CONFIRMED=0
_waited=0
while [ "$_waited" -lt "$CONFIRM_BUDGET" ]; do
    if "${BUTLER_BIN}" status "$ITCH_TARGET" 2>/dev/null | grep -q "$VERSION"; then
        CONFIRMED=1; break
    fi
    sleep 8; _waited=$((_waited+8))
done
# Assert the OUTCOME (this version registered), not a precondition (the word
# "linux" appears somewhere in a table). Two bugs in the original one-liner:
#   * it was hardcoded `grep -i linux`, so after parameterization a successful
#     Windows push would report failure and exit 4 — a false alarm on a real ship
#   * even on Linux it proved the wrong thing. The channel name is in the table
#     whether or not the new build landed, so it could pass on a push that never
#     registered. The loop above already waits for VERSION; this must check it.
# THE CONFIRMATION IS NOT THE PUSH, AND IT USED TO FAIL THE BATCH AS THOUGH IT WERE.
#
# On v3.33.294-alpha this exited 4 after ~5 minutes because itch was still processing. The
# push had SUCCEEDED — the status table printed by this very block already showed
# `#1966981 v3.33.294-alpha+5aef5287` — and publish_all stopped the batch, leaving web
# unattempted and the STORE SPLIT across two versions for half an hour. A split store is a
# worse state than an unconfirmed channel, and the stop produced it.
#
# The severities were inverted. `butler push` failing IS fatal and is already covered: this
# script runs under `set -euo pipefail`, so a non-zero push aborts before reaching here. What
# follows is a CONFIRMATION that the push registered — advisory, because the authoritative
# check is store-wide and happens after every channel (publish_all asserts store_status.sh).
#
# A fixed wall-clock budget is also a guess about someone else's queue, which is the same
# shape as the flat sleeps replaced with polling in the web smoke. Budget raised to 15 min and
# made overridable; exceeding it is REPORTED, not fatal.
if [ "$CONFIRMED" -eq 1 ]; then
    echo "[${PLAT}] LIVE: ${VERSION} — https://struktured.itch.io/cowardly-irregular"
else
    echo "[${PLAT}] PUSHED, NOT YET CONFIRMED: ${VERSION} has not appeared in butler status" >&2
    echo "        after ${CONFIRM_BUDGET}s. butler reported the push succeeded; itch may still" >&2
    echo "        be processing. NOT failing the batch — the authoritative check is" >&2
    echo "        tools/store_status.sh across all three channels, which publish_all asserts" >&2
    echo "        after the last one. Verify before assuming it shipped:" >&2
    echo "        https://itch.io/dashboard" >&2
    "${BUTLER_BIN}" status "$ITCH_TARGET" >&2 || true
fi
