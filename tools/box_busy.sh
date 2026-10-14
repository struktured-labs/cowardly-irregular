#!/usr/bin/env bash
# box_busy.sh — may a lane run a godot sweep right now? A script can read this; it cannot read the channel.
#
#   tools/box_busy.sh            exit 0 = box free · 1 = busy (the reason is printed) · 2 = usage
#   tools/box_busy.sh --wait N   poll every 20s for up to N seconds, then answer as above
#
# Busy means either of the two states that broke the .691 web publish: cowir-main's fold chain or
# gate is running (it writes BOX_MARKER with its PID and removes it on exit), or cowir-deploy has a
# publish in flight (publish.log without publish.ec). A marker whose PID is dead is reported as
# stale and does not block — a crashed chain must not close the box forever.
set -u
BOX_MARKER="${BOX_MARKER:-/home/struktured/projects/cowir-main/tmp/BOX_BUSY}"
DEPLOY_DIR="${DEPLOY_DIR:-/home/struktured/projects/cowir-deploy-wt/tmp/_detached}"

busy_reason() {
  if [ -f "$BOX_MARKER" ]; then
    local pid; pid="$(sed -n 's/^pid=//p' "$BOX_MARKER" | head -1)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "fold chain/gate running: $(tr '\n' ' ' < "$BOX_MARKER")"; return 0
    fi
    echo "box_busy: stale marker (pid ${pid:-?} not alive), ignoring: $BOX_MARKER" >&2
  fi
  local d
  for d in "$DEPLOY_DIR"/v3.33.*/; do
    [ -f "$d/publish.log" ] && [ ! -f "$d/publish.ec" ] && { echo "publish in flight: $(basename "$d")"; return 0; }
  done
  return 1
}

case "${1:-}" in
  "") ;;
  --wait) case "${2:-}" in ''|*[!0-9]*) echo "usage: tools/box_busy.sh [--wait SECONDS]" >&2; exit 2 ;; esac ;;
  *) echo "usage: tools/box_busy.sh [--wait SECONDS]" >&2; exit 2 ;;
esac

if [ "${1:-}" = "--wait" ]; then
  end=$(( $(date +%s) + $2 ))
  while r="$(busy_reason)"; do
    [ "$(date +%s)" -ge "$end" ] && { echo "BUSY (gave up after ${2}s): $r"; exit 1; }
    sleep 20
  done
  echo "FREE"; exit 0
fi

if r="$(busy_reason)"; then echo "BUSY: $r"; exit 1; fi
echo "FREE"; exit 0
