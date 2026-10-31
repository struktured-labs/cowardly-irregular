#!/usr/bin/env bash
# his_game_up.sh — is struktured's game running on his REAL profile right now? ONE source for every
# publish path that must not run beside it (.487: his autosave landed inside the profile check's
# window and RED the publish). box_busy.sh cannot answer this: it sorts engines by cwd, and his
# windowed session (2026-10-30, cwd cowir-main) read as a "fold-tree godot" gate only by accident.
#
#   exit 0 = his game is up (one HIS_GAME line per pid on stdout)
#   exit 1 = no game on his real profile
#   exit 2 = cannot tell (/proc or his home unreadable) — callers must treat this as 0, not 1
#   --selftest  plants fake games under every arm and checks each verdict by pid
#
# A game is any process whose exe basename is godot* or cowardly-irregular.x86_64. Its user:// is
# resolved the way Godot resolves it: XDG_DATA_HOME if NON-EMPTY (an empty one is no sandbox), else
# $HOME/.local/share. His real profile is the one under his passwd home, read from getent, so a
# caller running with a redirected HOME cannot move it.
# ⛔ A NON-DUMPABLE process hides its environ AND its exe link (measured 2026-10-31: readlink exits
#    1, environ is root:root 0400) and leaves only /proc/PID/comm. So when exe is unreadable the
#    name comes from comm (15 chars: "godot", "cowardly-irregu"), and a game whose environ cannot be
#    read is HIS GAME: we cannot prove it is sandboxed. Skipping on an unreadable exe, as the first
#    version did, made that arm unreachable.
# Not covered: the windows build under wine (its user data lives in a WINEPREFIX, not his user://).
set -u

game_name() {  # $1 = /proc/PID ; prints the name to match on, or nothing
  local e; e="$(readlink "$1/exe" 2>/dev/null)"
  if [ -n "$e" ]; then printf '%s\n' "${e##*/}"; return; fi
  [ -r "$1/comm" ] && printf 'comm:%s\n' "$(cat "$1/comm" 2>/dev/null)"
}

scan() {
  local home real p n env x h d found=1
  home="$(getent passwd "$(id -u)" | cut -d: -f6)"
  [ -n "$home" ] && [ -d "$home" ] || { echo "his_game_up: cannot read the passwd home for uid $(id -u)" >&2; return 2; }
  real="${home%/}/.local/share"
  compgen -G '/proc/[0-9]*' > /dev/null || { echo "his_game_up: /proc lists no processes" >&2; return 2; }
  for p in /proc/[0-9]*; do
    n="$(game_name "$p")"
    case "$n" in godot*|cowardly-irregular.x86_64|comm:godot*|comm:cowardly-irregu*) ;; *) continue ;; esac
    if env="$(tr '\0' '\n' < "$p/environ" 2>/dev/null)"; then
      x="$(printf '%s\n' "$env" | sed -n 's/^XDG_DATA_HOME=//p' | tail -1)"
      h="$(printf '%s\n' "$env" | sed -n 's/^HOME=//p' | tail -1)"
      d="${x:-$h/.local/share}"; d="${d%/}"
      [ "$d" = "$real" ] || continue
      echo "HIS_GAME pid=${p#/proc/} name=$n user://=$d"; found=0
    elif [ -d "$p" ]; then
      echo "HIS_GAME pid=${p#/proc/} name=$n environ unreadable: cannot prove a sandbox"; found=0
    fi
  done
  return $found
}

