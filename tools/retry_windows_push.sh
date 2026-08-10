#!/usr/bin/env bash
# retry_windows_push.sh — finish the Windows debut whose UPLOAD timed out.
#
# WHAT HAPPENED, 2026-08-09
#   tools/deploy_windows.sh --publish ran to gate 4 and passed EVERY gate:
#       gate 1  test suite   GREEN   7807/7807 passing, 0 failing, 1238/1238 scripts
#       gate 2  export       OK      tree byte-identical to gate 1's snapshot
#       gate 3  boot smoke   OK      booted to title screen UNDER WINE, 0 script errors
#       gate 3b combat smoke SKIPPED linux-only (wine+xvfb unverified) — a known gap
#       gate 4  butler push  FAILED  "context deadline exceeded" mid-upload of 328 MiB
#
#   The captured exit code was 1. The harness's completion notification said "exit code 0",
#   because the backgrounded command ended with `echo $? > file` and the notification
#   reports the LAST command. Reading the .ec FILE is what caught it. Do not trust the
#   notification; this script writes its status to a file for the same reason.
#
#   `butler status` afterwards: "No channel windows found". THE CHANNEL WAS NOT CREATED.
#   Nothing is public. The one-way door did not open, so a retry is still a debut and not
#   a repair.
#
# WHY THIS SCRIPT EXISTS RATHER THAN A COMMAND BLOCK
#   The retry needs a human's hands: the sandbox permission classifier declines publish
#   calls from the agent. It declined both the bare `butler push` and the gated script.
#   That is the correct default and this script does not try to evade it — it just puts
#   the same gated path behind one command you run yourself.
#
# USAGE
#   tools/retry_windows_push.sh --check     verify preconditions, PUBLISH NOTHING, exit 0/1
#   tools/retry_windows_push.sh --publish   re-run the FULL gated deploy, then push
#   tools/retry_windows_push.sh --fast      push the ALREADY-GATED artifact (md5-verified)
#
#   --check is safe to run at any time and is the default if you pass nothing.
set -uo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

# The tree and artifact that PASSED every gate. --fast refuses to push anything else.
GATED_SHA="08e90acf"
GATED_MD5="adb4b032cfa9ce5b8940ff0f5b304f73"
GATED_BYTES="344062096"
USERVERSION="v3.33.207-alpha+08e90acf"
TARGET="struktured/cowardly-irregular:windows"
ART="build/windows/cowardly-irregular.exe"
BUTLER="$(command -v butler || echo /home/struktured/.local/bin/butler)"

MODE="${1:---check}"

_hr() { printf '%s\n' "------------------------------------------------------------"; }

# ---------------------------------------------------------------- preconditions
# Every check NAMES what it found rather than returning a bare pass/fail, because a
# count or a boolean cannot tell "verified" from "never looked" — the failure mode this
# whole evening was about.
ok=0
_check() {
    local fail=0
    _hr; echo "PRECONDITIONS"; _hr

    local head dirty
    head="$(git rev-parse --short HEAD 2>/dev/null)"
    dirty="$(git status --porcelain 2>/dev/null | wc -l)"
    printf '  %-22s %s' "tree HEAD" "$head"
    if [ "$head" = "$GATED_SHA" ]; then echo "   OK (matches the gated tree)"
    else echo "   MISMATCH — gated tree was $GATED_SHA"; fail=1; fi

    # SCOPED DELIBERATELY. A dirty tree matters for --publish, which RE-EXPORTS the working
    # tree and would stamp BUILD_SHA with `-dirty`. It does NOT matter for --fast, where the
    # bits are already built and pinned by md5 — the artifact hash is a stronger statement
    # about what ships than any property of the tree that produced it.
    #   (This script's own file makes the tree dirty, which is how the distinction surfaced:
    #    the first version of this check refused --fast because the checker existed.)
    printf '  %-22s %s' "uncommitted files" "$dirty"
    if [ "$dirty" -eq 0 ]; then echo "        OK (no -dirty suffix)"
    elif [ "$MODE" != "--publish" ]; then
        echo "        note: irrelevant to --fast (md5 pins the bits); would block --publish"
        git status --porcelain | sed 's/^/                           /'
    else
        echo "        DIRTY — --publish re-exports the tree, so the label would say -dirty"
        git status --porcelain | sed 's/^/                           /'
        fail=1
    fi

    printf '  %-22s %s' "tag here" "$(git tag --points-at HEAD | tr '\n' ' ')"
    echo "   (label only; $GATED_SHA is the tree that was exported)"

    if [ -f "$ART" ]; then
        local bytes md5
        bytes="$(stat -c %s "$ART")"
        md5="$(md5sum "$ART" | cut -d' ' -f1)"
        printf '  %-22s %s\n' "artifact bytes" "$bytes"
        printf '  %-22s %s' "artifact md5" "$md5"
        if [ "$md5" = "$GATED_MD5" ] && [ "$bytes" = "$GATED_BYTES" ]; then
            echo "  OK (this is the binary that passed the gates)"
        else
            echo "  MISMATCH — NOT the gated binary; use --publish, not --fast"; fail=1
        fi
    else
        echo "  artifact                MISSING at $ART — use --publish to rebuild"; fail=1
    fi

    printf '  %-22s %s\n' "butler" "$BUTLER"
    [ -x "$BUTLER" ] || { echo "     butler NOT EXECUTABLE"; fail=1; }

    _hr; echo "CURRENT PUBLISHED STATE (nothing has been pushed by this script)"; _hr
    echo "  windows:"; "$BUTLER" status "$TARGET" 2>&1 | grep -Ev 'New version|Current version|Latest version|butler upgrade|^\+---|^\|  *\|' | sed 's/^/    /'
    echo "  linux (NOT this lane's to touch):"
    "$BUTLER" status struktured/cowardly-irregular:linux 2>&1 | grep -E '^\| linux' | sed 's/^/    /'

    _hr
    if [ "$fail" -eq 0 ]; then
        echo "RESULT: preconditions OK."
        echo "  --fast     pushes $USERVERSION to $TARGET (gates NOT re-run;"
        echo "             the md5 above is the binary that passed them ~20 min ago)"
        if [ "$dirty" -eq 0 ]; then
            echo "  --publish  also available — clean tree, would re-gate from scratch (~15 min)"
        else
            echo "  --publish  would label the build -dirty ($dirty untracked/modified file(s)"
            echo "             above). Commit or stash them first, or use --fast."
        fi
    else
        echo "RESULT: preconditions FAILED — see the MISMATCH/MISSING line(s) above."
        echo "        Do not use --fast. Rebuild with --publish from a clean $GATED_SHA."
    fi
    _hr
    ok=$fail
    return $fail
}

