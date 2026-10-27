#!/usr/bin/env bash
# box_busy.sh — may a lane run a godot sweep right now? A script can read this; it cannot read the channel.
#
#   tools/box_busy.sh            exit 0 = box free · 1 = busy (the reason is printed) · 2 = usage
#   tools/box_busy.sh --wait N   poll every 20s for up to N seconds, then answer as above
#   tools/box_busy.sh --publish  exit 0 = a publish is in flight (named, with its lane) · 1 = none
#   tools/box_busy.sh --others   exit 0 = another lane has an engine up (count printed) · 1 = none
#   tools/box_busy.sh --marker   print the BOX_MARKER path every box-protocol script must use
#   tools/box_busy.sh --roots    print each _detached dir the publish scan reads (exit 1 = none exist)
#   tools/box_busy.sh --selftest watch each arm flip (exit 0 = all eleven did)
#
# ONE SOURCE. The fold templates used to carry their own copies of the marker path AND their own
# publish scan, hardcoded to cowir-deploy-wt/tmp/_detached: the single-publisher defect this file
# fixed on 2026-10-17, still live in chain.sh.tmpl and rungate.sh.tmpl, so the fold's engine wait
# could not see a publish launched from any other lane. They now ask --publish and --marker.
#
# Busy means either of the two states that broke the .691 web publish: cowir-main's fold chain or
# gate is running (it writes BOX_MARKER with its PID and removes it on exit), or cowir-deploy has a
# ANY lane has a publish in flight (publish.log without publish.ec), or a godot is running in the fold tree itself.
# A marker whose PID is dead (fold marker, or a publish.pid beside the log) is reported as stale and
# does not block — a crashed chain or killed publish must not close the box forever.
set -u
FOLD_TREE="${FOLD_TREE:-/home/struktured/projects/cowir-main}"
## What an engine LOOKS like, injectable so the engine arms have a positive control that does not
## need a real godot: a negative from --others is not evidence until the answer has been watched
## flipping to YES, and starting an engine to prove it is exactly what the tool exists to prevent.
## Resolved to an ABSOLUTE path: /proc/<pid>/exe is always absolute, so a relative
## BOX_BUSY_ENGINE never matches and the control reads FREE while its stand-in is running —
## measured. A no-op for production: /usr/bin/godot is a real file, not a symlink.
ENGINE_EXE="$(readlink -f "${BOX_BUSY_ENGINE:-/usr/bin/godot}" 2>/dev/null || echo "${BOX_BUSY_ENGINE:-/usr/bin/godot}")"
BOX_MARKER="${BOX_MARKER:-$FOLD_TREE/tmp/BOX_BUSY}"
## DEPLOY_DIR named ONE publisher, so a publish launched from any other lane's worktree was
## INVISIBLE: measured 2026-10-17, this said FREE while v3.33.697-alpha published from
## cowir-sprites. A glob over every lane adds 1 true positive and 0 false ones (270 marker
## dirs on disk, 269 carry publish.ec so the log-without-ec predicate excludes them).
DEPLOY_DIR="${DEPLOY_DIR:-}"
## publish_detached.sh's _logdir writes ONE shape, <root>/tmp/_detached/<tag> (arm 11 asks _logdir
## itself). tmp/detached is the LEGACY shape its second branch wrote until 2026-10-24: kept, because
## --rollback publishes an old tag with that tag's own tools, and an old producer still writes it.
DEPLOY_GLOB="${DEPLOY_GLOB:-/home/struktured/projects/*/tmp/_detached /home/struktured/projects/*/tmp/detached}"

## The dirs the publish scan reads. A glob matching nothing expands to itself, which names no real
## dir, so the scan finds no publish and answers FREE: the one fail-OPEN direction here. --roots
## and arm 11 exist so that answer is never silent.
deploy_roots() {
  if [ -n "$DEPLOY_DIR" ]; then echo "$DEPLOY_DIR"; else echo $DEPLOY_GLOB; fi
}

