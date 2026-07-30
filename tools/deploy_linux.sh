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

ITCH_TARGET="struktured/cowardly-irregular:linux"
OUT_DIR="build/linux"
BIN="${OUT_DIR}/cowardly-irregular.x86_64"
BUTLER_BIN="$(command -v butler || echo ./butler-bin/butler)"

mkdir -p tmp "$OUT_DIR"
echo "[linux] target ${VERSION}  publish=${PUBLISH}"

# ── gate 0: import prewarm ───────────────────────────────────────────────────
# A fresh worktree has no .godot cache, so res:// paths resolve to nothing while
# the files sit right there on disk. A test run in that state exits 0 having run
# NOTHING, which is indistinguishable from success. Cheap and idempotent once warm.
echo "[linux] gate 0/4: import prewarm"
godot --headless --audio-driver Dummy --import --quit > tmp/linux_import.log 2>&1; EC=$?
test $EC -eq 0 || { echo "[linux] BLOCKED: asset import failed — see tmp/linux_import.log" >&2; exit 1; }

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
EXPORT_DIR_REAL="${HOME}/.local/share/godot/app_userdata/Cowardly Irregular/script_exports"
SNAP_DIR="tmp/script_exports_snapshot"
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
    echo "[linux] restored $(find "$SNAP_DIR" -type f | wc -l) exported script(s)"
}
if [ -d "$EXPORT_DIR_REAL" ] && [ -n "$(ls -A "$EXPORT_DIR_REAL" 2>/dev/null)" ]; then
    rm -rf "$SNAP_DIR"; mkdir -p "$SNAP_DIR"
    cp -a "$EXPORT_DIR_REAL/." "$SNAP_DIR/"
    echo "[linux] gate 0b: snapshotted $(find "$SNAP_DIR" -type f | wc -l) exported script(s)"
    # Restore on ANY exit, including a gate failure. A restore that only runs on
    # the success path is the teardown-abort shape: the thing you were protecting
    # is lost exactly when something else went wrong.
    trap _restore_exports EXIT
else
    echo "[linux] gate 0b: no exported scripts to protect"
fi

# ── gate 1: test suite ───────────────────────────────────────────────────────
# gate.sh checks Totals-present, scripts-run == test files on disk, reports
# tests that asserted NOTHING, and returns a real exit code. Consult it; do not
# parse its output.
echo "[linux] gate 1/4: test suite (tools/gate.sh)"
if [ -x tools/gate.sh ]; then
    ./tools/gate.sh > tmp/linux_gate.log 2>&1; EC=$?
    tail -12 tmp/linux_gate.log
    test $EC -eq 0 || { echo "[linux] BLOCKED: suite gate failed (exit ${EC}) — tmp/linux_gate.log" >&2; exit 1; }
else
    echo "[linux] BLOCKED: tools/gate.sh missing. Refusing to substitute a weaker check —" >&2
    echo "        a hand-rolled [Failed] count is what let a vacuous run reach a publish." >&2
    exit 1
fi

# ── gate 2: export ───────────────────────────────────────────────────────────
echo "[linux] gate 2/4: export"
godot --headless --audio-driver Dummy --export-release "Linux" "$BIN" > tmp/linux_export.log 2>&1; EC=$?
test $EC -eq 0 || { echo "[linux] BLOCKED: export failed — see tmp/linux_export.log" >&2; exit 2; }
[ -s "$BIN" ] || { echo "[linux] BLOCKED: export reported success but produced no binary" >&2; exit 2; }
echo "[linux] binary: $(( $(stat -c%s "$BIN") / 1048576 )) MiB"

# ── gate 3: does it actually boot? ───────────────────────────────────────────
# The gate web cannot have. An export can succeed and still produce something
# that dies on startup — a missing autoload, an unresolved class_name, a broken
# manifest entry. Asserting a POSITIVE marker rather than the absence of errors:
# "no errors" is also what an empty log looks like.
echo "[linux] gate 3/4: boot smoke"
timeout 120 "$BIN" --headless --quit > tmp/linux_boot.log 2>&1 || true
if ! grep -q "\[GAME\] Started" tmp/linux_boot.log; then
    echo "[linux] BLOCKED: exported binary did not reach '[GAME] Started'" >&2
    grep -iE "SCRIPT ERROR|Failed to load|Parse Error" tmp/linux_boot.log | head -5 >&2
    exit 3
fi
BOOT_ERRS=$(grep -icE "SCRIPT ERROR|Failed to load script" tmp/linux_boot.log || true)
echo "[linux] booted to title screen · script errors during boot: ${BOOT_ERRS}"
[ "$BOOT_ERRS" = "0" ] || echo "[linux] WARNING: booted, but with ${BOOT_ERRS} script error(s) — see tmp/linux_boot.log"

# ── gate 4: publish, only if explicitly asked ───────────────────────────────
if [ "$PUBLISH" != "1" ]; then
    echo "[linux] gate 4/4: SKIPPED — build verified, nothing published."
    echo "[linux] run it: ${BIN}"
    echo "[linux] to publish: tools/deploy_linux.sh --publish ${VERSION}"
    exit 0
fi

echo "[linux] gate 4/4: pushing to ${ITCH_TARGET} (userversion ${VERSION})"
"${BUTLER_BIN}" push "$OUT_DIR" "$ITCH_TARGET" --userversion "$VERSION"
# Bounded wait. deploy_web.sh's equivalent loop has no timeout, so a version that
# never registers hangs the deploy forever instead of reporting anything.
for _ in $(seq 1 40); do
    "${BUTLER_BIN}" status "$ITCH_TARGET" 2>/dev/null | grep -q "$VERSION" && break
    sleep 8
done
"${BUTLER_BIN}" status "$ITCH_TARGET" | grep -i linux || {
    echo "[linux] WARNING: pushed, but ${VERSION} has not appeared in butler status after ~5 min." >&2
    echo "        Check https://itch.io/dashboard before assuming it shipped." >&2
    exit 4
}
echo "[linux] LIVE: ${VERSION} — https://struktured.itch.io/cowardly-irregular"
