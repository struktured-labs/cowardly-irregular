#!/usr/bin/env bash
# Prove the combat smoke did not write into struktured's REAL godot profile.
#
# WHY THIS EXISTS
# ---------------
# deploy_desktop.sh gate 3b runs the exported binary FOR REAL — a full battle, under
# xvfb, with $HOME redirected at a throwaway directory so `user://` resolves inside the
# sandbox. It is the only gate allowed to do more than boot, and the entire licence for that
# is the isolation. The gate verified it like this:
#
#     REAL_N_BEFORE=$(find "$USERDATA" -type f | wc -l)
#     ... run the game ...
#     REAL_N_AFTER=$(find "$USERDATA" -type f | wc -l)
#     [ "$REAL_N_BEFORE" -ne "$REAL_N_AFTER" ] && BLOCKED
#     echo "... profile untouched (${REAL_N_BEFORE} files)"
#
# A FILE COUNT. It cannot see a save OVERWRITTEN IN PLACE — the case that matters most,
# because that is what a partially-failed HOME redirection looks like: the game finds an
# existing profile and writes slot files that are already there. Count unchanged, gate green,
# "profile untouched" printed over the top of it, publish proceeds.
#
# This is the same defect as the "masters untouched: N tracks still at 96k" line in
# make_web_stage.sh, which also counted files and claimed content. The stake here is higher:
# that one guarded audio masters, this one guards his save data.
#
# WHAT IT MEASURES INSTEAD
# ------------------------
# A per-file checksum over the whole profile, NUL-safe. Any modification, addition, removal or
# rename changes the signature. A count cannot distinguish those; a signature does not have to.
#
# TELLING "HE WAS PLAYING" FROM "ISOLATION LEAKED"
# ------------------------------------------------
# Both look identical in the real profile: it changed. The discriminator is the SANDBOX. If
# HOME redirection worked, the game's writes are in there; a smoke that ran a whole battle and
# left an EMPTY sandbox did not have a working redirect. So --verify takes the sandbox too and
# reports both, because a human reading a RED needs to know which of the two it is and the
# numbers answer it in one line.
#
# Either way this BLOCKS. Blocking a publish because he happened to be playing costs an hour;
# not blocking because a count could not see an overwrite costs his save file.
#
# Usage:  tools/check_profile_untouched.sh --sig <profile-dir>
#         tools/check_profile_untouched.sh --verify <profile-dir> <sig> [sandbox-dir]
#         tools/check_profile_untouched.sh --selftest
# Exit:   0 unchanged · 3 changed / unreadable (same code gate 3b already uses)

set -uo pipefail

# Per-file and NUL-safe. An unquoted glob here is the false zero that made
# `cat $(ls -1d "$UD/saves"/*)` read 0 bytes and cksum a tidy-looking "4294967295 0" — his
# profile path contains a space ("Cowardly Irregular"), so this is not hypothetical.
# `logs/` IS EXCLUDED, AND THE REASON IS THE SAME PROPERTY THIS FILE EXISTS FOR.
#
# Godot rotates user://logs/ with a fixed cap — measured on his profile: exactly 5 files, a
# new one written on each run and the oldest deleted. So the COUNT never moves while the
# CONTENT changes every time any godot process touches the real profile.
#
# That single property defeats both instruments, in opposite directions:
#   a COUNT check is BLIND to it   (5 -> 5, "profile untouched", and it would be blind to a
#                                   save overwrite for exactly the same reason)
#   a naive SIGNATURE check is NOISY on it (reds on routine log churn, every publish)
#
# Discovered by running the real gate chain rather than reasoning about it: my pre-chain
# baseline and the gate's own baseline disagreed, and the single differing file was a rotated
# log. A whole-profile signature would have shipped a gate that blocks constantly, which gets
# a guard disabled and is worse than the guard it replaced.
#
# Excluding logs/ is not a loosening. Logs are godot's own churn, regenerable and worthless.
# What this gate protects is saves/ and the rest of the profile, and against THAT the
# signature is exact: measured 1864063109 16959 for both gate 0b's snapshot and his live
# directory across a full chain run.
_EXCLUDE='*/logs/*'

_sig() {
    local dir="$1" n
    n="$(find "$dir" -type f -not -path "$_EXCLUDE" 2>/dev/null | wc -l)"
    if [ "$n" -eq 0 ]; then
        echo "0 EMPTY"
        return 0
    fi
    printf '%s ' "$n"
    find "$dir" -type f -not -path "$_EXCLUDE" -print0 2>/dev/null | sort -z \
        | while IFS= read -r -d '' f; do printf '%s ' "${f#"$dir"/}"; cksum < "$f"; done \
        | cksum | awk '{print $1, $2}'
}

_changed_files() {
    local dir="$1" limit="${2:-8}"
    find "$dir" -type f -newermt '-2 hours' 2>/dev/null | head -"$limit"
}