case "$MODE" in
  --check)
      _check; exit $?
      ;;

  --fast)
      _check || { echo "REFUSING: preconditions failed." >&2; exit 1; }
      echo
      echo ">>> pushing the ALREADY-GATED artifact. Gates are NOT re-run."
      echo ">>> this is a DEBUT: it creates the 'windows' channel, and butler cannot delete one."
      echo ">>> the build is BOOT-verified under wine, NOT combat-verified on Windows."
      # Confirmation is an ARGUMENT, not a prompt: run inline (`! ./tools/...`) and stdin
      # is not a terminal, so a `read` would either hang or silently take EOF as "no".
      a="${2:-}"
      [ -z "$a" ] && [ -t 0 ] && read -r -p ">>> type CREATE to proceed: " a
      [ "$a" = "CREATE" ] || {
          echo "aborted — pass CREATE as the second argument to proceed:"
          echo "    $0 $MODE CREATE"; exit 1; }
      "$BUTLER" push build/windows "$TARGET" --userversion "$USERVERSION"
      ec=$?
      echo "PUSH_EXIT=$ec" | tee tmp/win_retry.ec
      _hr; echo "AFTER:"; "$BUTLER" status "$TARGET" 2>&1 | grep -E '^\| windows|No channel'
      echo
      echo "The artifact is the BUILD ID, not the version string — a version string that"
      echo "was already on the channel proves nothing. On a debut, the channel existing at"
      echo "all is the evidence."
      exit $ec
      ;;

  --publish)
      echo ">>> re-running the FULL gated chain (~15 min; the test suite is most of it)."
      echo ">>> this is a DEBUT: it creates the 'windows' channel, and butler cannot delete one."
      # Confirmation is an ARGUMENT, not a prompt: run inline (`! ./tools/...`) and stdin
      # is not a terminal, so a `read` would either hang or silently take EOF as "no".
      a="${2:-}"
      [ -z "$a" ] && [ -t 0 ] && read -r -p ">>> type CREATE to proceed: " a
      [ "$a" = "CREATE" ] || {
          echo "aborted — pass CREATE as the second argument to proceed:"
          echo "    $0 $MODE CREATE"; exit 1; }
      mkdir -p tmp
      bash tools/deploy_windows.sh --publish > tmp/win_retry.log 2>&1
      ec=$?
      # Written to a FILE deliberately. A trailing `echo` makes any wrapper report the
      # ECHO's status, which is how the first run's failure read as "exit code 0".
      echo "$ec" > tmp/win_retry.ec
      _hr
      echo "CAPTURED EXIT CODE: $ec   (read this, never a completion notification)"
      tail -25 tmp/win_retry.log
      _hr; echo "AFTER:"; "$BUTLER" status "$TARGET" 2>&1 | grep -E '^\| windows|No channel'
      exit $ec
      ;;

  *)
      echo "usage: $0 [--check|--fast|--publish]" >&2; exit 2 ;;
esac
