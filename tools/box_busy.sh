#!/usr/bin/env bash
# box_busy.sh — may a lane run a godot sweep right now? A script can read this; it cannot read the channel.
#
#   tools/box_busy.sh            exit 0 = box free · 1 = busy (the reason is printed) · 2 = usage
#   tools/box_busy.sh --wait N   poll every 20s for up to N seconds, then answer as above
#   tools/box_busy.sh --publish  exit 0 = a publish is in flight (named, with its lane) · 1 = none
#   tools/box_busy.sh --is-player PID  exit 0 = that pid is a player instance (bare `godot`, or
#                                `godot --path <dir>` alone: a preview build), 1 = not
#   tools/box_busy.sh --others   exit 0 = another lane has an engine up (count printed) · 1 = none
#   tools/box_busy.sh --marker   print the BOX_MARKER path every box-protocol script must use
#   tools/box_busy.sh --slot-marker  print the path tools/box_hold.sh writes a lane's claimed slot to
#   tools/box_busy.sh --roots    print each _detached dir the publish scan reads (exit 1 = none exist)
#   tools/box_busy.sh --selftest watch each arm flip (exit 0 = every arm RAN and held;
#                                the run prints the count it derived, not a literal)
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
## A LANE'S CLAIMED SLOT (tools/box_hold.sh writes it). 2026-11-11: this said "FREE (other lanes' godot up: 2)" while
## cowir-adhoc's claimed slot was mid-run, and cowir-battle started an engine on that reading. A slot is invisible BETWEEN
## its steps to any process count, so it gets a marker of its own, beside the fold's and resolved the same way.
BOX_SLOT_MARKER="${BOX_SLOT_MARKER:-$(dirname "$BOX_MARKER")/BOX_SLOT}"
## Is PID $1 this process or one of its ancestors? A slot's own steps (run_publish_selftests, pre_ready_guards) ask
## box_busy first, and must not be refused by the hold they run under. Ancestry, not an env var: a variable survives into
## a detached child and would exempt it for ever.
_is_self_or_ancestor() {
  local p="$$" n=0
  while [ -n "$p" ] && [ "$p" != 0 ] && [ "$n" -lt 64 ]; do
    [ "$p" = "$1" ] && return 0
    p="$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null)"; n=$((n + 1))
  done
  return 1
}
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

## Argv entries of a live pid. Unreadable (gone, or not ours) yields 0, which is NOT 1, so the
## caller treats it as a gate: the fail-closed direction.
argv_len() {
  local n=0 a
  while IFS= read -r -d "" a; do n=$((n + 1)); done < "/proc/$1/cmdline" 2>/dev/null
  printf "%s\n" "$n"
}

## THE PLAYER TEST, ONE PLACE. A human-launched game is argv of exactly 1 (launch.sh's bare `godot`)
## OR exactly `godot --path <dir>` and nothing else: cowir-main starts his PREVIEW builds that way from
## tmp/preview<N>/. On 2026-11-04 his .760 preview (pid 1335547, cwd cowir-main/tmp/preview760) read
## "fold-tree godot running" to every lane for hours, and two lanes declined a free box over it.
## Still narrow: `git grep -- --path` over tools/ finds NO automated godot invocation passing --path
## at all, and every automated one passes some other flag, so any extra argument is still a gate.
## ⛔ SHAPE ALONE IS TOO WIDE (cowir-adhoc 21558): rungate.sh.tmpl asks --is-player of EVERY godot on
## the box, so a lane opening a windowed `godot --path <its own tree>` to eyeball a build would be
## waved through as "his game". So <dir> must resolve (realpath, against the process's own cwd when
## relative) INSIDE "$FOLD_TREE"/tmp/preview*: the trees main builds for him and nothing else. The
## pid cannot be told apart by ancestry: his preview is reparented to init (PPID 1). Reads a cmdline FILE
## so the selftest can feed it argv fixtures without starting anything shaped like an engine.
## Unreadable or empty -> not a player: the fail-closed direction.
argv_is_player() {  # <cmdline file> <cwd of that process>
  local -a a=(); local x d
  while IFS= read -r -d "" x; do a+=("$x"); done 2>/dev/null < "$1"
  [ "${#a[@]}" = 1 ] && return 0
  [ "${#a[@]}" = 3 ] && [ "${a[1]}" = --path ] || return 1
  case "${a[2]}" in /*) d="${a[2]}" ;; "") return 1 ;; *) d="$2/${a[2]}" ;; esac
  [ -d "$d" ] || return 1
  d="$(realpath "$d")"
  case "$d/" in "$(realpath -m "$FOLD_TREE")"/tmp/preview*/*) return 0 ;; esac
  return 1
}
is_player() { argv_is_player "/proc/$1/cmdline" "$(readlink "/proc/$1/cwd" 2>/dev/null)"; }