if [ "${1:-}" = "--selftest" ]; then
  root="$(cd "$(dirname "$0")/.." && pwd)"; mkdir -p "$root/tmp"
  T="$(mktemp -d "$root/tmp/his_game_selftest.XXXXXX")" || { echo "FAIL: no fixture dir"; exit 1; }
  pids=()
  cleanup() { local q; for q in "${pids[@]}"; do kill "$q" 2>/dev/null; done; wait 2>/dev/null
              case "$T" in "$root"/tmp/his_game_selftest.?*) rm -rf -- "$T" ;; esac; }
  trap cleanup EXIT INT TERM
  home="$(getent passwd "$(id -u)" | cut -d: -f6)"
  mkdir -p "$T/bin" "$T/sbx"
  for b in godot cowardly-irregular.x86_64 notgame; do cp -L /usr/bin/bash "$T/bin/$b"; done
  # The non-dumpable fake is a python that renames ITSELF (PR_SET_NAME) and then drops dumpability, so
  # only comm is left readable — the exact state the comm fallback exists for. Not a copied python: a
  # relocated standalone build cannot find its stdlib and dies before the arm can run.
  PY="$(command -v /usr/bin/python3 || command -v python3)" || { echo "FAIL: python3 needed for the non-dumpable arm"; exit 1; }
  fails=0
  # spawn NAME ENV... : a fake that stays alive as that exe. ⛔ It must not leave a child behind: the
  # first version ran `sleep 60; :`, killing the fake orphaned its sleep, and the orphan held the
  # CALLER's stdout open — so `out=$(his_game_up.sh --selftest)` (run_publish_selftests.sh's form)
  # blocked up to 60s after the selftest had exited. The fake now waits on its own sleep, kills it on
  # TERM, and has no stdio of the caller's to hold.
  spawn() { local b="$1"; shift; FN="$b"
    env -i PATH=/usr/bin "$@" "$T/bin/$b" -c 'trap "kill \$s 2>/dev/null; exit 0" TERM; sleep 60 & s=$!; wait $s' \
      < /dev/null > /dev/null 2>&1 & pids+=("$!"); FP=$!; }
  arm() {  # LABEL EXPECT(listed|absent)
    # Wait for the EXACT name: right after the fork comm still reads "bash" (pre-exec), and a scan
    # there would fail every listed arm and pass every absent arm for the wrong reason.
    local i; for i in $(seq 1 30); do [ "$(cat /proc/$FP/comm 2>/dev/null)" = "${FN:0:15}" ] && break; sleep 0.1; done
    [ "$(cat /proc/$FP/comm 2>/dev/null)" = "${FN:0:15}" ] || { echo "FAIL  $1: the fake never came alive as ${FN:0:15} (control)"; fails=1; return; }
    local out got; out="$(scan 2>&1)"
    case "$out" in *"HIS_GAME pid=$FP "*) got=listed ;; *) got=absent ;; esac
    if [ "$got" = "$2" ]; then echo "ok    $1 -> $got"; else echo "FAIL  $1 -> $got, expected $2: $out"; fails=1; fi
    kill "$FP" 2>/dev/null; wait "$FP" 2>/dev/null
  }
  spawn godot HOME="$home";                                       arm "godot, XDG unset, HOME=his"            listed
  spawn godot HOME="$home" XDG_DATA_HOME=;                        arm "godot, XDG EMPTY (no sandbox)"         listed
  spawn godot HOME=/nowhere XDG_DATA_HOME="$home/.local/share/";  arm "godot, XDG = his dir + slash"          listed
  spawn godot HOME="$home" XDG_DATA_HOME="$T/sbx";                arm "godot, XDG = a sandbox"                absent
  spawn godot HOME="$T/sbx";                                      arm "godot, HOME redirected (desktop smoke)" absent
  spawn cowardly-irregular.x86_64 HOME="$home";                   arm "exported binary, HOME=his"             listed
  spawn notgame HOME="$home";                                     arm "non-game exe, HOME=his (vacuity)"      absent
  env -i PATH=/usr/bin HOME="$T/sbx" XDG_DATA_HOME="$T/sbx" "$PY" -I -c \
    'import ctypes,time; c=ctypes.CDLL(None); c.prctl(15,b"godot-py",0,0,0); c.prctl(4,0,0,0,0); time.sleep(60)' < /dev/null > /dev/null 2>&1 &
  pids+=("$!"); FP=$!; FN=godot-py
  for i in $(seq 1 30); do [ "$(cat /proc/$FP/comm 2>/dev/null)" = godot-py ] && [ -z "$(readlink /proc/$FP/exe 2>/dev/null)" ] && break; sleep 0.1; done
  # A DEAD process also has no readable exe or environ, so the arm must first prove the fake is alive.
  if [ ! -d "/proc/$FP" ] || [ -n "$(readlink /proc/$FP/exe 2>/dev/null)" ] || { tr '\0' '\n' < /proc/$FP/environ; } > /dev/null 2>&1; then
    echo "FAIL  non-dumpable arm: the fake is dead or its exe/environ are still readable, so the arm would test nothing"; fails=1
  else
    arm "non-dumpable godot (exe+environ hidden), SANDBOXED env" listed
  fi
  [ "$fails" = 0 ] && echo "his_game_up selftest: all arms as expected" || echo "his_game_up selftest: FAILED"
  exit "$fails"
fi

[ $# -eq 0 ] || { echo "usage: his_game_up.sh [--selftest]" >&2; exit 2; }
scan
