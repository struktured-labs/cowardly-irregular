#!/usr/bin/env bash
# Is struktured's FPGA toolchain compiling? Quartus holds a deploy; OBS does not (he waived it).
#
# PROMOTED FROM tmp/ ON 2026-10-12. It lived in the lane's gitignored scratch, where it would have
# gone with the worktree — along with the only record of why it is written this way. It is an
# OPERATOR guard run before a launch, not a chain gate: nothing on the publish path invokes it, so
# it does not enter derive_selftest_corpus.py's set and its arms do not run on every publish. Run
# `tools/quartus_guard.sh --selftest` by hand after touching it.
#
# ⛔ WHY NOT pgrep. 2026-10-12, twice in one day: `pgrep -c -f "[q]uartus"` reported q=1 for five
# straight samples with NO Quartus on the box. The bracket trick protects against the needle in
# ITS OWN argv, not against the needle in a SECOND instrumentation process — my sampler and a
# concurrent checker each carried the pattern in an eval'd string, so each matched the other and
# the hold looked real. A publish was held on it. [[the-label-defeats-the-bracket]]
#
# COMM CANNOT CARRY A PATTERN. /proc/<pid>/comm is set by the kernel from the exec'd filename, so
# a real quartus_sh/quartus_fit/quartus_map says so and a bash loop that merely MENTIONS quartus
# says "bash". The needle is in a place no shell can type.
#
# Usage:  tmp/quartus_guard.sh            prints the count; 0 = clear to publish
#         tmp/quartus_guard.sh --names    also names what it found
#         tmp/quartus_guard.sh --selftest
# Exit:   0 clear · 1 compiling · 2 usage
set -uo pipefail

_scan() { # prints "pid comm" per process whose EXEC NAME is quartus_*
    local d pid comm
    for d in /proc/[0-9]*; do
        pid="${d#/proc/}"
        [ "$pid" = "$$" ] && continue
        [ -r "$d/comm" ] || continue
        IFS= read -r comm < "$d/comm" || continue
        case "${comm,,}" in quartus*|quartus_*) printf '%s %s\n' "$pid" "$comm" ;; esac
    done
}

# ⛔ comm AND pgrep FAIL IN OPPOSITE DIRECTIONS, so neither alone is the guard. (@cowir-battle
# raised the second half, and it is the expensive half for a publish gate.)
#
#   pgrep -f <word>   OVER-matches: wrappers, samplers, my own shell. That is the q=1 phantom
#                     that held a publish on 2026-10-12.
#   comm              UNDER-matches: it is the name of the EXEC'D BINARY, so ANY SCRIPT REPORTS
#                     ITS INTERPRETER. A quartus shell or python wrapper shows comm=bash and
#                     _scan above sees nothing. Measured here on the way in: a script with
#                     `#!/usr/bin/env bash` reports comm=bash because env execs a second time.
#
# ⛔ AND A PATH-SHAPED NEEDLE IS STILL A STRING, SO IT STILL SELF-MATCHES. First attempt used
# patterns like `/quartus/` and `quartus_sh` on the command line, on the theory that only a real
# wrapper would name a quartus INSTALL. The very next live reading flagged MY OWN SHELL: the
# command that edits this file contains `quartus_sh`. Three rounds, three self-matches — the
# word, the bracketed word, the path-shaped word. A pattern cannot be made untypeable.
#
# SO STOP TESTING THE STRING AND TEST THE WORLD. A wrapper's command line names a file THAT
# EXISTS: /opt/intelFPGA/<v>/quartus/bin/quartus_sh, or a .qsf project. Instrumentation that
# merely discusses quartus names nothing that resolves. Existence is a fact about the box, not
# about the spelling, and no amount of quoting can make a sampler's argument into a file.
# Relative tokens resolve against the PROCESS's cwd, not ours.
_TOOLISH='(^|/)(quartus(_[a-z]+)?|qsys-[a-z]+)$|\.qsf$|/quartus/'

