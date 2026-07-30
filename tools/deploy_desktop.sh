#!/usr/bin/env bash
# deploy_linux.sh — build, verify and (only when explicitly told) publish the
# native Linux build.
#
# WHY LINUX IS FIRST-CLASS HERE
#   It is struktured's own platform and his dev cycle. Not a market tier — the
#   build he actually plays. Web stays the portability/collaboration channel
#   (phone, laptops, friends, and the artist's sprite review).
#
# HOW THIS DIFFERS FROM deploy_web.sh
#   * No pck size gate. That limit is itch's HTML5 *embed* cap; a downloadable
#     build is not subject to it. A 316 MB Linux binary is unremarkable.
#   * A BOOT gate instead of a render/WASM smoke. The exported binary is run
#     headless and must reach the title screen. Web cannot do this; desktop can,
#     and it is the cheapest possible proof the artifact is not merely large.
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

ITCH_TARGET="struktured/cowardly-irregular:${CHANNEL}"
BIN="${OUT_DIR}/${ARTIFACT}"
BUTLER_BIN="$(command -v butler || echo ./butler-bin/butler)"

mkdir -p tmp "$OUT_DIR"
echo "[${PLAT}] target ${VERSION}  publish=${PUBLISH}"

# ── gate 0: import prewarm ───────────────────────────────────────────────────
# A fresh worktree has no .godot cache, so res:// paths resolve to nothing while
# the files sit right there on disk. A test run in that state exits 0 having run
# NOTHING, which is indistinguishable from success. Cheap and idempotent once warm.
echo "[${PLAT}] gate 0/4: import prewarm"
godot --headless --audio-driver Dummy --import --quit > tmp/${PLAT}_import.log 2>&1; EC=$?
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
# user://autogrind/ IS DELIBERATELY NOT RESTORED. I had it in this list for about
# a minute, which would have been strictly worse than the gap it was closing:
#   * tests CANNOT write there — every save path in src/autogrind/AutogrindSystem.gd
#     opens with `if _test_disable_persistence: return`, set by 24 test files,
#     added after autogrind tests corrupted struktured's live saves on 2026-07-14
#   * so it is the GAME's live save path, and its mtimes during a deploy window
#     mean he is playing — restoring it would revert his session
# The lesson generalises: the paths a deploy may put back are the ones only a
# test writes, never the ones the game writes. Adding a directory here needs that
# established, not assumed — I assumed it from a suspicious mtime and was wrong.
FULL_SNAP="tmp/userdata_snapshot"
RESTORE_PATHS=(script_exports)
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
        [ -e "$FULL_SNAP/$rel" ] && continue
        changed=$(( changed + 1 ))
        echo "[${PLAT}]   new: $rel"
    done < <(find "$USERDATA" -type f | sort)
    case $changed in
        0) echo "[${PLAT}] userdata drift outside ${RESTORE_PATHS[*]}: none" ;;
        *) echo "[${PLAT}] NOTE: ${changed} user:// file(s) changed during this deploy." >&2
           echo "        NOT reverted — if you were playing, that is your own save." >&2
           echo "        Pre-deploy copy kept at ${FULL_SNAP}/ if you need to compare." >&2 ;;
    esac
}
# ONE trap, both handlers. `trap X EXIT` followed by `trap Y EXIT` does not add a
# second handler — the second REPLACES the first, silently. I wrote both and the
# restore would have won, leaving the drift report defined and never called: a
# handler that looks installed and isn't, which is this evening's whole theme.
_on_exit() { _restore_exports; _report_userdata_drift; }
trap _on_exit EXIT
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
echo "[${PLAT}] gate 1/4: test suite (tools/gate.sh)"
if [ -x tools/gate.sh ]; then
    ./tools/gate.sh > tmp/${PLAT}_gate.log 2>&1; EC=$?
    tail -12 tmp/${PLAT}_gate.log
    test $EC -eq 0 || { echo "[${PLAT}] BLOCKED: suite gate failed (exit ${EC}) — tmp/${PLAT}_gate.log" >&2; exit 1; }
else
    echo "[${PLAT}] BLOCKED: tools/gate.sh missing. Refusing to substitute a weaker check —" >&2
    echo "        a hand-rolled [Failed] count is what let a vacuous run reach a publish." >&2
    exit 1
