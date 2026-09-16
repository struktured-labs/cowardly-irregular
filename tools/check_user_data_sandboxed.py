#!/usr/bin/env python3
"""Every deploy invocation that can write user:// must redirect it, or say why it cannot.

WHY THIS EXISTS
---------------
2026-09-16. Struktured's live profile took five log rotations from the desktop chain in one day
— stamped 08:53 · 09:11 · 10:00 · 10:35, each three seconds before this lane's own archived boot
log for .355 · .356 · .357 · .358 — plus a .recovery_mode_lock at 10:40 from the import prewarm.
Godot keeps exactly five rotations, so every slot held one of those boots and none of his own
play survived in the ring. A crash trace is the one log that cannot be regenerated.

THE TWO REASONS NOBODY CAUGHT IT, and this file is shaped by both:

  1. THERE IS NO `godot` ON THE LINE. The boot gate runs the EXPORTED BINARY by path:
         ( cd "$OUT_DIR" && timeout 240 "./${ARTIFACT}" --headless --quit )
     Every sandbox rule any lane carries is written as `godot <flags>`, so the one invocation
     that boots the whole game against a real profile is invisible to the check you would reach
     for. The axis is what the process DOES to user://, never what the command line looks like.

  2. A CHECK WRITTEN FOR ONE VARIABLE NAME IS BLIND TO THE OTHERS. Three env vars redirect
     user:// and all three are in use in this repo:
         XDG_DATA_HOME   relocates godot's whole data root
         HOME            a linux build resolves user:// from it
         WINEPREFIX      a wine build resolves it through %APPDATA% inside the prefix
     A lane grepped for XDG_DATA_HOME, found none on the battle smoke, and reported it
     unsandboxed — it is sandboxed by HOME and WINEPREFIX one line up. That false positive and
     the real defect are the same mistake with opposite signs.

DECLARED EXCEPTIONS, never silent ones. `--export-release` CANNOT carry XDG_DATA_HOME: export
templates live at ~/.local/share/godot/export_templates/, under the data root it would relocate,
and a sandboxed export fails "No export template found at the expected path". It is exempt
because it is measured to be, and the exemption is checked: if the line ever stops being an
export, it stops being exempt.

    tools/check_user_data_sandboxed.py [files...]      default: tools/deploy_*.sh
    tools/check_user_data_sandboxed.py --selftest

Exit 0 every invocation is sandboxed or declared · 1 something is not · 2 nothing was examined.
"""
import glob
import os
import re
import sys

REDIRECTS = ("XDG_DATA_HOME=", "HOME=", "WINEPREFIX=")

# Things that can write user://. Two families, because one of them has no "godot" in it.
EDITOR_CLASS = re.compile(r'(?<!\w)godot\s+--')                    # godot --headless, --import…
EXPORTED_BIN = re.compile(r'"\./\$\{ARTIFACT\}"|"\$BIN"|"\./\$ARTIFACT"')
# A line that MENTIONS the binary is not a line that RUNS it. `[ -s "$BIN" ]` and
# `stat -c%s "$BIN"` both matched on the first real run and both were false positives.
#
# The discriminator is the COMMAND that governs the reference, not the shape of the token
# before it: my first attempt keyed on "a flag precedes it", which then classified
# `xvfb-run -a "$BIN"` as non-execution — the flag belongs to the RUNNER and the binary is
# still the command. Runners execute; inspectors do not.
RUNNERS = {"timeout", "xvfb-run", "wine", "env", "nice", "setsid", "exec", "sudo", "stdbuf"}
INSPECTORS = {"[", "test", "stat", "echo", "printf", "ls", "du", "cksum", "cat", "cp", "mv",
              "rm", "file", "dirname", "basename", "wc", "head", "tail"}


def _in_command_position(before):
    """Is what follows `before` an actual command, or is it text/data?

    Three ways it is NOT, all measured on this repo's own tools/:
      BASE=(godot …)                  an array DEFINITION — run_tests.sh:24
      echo "Run: godot --import …"    ADVICE TEXT inside a string — run_tests.sh:223, :239
      [ -s "$BIN" ] / stat …          the binary as an ARGUMENT
    The second is this lane's documented quoted-text class: a stripper that handles `#` and
    nothing else reads text inside quotes as code.
    """
    # INSIDE A STRING is data, whatever it looks like. An odd number of unescaped quotes before
    # the match means the match is inside one. This is the lane's documented quoted-text class:
    # a stripper that handles `#` and nothing else reads an echo'd command as a command, and
    # run_tests.sh:223 prints the exact `godot --headless --import` line it advises you to run.
    if before.count('"') % 2 == 1 or before.count("'") % 2 == 1:
        return False
    trimmed = before.rstrip()
    if trimmed.endswith("=(") or trimmed.endswith("="):
        return False                       # NAME=( … )  or  NAME=<thing>
    gov = ""
    for tok in reversed(before.replace("(", " ( ").replace("&&", " && ").split()):
        if tok.startswith("-") or "=" in tok:
            continue
        gov = tok
        break
    if gov in INSPECTORS:
        return False
    return True