busy_reason() {
  if [ -f "$BOX_MARKER" ]; then
    local pid; pid="$(sed -n 's/^pid=//p' "$BOX_MARKER" | head -1)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "fold chain/gate running: $(tr '\n' ' ' < "$BOX_MARKER")"; return 0
    fi
    echo "box_busy: stale marker (pid ${pid:-?} not alive), ignoring: $BOX_MARKER" >&2
  fi
  if [ -f "$BOX_SLOT_MARKER" ]; then
    local spid; spid="$(sed -n 's/^pid=//p' "$BOX_SLOT_MARKER" | head -1)"
    if [ -n "$spid" ] && kill -0 "$spid" 2>/dev/null; then
      _is_self_or_ancestor "$spid" || { echo "slot $(sed -n 's/^lane=//p' "$BOX_SLOT_MARKER" | head -1) running: $(tr '\n' ' ' < "$BOX_SLOT_MARKER")"; return 0; }
    else
      echo "box_busy: stale slot marker (pid ${spid:-?} not alive), ignoring: $BOX_SLOT_MARKER" >&2
    fi
  fi
  ## A godot running in the fold tree IS the chain or gate, marker or not — so a missing marker
  ## cannot turn a running gate into FREE (cowir-autogrind: it said FREE beside the .692 chain).
  ## EXCEPT struktured's own game: launch.sh starts it as bare `godot &` from this very tree, so
  ## while he plays, every lane read BUSY and the whole fleet stalled on his play session.
  ## The discriminator is ARGV LENGTH, not --headless: 5 of 20 real invocations in tools/ omit
  ## --headless (the xvfb screenshot and render-smoke paths), while EVERY automated invocation
  ## passes at least one flag. Argv of exactly 1 is the player and nothing else. An unreadable
  ## argv counts as a gate, so the unknown case still closes the box.
  local p c pid
  PLAYER_PIDS=""
  for p in /proc/[0-9]*; do
    [ "$(readlink "$p/exe" 2>/dev/null)" = "$ENGINE_EXE" ] || continue
    c="$(readlink "$p/cwd" 2>/dev/null)"
    case "$c" in "$FOLD_TREE"|"$FOLD_TREE"/*) ;; *) continue ;; esac
    pid="${p#/proc/}"
    if is_player "$pid"; then PLAYER_PIDS="${PLAYER_PIDS}${PLAYER_PIDS:+ }$pid"; continue; fi
    echo "fold-tree godot running: pid $pid cwd=$c"; return 0
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
  ## ⛔ THE COUNT USED TO BE THE STRING "12/12", WHICH PRINTED ON SUCCESS WHETHER TWELVE ARMS RAN OR
  ## NONE. I added arm 12 and updated that literal in ONE edit, ran it, and read my own string back
  ## as proof the arm was wired (@cowir-music, 2026-10-27, on the first run of this selftest by
  ## anything but my own hand). Arm 12 was in fact reached -- it RED on its first run, which a
  ## literal cannot fake -- but reach rested on that historical accident rather than on the run.
  ## `Scripts == authored` applied one level down: count arms as they run, check the derived total,
  ## print the derived number.
  ##
  ## ⚠️ THE UNIT IS AN ARM, NOT AN ASSERTION, AND THAT IS A REAL LIMIT: the 12 arms hold 21 `FAIL:`
  ## sites, so a check dropped from INSIDE an arm still passes this. Stated rather than implied --
  ## the grouping into arms is a judgement the output cannot settle, which is half of why the old
  ## literal went unexamined for so long.
  arms=0
  EXPECT_ARMS=19
  A() { arms=$((arms + 1)); }
  A  # arm 1  nothing set -> FREE
  BOX_MARKER="$T/m" DEPLOY_DIR="$T/d" FOLD_TREE="$T/none" "$0" >/dev/null || { echo "FAIL: not FREE with nothing set"; fails=1; }
  A  # arm 2  live marker -> BUSY
  printf 'pid=%s\n' "$$" > "$T/m"
  out="$(BOX_MARKER="$T/m" DEPLOY_DIR="$T/d" FOLD_TREE="$T/none" "$0")"
  case "$out" in "BUSY: fold chain/gate running"*) ;; *) echo "FAIL: a live marker did not read BUSY for THAT reason: $out"; fails=1 ;; esac
  A  # arm 3  dead marker does not block
  printf 'pid=999999\n' > "$T/m"
  BOX_MARKER="$T/m" DEPLOY_DIR="$T/d" FOLD_TREE="$T/none" "$0" >/dev/null 2>&1 || { echo "FAIL: a dead marker blocked"; fails=1; }
  A  # arm 4  publish in flight -> BUSY, named
  rm -f "$T/m"; mkdir -p "$T/d/v3.33.0-alpha"; : > "$T/d/v3.33.0-alpha/publish.log"
  out="$(BOX_MARKER="$T/m" DEPLOY_DIR="$T/d" FOLD_TREE="$T/none" "$0")"
  case "$out" in "BUSY: publish in flight: v3.33.0-alpha") ;; *) echo "FAIL: a publish in flight did not read BUSY naming its tag: $out"; fails=1 ;; esac
  A  # arm 5  dead publish.pid does not block
  echo 999999 > "$T/d/v3.33.0-alpha/publish.pid"
  BOX_MARKER="$T/m" DEPLOY_DIR="$T/d" FOLD_TREE="$T/none" "$0" >/dev/null 2>&1 || { echo "FAIL: a dead publish.pid blocked"; fails=1; }
  ## ARM 6 — THE REGRESSION ARM. DEPLOY_DIR used to name ONE publisher, so a publish from any
  ## other lane's worktree read FREE. This arm takes the GLOB path (DEPLOY_DIR empty) and plants a
  ## marker in a lane that is not the old hardcoded one; it also pins that the lane is NAMED, since
  ## a BUSY you cannot attribute is a BUSY nobody can clear.
  A  # arm 6  another lane via the GLOB
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
  A  # arm 7  --publish sees it
  rm -f "$T/lanes/some-other-lane/tmp/_detached/v3.33.0-alpha/publish.ec"
  out="$(DEPLOY_DIR= DEPLOY_GLOB="$T/lanes/*/tmp/_detached" BOX_MARKER="$T/m" FOLD_TREE="$T/none" "$0" --publish)"; e=$?
  { [ "$e" = 0 ] && [ "$out" = "publish in flight: v3.33.0-alpha (from some-other-lane)" ]; } \
    || { echo "FAIL: --publish did not report another lane's publish (ec=$e): $out"; fails=1; }
  A  # arm 8  --publish ignores a dead pid
  echo 999999 > "$T/lanes/some-other-lane/tmp/_detached/v3.33.0-alpha/publish.pid"
  DEPLOY_DIR= DEPLOY_GLOB="$T/lanes/*/tmp/_detached" BOX_MARKER="$T/m" FOLD_TREE="$T/none" "$0" --publish >/dev/null 2>&1 \
    && { echo "FAIL: --publish reported a publish whose pid is dead"; fails=1; }
  ## ... and --publish ignores the fold marker: the chain asks it while HOLDING that marker.
  A  # arm 9  --publish ignores the fold marker
  rm -f "$T/lanes/some-other-lane/tmp/_detached/v3.33.0-alpha/publish.pid"
  : > "$T/lanes/some-other-lane/tmp/_detached/v3.33.0-alpha/publish.ec"; printf 'pid=%s\n' "$$" > "$T/m"
  DEPLOY_DIR= DEPLOY_GLOB="$T/lanes/*/tmp/_detached" BOX_MARKER="$T/m" FOLD_TREE="$T/none" "$0" --publish >/dev/null 2>&1 \
    && { echo "FAIL: --publish read the fold marker as a publish (the chain would wait on itself)"; fails=1; }
  ## --marker: the default derives from FOLD_TREE (one literal), and an explicit BOX_MARKER wins.
  A  # arm 10 --marker derives and is overridable
  out="$(env -u BOX_MARKER FOLD_TREE="$T/ft" "$0" --marker)"
  [ "$out" = "$T/ft/tmp/BOX_BUSY" ] || { echo "FAIL: --marker default not derived from FOLD_TREE: $out"; fails=1; }
  out="$(BOX_MARKER="$T/x" FOLD_TREE="$T/ft" "$0" --marker)"
  [ "$out" = "$T/x" ] || { echo "FAIL: --marker ignored an explicit BOX_MARKER: $out"; fails=1; }
  ## ARM 11 — THE SHIPPED DEFAULT. Arms 1-10 all override DEPLOY_GLOB, so a typo in its default
  ## passed 10/10 while the scan read FREE beside every publish. This arm must run UNOVERRIDDEN to
  ## mean anything: it asks the real filesystem whether the default names at least one real dir.
  A  # arm 11 the SHIPPED default, unoverridden
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
  A  # arm 12 --others, both directions
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

  ## The player/gate split. DEPLOY_GLOB is isolated too: publish_reason runs AFTER the engine
  ## loop, so a real publish in flight would make the FREE arm fail for an unrelated reason.
  ## The blocker is a copy of `cat` on a fifo because it is the one long-lived process whose argv
  ## is exactly 1 — `sleep` needs an argument, which is the very thing under test.
  A  # arm 13 a bare-argv engine in the fold tree is the PLAYER: FREE, and NAMED
  ## T is RELATIVE (mktemp under dirname $0), so the stand-in path must be absolutised before any
  ## `cd` — and the marker must be a path NO earlier arm has written, or its live pid answers first.
  TA="$(cd "$T" && pwd)"
  mkdir -p "$TA/bin" "$TA/fold"
  cp "$(readlink -f /usr/bin/cat)" "$TA/bin/cat"
  mkfifo "$TA/fifo"
  ( cd "$TA/fold" && exec "$TA/bin/cat" ) < "$TA/fifo" & PLAYER=$!
  exec 9> "$TA/fifo"
  sleep 1
  PENV=(BOX_BUSY_ENGINE="$TA/bin/cat" DEPLOY_DIR="$TA/d" DEPLOY_GLOB="$TA/none" BOX_MARKER="$TA/m_player_none" FOLD_TREE="$TA/fold")
  out="$(env "${PENV[@]}" "$0")"; e=$?
  [ "$e" = 0 ] || { echo "FAIL arm13: a bare-argv engine in the fold tree read BUSY (ec=$e): $out"; fails=1; }
  case "$out" in *"a player instance, not a gate"*) ;; *) echo "FAIL arm13b: FREE did not name the player: $out"; fails=1 ;; esac
  "$0" --is-player "$PLAYER" || { echo "FAIL arm13c: --is-player said no to a bare-argv engine"; fails=1; }
  kill "$PLAYER" 2>/dev/null; wait "$PLAYER" 2>/dev/null

  A  # arm 14 THE CONTROL: same binary, ONE flag, same tree -> BUSY. Without it arm 13 passes for
     #        any reason at all, including a scan that never saw the process.
  ( cd "$TA/fold" && exec "$TA/bin/cat" -u ) < "$TA/fifo" & GATE=$!
  sleep 1
  out="$(env "${PENV[@]}" "$0")"; e=$?
  [ "$e" = 1 ] || { echo "FAIL arm14: a FLAGGED engine in the fold tree read FREE (ec=$e) — the player skip is too wide: $out"; fails=1; }
  case "$out" in *"fold-tree godot running"*) ;; *) echo "FAIL arm14b: BUSY did not name the fold-tree engine: $out"; fails=1 ;; esac
  "$0" --is-player "$GATE" && { echo "FAIL arm14c: --is-player said yes to a flagged engine"; fails=1; }
  kill "$GATE" 2>/dev/null; wait "$GATE" 2>/dev/null
  exec 9>&-

  A  # arm 15 the PREVIEW player: argv fixtures through the same predicate the scan and --is-player use.
     #        Each case is the argv a real process carried; the -s case is the shape of cowir-main's
     #        bare GUT run from tmp/preview760 on 2026-11-02 (main 21546), which must stay a GATE.
  ## Fixtures live under a FAKE fold tree ($TA/fold, as arms 13/14), so the preview rule is exercised
  ## against FOLD_TREE and never against the real cowir-main.
  mkdir -p "$TA/fold/tmp/preview760" "$TA/fold/tmp/preview760/sub" "$TA/fold/tmp/notpreview" "$TA/lanes/cowir-sprites" "$TA/pv/cwd"
  ln -s "$TA/lanes/cowir-sprites" "$TA/fold/tmp/preview999"   # a "preview" that is really a lane tree
  ln -s "$TA/fold/tmp/preview760" "$TA/pv/cwd/rel"
  _argv() { local f="$TA/pv/argv.$1"; shift; : > "$f"; local x; for x in "$@"; do printf '%s\0' "$x" >> "$f"; done; printf '%s' "$f"; }
  _pl() { # label want(yes|no) argv...
    local label="$1" want="$2" f got; shift 2; f="$(_argv "$label" "$@")"
    if FOLD_TREE="$TA/fold" argv_is_player "$f" "$TA/pv/cwd"; then got=yes; else got=no; fi
    [ "$got" = "$want" ] || { echo "FAIL arm15 $label: player=$got, want $want (argv: $*)"; fails=1; }
  }
  ## The engine name comes from a variable: these lines are argv DATA for the predicate, and a literal
  ## `godot --` in command position is what check_user_data_sandboxed.py (rightly) reads as a launch.
  G=godot
  _pl bare            yes "$G"
  _pl preview_abs     yes "$G" --path "$TA/fold/tmp/preview760"
  _pl preview_sub     yes "$G" --path "$TA/fold/tmp/preview760/sub"
  _pl preview_rel     yes "$G" --path rel
  _pl lane_tree       no  "$G" --path "$TA/lanes/cowir-sprites"
  _pl fold_root       no  "$G" --path "$TA/fold"
  _pl fold_tmp_other  no  "$G" --path "$TA/fold/tmp/notpreview"
  _pl preview_symlink_to_lane no "$G" --path "$TA/fold/tmp/preview999"
  _pl preview_missing no  "$G" --path "$TA/fold/tmp/preview404"
  _pl preview_empty   no  "$G" --path ""
  _pl path_no_dir     no  "$G" --path
  _pl gut_from_tree   no  "$G" --path "$TA/fold/tmp/preview760" -s addons/gut/gut_cmdln.gd
  _pl headless_first  no  "$G" --headless --path "$TA/fold/tmp/preview760"
  _pl other_flag      no  "$G" --rendering-driver "$TA/fold/tmp/preview760"
  : > "$TA/pv/argv.empty"
  FOLD_TREE="$TA/fold" argv_is_player "$TA/pv/argv.empty" "$TA/pv/cwd" && { echo "FAIL arm15 empty: an empty cmdline read as a player"; fails=1; }
  FOLD_TREE="$TA/fold" argv_is_player "$TA/pv/argv.gone" "$TA/pv/cwd" && { echo "FAIL arm15 gone: an unreadable cmdline read as a player"; fails=1; }

  A  # arm 16  a HELD slot reads BUSY, names its lane; a dead one does not block
  sleep 30 & hp=$!
  printf 'pid=%s\nlane=cowir-zz\nwhat=slot.sh\nsince=00:00:00Z\n' "$hp" > "$T/slot"
  out="$(BOX_SLOT_MARKER="$T/slot" BOX_MARKER="$T/none.m" DEPLOY_DIR="$T/d" FOLD_TREE="$T/none" "$0")"; e=$?
  case "$e/$out" in "1/BUSY: slot cowir-zz running"*) ;; *) echo "FAIL arm16a: a live slot marker did not read BUSY naming its lane (ec=$e): $out"; fails=1 ;; esac
  kill "$hp" 2>/dev/null; wait "$hp" 2>/dev/null
  BOX_SLOT_MARKER="$T/slot" BOX_MARKER="$T/none.m" DEPLOY_DIR="$T/d" FOLD_TREE="$T/none" "$0" >/dev/null 2>&1 || { echo "FAIL arm16b: a dead slot marker blocked"; fails=1; }
  A  # arm 17  the holder's OWN descendants still read free (a slot's steps ask box_busy first)
  printf 'pid=%s\nlane=cowir-zz\n' "$$" > "$T/slot"
  BOX_SLOT_MARKER="$T/slot" BOX_MARKER="$T/none.m" DEPLOY_DIR="$T/d" FOLD_TREE="$T/none" "$0" >/dev/null 2>&1 || { echo "FAIL arm17: a process inside its own hold read BUSY"; fails=1; }
  A  # arm 18  another lane's engine with no hold: exit 0, and never the bare word FREE
  ## the stand-in keeps the NAME sleep: on this box coreutils is one multi-call binary that dispatches on argv[0], so a copy
  ## named anything else exits "function/utility not found" at once (my first arm 18 read FREE for that reason)
  "$STANDIN" 25 & ep=$!; sleep 1
  out="$(BOX_BUSY_ENGINE="$STANDIN" BOX_SLOT_MARKER="$T/none.s" BOX_MARKER="$T/none.m" DEPLOY_DIR="$T/d" FOLD_TREE="$T/none" "$0")"; e=$?
  kill "$ep" 2>/dev/null; wait "$ep" 2>/dev/null
  case "$e/$out" in "0/NO GATE/PUBLISH/HELD SLOT (lanes' godot up: 1;"*) ;; *) echo "FAIL arm18a: an unheld lane engine was not reported as such (ec=$e): $out"; fails=1 ;; esac
  out="$(BOX_BUSY_ENGINE="$STANDIN" BOX_SLOT_MARKER="$T/none.s" BOX_MARKER="$T/none.m" DEPLOY_DIR="$T/d" FOLD_TREE="$T/none" "$0")"
  case "$out" in "FREE (other lanes' godot up: 0)") ;; *) echo "FAIL arm18b: with no engine up it did not read plain FREE: $out"; fails=1 ;; esac

  A  # arm 19  the tool that WRITES the slot marker passes its own selftest against THIS box_busy (so the pair cannot drift)
  if [ -x "$(dirname "$0")/box_hold.sh" ]; then
    hs="$(BOX_HOLD_BUSY="$(cd "$(dirname "$0")" && pwd)/box_busy.sh" "$(dirname "$0")/box_hold.sh" --selftest 2>&1)" \
      || { echo "FAIL arm19: tools/box_hold.sh --selftest failed: $(printf '%s' "$hs" | tail -3)"; fails=1; }
  else echo "FAIL arm19: tools/box_hold.sh is missing or not executable beside box_busy.sh"; fails=1; fi

  [ "$arms" = "$EXPECT_ARMS" ] \
    || { echo "FAIL: $arms of $EXPECT_ARMS arms ran — one was dropped, never wired, or an earlier arm exited"; fails=1; }
  [ "$fails" = 0 ] && echo "box_busy selftest: $arms/$EXPECT_ARMS arms ran, every assertion held"
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
  ## The player test as a QUESTION, so the gate templates ask it instead of carrying a copy. rungate
  ## had its own godot scan, and it held the .746 gate 35 min on struktured's game after this file
  ## had already learned to tell a player from a gate. Two scans, one fact, and only one was fixed.
  --is-player) [ -n "${2:-}" ] && is_player "$2" && exit 0; exit 1 ;;
  --others) n="$(others)"; [ "${n:-0}" -gt 0 ] && { echo "other lanes' engines up: $n"; exit 0; }; exit 1 ;;
  --marker) printf '%s\n' "$BOX_MARKER"; exit 0 ;;
  --slot-marker) printf '%s\n' "$BOX_SLOT_MARKER"; exit 0 ;;
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
## busy_reason ran in a subshell above, so re-derive PLAYER_PIDS here rather than read a variable
## that cannot have crossed back. Named, not silent: a FREE beside a running engine must say why.
busy_reason >/dev/null || true
if [ -n "${PLAYER_PIDS:-}" ]; then
  echo "FREE (struktured's game is up: pid $PLAYER_PIDS — a player instance, not a gate; other lanes' godot up: $(others))"; exit 0
fi
## Never a bare FREE beside another lane's engine (main 23935): the verdict covers a gate, a publish and a HELD slot; an
## engine in a lane tree with no hold is reported, not judged, and the reader is told what that means. Exit 0 either way:
## callers decide on the exit code, and --others is the mode that judges engines.
_n="$(others)"
if [ "${_n:-0}" -gt 0 ]; then
  echo "NO GATE/PUBLISH/HELD SLOT (lanes' godot up: $_n; an unheld slot may be running: the channel RELEASE is the gate, and tools/box_hold.sh makes a slot visible here)"; exit 0
fi
echo "FREE (other lanes' godot up: 0)"; exit 0