# ── WHO IS WRITING: ASK THE PROCESSES, DO NOT GUESS ──────────────────────────
# On 2026-10-12 this gate blocked the .653 rollback with
#     before: 181 2210526642 17774
#     after:  180 2652070075 17734
# and, because the sandbox held writes, printed "more likely struktured playing".
# IT WAS NOT HIM. The writer was an UNSANDBOXED HEADLESS godot in ANOTHER AGENT'S CHECKOUT
# (pid 2323893, cwd .../cowir-adhoc-wt): tools/run_tests.sh honoured XDG_DATA_HOME but never
# SET one, so a bare lane run resolved `user://` to HIS profile.
#
# The block was right. The sentence under it was wrong, AND THE SENTENCE IS WHAT A HUMAN ACTS
# ON: "he is playing" means wait an hour, "a lane is writing" means go find a pid. I waited.
#
# WHY THE SANDBOX COULD NOT ANSWER IT: the sandbox tells you whether THIS gate leaked. Who
# ELSE is writing is a question about OTHER PROCESSES, and nothing here was asking any.
# So ask them. Two independent instruments, because they fail in opposite directions:
#
#   _profile_handles   NAME-BLIND, present-tense. Anything holding a file under his profile
#                      open right now, whatever it is called. Misses a writer that has closed.
#   _engine_writers    NAME-BASED, capability-tense. Engine processes whose `user://` RESOLVES
#                      into his profile — they can write even with nothing open this instant.
#                      Misses a writer whose argv[0]/exe is named nothing like godot.
#
# ⛔ `pgrep -f godot` IS UNUSABLE HERE AND NOT FOR THE USUAL REASON. The protected path
# CONTAINS the literal "godot" ($HOME/.local/share/godot/app_userdata/...), and it arrives as
# OUR OWN ARGUMENT, so `pgrep -f` names this very process — and every parent that passed the
# path along. No [b]racket or split-literal trick helps: the needle is in argv[1], not in a
# string we control. [[the-label-defeats-the-bracket]]. argv[0] and /proc/<pid>/exe cannot
# carry a path argument, so they are the self-match-free place to ask "what IS this process".
#
# NOTHING HERE CHANGES A VERDICT. Every line below runs only after a signature MISMATCH, on
# the way to the same `return 3` this file always returned. It cannot soften a RED and cannot
# cost a green publish a millisecond.
_WRITERS_LIMIT=8

# Longest resolvable prefix, resolved; remainder appended verbatim. A candidate's
# app_userdata path often does not exist yet (a sandbox HOME), so `readlink -f` alone returns
# nothing and every comparison silently becomes "no match" — the false-clean direction.
# Resolving matters because HOME can reach the same directory through a symlink and a string
# compare then says two names are two places. [[check-identity-before-comparing]]
_norm() {
    local p="$1" head="$1" tail='' r
    while [ -n "$head" ] && [ "$head" != "/" ] && [ ! -e "$head" ]; do
        tail="${head##*/}${tail:+/$tail}"; head="${head%/*}"
    done
    [ -z "$head" ] && { printf '%s\n' "$p"; return 0; }
    r="$(readlink -f "$head" 2>/dev/null)"; [ -z "$r" ] && r="$head"
    printf '%s\n' "${r%/}${tail:+/$tail}"
}

# The app_userdata directory a pid's `user://` resolves under, or UNREADABLE.
_eff_userdata_base() {
    local pid="$1" home='' xdg='' kv base
    # Readability IS the measurement — another uid's environ is unreadable and that is a
    # different fact from "has no HOME". Test it, do not discard the error.
    [ -r "/proc/$pid/environ" ] || { printf 'UNREADABLE\n'; return 0; }
    while IFS= read -r -d '' kv; do
        case "$kv" in
            HOME=*)          home="${kv#HOME=}" ;;
            XDG_DATA_HOME=*) xdg="${kv#XDG_DATA_HOME=}" ;;
        esac
    done < "/proc/$pid/environ"
    # Godot takes XDG_DATA_HOME only when it is set AND ABSOLUTE; empty or relative falls back
    # to $HOME/.local/share. An EMPTY value therefore resolves to the REAL profile while
    # looking, in a process listing, exactly like a sandbox. [[an-invalid-sandbox-is-worse-than-none]]
    case "$xdg" in
        /*) base="$xdg" ;;
        *)  [ -n "$home" ] || { printf 'UNREADABLE\n'; return 0; }; base="$home/.local/share" ;;
    esac
    _norm "$base/godot/app_userdata"
}

_argv0() { # first NUL-separated field of the command line
    local pid="$1" a0=''
    [ -r "/proc/$pid/cmdline" ] || return 1
    IFS= read -r -d '' a0 < "/proc/$pid/cmdline" || true
    printf '%s\n' "$a0"
}

_cmdline_full() { # whole command line, spaces for NULs, NOT truncated
    local pid="$1"
    [ -r "/proc/$pid/cmdline" ] || return 1
    tr '\0' ' ' < "/proc/$pid/cmdline"
    printf '\n'
}

# ⛔ DISPLAY TRUNCATION MUST NOT REACH A PREDICATE. This used to be one function, truncated to
# 120 characters, and the --headless test read it. A lane runner with a long command line —
# `godot --headless --path <long> -s tools/run_tests.sh …`, or anything that puts the flag
# after a path — would have had its flag cut off and been CLASSED WINDOWED, i.e. reported as
# "struktured is playing". That is the exact wrong answer this file was rewritten to stop
# giving, reintroduced by a cosmetic limit. Predicates read _cmdline_full; only printing
# truncates. [[a-bound-you-cannot-see]]
_cmdline() { # for DISPLAY only
    local pid="$1" c
    c="$(_cmdline_full "$pid")" || return 1
    printf '%s\n' "${c:0:120}"
}

# Engine-ish by WHAT IT CALLS ITSELF (argv[0]) *or* WHAT THE KERNEL CALLS IT (/proc/<pid>/comm).
# Never the whole command line, for the self-match reason above.
#
# Two names, because each one alone has a hole and they are not the same hole:
#   argv[0] is what the parent passed. `exec -a` can point it anywhere, in either direction.
#   comm    is set by the kernel from the exec'd filename. It survives a spoofed argv[0] — and
#           it is the ONLY name a shebang script has, because bash rewrites argv[0] to
#           /bin/bash while comm stays the script's own name (measured, not assumed).
# comm is truncated to 15 characters, so the artifact's glob has to match "CowardlyIrregul"
# as well as the full name. Both are BUILTIN reads: no fork, callable once per process.
#
# What this intentionally does NOT do is read /proc/<pid>/exe. It costs a fork per process
# (~400 kernel threads on this box, 1.6s of a 1.7s scan) and comm already answers the same
# question — including for a zombie, whose command line is empty but whose comm is not.
_is_engine_name() {
    case "$1" in
        *[gG]odot*|*[cC]owardly[iI]rregul*|*cowardly-irregular*) return 0 ;;
    esac
    return 1
}

# pid<TAB>class<TAB>cwd<TAB>cmdline for every engine process whose user:// lands in $1.
#
# ⏱ SPEED IS A CORRECTNESS PROPERTY HERE, not a nicety: this runs inside a publish gate on a
# box with ~3,400 processes. A fork per process (`readlink`, or a `$(...)` per pid) took the
# scan from milliseconds to minutes under load — measured, by writing it that way first. The
# hot loop therefore uses BUILTIN reads only, and forks exactly once per engine CANDIDATE.
_engine_writers() {
    local dir="$1" want d pid a0 comm base cwd cls
    want="$(_norm "${dir%/}")"; want="${want%/*}"   # the app_userdata parent of his profile
    for d in /proc/[0-9]*; do
        pid="${d#/proc/}"
        [ "$pid" = "$$" ] && continue
        a0=''; comm=''
        [ -r "$d/cmdline" ] && { IFS= read -r -d '' a0 < "$d/cmdline" || true; }
        [ -r "$d/comm" ]    && { IFS= read -r comm < "$d/comm" || true; }
        _is_engine_name "${a0##*/}" || _is_engine_name "$comm" || continue
        base="$(_eff_userdata_base "$pid")"
        [ "$base" = "$want" ] || continue
        cwd="$(readlink "/proc/$pid/cwd" 2>/dev/null)"; [ -n "$cwd" ] || cwd='<unreadable>'
        # A WINDOW is the discriminator between him and us: his session is windowed, every lane
        # runner is --headless. Not a guess about intent — a fact in the command line.
        case " $(_cmdline_full "$pid") " in *" --headless "*) cls=headless ;; *) cls=windowed ;; esac
        printf '%s\t%s\t%s\t%s\n' "$pid" "$cls" "$cwd" "$(_cmdline "$pid")"
    done
}