fi

# ── gate 2: export ───────────────────────────────────────────────────────────
echo "[${PLAT}] gate 2/4: export"
godot --headless --audio-driver Dummy --export-release "$PRESET" "$BIN" > tmp/${PLAT}_export.log 2>&1; EC=$?
test $EC -eq 0 || { echo "[${PLAT}] BLOCKED: export failed — see tmp/${PLAT}_export.log" >&2; exit 2; }
[ -s "$BIN" ] || { echo "[${PLAT}] BLOCKED: export reported success but produced no binary" >&2; exit 2; }
echo "[${PLAT}] binary: $(( $(stat -c%s "$BIN") / 1048576 )) MiB"

# ── gate 3: does it actually boot? ───────────────────────────────────────────
# The gate web cannot have. An export can succeed and still produce something
# that dies on startup — a missing autoload, an unresolved class_name, a broken
# manifest entry. Asserting a POSITIVE marker rather than the absence of errors:
# "no errors" is also what an empty log looks like.
echo "[${PLAT}] gate 3/4: boot smoke"
( cd "$OUT_DIR" && timeout 240 ${BOOT_RUNNER[@]+"${BOOT_RUNNER[@]}"} "./${ARTIFACT}" \
    --headless --quit ) > "tmp/${PLAT}_boot.log" 2>&1 || true
if ! grep -q "\[GAME\] Started" tmp/${PLAT}_boot.log; then
    echo "[${PLAT}] BLOCKED: exported binary did not reach '[GAME] Started'" >&2
    grep -iE "SCRIPT ERROR|Failed to load|Parse Error" tmp/${PLAT}_boot.log | head -5 >&2
    exit 3
fi
BOOT_ERRS=$(grep -icE "SCRIPT ERROR|Failed to load script" tmp/${PLAT}_boot.log || true)
echo "[${PLAT}] booted to title screen · script errors during boot: ${BOOT_ERRS}"
[ "$BOOT_ERRS" = "0" ] || echo "[${PLAT}] WARNING: booted, but with ${BOOT_ERRS} script error(s) — see tmp/${PLAT}_boot.log"

# ── gate 4: publish, only if explicitly asked ───────────────────────────────
if [ "$PUBLISH" != "1" ]; then
    echo "[${PLAT}] gate 4/4: SKIPPED — build verified, nothing published."
    echo "[${PLAT}] run it: ${BIN}"
    echo "[${PLAT}] to publish: tools/deploy_${PLAT}.sh --publish ${VERSION}"
    exit 0
fi

echo "[${PLAT}] gate 4/4: pushing to ${ITCH_TARGET} (userversion ${VERSION})"
"${BUTLER_BIN}" push "$OUT_DIR" "$ITCH_TARGET" --userversion "$VERSION"
# Bounded wait. deploy_web.sh's equivalent loop has no timeout, so a version that
# never registers hangs the deploy forever instead of reporting anything.
for _ in $(seq 1 40); do
    "${BUTLER_BIN}" status "$ITCH_TARGET" 2>/dev/null | grep -q "$VERSION" && break
    sleep 8
done
# Assert the OUTCOME (this version registered), not a precondition (the word
# "linux" appears somewhere in a table). Two bugs in the original one-liner:
#   * it was hardcoded `grep -i linux`, so after parameterization a successful
#     Windows push would report failure and exit 4 — a false alarm on a real ship
#   * even on Linux it proved the wrong thing. The channel name is in the table
#     whether or not the new build landed, so it could pass on a push that never
#     registered. The loop above already waits for VERSION; this must check it.
"${BUTLER_BIN}" status "$ITCH_TARGET" | grep -q "$VERSION" || {
    echo "[${PLAT}] WARNING: pushed, but ${VERSION} has not appeared in butler status after ~5 min." >&2
    echo "        Check https://itch.io/dashboard before assuming it shipped." >&2
    "${BUTLER_BIN}" status "$ITCH_TARGET" >&2 || true
    exit 4
}
echo "[${PLAT}] LIVE: ${VERSION} — https://struktured.itch.io/cowardly-irregular"
