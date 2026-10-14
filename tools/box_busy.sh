#!/usr/bin/env bash
# box_busy.sh — may a lane run a godot sweep right now? A script can read this; it cannot read the channel.
#
#   tools/box_busy.sh            exit 0 = box free · 1 = busy (the reason is printed) · 2 = usage
#   tools/box_busy.sh --wait N   poll every 20s for up to N seconds, then answer as above
#   tools/box_busy.sh --selftest watch each arm flip (exit 0 = all five did)
#
# Busy means either of the two states that broke the .691 web publish: cowir-main's fold chain or
# gate is running (it writes BOX_MARKER with its PID and removes it on exit), or cowir-deploy has a
# publish in flight (publish.log without publish.ec), or a godot is running in the fold tree itself.
# A marker whose PID is dead (fold marker, or a publish.pid beside the log) is reported as stale and
# does not block — a crashed chain or killed publish must not close the box forever.
set -u
BOX_MARKER="${BOX_MARKER:-/home/struktured/projects/cowir-main/tmp/BOX_BUSY}"
DEPLOY_DIR="${DEPLOY_DIR:-/home/struktured/projects/cowir-deploy-wt/tmp/_detached}"
FOLD_TREE="${FOLD_TREE:-/home/struktured/projects/cowir-main}"

busy_reason() {
  if [ -f "$BOX_MARKER" ]; then
    local pid; pid="$(sed -n 's/^pid=//p' "$BOX_MARKER" | head -1)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "fold chain/gate running: $(tr '\n' ' ' < "$BOX_MARKER")"; return 0
    fi
    echo "box_busy: stale marker (pid ${pid:-?} not alive), ignoring: $BOX_MARKER" >&2
  fi
  ## A godot running in the fold tree IS the chain or gate, marker or not — so a missing marker
  ## cannot turn a running gate into FREE (cowir-autogrind: it said FREE beside the .692 chain).
  local p c
  for p in /proc/[0-9]*; do
    [ "$(readlink "$p/exe" 2>/dev/null)" = "/usr/bin/godot" ] || continue
    c="$(readlink "$p/cwd" 2>/dev/null)"
    case "$c" in "$FOLD_TREE"|"$FOLD_TREE"/*) echo "fold-tree godot running: pid ${p#/proc/} cwd=$c"; return 0 ;; esac
  done
  local d
  for d in "$DEPLOY_DIR"/v3.33.*/; do
    [ -f "$d/publish.log" ] && [ ! -f "$d/publish.ec" ] || continue
    ## A publish that writes publish.pid gets the same liveness test as the fold marker.
    if [ -f "$d/publish.pid" ] && ! kill -0 "$(head -1 "$d/publish.pid")" 2>/dev/null; then
      echo "box_busy: stale publish marker (pid not alive), ignoring: $(basename "$d")" >&2; continue
    fi
    echo "publish in flight: $(basename "$d")"; return 0
  done
  return 1
}

others() {  # other lanes' engines: reported, not judged
  local n=0 p c
  for p in /proc/[0-9]*; do
    [ "$(readlink "$p/exe" 2>/dev/null)" = "/usr/bin/godot" ] || continue
    c="$(readlink "$p/cwd" 2>/dev/null)"; case "$c" in "$FOLD_TREE"|"$FOLD_TREE"/*) continue ;; esac
    n=$((n+1))
  done
  echo "$n"
}

if [ "${1:-}" = "--selftest" ]; then  # watch the answer flip, so a FREE is never trusted unseen
  mkdir -p "$(dirname "$0")/../tmp"; T="$(mktemp -d "$(dirname "$0")/../tmp/box_busy_selftest.XXXXXX")"; trap 'rm -rf "$T"' EXIT
  fails=0
  BOX_MARKER="$T/m" DEPLOY_DIR="$T/d" FOLD_TREE="$T/none" "$0" >/dev/null || { echo "FAIL: not FREE with nothing set"; fails=1; }
  printf 'pid=%s\n' "$$" > "$T/m"
  out="$(BOX_MARKER="$T/m" DEPLOY_DIR="$T/d" FOLD_TREE="$T/none" "$0")"
  case "$out" in "BUSY: fold chain/gate running"*) ;; *) echo "FAIL: a live marker did not read BUSY for THAT reason: $out"; fails=1 ;; esac
  printf 'pid=999999\n' > "$T/m"
  BOX_MARKER="$T/m" DEPLOY_DIR="$T/d" FOLD_TREE="$T/none" "$0" >/dev/null 2>&1 || { echo "FAIL: a dead marker blocked"; fails=1; }
  rm -f "$T/m"; mkdir -p "$T/d/v3.33.0-alpha"; : > "$T/d/v3.33.0-alpha/publish.log"
  out="$(BOX_MARKER="$T/m" DEPLOY_DIR="$T/d" FOLD_TREE="$T/none" "$0")"
  case "$out" in "BUSY: publish in flight: v3.33.0-alpha") ;; *) echo "FAIL: a publish in flight did not read BUSY naming its tag: $out"; fails=1 ;; esac
  echo 999999 > "$T/d/v3.33.0-alpha/publish.pid"
  BOX_MARKER="$T/m" DEPLOY_DIR="$T/d" FOLD_TREE="$T/none" "$0" >/dev/null 2>&1 || { echo "FAIL: a dead publish.pid blocked"; fails=1; }
  [ "$fails" = 0 ] && echo "box_busy selftest: 5/5 arms flipped as expected"
  exit "$fails"
fi

case "${1:-}" in
  "") ;;
  --wait) case "${2:-}" in ''|*[!0-9]*) echo "usage: tools/box_busy.sh [--wait SECONDS]" >&2; exit 2 ;; esac ;;
  *) echo "usage: tools/box_busy.sh [--wait SECONDS]" >&2; exit 2 ;;
esac

if [ "${1:-}" = "--wait" ]; then
  ## The bound sits in the loop condition, where check_polling_bounded can read it (.693 pre-gate).
  waited=0
  while [ "$waited" -lt "$2" ]; do
    r="$(busy_reason)" || { echo "FREE"; exit 0; }
    sleep 20
    waited=$(( waited + 20 ))
  done
  if r="$(busy_reason)"; then echo "BUSY (gave up after ${2}s): $r"; exit 1; fi
  echo "FREE"; exit 0
fi

if r="$(busy_reason)"; then echo "BUSY: $r"; exit 1; fi
echo "FREE (other lanes' godot up: $(others))"; exit 0