_scan_wrappers() { # pid exe token — interpreters whose command line names a quartus file that EXISTS
    local d pid comm cmd exe cwd tok res
    for d in /proc/[0-9]*; do
        pid="${d#/proc/}"
        [ "$pid" = "$$" ] && continue
        [ -r "$d/comm" ] || continue
        IFS= read -r comm < "$d/comm" || continue
        case "${comm,,}" in quartus*) continue ;; esac   # already decided by _scan
        [ -r "$d/cmdline" ] || continue
        cmd="$(tr '\0' ' ' < "$d/cmdline")"
        cwd="$(readlink "$d/cwd" 2>/dev/null)"
        for tok in $cmd; do
            printf '%s' "$tok" | command grep -Eq -- "$_TOOLISH" || continue
            case "$tok" in
                /*) res="$tok" ;;
                *)  res="${cwd:-/nonexistent}/$tok" ;;
            esac
            [ -e "$res" ] || continue
            exe="$(readlink "$d/exe" 2>/dev/null)"
            printf '%s %s %s\n' "$pid" "${exe:-<unreadable>}" "$res"
            break
        done
    done
}

case "${1:-}" in
    --selftest)
        pass=0; fail=0
        # ⛔ REPO-LOCAL tmp/, NOT ${TMPDIR:-/tmp}. tools/reap_probe.sh blocked v3.33.661-alpha at
        # gate 0d because its fixture used TMPDIR and I had run the selftest with TMPDIR pointing
        # inside a git worktree, which quietly supplied a precondition the arm never asserted. The
        # chain sets no TMPDIR. A fixture belongs where the tool runs in production.
        # [[the-harness-supplies-what-the-file-lacks]]
        mkdir -p tmp
        dir="$(mktemp -d "$PWD/tmp/qguard.XXXXXX")"
        pids=""
        # shellcheck disable=SC2064
        trap "for p in \$pids; do kill \$p 2>/dev/null; done; rm -rf '$dir'" EXIT
        mkfifo "$dir/f" 2>/dev/null
        # ⛔ `#!/bin/bash`, NOT `#!/usr/bin/env bash`. Measured here: env performs a SECOND
        # execve, which resets comm to "bash", so an env-indirected fixture is invisible to the
        # very field this guard reads and the arm red on a working guard. A compiled quartus
        # binary has no such indirection, which is why comm is trustworthy for the real subject.
        printf '#!/bin/bash\nexec < "$1"\n' > "$dir/quartus_sh"
        cp "$dir/quartus_sh" "$dir/geditor"
        chmod +x "$dir/quartus_sh" "$dir/geditor"
        # A real compile is a process whose EXECUTABLE is named quartus_*. A shebang script gets
        # its own name in comm even though argv[0] becomes /bin/bash, which is exactly the
        # property this guard relies on.
        "$dir/quartus_sh" "$dir/f" >/dev/null 2>&1 & q=$!; pids="$pids $q"
        "$dir/geditor"    "$dir/f" >/dev/null 2>&1 & g=$!; pids="$pids $g"
        i=0; while [ $i -lt 100 ]; do
            [ "$(cat "/proc/$q/comm" 2>/dev/null)" = quartus_sh ] && break
            sleep 0.05; i=$((i+1))
        done
        out="$(_scan)"
        if printf '%s\n' "$out" | command grep -q "^$q quartus_sh$"; then
            pass=$((pass+1)); echo "  ok    a quartus_* process IS found"
        else fail=$((fail+1)); echo "  FAIL  a quartus_* process is NOT found"; fi
        if printf '%s\n' "$out" | command grep -q "^$g "; then
            fail=$((fail+1)); echo "  FAIL  an unrelated process was named"
        else pass=$((pass+1)); echo "  ok    an unrelated process is NOT named"; fi
        # ⛔ THE ARM THE pgrep VERSION COULD NOT PASS: a shell whose command line carries the
        # needle in the clear must NOT count. This is the false hold, reproduced.
        FIFO="$dir/f" bash -c 'exec -a "watcher-quartus-compile-check" bash -c "read -r _ < \"\$FIFO\""' \
            >/dev/null 2>&1 & w=$!; pids="$pids $w"
        sleep 0.4
        if printf '%s\n' "$(_scan)" | command grep -q "^$w "; then
            fail=$((fail+1)); echo "  FAIL  a process that merely MENTIONS quartus was counted"
        else pass=$((pass+1)); echo "  ok    a process that merely MENTIONS quartus is ignored"; fi
        # ...and the control for that arm: its command line really does carry the word.
        if tr '\0' ' ' < "/proc/$w/cmdline" | command grep -q 'quartus'; then
            pass=$((pass+1)); echo "  ok    ...and its command line really does say quartus"
        else fail=$((fail+1)); echo "  FAIL  the mention control does not mention quartus"; fi
        # ⛔ THE WRAPPER ARM. Without it, "a process that merely MENTIONS quartus is ignored"
        # is satisfied BOTH by the correct behaviour and by being blind to every quartus shell
        # wrapper on the box — one green tick over two opposite outcomes. (@cowir-battle)
        printf '#!/bin/bash\nexec < "$1"\n' > "$dir/run_build"      # comm will say "run_build"
        chmod +x "$dir/run_build"
        mkdir -p "$dir/intelFPGA/23.1/quartus/bin"
        printf '#!/bin/sh\nexit 0\n' > "$dir/intelFPGA/23.1/quartus/bin/quartus_sh"
        chmod +x "$dir/intelFPGA/23.1/quartus/bin/quartus_sh"
        QPATH="$dir/intelFPGA/23.1/quartus/bin/quartus_sh" FIFO="$dir/f" \
            bash -c 'exec -a "wrap" bash -c "read -r _ < \"\$FIFO\"" --flow compile "$QPATH"' \
            >/dev/null 2>&1 & wr=$!; pids="$pids $wr"
        sleep 0.4
        if printf '%s\n' "$(_scan_wrappers)" | command grep -q "^$wr "; then
            pass=$((pass+1)); echo "  ok    a quartus WRAPPER script is flagged (comm says bash)"
        else fail=$((fail+1)); echo "  FAIL  a quartus wrapper is INVISIBLE — comm-only blindness"; fi
        if [ "$(cat "/proc/$wr/comm" 2>/dev/null)" != quartus_sh ]; then
            pass=$((pass+1)); echo "  ok    ...and comm really does NOT say quartus for it"
        else fail=$((fail+1)); echo "  FAIL  the wrapper control's comm says quartus, so it proves nothing"; fi
        # ⛔ THE ARM THAT KILLED THE PREVIOUS TWO IMPLEMENTATIONS: a process whose command line
        # names a quartus TOOL PATH THAT DOES NOT EXIST must be ignored. That is the shape of
        # every sampler, every guard edit and every chat-pasted command on this box — including
        # the one that wrote this file.
        NOPE="/opt/intelFPGA/23.1/quartus/bin/quartus_sh" FIFO="$dir/f" \
            bash -c 'exec -a "wrap2" bash -c "read -r _ < \"\$FIFO\"" --flow compile "$NOPE"' \
            >/dev/null 2>&1 & nx=$!; pids="$pids $nx"
        sleep 0.4
        if printf '%s\n' "$(_scan_wrappers)" | command grep -q "^$nx "; then
            fail=$((fail+1)); echo "  FAIL  a NON-EXISTENT quartus path was treated as a compile"
        else pass=$((pass+1)); echo "  ok    a quartus path that does not exist is ignored"; fi
        if [ ! -e "/opt/intelFPGA/23.1/quartus/bin/quartus_sh" ]; then
            pass=$((pass+1)); echo "  ok    ...and that path really is absent on this box"
        else fail=$((fail+1)); echo "  FAIL  the absent-path control names a file that EXISTS"; fi
        # ...and the bare-mention control must still be ignored.
        if printf '%s\n' "$(_scan_wrappers)" | command grep -q "^$w "; then
            fail=$((fail+1)); echo "  FAIL  the wrapper scan matched a bare MENTION of quartus"
        else pass=$((pass+1)); echo "  ok    the wrapper scan ignores a bare mention"; fi

        echo; echo "selftest: $pass passed, $fail failed"
        [ "$fail" -eq 0 ] ;;
    --names)
        n="$(_scan)"; w="$(_scan_wrappers)"
        printf '%s\n' "${n:-}" | sed '/^$/d'
        [ -n "$w" ] && { echo "possible WRAPPERS (comm is an interpreter, command line names quartus itself):"; printf '%s\n' "$w" | sed 's/^/  /'; }
        c=$(( $(printf '%s\n' "$n" | sed '/^$/d' | wc -l) + $(printf '%s\n' "$w" | sed '/^$/d' | wc -l) ))
        echo "quartus processes: $c"
        [ "$c" -eq 0 ] ;;
    '')      c=$(( $(_scan | wc -l) + $(_scan_wrappers | wc -l) )); echo "$c"; [ "$c" -eq 0 ] ;;
    *)       echo "usage: $0 [--names|--selftest]" >&2; exit 2 ;;
esac
