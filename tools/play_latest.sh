#!/usr/bin/env bash
# play_latest.sh — play the newest TAGGED build from source, in a checkout nobody else moves.
# struktured's 2026-10-12 morning session ran code a week old: he launches from whichever
# checkout is to hand, and every lane's tree sits at a different commit. This keeps ONE
# dedicated worktree at the latest vX.Y.Z-alpha tag and launches the game from it.
#
#   tools/play_latest.sh            update the play worktree to the newest tag, then launch
#   tools/play_latest.sh --print    say what it would do and exit (no fetch of new state, no launch)
#   tools/play_latest.sh --prepare  update and import the play worktree, but do not launch
#   tools/play_latest.sh v3.33.657-alpha    play that tag instead of the newest
#
# It NEVER restarts a running game: if a godot is already running from the play worktree it
# says so and stops, because moving the tree under a live session is how a session dies.
# The import is sandboxed (tmp/xdg); the launch is not — his user:// is where his saves live.
set -euo pipefail

# Everything runs inside main() so bash has read the WHOLE file before the checkout below can replace it
# (this script may live in the very worktree it moves).
main() {
  REPO="$(cd "$(dirname "$0")/.." && pwd)"
  PLAY_DIR="${COWIR_PLAY_DIR:-$HOME/projects/cowir-play}"
  PRINT=0
  PREPARE=0
  WANT=""
  for a in "$@"; do
    case "$a" in
      --print) PRINT=1 ;;
      --prepare) PREPARE=1 ;;
      v*) WANT="$a" ;;
      *) echo "play_latest: unknown argument '$a'" >&2; exit 2 ;;
    esac
  done

  cd "$REPO"
  [ "$PRINT" = "1" ] || git fetch -q origin --tags
  if [ -z "$WANT" ]; then
    WANT="$(git for-each-ref --count=1 --sort=-v:refname --format='%(refname:short)' 'refs/tags/v*-alpha')"
  fi
  if [ -z "$WANT" ] || ! git rev-parse -q --verify "refs/tags/$WANT" > /dev/null; then
    echo "play_latest: no such tag '${WANT:-<none found>}'" >&2
    exit 2
  fi
  SHA="$(git rev-list -n 1 "$WANT")"

  HAVE="<no worktree yet>"
  if [ -d "$PLAY_DIR/.git" ] || [ -f "$PLAY_DIR/.git" ]; then
    HAVE="$(git -C "$PLAY_DIR" rev-parse HEAD)"
  fi
  echo "play_latest: tag $WANT = ${SHA:0:9} · play worktree $PLAY_DIR is at ${HAVE:0:9}"

  for p in $(pgrep -x godot 2> /dev/null || true); do
    if [ "$(readlink "/proc/$p/cwd" 2> /dev/null || true)" = "$PLAY_DIR" ]; then
      echo "play_latest: a game is already running from $PLAY_DIR (pid $p) — not touching it. Quit it first to update." >&2
      exit 3
    fi
  done

  if [ "$PRINT" = "1" ]; then
    [ "$HAVE" = "$SHA" ] && echo "play_latest: already current — would launch as is" || echo "play_latest: would move the worktree to $WANT, import, then launch"
    exit 0
  fi

  if [ "$HAVE" = "<no worktree yet>" ]; then
    git worktree add --detach "$PLAY_DIR" "$SHA"
  elif [ "$HAVE" != "$SHA" ]; then
    if [ -n "$(git -C "$PLAY_DIR" status --porcelain)" ]; then
      echo "play_latest: $PLAY_DIR has local changes — refusing to move it. Commit or discard them yourself." >&2
      exit 3
    fi
    git -C "$PLAY_DIR" checkout -q --detach "$SHA"
  fi

  cd "$PLAY_DIR"
  git lfs pull > /dev/null 2>&1 || true
  mkdir -p tmp
  XDG_DATA_HOME="$PLAY_DIR/tmp/xdg" timeout 900 godot --headless --audio-driver Dummy --import --quit > tmp/play_import.log 2>&1 \
    || { echo "play_latest: import failed — see $PLAY_DIR/tmp/play_import.log" >&2; exit 1; }
  if [ "$PREPARE" = "1" ]; then
    echo "play_latest: $PLAY_DIR is ready at $WANT — run tools/play_latest.sh (or ./launch.sh there) to play"
    exit 0
  fi
  echo "play_latest: launching $WANT from $PLAY_DIR"
  exec ./launch.sh
}

main "$@"
exit $?