# pid<TAB>exe<TAB>path for anything holding a file under $1 open. NAME-BLIND on purpose: this
# is the instrument that would catch a writer called nothing like godot — an editor, a python
# tool, a lane's own script. One readlink per READABLE fd table (not per fd, which is another
# thousands-of-forks mistake); an unreadable table belongs to another uid, which cannot write
# into his profile anyway.
_profile_handles() {
    local dir="$1" want d pid tgt exe
    want="$(_norm "${dir%/}")"
    for d in /proc/[0-9]*; do
        pid="${d#/proc/}"
        [ "$pid" = "$$" ] && continue
        [ -r "$d/fd" ] || continue
        while IFS= read -r tgt; do
            case "$tgt" in
                "$want"/*|"$want")
                    exe="$(readlink "/proc/$pid/exe" 2>/dev/null)"
                    printf '%s\t%s\t%s\n' "$pid" "${exe##*/}" "${tgt#"$want"/}" ;;
            esac
        # fds come and go while this reads; readlink's per-fd noise is that race, not a
        # finding. The targets ARE the measurement and none of them is suppressed.
        done < <(readlink "$d"/fd/* 2>/dev/null)
    done
}

# The sentence that replaced the guess. Three outcomes, three different texts — a diagnosis
# that cannot come out differently is not reporting. [[label-that-cannot-vary-is-not-reporting]]
_report_writers() {
    local dir="$1" w h n=0 hl=0 wd=0
    w="$(_engine_writers "$dir")"
    h="$(_profile_handles "$dir")"

    if [ -n "$h" ]; then
        echo "          holding his profile OPEN right now:" >&2
        printf '%s\n' "$h" | head -"$_WRITERS_LIMIT" \
            | while IFS="$(printf '\t')" read -r p e f; do
                  printf '            pid %-8s %-16s %s\n' "$p" "${e:-<unreadable>}" "$f" >&2
              done
    fi

    if [ -z "$w" ]; then
        echo "          ⚠️ NO live engine process resolves user:// to his profile. The writer has" >&2
        echo "             ALREADY EXITED, so this cannot name it — the file list below is the only" >&2
        echo "             evidence left. Do not read this as 'nobody wrote': something did." >&2
        return 0
    fi

    n="$(printf '%s\n' "$w" | wc -l)"
    hl="$(printf '%s\n' "$w" | cut -f2 | command grep -c '^headless$')"
    wd="$(printf '%s\n' "$w" | cut -f2 | command grep -c '^windowed$')"
    if [ "$hl" -gt 0 ]; then
        echo "          ⛔ AN AUTOMATED RUN is writing to his profile — NOT struktured:" >&2
    else
        echo "          ⚠️ A WINDOWED session is writing to his profile — struktured is playing:" >&2
    fi
    printf '%s\n' "$w" | head -"$_WRITERS_LIMIT" \
        | while IFS="$(printf '\t')" read -r p c cw cl; do
              printf '            pid %-8s %-8s cwd %s\n' "$p" "$c" "$cw" >&2
              printf '              %s\n' "$cl" >&2
          done
    if [ "$hl" -gt 0 ]; then
        echo "          A headless godot with no absolute XDG_DATA_HOME writes to the REAL profile." >&2
        echo "          The cwd above names the checkout, which names the lane. Signal THAT pid (or" >&2
        echo "          its wrapper) and re-run — do not wait for struktured. [[kill-the-wrapper-not-the-child]]" >&2
    else
        echo "          A windowed session is his. Waiting is the correct hold." >&2
    fi
    [ "$wd" -gt 0 ] && [ "$hl" -gt 0 ] && \
        echo "          (both kinds are present: ${hl} headless, ${wd} windowed, ${n} total)" >&2
    return 0
}

verify() {
    local dir="$1" want="$2" sandbox="${3:-}" got

    if [ ! -d "$dir" ]; then
        echo "[profile] BLOCKED: ${dir} does not exist. A missing profile is not an unchanged one." >&2
        return 3
    fi
    if [ -z "$want" ]; then
        echo "[profile] BLOCKED: no baseline signature — nothing to compare against." >&2
        return 3
    fi
    got="$(_sig "$dir")"
    if [ "$got" = "0 EMPTY" ]; then
        echo "[profile] BLOCKED: his profile now holds no files at all." >&2
        return 3
    fi
    if [ "$got" = "$want" ]; then
        echo "[profile] verified unchanged: ${got}"
        return 0
    fi

    echo "[profile] BLOCKED: struktured's REAL profile CHANGED during the combat smoke." >&2
    echo "          before: ${want}" >&2
    echo "          after:  ${got}" >&2
    if [ -n "$sandbox" ] && [ -d "$sandbox" ]; then
        local sn; sn="$(find "$sandbox" -type f 2>/dev/null | wc -l)"
        echo "          sandbox holds ${sn} file(s)." >&2
        if [ "$sn" -eq 0 ]; then
            echo "          ⛔ THE SANDBOX IS EMPTY — a battle ran and wrote nothing there, so HOME" >&2
            echo "             redirection did NOT work. Treat this as a real leak." >&2
        else
            echo "          The redirect worked — the writes landed in the sandbox, so this gate's own" >&2
            echo "             child is not the suspect. Who else is writing:" >&2
        fi
    fi
    # Replaces a GUESS with a measurement. The line that used to stand here said "more likely
    # struktured playing", and on 2026-10-12 it was wrong about a headless lane run and cost
    # an hour of waiting for a man who was not at the keyboard.
    _report_writers "$dir"
    echo "          recently modified in his profile:" >&2
    _changed_files "$dir" | sed 's/^/            /' >&2
    return 3
}

# ── self-test ────────────────────────────────────────────────────────────────
# Every arm runs THIS FILE as a subprocess against constructed directories. Never against his
# real profile: a test that writes into the thing it protects is not a test.
_ST_DIR=""; _ST_PIDF=""
_st_cleanup() {
    local p
    if [ -n "$_ST_PIDF" ] && [ -f "$_ST_PIDF" ]; then
        while IFS= read -r p; do [ -n "$p" ] && kill "$p" 2>/dev/null; done < "$_ST_PIDF"
    fi
    [ -n "$_ST_DIR" ] && rm -rf "$_ST_DIR"
}

selftest() {
    local dir pass=0 fail=0 saw0=0 saw3=0 self
    self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    dir="$(mktemp -d "${TMPDIR:-/tmp}/profile.XXXXXX")"
    # The writer arms below spawn REAL processes, so cleanup has to kill as well as delete.
    # BY RECORDED PID, NEVER `pkill -f`: any pattern wide enough to match these probes also
    # matches the shell that spawned them, and that shell is this test.
    # [[the-label-defeats-the-bracket]]
    _ST_DIR="$dir"; _ST_PIDF="$dir/.probe_pids"; : > "$_ST_PIDF"
    trap '_st_cleanup' EXIT
    # The space is deliberate: his real path is "Cowardly Irregular", and the bug this file
    # cites is an unquoted glob splitting on exactly that.
    local P="$dir/Cowardly Irregular"
    mkdir -p "$P/saves" "$P/screenshots" "$dir/sandbox"

    printf 'slot one\n'   > "$P/saves/slot1.json"
    printf 'slot two\n'   > "$P/saves/slot2.json"
    printf 'PNGDATA\n'    > "$P/screenshots/a.png"
    local BASE; BASE="$("$self" --sig "$P")"

    arm() { # name want-exit sig [sandbox]
        local name="$1" want="$2" got
        "$self" --verify "$P" "$3" "${4:-}" >/dev/null 2>&1
        got=$?
        [ "$got" -eq 0 ] && saw0=1
        [ "$got" -eq 3 ] && saw3=1
        if [ "$got" -eq "$want" ]; then pass=$((pass+1)); printf '  ok    %-50s exit %s\n' "$name" "$got"
        else fail=$((fail+1)); printf '  FAIL  %-50s exit %s (wanted %s)\n' "$name" "$got" "$want"; fi
    }

    arm "untouched"                                        0 "$BASE"

    # THE CASE THE COUNT COULD NOT SEE: same file count, same names, different bytes.
    printf 'OVERWRITTEN BY THE SMOKE\n' > "$P/saves/slot1.json"
    arm "a save OVERWRITTEN IN PLACE (count unchanged)"    3 "$BASE"
    printf 'slot one\n' > "$P/saves/slot1.json"
    arm "restored"                                         0 "$BASE"

    printf 'new\n' > "$P/saves/slot3.json"
    arm "a save added"                                     3 "$BASE"
    rm -f "$P/saves/slot3.json"

    mv "$P/saves/slot2.json" "$P/saves/slot9.json"
    arm "a save renamed, bytes identical"                  3 "$BASE"
    mv "$P/saves/slot9.json" "$P/saves/slot2.json"

    rm -f "$P/screenshots/a.png"
    arm "a file deleted"                                   3 "$BASE"
    printf 'PNGDATA\n' > "$P/screenshots/a.png"

    # LOG CHURN MUST NOT RED. This is the arm that keeps the gate usable: godot rewrites
    # user://logs/ on every run with a fixed file cap, so if this tripped, the gate would
    # block every publish and be disabled within a day.
    mkdir -p "$P/logs"
    printf 'run one\n' > "$P/logs/godot.log"
    local BASE_L; BASE_L="$("$self" --sig "$P")"
    printf 'run two, different bytes, same count\n' > "$P/logs/godot.log"
    arm "a rotated log changed (must NOT red)"             0 "$BASE_L"
    printf 'a whole new log\n' > "$P/logs/godot2026.log"
    arm "a log ADDED (must NOT red)"                       0 "$BASE_L"
    # ...and the exclusion must not hide a real save change happening at the same time.
    printf 'OVERWRITTEN WHILE LOGS ALSO CHURNED\n' > "$P/saves/slot1.json"
    arm "save overwritten WHILE logs churn (must red)"     3 "$BASE_L"
    printf 'slot one\n' > "$P/saves/slot1.json"
    rm -rf "$P/logs"

    arm "no baseline given"                                3 ""
    "$self" --verify "$dir/nope" "$BASE" >/dev/null 2>&1
    local g=$?; [ "$g" -eq 3 ] && saw3=1
    if [ "$g" -eq 3 ]; then pass=$((pass+1)); printf '  ok    %-50s exit %s\n' "profile directory missing" "$g"
    else fail=$((fail+1)); printf '  FAIL  %-50s exit %s (wanted 3)\n' "profile directory missing" "$g"; fi

    # The leak-vs-playing discriminator must actually say different things.
    printf 'OVERWRITTEN\n' > "$P/saves/slot1.json"
    local empty_out full_out
    empty_out="$("$self" --verify "$P" "$BASE" "$dir/sandbox" 2>&1)"
    printf 'sandbox wrote this\n' > "$dir/sandbox/user_data.bin"
    full_out="$("$self" --verify "$P" "$BASE" "$dir/sandbox" 2>&1)"
    printf 'slot one\n' > "$P/saves/slot1.json"

    if printf '%s' "$empty_out" | grep -q 'SANDBOX IS EMPTY'; then
        pass=$((pass+1)); printf '  ok    %-50s\n' "empty sandbox -> named as a real leak"
    else fail=$((fail+1)); printf '  FAIL  %-50s\n' "empty sandbox -> not identified as a leak"; fi
    # RETARGETED, NOT RELAXED. This arm used to assert the literal "more likely struktured
    # playing" — the guess that was wrong on 2026-10-12. Its SUBJECT is unchanged: a sandbox
    # that holds writes must get its own diagnosis rather than the leak one. What moved is the
    # sentence, which is the only thing the arm ever certified.
    if printf '%s' "$full_out" | grep -q 'Who else is writing'; then
        pass=$((pass+1)); printf '  ok    %-50s\n' "written sandbox -> asks who else is writing"
    else fail=$((fail+1)); printf '  FAIL  %-50s\n' "written sandbox -> not distinguished"; fi
    # ...and the two messages must not be the same message.
    if [ "$empty_out" != "$full_out" ]; then
        pass=$((pass+1)); printf '  ok    %-50s\n' "the two diagnoses differ"
    else fail=$((fail+1)); printf '  FAIL  %-50s (a verdict that cannot vary)\n' "the two diagnoses are identical"; fi

    # ⛔ THE DIAGNOSTIC MUST NAME THE FILE, AND NOTHING ASSERTED THAT. `_changed_files` runs at
    # the ONE moment anyone needs it -- beneath a signature MISMATCH, to say WHICH of his files
    # moved -- and every arm above tests the VERDICT, not the sentence under it. A predicate that
    # silently matched nothing would leave the gate blocking correctly above an EMPTY list, which
    # reads as a confused tool rather than a broken one, and invites someone to override it.
    #
    # ⚠️ These arms exist because I convinced myself that had already happened. Measuring by hand,
    # `-newermt '-2 hours'` returned 0 and printed `bfs: error: Invalid timestamp` -- so I nearly
    # "fixed" a gate that was never broken. An AGENT SHELL resolves `find` through a shell FUNCTION
    # to bfs 4.1.1; a SCRIPT gets /usr/bin/find, GNU findutils 4.10.0, which accepts that syntax and
    # returns the file. CLAUDE.md's "`find` is bfs, not GNU find" is true of the terminal and FALSE
    # of every tool in this directory -- the same interactive-only asymmetry it already documents
    # for grep. The predicate is left EXACTLY as it was; only these arms are new.
    printf 'freshly written\n' > "$P/saves/slot_recent.json"
    local changed; changed="$(_changed_files "$P")"
    case "$changed" in
        *slot_recent.json*) pass=$((pass+1)); printf '  ok    %-50s\n' "the diagnostic NAMES a just-written file" ;;
        *) fail=$((fail+1)); printf '  FAIL  %-50s (got: %s)\n' "the diagnostic names a just-written file" "${changed:-<empty>}" ;;
    esac
    # CONTROL: it must NOT name a file that has not moved, or the arm above passes on anything.
    touch -d '3 days ago' "$P/saves/slot1.json"
    case "$(_changed_files "$P")" in
        *slot1.json*) fail=$((fail+1)); printf '  FAIL  %-50s\n' "a 3-day-old file is NOT named" ;;
        *) pass=$((pass+1)); printf '  ok    %-50s\n' "a 3-day-old file is NOT named" ;;
    esac
    rm -f "$P/saves/slot_recent.json"

    # ── WHO IS WRITING: arms against REAL PROCESSES ──────────────────────────
    # ⚠️ These probes are actual processes with actual environments, not a stubbed process
    # table. A stub would have been written to agree with the predicate it was built to watch
    # and could not have rejected it. [[arrival-is-not-effect]]
    #
    # Every arm is a MEMBERSHIP test, never a count: struktured's own game or another lane's
    # run may be alive while this runs, and a "writers == 3" arm would red on his play session.
    # (His processes resolve to the REAL app_userdata; these resolve into $dir, so they do not
    # mix — but the arm must not DEPEND on that.) [[a-constant-is-not-a-measurement]]
    local FH="$dir/fakehome" SB="$dir/sandbox_home" FP
    FP="$FH/.local/share/godot/app_userdata/Cowardly Irregular"
    mkdir -p "$FP/saves" "$SB" "$dir/elsewhere" "$dir/sandbox_xdg"
    printf 'his save\n' > "$FP/saves/slot1.json"
    # Every probe blocks on this. Nothing ever opens it for writing, so the open never
    # completes and the probe sleeps in one process with no child to orphan.
    mkfifo "$dir/blockfifo" 2>/dev/null || true

    _probe() { # argv0 extra-cmdline-arg -- then KEY=VAL env assignments
        local a0="$1" extra="$2"; shift 2
        # ⛔ THREE TRAPS, ALL HIT WHILE WRITING THIS:
        #  1. `>/dev/null` is load-bearing. Started inside a $(...) without it, the probe
        #     inherits the command substitution's PIPE, so the substitution does not return
        #     until the probe exits — the selftest hung for 900s per arm and read as a slow
        #     scan rather than a plumbing mistake.
        #  2. the probe must be ONE process. `sh -c 'sleep 900'` leaves a CHILD sleep that
        #     survives the kill, and an orphan with a fake argv[0] called godot is precisely
        #     the thing this gate exists to notice. Blocking in a FIFO open needs no child.
        #  3. ⛔ NOT python, AND NOT ANY uutils BINARY. `exec -a godot python3` makes python
        #     resolve its own prefix from argv[0]: it looked up "godot" on PATH, FOUND THE
        #     REAL ENGINE at /usr/bin/godot, set sys.executable to it and died with
        #     "No module named 'encodings'". And /usr/bin/{sleep,cat,tail} are a uutils
        #     multicall that dispatches on argv[0] and refuses a name it does not own
        #     ("Security violation"). bash ignores argv[0] entirely, so it is the only
        #     sleeper on this box that can be renamed.
        env -i PATH="$PATH" ST_FIFO="$dir/blockfifo" "$@" bash -c \
            "exec -a '$a0' bash -c 'read -r _ < \"\$ST_FIFO\"' ${extra:+\"$extra\"}" \
            >/dev/null 2>&1 &
        local pid=$!
        echo "$pid" >> "$_ST_PIDF"
        local i=0
        while [ "$i" -lt 100 ]; do
            [ "$(_argv0 "$pid")" = "$a0" ] && break
            sleep 0.05; i=$((i+1))
        done
        printf '%s\n' "$pid"
    }
    _reap() { local p; for p in "$@"; do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done; }
    _pids_of() { printf '%s\n' "$1" | cut -f1; }
    _named() { printf '%s\n' "$2" | cut -f1 | command grep -qx -- "$1"; }
    _class_of() { printf '%s\n' "$2" | awk -F'\t' -v p="$1" '$1==p{print $2}'; }
    parm() { # name 0-or-1-expected actual-boolean-cmd...
        local name="$1" want="$2"; shift 2
        if "$@"; then [ "$want" = 1 ] && { pass=$((pass+1)); printf '  ok    %-50s\n' "$name"; return; }
        else [ "$want" = 0 ] && { pass=$((pass+1)); printf '  ok    %-50s\n' "$name"; return; }
        fi
        fail=$((fail+1)); printf '  FAIL  %-50s (wanted %s)\n' "$name" "$want"
    }

    local W_WIN W_HL W_XDG W_EMPTY W_SB W_XSB W_CAT W_SELF W_TAIL
    W_WIN="$(_probe   godot ''           HOME="$FH")"
    W_HL="$(_probe    godot '--headless' HOME="$FH")"
    W_XDG="$(_probe   godot ''           HOME="$dir/elsewhere" XDG_DATA_HOME="$FH/.local/share")"
    W_EMPTY="$(_probe godot ''           HOME="$FH" XDG_DATA_HOME="")"
    W_SB="$(_probe    godot ''           HOME="$SB")"
    # THE TWO CALLERS ISOLATE DIFFERENTLY AND ONLY ONE SHAPE WAS COVERED. deploy_desktop.sh
    # gate 3b redirects HOME; deploy_web.sh gate 4 sets XDG_DATA_HOME and leaves HOME pointing
    # at his real one (`env XDG_DATA_HOME=$_SMOKE_XDG … godot`). Without this arm the scan was
    # untested against the exact configuration of one of its two call sites, and getting it
    # wrong would name the gate's own child as a writer and block every web publish.
    # [[asymmetry-is-a-finding-about-the-instrument]]
    W_XSB="$(_probe   godot ''           HOME="$FH" XDG_DATA_HOME="$dir/sandbox_xdg")"
    W_CAT="$(_probe   cat   ''           HOME="$FH")"
    # The self-match control: shaped like THIS SCRIPT — a non-engine process whose command
    # line carries the protected path, and that path contains the literal "godot".
    # A SHORT needle on purpose: given the real $FP, "godot" lands ~160 characters into the
    # command line, so an implementation that matched the whole line would still miss it HERE
    # and this control would pass for the wrong reason. The literal is the same substring the
    # protected path carries.
    W_SELF="$(_probe  check_profile_untouched.sh "/godot/app_userdata/Cowardly Irregular" HOME="$FH")"
    tail -f "$FP/saves/slot1.json" >/dev/null 2>&1 &
    W_TAIL=$!; echo "$W_TAIL" >> "$_ST_PIDF"

    local WOUT; WOUT="$(_engine_writers "$FP")"
    parm "a windowed godot under his HOME is NAMED"        1 _named "$W_WIN" "$WOUT"
    parm "a headless godot under his HOME is NAMED"        1 _named "$W_HL" "$WOUT"
    parm "XDG_DATA_HOME is honoured (the .654 cause)"      1 _named "$W_XDG" "$WOUT"
    parm "an EMPTY XDG_DATA_HOME falls back to HOME"       1 _named "$W_EMPTY" "$WOUT"
    parm "a SANDBOXED godot is NOT named (the gate's own)" 0 _named "$W_SB" "$WOUT"
    parm "an XDG-sandboxed godot is NOT named (web gate)"  0 _named "$W_XSB" "$WOUT"
    parm "a non-engine process is NOT named"               0 _named "$W_CAT" "$WOUT"
    parm "the self-match control is NOT named"             0 _named "$W_SELF" "$WOUT"
    parm "a tail holding a save open is NOT an engine"     0 _named "$W_TAIL" "$WOUT"
    [ "$(_class_of "$W_HL" "$WOUT")" = headless ] \
        && { pass=$((pass+1)); printf '  ok    %-50s\n' "the headless one is CLASSED headless"; } \
        || { fail=$((fail+1)); printf '  FAIL  %-50s (got %s)\n' "the headless one is CLASSED headless" "$(_class_of "$W_HL" "$WOUT")"; }
    [ "$(_class_of "$W_WIN" "$WOUT")" = windowed ] \
        && { pass=$((pass+1)); printf '  ok    %-50s\n' "the windowed one is CLASSED windowed"; } \
        || { fail=$((fail+1)); printf '  FAIL  %-50s (got %s)\n' "the windowed one is CLASSED windowed" "$(_class_of "$W_WIN" "$WOUT")"; }


    # The flag BEYOND the display window. 150 characters of padding put --headless past the
    # 120-character cut, which is exactly how a real lane runner's long command line looks.
    local W_LONG PAD
    PAD="$(printf 'p%.0s' $(seq 1 150))"
    env -i PATH="$PATH" ST_FIFO="$dir/blockfifo" HOME="$FH" bash -c \
        "exec -a godot bash -c 'read -r _ < \"\$ST_FIFO\"' $PAD --headless" >/dev/null 2>&1 &
    W_LONG=$!; echo "$W_LONG" >> "$_ST_PIDF"
    i=0; while [ "$i" -lt 100 ]; do
        [ "$(_argv0 "$W_LONG")" = godot ] && break
        sleep 0.05; i=$((i+1))
    done
    local WLOUT; WLOUT="$(_engine_writers "$FP")"
    parm "a long-command-line lane run is NAMED"            1 _named "$W_LONG" "$WLOUT"
    [ "$(_class_of "$W_LONG" "$WLOUT")" = headless ] \
        && { pass=$((pass+1)); printf '  ok    %-50s\n' "--headless PAST the display cut still classes"; } \
        || { fail=$((fail+1)); printf '  FAIL  %-50s (got %s)\n' "--headless PAST the display cut still classes" "$(_class_of "$W_LONG" "$WLOUT")"; }
    # CONTROL: the arm above is only a test if the line is long enough to BE cut. Without this,
    # a short probe would class headless for the boring reason and the arm would prove nothing.
    local CFULL CDISP
    CFULL="$(_cmdline_full "$W_LONG")"; CDISP="$(_cmdline "$W_LONG")"
    if [ "${#CFULL}" -gt 120 ] && [ "${#CDISP}" -le 121 ]; then
        pass=$((pass+1)); printf '  ok    %-50s\n' "...and the printed line IS cut (${#CFULL}->${#CDISP})"
    else
        fail=$((fail+1)); printf '  FAIL  %-50s (%s->%s)\n' "the printed line is not actually cut" "${#CFULL}" "${#CDISP}"
    fi
    _reap "$W_LONG"

    # The name test itself, both directions, with comm's 15-character truncation included. The
    # expected answer is a COLUMN here, not something I remember between runs.
    # [[label-that-cannot-vary-is-not-reporting]]
    local nm
    for nm in godot godot.linuxbsd.editor.x86_64 CowardlyIrregular.x86_64 CowardlyIrregul cowardly-irregular; do
        parm "name: '$nm' IS the engine"                   1 _is_engine_name "$nm"
    done
    for nm in check_profile_untouched.sh cat bash python3 kworker/3:2 Xwayland butler; do
        parm "name: '$nm' is NOT"                          0 _is_engine_name "$nm"
    done

    # A SHEBANG SCRIPT HAS ONLY ONE NAME AND IT IS NOT argv[0]: bash rewrites argv[0] to
    # /bin/bash, while the kernel leaves comm as the script's own basename. That asymmetry is
    # measured here, not assumed, and it is the entire reason the scan reads comm at all.
    # The probe blocks in a FIFO open, so it has no child to orphan.
    mkdir -p "$dir/bin"
    printf '#!/bin/bash\nexec < "$1"\n' > "$dir/bin/godot-probe"
    cp "$dir/bin/godot-probe" "$dir/bin/benign-probe"
    chmod +x "$dir/bin/godot-probe" "$dir/bin/benign-probe"
    local W_COMM W_BENIGN W2OUT i=0
    env -i PATH="$PATH" HOME="$FH" "$dir/bin/godot-probe"  "$dir/blockfifo" >/dev/null 2>&1 &
    W_COMM=$!;   echo "$W_COMM"   >> "$_ST_PIDF"
    env -i PATH="$PATH" HOME="$FH" "$dir/bin/benign-probe" "$dir/blockfifo" >/dev/null 2>&1 &
    W_BENIGN=$!; echo "$W_BENIGN" >> "$_ST_PIDF"
    while [ "$i" -lt 100 ]; do
        [ -r "/proc/$W_COMM/comm" ] && [ "$(cat "/proc/$W_COMM/comm")" = godot-probe ] && break
        sleep 0.05; i=$((i+1))
    done
    W2OUT="$(_engine_writers "$FP")"
    parm "a process named only by COMM is NAMED"           1 _named "$W_COMM" "$W2OUT"
    parm "...whose argv[0] is /bin/bash, not its own name" 1 \
        bash -c "[ \"\$(tr '\\0' '\\n' < /proc/$W_COMM/cmdline | head -1)\" = /bin/bash ]"
    parm "the same probe NOT named godot is skipped"       0 _named "$W_BENIGN" "$W2OUT"

    # ⛔ THE HAZARD THE COMMENT CLAIMS, DEMONSTRATED RATHER THAN ASSERTED. If `pgrep -f` did
    # NOT name the self-match control, the paragraph above `_engine_writers` would be folklore
    # and the exe/argv[0] detour would be unjustified complexity. [[documented-is-not-handled]]
    parm "pgrep -f WOULD have named it (hazard is real)"   1 \
        bash -c "pgrep -f -- '/godot/app_userdata' 2>/dev/null | command grep -qx -- '$W_SELF'"

    # The name-blind instrument: it must see the one the name-based one cannot.
    local HOUT; HOUT="$(_profile_handles "$FP")"
    parm "the OPEN-HANDLE scan names the tail"             1 _named "$W_TAIL" "$HOUT"
    parm "...and does NOT name a probe holding nothing"    0 _named "$W_WIN" "$HOUT"

    # ── the three diagnoses must be three different sentences ───────────────
    local T_HL T_WIN T_NONE
    T_HL="$(_report_writers "$FP" 2>&1)"
    _reap "$W_HL"
    T_WIN="$(_report_writers "$FP" 2>&1)"
    _reap "$W_WIN" "$W_XDG" "$W_EMPTY" "$W_COMM"
    T_NONE="$(_report_writers "$FP" 2>&1)"

    case "$T_HL" in *"AN AUTOMATED RUN"*) pass=$((pass+1)); printf '  ok    %-50s\n' "headless present -> AUTOMATED RUN, not him" ;;
        *) fail=$((fail+1)); printf '  FAIL  %-50s\n' "headless present -> AUTOMATED RUN, not him" ;; esac
    case "$T_HL" in *"$W_HL"*) pass=$((pass+1)); printf '  ok    %-50s\n' "...and it prints the offending pid" ;;
        *) fail=$((fail+1)); printf '  FAIL  %-50s\n' "...and it prints the offending pid" ;; esac
    case "$T_HL" in *"cwd "*) pass=$((pass+1)); printf '  ok    %-50s\n' "...and a cwd, which names the checkout" ;;
        *) fail=$((fail+1)); printf '  FAIL  %-50s\n' "...and a cwd, which names the checkout" ;; esac
    case "$T_WIN" in *"A WINDOWED session"*) pass=$((pass+1)); printf '  ok    %-50s\n' "only windowed left -> struktured is playing" ;;
        *) fail=$((fail+1)); printf '  FAIL  %-50s\n' "only windowed left -> struktured is playing" ;; esac
    case "$T_WIN" in *"AN AUTOMATED RUN"*) fail=$((fail+1)); printf '  FAIL  %-50s\n' "...and does NOT still blame a lane" ;;
        *) pass=$((pass+1)); printf '  ok    %-50s\n' "...and does NOT still blame a lane" ;; esac
    case "$T_NONE" in *"ALREADY EXITED"*) pass=$((pass+1)); printf '  ok    %-50s\n' "no writer alive -> says the writer EXITED" ;;
        *) fail=$((fail+1)); printf '  FAIL  %-50s\n' "no writer alive -> says the writer EXITED" ;; esac
    if [ "$T_HL" != "$T_WIN" ] && [ "$T_WIN" != "$T_NONE" ] && [ "$T_HL" != "$T_NONE" ]; then
        pass=$((pass+1)); printf '  ok    %-50s\n' "the three diagnoses differ pairwise"
    else fail=$((fail+1)); printf '  FAIL  %-50s (a verdict that cannot vary)\n' "the three diagnoses differ pairwise"; fi

    # ── END TO END through the real entry point, not the function ───────────
    # A function that works while the splice into verify() is wrong ships a guard that never
    # speaks. This arm runs the FILE, as gate 3b runs it, and reads its stderr.
    local BASE_F E2E e2e_rc
    BASE_F="$("$self" --sig "$FP")"
    local W_E2E; W_E2E="$(_probe godot '--headless' HOME="$FH")"
    printf 'OVERWRITTEN BY SOMETHING\n' > "$FP/saves/slot1.json"
    E2E="$("$self" --verify "$FP" "$BASE_F" "$SB" 2>&1)"; e2e_rc=$?
    _reap "$W_E2E" "$W_SB" "$W_XSB" "$W_CAT" "$W_SELF" "$W_TAIL" "$W_BENIGN"
    if [ "$e2e_rc" -eq 3 ]; then pass=$((pass+1)); printf '  ok    %-50s exit %s\n' "e2e: naming a writer still BLOCKS" "$e2e_rc"
    else fail=$((fail+1)); printf '  FAIL  %-50s exit %s (wanted 3)\n' "e2e: naming a writer still BLOCKS" "$e2e_rc"; fi
    case "$E2E" in *"AN AUTOMATED RUN"*) pass=$((pass+1)); printf '  ok    %-50s\n' "e2e: the RED carries the diagnosis" ;;
        *) fail=$((fail+1)); printf '  FAIL  %-50s\n' "e2e: the RED carries the diagnosis" ;; esac
    # The old sentence must be GONE, not merely outvoted: it is the thing that misled a human.
    case "$E2E" in *"more likely struktured playing"*) fail=$((fail+1)); printf '  FAIL  %-50s\n' "e2e: the old GUESS is gone" ;;
        *) pass=$((pass+1)); printf '  ok    %-50s\n' "e2e: the old GUESS is gone" ;; esac

    echo
    echo "selftest: ${pass} passed, ${fail} failed"
    if [ "$saw0" -ne 1 ] || [ "$saw3" -ne 1 ]; then
        echo "selftest: BROKEN — outcomes seen: unchanged=${saw0} changed=${saw3}; both required" >&2
        return 1
    fi
    [ "$fail" -eq 0 ]
}

case "${1:-}" in
    --selftest) selftest ;;
    --sig)      _sig "${2:-}" ;;
    --verify)   verify "${2:-}" "${3:-}" "${4:-}" ;;
    *)          echo "usage: $0 --sig <dir> | --verify <dir> <sig> [sandbox] | --selftest" >&2; exit 2 ;;
esac