def _runs_the_binary(code):
    """True only where the exported binary is in COMMAND position."""
    for m in EXPORTED_BIN.finditer(code):
        before = code[:m.start()]
        # the governing word: the last token that is neither a flag nor an env assignment
        if not _in_command_position(before):
            continue
        return True
    return False


def _runs_godot(code):
    """True only where a `godot --` match is an invocation rather than data."""
    for m in EDITOR_CLASS.finditer(code):
        if _in_command_position(code[:m.start()]):
            return True
    return False


# A line is exempt only for a reason that is itself checkable on that line.
EXEMPT = (
    ("--export-release",
     "export templates live under the data root XDG_DATA_HOME would relocate; a sandboxed "
     "export fails 'No export template found'"),
)


def _commands(path):
    """Yield (lineno, logical line). Shell continuations are joined so a redirect on the
    previous physical line still counts — the battle smoke's WINEPREFIX sits there, and
    splitting on newlines is exactly how a check reports it unsandboxed."""
    with open(path, encoding="utf-8", errors="replace") as f:
        raw = f.readlines()
    buf, start = "", 0
    for i, line in enumerate(raw, 1):
        stripped = line.rstrip("\n")
        if not buf:
            start = i
        if stripped.endswith("\\"):
            buf += stripped[:-1] + " "
            continue
        buf += stripped
        yield start, buf
        buf = ""
    if buf:
        yield start, buf


def audit(paths):
    findings, ok, declared, scanned = [], 0, 0, 0
    for path in paths:
        if not os.path.exists(path):
            continue
        scanned += 1
        for lineno, cmd in _commands(path):
            code = cmd.split("#", 1)[0] if not cmd.lstrip().startswith("#") else ""
            if not code.strip():
                continue
            is_editor = _runs_godot(code)
            is_binary = _runs_the_binary(code)
            if not (is_editor or is_binary):
                continue
            # A definition is not an invocation: `BIN="$OUT_DIR/x"` writes nothing.
            if re.match(r'\s*\w+=("|\$|\w)', code) and not any(r in code for r in REDIRECTS) \
               and "timeout" not in code and "&&" not in code and not code.strip().startswith("("):
                if "godot" not in code and not is_editor:
                    continue
            exempt_reason = next((r for token, r in EXEMPT if token in code), None)
            if any(r in code for r in REDIRECTS):
                ok += 1
            elif exempt_reason:
                declared += 1
                print(f"  declared  {path}:{lineno}  {exempt_reason}")
            else:
                findings.append((path, lineno, code.strip()[:100],
                                 "exported binary" if is_binary and not is_editor else "godot"))
    return findings, ok, declared, scanned


def main(argv):
    # tools/*.sh, not tools/deploy_*.sh. The first corpus was hand-shaped and covered 4 files;
    # the tools that can write user:// are 10, and the one it missed — make_web_stage.sh — runs
    # on EVERY web publish. A neighbour list is a hypothesis about blast radius; a pattern over
    # the tree is a measurement of it (cowir-sprites, 2026-09-16).
    paths = argv or sorted(glob.glob("tools/*.sh"))
    findings, ok, declared, scanned = audit(paths)
    if scanned == 0:
        print("[sandbox] BLOCKED: examined no files — a check with an empty corpus passes "
              "everything.", file=sys.stderr)
        return 2
    total = ok + declared + len(findings)
    if total == 0:
        print(f"[sandbox] BLOCKED: {scanned} file(s) examined and NOT ONE invocation matched. "
              f"These scripts run godot; a zero here means the patterns stopped matching, not "
              f"that the risk went away.", file=sys.stderr)
        return 2
    print(f"[sandbox] {scanned} file(s) · {total} invocation(s) that can write user:// · "
          f"{ok} sandboxed · {declared} declared · {len(findings)} UNSANDBOXED")
    for path, lineno, code, kind in findings:
        print(f"[sandbox] UNSANDBOXED ({kind})  {path}:{lineno}", file=sys.stderr)
        print(f"          {code}", file=sys.stderr)
        print(f"          add XDG_DATA_HOME= (or HOME=/WINEPREFIX= for an exported build), or "
              f"declare why it cannot carry one.", file=sys.stderr)
    return 1 if findings else 0