## A publish in flight in ANY lane: publish.log without publish.ec, unless its publish.pid is dead.
publish_reason() {
  local d who
  for d in $(for r in $(deploy_roots); do printf '%s\n' "$r"/v3.33.*/; done); do
    [ -f "$d/publish.log" ] && [ ! -f "$d/publish.ec" ] || continue
    if [ -f "$d/publish.pid" ] && ! kill -0 "$(head -1 "$d/publish.pid")" 2>/dev/null; then
      echo "box_busy: stale publish marker (pid not alive), ignoring: $(basename "$d")" >&2; continue
    fi
    case "$d" in
      */tmp/_detached/*) who="${d%%/tmp/_detached/*}"; who="$(basename "$who")" ;;
      */tmp/detached/*)  who="${d%%/tmp/detached/*}"; who="$(basename "$who")" ;;
      *) who="" ;;
    esac
    if [ -n "$who" ]; then echo "publish in flight: $(basename "$d") (from $who)"
    else echo "publish in flight: $(basename "$d")"; fi
    return 0
  done
  return 1
}

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
    [ "$(readlink "$p/exe" 2>/dev/null)" = "$ENGINE_EXE" ] || continue
    c="$(readlink "$p/cwd" 2>/dev/null)"
    case "$c" in "$FOLD_TREE"|"$FOLD_TREE"/*) echo "fold-tree godot running: pid ${p#/proc/} cwd=$c"; return 0 ;; esac
  done
  publish_reason && return 0
  return 1
}

others() {  # other lanes' engines: reported, not judged
  local n=0 p c
  for p in /proc/[0-9]*; do
    [ "$(readlink "$p/exe" 2>/dev/null)" = "$ENGINE_EXE" ] || continue
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
  ## ARM 6 — THE REGRESSION ARM. DEPLOY_DIR used to name ONE publisher, so a publish from any
  ## other lane's worktree read FREE. This arm takes the GLOB path (DEPLOY_DIR empty) and plants a
  ## marker in a lane that is not the old hardcoded one; it also pins that the lane is NAMED, since
  ## a BUSY you cannot attribute is a BUSY nobody can clear.
  mkdir -p "$T/lanes/some-other-lane/tmp/_detached/v3.33.0-alpha"
  : > "$T/lanes/some-other-lane/tmp/_detached/v3.33.0-alpha/publish.log"
  out="$(DEPLOY_DIR= DEPLOY_GLOB="$T/lanes/*/tmp/_detached" BOX_MARKER="$T/m" FOLD_TREE="$T/none" "$0")"
  case "$out" in
    "BUSY: publish in flight: v3.33.0-alpha (from some-other-lane)") ;;
    *) echo "FAIL: a publish in ANOTHER lane's worktree did not read BUSY naming that lane: $out"; fails=1 ;;
  esac
  ## and the glob must not invent a publish where none is in flight
  : > "$T/lanes/some-other-lane/tmp/_detached/v3.33.0-alpha/publish.ec"
  DEPLOY_DIR= DEPLOY_GLOB="$T/lanes/*/tmp/_detached" BOX_MARKER="$T/m" FOLD_TREE="$T/none" "$0" >/dev/null 2>&1 \
    || { echo "FAIL: a FINISHED publish (ec present) still blocked under the glob"; fails=1; }
  ## ARMS 7-10 — the two one-source modes the fold templates call. --publish must see the SAME
  ## lane-glob publish arm 6 sees, and must not see a finished or dead one.
  rm -f "$T/lanes/some-other-lane/tmp/_detached/v3.33.0-alpha/publish.ec"
  out="$(DEPLOY_DIR= DEPLOY_GLOB="$T/lanes/*/tmp/_detached" BOX_MARKER="$T/m" FOLD_TREE="$T/none" "$0" --publish)"; e=$?
  { [ "$e" = 0 ] && [ "$out" = "publish in flight: v3.33.0-alpha (from some-other-lane)" ]; } \
    || { echo "FAIL: --publish did not report another lane's publish (ec=$e): $out"; fails=1; }
  echo 999999 > "$T/lanes/some-other-lane/tmp/_detached/v3.33.0-alpha/publish.pid"
  DEPLOY_DIR= DEPLOY_GLOB="$T/lanes/*/tmp/_detached" BOX_MARKER="$T/m" FOLD_TREE="$T/none" "$0" --publish >/dev/null 2>&1 \
    && { echo "FAIL: --publish reported a publish whose pid is dead"; fails=1; }
  ## ... and --publish ignores the fold marker: the chain asks it while HOLDING that marker.
  rm -f "$T/lanes/some-other-lane/tmp/_detached/v3.33.0-alpha/publish.pid"
  : > "$T/lanes/some-other-lane/tmp/_detached/v3.33.0-alpha/publish.ec"; printf 'pid=%s\n' "$$" > "$T/m"
  DEPLOY_DIR= DEPLOY_GLOB="$T/lanes/*/tmp/_detached" BOX_MARKER="$T/m" FOLD_TREE="$T/none" "$0" --publish >/dev/null 2>&1 \
    && { echo "FAIL: --publish read the fold marker as a publish (the chain would wait on itself)"; fails=1; }
  ## --marker: the default derives from FOLD_TREE (one literal), and an explicit BOX_MARKER wins.
  out="$(env -u BOX_MARKER FOLD_TREE="$T/ft" "$0" --marker)"
  [ "$out" = "$T/ft/tmp/BOX_BUSY" ] || { echo "FAIL: --marker default not derived from FOLD_TREE: $out"; fails=1; }
  out="$(BOX_MARKER="$T/x" FOLD_TREE="$T/ft" "$0" --marker)"
  [ "$out" = "$T/x" ] || { echo "FAIL: --marker ignored an explicit BOX_MARKER: $out"; fails=1; }
  ## ARM 11 — THE SHIPPED DEFAULT. Arms 1-10 all override DEPLOY_GLOB, so a typo in its default
  ## passed 10/10 while the scan read FREE beside every publish. This arm must run UNOVERRIDDEN to
  ## mean anything: it asks the real filesystem whether the default names at least one real dir.
  out="$(env -u DEPLOY_DIR -u DEPLOY_GLOB "$0" --roots)" \
    || { echo "FAIL: the shipped DEPLOY_GLOB default names no existing _detached dir (the scan would read FREE beside any publish): $out"; fails=1; }
  ## ... and an existing dir is not enough: a typo'd tmp/_detached -> tmp/detached passed the line
  ## above, because that dir exists too. So the default must also MATCH where _logdir writes. The
  ## shapes come from publish_detached.sh's OWN _logdir, driven down both branches, not a hand copy;
  ## the legacy shape is listed by hand because no current producer writes it.
  dflt="$(env -u DEPLOY_GLOB bash -c 'eval "$(command grep -m1 "^DEPLOY_GLOB=" "$1")"; printf "%s" "$DEPLOY_GLOB"' _ "$0")"
  pd="$(dirname "$0")/publish_detached.sh"
  shapes="$(bash -c 'eval "$(sed -n "/^_logdir() {/,/^}/p" "$1")"; declare -F _logdir >/dev/null || exit 9
                     dirname "$(_logdir v /home/struktured/projects/some-lane/tmp/pub1)"
                     dirname "$(_logdir v /home/struktured/projects/some-lane)"' _ "$pd")" \
    || { echo "FAIL: could not drive _logdir from $pd, so where publishes write is unknown"; fails=1; }
  [ "$(printf '%s\n' "$shapes" | command grep -c '^/')" = 2 ] \
    || { echo "FAIL: _logdir did not return two absolute dirs: $shapes"; fails=1; }
  for shape in $shapes /home/struktured/projects/some-lane/tmp/detached; do
    hit=0; set -f; for g in $dflt; do case "$shape" in $g) hit=1 ;; esac; done; set +f  # patterns, not paths
    [ "$hit" = 1 ] || { echo "FAIL: the shipped DEPLOY_GLOB ($dflt) does not cover $shape, a dir a publish writes"; fails=1; }
  done
  ## and the lane is NAMED for the second shape too
  mkdir -p "$T/l2/root-lane/tmp/detached/v3.33.0-alpha"; : > "$T/l2/root-lane/tmp/detached/v3.33.0-alpha/publish.log"
  out="$(DEPLOY_DIR= DEPLOY_GLOB="$T/l2/*/tmp/detached" BOX_MARKER="$T/m" FOLD_TREE="$T/none" "$0" --publish)"
  [ "$out" = "publish in flight: v3.33.0-alpha (from root-lane)" ] || { echo "FAIL: a tmp/detached publish was not named with its lane: $out"; fails=1; }
  ## ARM 12 — --others, BOTH directions, with `sleep` standing in for the engine so the arm needs no
  ## godot. The fold chain now WAITS on this answer, so a mode that could only ever say FREE would
  ## silently restore the overlap it was added to prevent — and a negative is not evidence until the
  ## answer has been watched flipping to YES.
  ##
  ## ⛔ RESOLVE the stand-in: /usr/bin/sleep is a symlink to uutils (/usr/lib/cargo/bin/coreutils/
  ## sleep) and /proc/<pid>/exe reads the RESOLVED target, so comparing against /usr/bin/sleep can
  ## never match and this arm failed on its first run. A real godot is not a symlink — its exe reads
  ## /usr/bin/godot directly, measured — so production was never affected, only the control.
  ## And a UNIQUE COPY, because the resolved path is shared: every `sleep` on the box runs
  ## /usr/lib/cargo/bin/coreutils/sleep, including this file's own waiters, so the arm read
  ## "engines up: 4" with no stand-in started at all. The basename stays `sleep` because uutils is a
  ## multicall binary that dispatches on argv[0].
  mkdir -p "$T/bin"; cp "$(readlink -f /usr/bin/sleep)" "$T/bin/sleep"
  STANDIN="$T/bin/sleep"
  out="$(BOX_BUSY_ENGINE="$STANDIN" DEPLOY_DIR="$T/d" BOX_MARKER="$T/m" FOLD_TREE="$T/none" "$0" --others)"; e=$?
  [ "$e" = 1 ] || { echo "FAIL: --others reported busy with no stand-in engine: $out"; fails=1; }
  "$STANDIN" 25 & SLEEPER=$!
  sleep 1
  out="$(BOX_BUSY_ENGINE="$STANDIN" DEPLOY_DIR="$T/d" BOX_MARKER="$T/m" FOLD_TREE="$T/none" "$0" --others)"; e=$?
  case "$out" in "other lanes' engines up: "*) [ "$e" = 0 ] || { echo "FAIL: --others printed a count but exited $e"; fails=1; } ;;
                 *) echo "FAIL: --others did not see a running stand-in engine (ec=$e): $out"; fails=1 ;; esac
  kill "$SLEEPER" 2>/dev/null; wait "$SLEEPER" 2>/dev/null
  out="$(BOX_BUSY_ENGINE="$STANDIN" DEPLOY_DIR="$T/d" BOX_MARKER="$T/m" FOLD_TREE="$T/none" "$0" --others)"; e=$?
  [ "$e" = 1 ] || { echo "FAIL: --others still busy after the stand-in engine exited: $out"; fails=1; }

  [ "$fails" = 0 ] && echo "box_busy selftest: 12/12 arms flipped as expected"
  exit "$fails"
fi

case "${1:-}" in
  "") ;;
  --wait) case "${2:-}" in ''|*[!0-9]*) echo "usage: tools/box_busy.sh [--wait SECONDS | --publish | --marker | --roots]" >&2; exit 2 ;; esac ;;
  --publish) publish_reason; exit $? ;;
  ## ⛔ others() is "reported, not judged" for a HUMAN reading FREE, but the fold chain needs it as a
  ## DECISION: it waits for an in-flight publish and ignored other lanes' engines, so a lane that
  ## checked FREE correctly and then ran a 250s sweep got a gate launched into it seconds later
  ## (@cowir-music, 2026-10-26). Neither instrument was wrong — there was no mutual exclusion at all,
  ## only a point-in-time check on each side. Exit 0 = busy, matching --publish.
  --others) n="$(others)"; [ "${n:-0}" -gt 0 ] && { echo "other lanes' engines up: $n"; exit 0; }; exit 1 ;;
  --marker) printf '%s\n' "$BOX_MARKER"; exit 0 ;;
  --roots) n=0; for r in $(deploy_roots); do [ -d "$r" ] && { echo "$r"; n=$((n+1)); }; done
           [ "$n" -gt 0 ] || { echo "no existing dir in: $(deploy_roots)"; exit 1; }; exit 0 ;;
  *) echo "usage: tools/box_busy.sh [--wait SECONDS | --publish | --marker | --roots]" >&2; exit 2 ;;
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