def selftest():
    import tempfile
    fails = []

    def check(label, got, want):
        ok_ = got == want
        print(f"  {'ok  ' if ok_ else 'FAIL'} {label}: {got} (want {want})")
        if not ok_:
            fails.append(label)

    with tempfile.TemporaryDirectory(dir=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                      "..", "tmp")) as d:
        def w(name, body):
            p = os.path.join(d, name)
            open(p, "w").write(body)
            return p

        # bare godot -> flagged
        f, o, dec, _ = audit([w("a.sh", 'godot --headless --import --quit > log 2>&1\n')])
        check("a bare `godot --` invocation is FLAGGED", len(f), 1)
        # each redirect in turn -> not flagged. One arm per variable, because a check written
        # for one name is the exact defect this file exists for.
        for var in ("XDG_DATA_HOME", "HOME", "WINEPREFIX"):
            f, o, dec, _ = audit([w("b.sh", f'{var}="$PWD/tmp/x" godot --headless --quit\n')])
            check(f"...and is CLEAN when redirected by {var}", len(f), 0)
        # the exported binary, which carries no `godot` at all
        f, o, dec, _ = audit([w("c.sh", '( cd "$OUT" && timeout 240 "./${ARTIFACT}" --headless --quit )\n')])
        check("an EXPORTED BINARY with no redirect is FLAGGED", len(f), 1)
        f, o, dec, _ = audit([w("d.sh", '( cd "$OUT" && XDG_DATA_HOME="$X" "./${ARTIFACT}" --headless --quit )\n')])
        check("...and is CLEAN when redirected", len(f), 0)
        # a continuation: the redirect is on the PREVIOUS physical line
        f, o, dec, _ = audit([w("e.sh", 'WINEPREFIX="$S" timeout 900 xvfb-run -a \\\n    wine "./${ARTIFACT}" -- --battle-smoke\n')])
        check("a redirect on a CONTINUED line still counts", len(f), 0)
        # the instrument's OWN false positives, which the first real run produced:
        # a line that mentions the binary is not a line that runs it.
        f, o, dec, _ = audit([w("fp1.sh", '[ -s "$BIN" ] || { echo "no binary" >&2; exit 2; }\n')])
        check("`[ -s \"$BIN\" ]` is NOT an invocation", len(f), 0)
        f, o, dec, _ = audit([w("fp2.sh", 'echo "size: $(( $(stat -c%s "$BIN") / 1048576 )) MiB"\n')])
        check("`stat -c%s \"$BIN\"` is NOT an invocation", len(f), 0)
        f, o, dec, _ = audit([w("fp3.sh", 'HOME="$S" xvfb-run -a "$BIN" -- --battle-smoke\n')])
        check("...but a REAL sandboxed run still parses", len(f), 0)
        f, o, dec, _ = audit([w("fp4.sh", 'xvfb-run -a "$BIN" -- --battle-smoke\n')])
        check("...and a REAL unsandboxed run is still FLAGGED", len(f), 1)

        # data that LOOKS like an invocation. Both measured in tools/run_tests.sh.
        f, o, dec, _ = audit([w("fp5.sh", 'BASE=(godot --headless --audio-driver Dummy -s gut.gd)\n')])
        check("an array DEFINITION is not an invocation", len(f), 0)
        f, o, dec, _ = audit([w("fp6.sh", 'echo "      Run: godot --headless --import --quit, then re-run" >&2\n')])
        check("ADVICE TEXT in an echo is not an invocation", len(f), 0)
        f, o, dec, _ = audit([w("fp7.sh", 'godot --headless --import --quit\n')])
        check("...but the same command, bare, IS flagged", len(f), 1)

        # the declared exception
        f, o, dec, _ = audit([w("f.sh", 'godot --headless --export-release "$PRESET" "$BIN"\n')])
        check("--export-release is DECLARED, not flagged", len(f), 0)
        check("...and is counted as declared", dec, 1)
        # and the exemption is not a blanket one
        f, o, dec, _ = audit([w("g.sh", 'godot --headless --quit "$PRESET"\n')])
        check("a NON-export godot line gets no exemption", len(f), 1)
        # vacuity floors
        rc = main([w("h.sh", "# nothing but a comment\n")])
        check("a corpus with no invocations is BLOCKED (2)", rc, 2)
        rc = main([os.path.join(d, "does-not-exist.sh")])
        check("a corpus of missing files is BLOCKED (2)", rc, 2)

    print(f"\n{'FAILED: ' + ', '.join(fails) if fails else 'all arms as expected'}")
    return 1 if fails else 0


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    sys.exit(main(sys.argv[1:]))
