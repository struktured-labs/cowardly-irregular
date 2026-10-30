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

⛔ THERE ARE NO EXEMPTIONS ANY MORE, and the one there was is why this paragraph is long.
`--export-release` was exempt on a measured premise: export templates live under the data root
XDG_DATA_HOME relocates, so a sandboxed export fails "No export template found". True — of a
BARE sandbox. Symlink the real templates into the sandbox and the export runs clean, because
templates are read-only to it. Measured both ways on a real Linux export, 2026-09-16:
bare -> produced nothing; linked -> 318,140,832 bytes, exit 0, his lock untouched.

WHAT THE EXEMPTION COST: v3.33.360-alpha shipped with the boot gate and both imports sandboxed —
his user://logs/ survived a full three-channel publish byte-identical for the first time that day
— and his .recovery_mode_lock still moved 10:40:04 -> 12:22:04, stamped by the web export. This
tool reported that line as `declared`, which reads as handled. A declaration is a licence not to
fix something, and this one was issued on a premise that held only for the sandbox nobody had
tried to fix. Exports now carry a redirect like every other invocation; see tools/export_sandbox.sh.

    tools/check_user_data_sandboxed.py [files...]      default: tools/deploy_*.sh
    tools/check_user_data_sandboxed.py --selftest

Exit 0 every invocation is sandboxed or declared · 1 something is not · 2 nothing was examined.
"""
import ast
import glob
import io
import subprocess
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
# ⛔ AN INTERPRETER EARLIER IN THE SAME COMMAND MEANS THE BINARY IS AN ARGUMENT.
# `_in_command_position` takes the LAST non-flag token as the governing word, which for
#     python3 "$_RAW_CHECK" "$BIN" --src=src
# is the CHECKER SCRIPT, not `python3` -- so the binary read as a command and both of gate 3c's
# and gate 3d's desktop wirings were reported UNSANDBOXED. They do not run the binary; they READ
# it, to parse the pack embedded in it. Measured 2026-09-17: 2 UNSANDBOXED, both mine, both false,
# and this guard blocks publish_all.sh -- so the next publish would have been stopped by it.
# ⚠️ SCOPE: this says the binary is not the COMMAND. A python script that goes on to exec it via
# subprocess is a different line and is still matched there.
INTERPRETERS = {"python3", "python", "bash", "sh", "perl", "ruby", "node"}


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
    # The command word of THIS simple command: everything after the last separator. An
    # interpreter there means what follows is an argument list, not a command.
    seg = before
    for sep in (";", "&&", "||", "|", "(", "then", "do", "else"):
        seg = seg.rsplit(sep, 1)[-1]
    for tok in seg.split():
        if tok.strip('"\'') in INTERPRETERS:
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


# Deliberately EMPTY. Kept as a named, greppable place so that adding an exemption is a visible
# act with a reason attached, rather than a special case buried in the matcher — and so the
# report keeps a `declared` column that reads 0 instead of silently having no such concept.
# ⛔ DROPPED 2026-10-15, and it was 0-FOR-2 ON ITS OWN JUSTIFICATION (cowir-sfx).
# The entry was ("launch.sh", "the player's own launcher — running against the real profile is
# its purpose"). That reason is true of `godot &` at launch.sh:50 and FALSE of the two
# `godot --headless --import` prewarms at :40 and :45 -- and because the tuple matches on
# `path == token` it declared the whole FILE, so it licensed exactly the two lines its reason is
# not about. Worse, the line it IS about was never a finding: `godot &` carries no `--`, so it
# never matches EDITOR_CLASS. A file-scoped licence for a line-scoped reason.
# The docstring above already said "THERE ARE NO EXEMPTIONS ANY MORE"; now that is true.
# ⚠️ The MECHANISM (a declaration may name a FILE, not just a line fragment) is still pinned --
# selftest injects a synthetic EXEMPT, because an arm that needs a live licence to stay green
# is a reason never to remove one.
EXEMPT = ()


# ⛔ THE CORPUS WAS A LANGUAGE. main()'s comment celebrates deriving the corpus "from the index,
# not from a pattern" while the derivation stayed `git ls-files "*.sh"` -- an EXTENSION standing
# in for "everything that can launch godot", which is the same substitution one layer over.
# 220 tracked python files exist, one of them launched the engine, and this guard could not see
# the language it is itself written in. (Seven lanes made the identical shell-only corpus error
# in their own audits on 2026-10-15; this one was frozen into a guard the publish chain blocks on.)
#
# ⛔ AND IT IS AST, NOT REGEX, BECAUSE THE FIRST VERSION FLAGGED ITS OWN SELFTEST FIXTURES.
# A pattern cannot separate `subprocess.run(["godot"...])` from a STRING containing that text,
# and this file is full of the latter by construction -- 5 false findings, in the guard itself,
# on the first run. The shell arm has the same hazard and solves it by hand (`ADVICE TEXT in an
# echo is not an invocation`); python hands us an exact answer, since a string holding code is a
# Constant and never a Call. Nothing here can be fooled by a quoted example.
PY_SUBPROC_FNS = {"run", "Popen", "call", "check_call", "check_output"}


def _py_is_subprocess(func):
    if isinstance(func, ast.Attribute) and func.attr in PY_SUBPROC_FNS:
        return isinstance(func.value, ast.Name) and func.value.id == "subprocess"
    if isinstance(func, ast.Attribute) and func.attr in ("system", "popen"):
        return isinstance(func.value, ast.Name) and func.value.id == "os"
    return False


def _py_names_engine(call):
    """An engine named as an ARGUMENT, by basename -- so `project.godot` (a filename) and
    `res://.godot/imported/x` (a path) are data, which is the false-positive class that cost
    three lanes a wrong audit number on 2026-10-15."""
    def _is_engine(sval):
        base = sval.rsplit("/", 1)[-1]
        return base == "godot" or base.endswith("run_tests.sh")

    for arg in call.args:
        if isinstance(arg, (ast.List, ast.Tuple)):
            for el in arg.elts:
                if isinstance(el, ast.Constant) and isinstance(el.value, str) and _is_engine(el.value):
                    return True
        elif isinstance(arg, ast.Constant) and isinstance(arg.value, str):
            # shell=True form: the engine must be in command position, not merely present.
            if EDITOR_CLASS.search(arg.value) and _in_command_position(
                    arg.value[:EDITOR_CLASS.search(arg.value).start()]):
                return True
            if "run_tests.sh" in arg.value:
                return True
    return False


def _py_module_env_governs(tree):
    """A MODULE-LEVEL os.environ write governs every later subprocess in the process, because
    subprocess inherits os.environ by default. This has no shell analogue.

    Only `tree.body` counts. An indented write is reached only if its function ran first, which
    this cannot know -- clearing on it would be textual presence standing in for a structural
    property, the exact failure _redirect_governs documents for shell."""
    for node in tree.body:
        tgts = []
        if isinstance(node, ast.Assign):
            tgts = node.targets
        elif isinstance(node, ast.AnnAssign):
            tgts = [node.target]
        for t in tgts:
            if isinstance(t, ast.Subscript) and isinstance(t.value, ast.Attribute) \
               and t.value.attr == "environ" and isinstance(t.slice, ast.Constant) \
               and t.slice.value == "XDG_DATA_HOME":
                return True
        if isinstance(node, ast.Expr) and isinstance(node.value, ast.Call) \
           and isinstance(node.value.func, ast.Attribute) and node.value.func.attr == "setdefault" \
           and node.value.args and isinstance(node.value.args[0], ast.Constant) \
           and node.value.args[0].value == "XDG_DATA_HOME":
            return True
    return False


def _py_env_parents(value):
    """Names a derived env could have inherited XDG_DATA_HOME FROM. Every idiom that
    re-derives one mapping from another: dict(base, ...), base.copy(), {**base, ...},
    and base | {...}. A form not listed yields nothing, so the chain ends and reds."""
    out = []
    if isinstance(value, ast.Call):
        for a in value.args:
            if isinstance(a, ast.Name):
                out.append(a.id)
        if isinstance(value.func, ast.Attribute) and value.func.attr == "copy" \
           and isinstance(value.func.value, ast.Name):
            out.append(value.func.value.id)
    elif isinstance(value, ast.Dict):
        for k, v in zip(value.keys, value.values):
            if k is None and isinstance(v, ast.Name):
                out.append(v.id)
    elif isinstance(value, ast.BinOp) and isinstance(value.op, ast.BitOr):
        for side in (value.left, value.right):
            if isinstance(side, ast.Name):
                out.append(side.id)
    return out


def _py_env_governs(call, tree):
    """`env=` on THIS call. Two spellings, plus a CHAIN of name indirection, because a
    sandboxed base env is routinely re-derived per call: `env = dict(os.environ,
    XDG_DATA_HOME=sb)` then `e = dict(env, EXTRA=...)` then `env=e`. Resolving only the
    last hop red `tools/boss_ladder_sweep.py:112`, which IS sandboxed — a false positive
    that blocks every publish (publish_all.sh gate 0a). An UNRESOLVABLE chain still reds,
    which is the safe direction and names its own cure."""
    kw = next((k for k in call.keywords if k.arg == "env"), None)
    if kw is None:
        return False
    if isinstance(kw.value, ast.Dict):
        for k in kw.value.keys:
            if isinstance(k, ast.Constant) and k.value == "XDG_DATA_HOME":
                return True
    if isinstance(kw.value, ast.Name):
        pending, seen = [kw.value.id], set()
        while pending:
            name = pending.pop()
            if name in seen or len(seen) >= 16:
                break
            seen.add(name)
            for node in ast.walk(tree):
                if not isinstance(node, ast.Assign):
                    continue
                for t in node.targets:
                    if isinstance(t, ast.Subscript) and isinstance(t.value, ast.Name) \
                       and t.value.id == name and isinstance(t.slice, ast.Constant) \
                       and t.slice.value == "XDG_DATA_HOME":
                        return True
                    if isinstance(t, ast.Name) and t.id == name:
                        if "XDG_DATA_HOME" in ast.dump(node.value):
                            return True
                        pending.extend(_py_env_parents(node.value))
    return False


def _py_invocations(path):
    """Yield (lineno, text, sandboxed) for every engine launch in a python file."""
    src = io.open(path, encoding="utf-8", errors="replace").read()
    try:
        tree = ast.parse(src)
    except SyntaxError as exc:
        # A file we cannot parse is a file we cannot certify. All 220 tracked .py parse today;
        # if that changes, say so rather than reporting it clean.
        print(f"  BLOCKED   {path}: does not parse ({exc}) -- cannot certify its invocations",
              file=sys.stderr)
        return
    module_ok = _py_module_env_governs(tree)
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not _py_is_subprocess(node.func):
            continue
        if not _py_names_engine(node):
            continue
        text = (ast.get_source_segment(src, node) or "").split("\n")[0]
        yield node.lineno, " ".join(text.split())[:100], module_ok or _py_env_governs(node, tree)


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
        if path.endswith(".py"):
            for lineno, text, sandboxed in _py_invocations(path):
                exempt_reason = next((r for token, r in EXEMPT
                                      if path == token or path.endswith("/" + token)), None)
                if sandboxed:
                    ok += 1
                elif exempt_reason:
                    declared += 1
                    print(f"  declared  {path}:{lineno}  {exempt_reason}")
                else:
                    findings.append((path, lineno, text, "godot (python)"))
            continue
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
            # ⚠️ Matched against the PATH as well as the line. The tuple used to be tested only
            # against `code`, so a declaration naming a FILE could never fire — the first
            # entry added here (launch.sh) silently did nothing until this was measured.
            exempt_reason = next((r for token, r in EXEMPT
                                  if token in code or path == token or path.endswith("/" + token)), None)
            if _redirect_governs(code):
                ok += 1
            elif exempt_reason:
                declared += 1
                print(f"  declared  {path}:{lineno}  {exempt_reason}")
            else:
                findings.append((path, lineno, code.strip()[:100],
                                 "exported binary" if is_binary and not is_editor else "godot"))
    return findings, ok, declared, scanned



def _redirect_governs(code):
    """Does a redirect on this line actually apply to the process the line starts?

    ⛔ WAS: `any(r in code for r in REDIRECTS)` — a SUBSTRING anywhere on the line marked it
    sandboxed. That is a textual presence standing in for a structural property, and it fails
    CLEAN on the guard whose whole job is protecting struktured's profile. Demonstrated:

        XDG_DATA_HOME="$SB" ./tools/prep.sh; godot --headless --quit   -> counted SANDBOXED
        echo "run with XDG_DATA_HOME=<sandbox>" && godot --headless    -> counted SANDBOXED

    In the first, the redirect governs prep.sh and godot runs against the real profile. In the
    second it is display text. Both would have been certified as protected.

    ✅ LATENT, NOT LIVE when found (2026-09-17): all 14 lines the guard counted as sandboxed
    genuinely redirect — 13 by command prefix, 1 through `env`. Fixed because the direction is
    false-CLEAN on the one guard that stands between a deploy and his save files.

    Two legitimate forms, and `env` is why this cannot just reject quotes:

        XDG_DATA_HOME=x godot ...                 a command-prefix assignment
        env "XDG_DATA_HOME=$x" xvfb-run godot     an argument to env, which applies it
                                                  (tools/deploy_web.sh:427 — a real line)
    """
    for r in REDIRECTS:
        i = code.find(r)
        while i >= 0:
            before, after = code[:i], code[i:]
            quoted = (before.count('"') % 2 == 1) or (before.count("'") % 2 == 1)
            # `env "VAR=..."` is the one quoted form that DOES apply. Accept it only when env
            # is the governing command, not merely present somewhere on the line.
            via_env = re.search(r'(^|[;&|]|\()\s*(\w+=\S+\s+)*env\s+[^;&|]*$', before) is not None
            if not quoted or via_env:
                # Nothing may separate the redirect from what it is supposed to wrap — and
                # "what it wraps" is THIS line's invocation, which is often not the literal
                # word `godot`.
                #
                # ⚠️ My first version split on "godot" and fell through to the whole tail when
                # the line ran `"$BIN"` or `wine "./${ARTIFACT}"` instead. The tail then
                # contained `2>&1 &`, whose `&` characters are a REDIRECTION and a BACKGROUND
                # operator, not command separators — so it rejected two correctly-sandboxed
                # lines (deploy_desktop.sh:675 and :678, `HOME=`/`WINEPREFIX=` prefixes).
                # A guard that reds on correct code gets read as noise and deleted, so the
                # false positive was the more expensive half of the two.
                m = re.search(r'(?<!\w)godot(?!\w)|"\./\$\{ARTIFACT\}"|"\$BIN"|"\./\$ARTIFACT"', after)
                head = after[:m.start()] if m else after
                # strip redirections before looking for separators: 2>&1, &>, >& are not one
                head = re.sub(r'\d*>&\d*-?|&>', ' ', head)
                if not re.search(r';|&&|\|\||(?<![>&])&(?![&])', head):
                    return True
            i = code.find(r, i + 1)
    return False

def main(argv):
    # tools/*.sh, not tools/deploy_*.sh. The first corpus was hand-shaped and covered 4 files;
    # the tools that can write user:// are 10, and the one it missed — make_web_stage.sh — runs
    # on EVERY web publish. A neighbour list is a hypothesis about blast radius; a pattern over
    # the tree is a measurement of it (cowir-sprites, 2026-09-16).
    # ⛔ THE CORPUS WAS A GLOB. `tools/*.sh` is a FILENAME PATTERN standing in for "everything
    # that can launch godot", and this guard's whole claim is about that set. It reported
    # 16 invocations · 16 sandboxed · 0 UNSANDBOXED while test/smoke/run_smoke_tests.sh:12 ran
    #
    #     godot --headless -s test/smoke/test_battle_smoke.gd
    #
    # with no redirect at all — against struktured's real profile, from outside the glob.
    # Pointed at that file the predicate flags it immediately: the detector was right and the
    # corpus was wrong, which is the failure seven lanes measured in their own instruments on
    # 2026-09-17 and nobody measured in their predicate.
    #
    # Derived from the index now, not from a pattern: every tracked *.sh in the repository.
    if argv:
        paths = argv
    else:
        try:
            # ⛔ `*.sh` ALONE WAS STILL A PATTERN STANDING IN FOR A SET -- see the PY_SUBPROC
            # comment. The index is the right source; the extension list is the part that was
            # a hypothesis, and python is where the one missed invocation lived.
            out = subprocess.run(["git", "ls-files", "*.sh", "*.py"], capture_output=True, text=True, timeout=30)
            paths = sorted(p for p in out.stdout.split("\n") if p.endswith((".sh", ".py")))
        except Exception:
            paths = []
        if not paths:
            print("[sandbox] BLOCKED: could not derive the script corpus from git. A guard that "
                  "cannot enumerate its subjects is not a passing one.", file=sys.stderr)
            return 2
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
        # ⛔ THE CORPUS ARM. The default corpus was `glob.glob("tools/*.sh")` — a filename
        # pattern standing in for "everything that can launch godot" — and it missed
        # test/smoke/run_smoke_tests.sh entirely. A guard whose predicate is right and whose
        # corpus is a glob reports a clean sweep of the part it looked at.
        f, o, dec, scanned = audit([w("corpus_a.sh", 'godot --headless --quit\n')])
        check("a file OUTSIDE tools/ is still audited when named", len(f), 1)
        # ...and the derived default must reach beyond tools/. Measured on the real index:
        # 55 files, where the old glob saw 44 — the difference is test/, scripts/ and the root.
        import subprocess as _sp
        _all = sorted(x for x in _sp.run(["git", "ls-files", "*.sh"], capture_output=True,
                                          text=True).stdout.split("\n") if x.endswith(".sh"))
        _outside = [x for x in _all if not (x.startswith("tools/"))]
        check("the derived corpus reaches OUTSIDE tools/", len(_outside) > 0, True)
        check("  ...and it is derived, not a glob", "ls-files" in open(__file__).read(), True)

        # a declaration must be able to name a FILE, not only a line fragment.
        # SYNTHETIC since 2026-10-15: EXEMPT is empty, and this pins the MECHANISM rather than
        # any live entry. Previously it read the real tuple, so the arm could only stay green
        # while an exemption existed -- a guard that pays you to keep a licence.
        _saved_exempt = EXEMPT
        globals()["EXEMPT"] = (("launch.sh", "synthetic: the mechanism, not a live licence"),)
        try:
            f, o, dec, _ = audit([w("launch.sh", 'godot --headless --import\n')])
            check("a PATH-named exemption is honoured (synthetic)", dec, 1)
            check("  ...and it is not counted as a finding", len(f), 0)
            check("  ...and the real tuple is EMPTY, so that was the mechanism only",
                  len(_saved_exempt), 0)
        finally:
            globals()["EXEMPT"] = _saved_exempt

        # the exported binary, which carries no `godot` at all
        f, o, dec, _ = audit([w("c.sh", '( cd "$OUT" && timeout 240 "./${ARTIFACT}" --headless --quit )\n')])
        check("an EXPORTED BINARY with no redirect is FLAGGED", len(f), 1)
        f, o, dec, _ = audit([w("d.sh", '( cd "$OUT" && XDG_DATA_HOME="$X" "./${ARTIFACT}" --headless --quit )\n')])
        check("...and is CLEAN when redirected", len(f), 0)

        # ── a redirect must GOVERN the invocation, not merely appear on the line ────────────
        # The check was `any(r in code for r in REDIRECTS)` — a substring standing in for a
        # structural property, failing CLEAN on the guard that protects his profile.
        f, o, dec, _ = audit([w("e.sh", 'XDG_DATA_HOME="$SB" ./tools/prep.sh; godot --headless --quit\n')])
        check("a redirect on a DIFFERENT command is FLAGGED", len(f), 1)
        f, o, dec, _ = audit([w("f.sh", 'echo "run with XDG_DATA_HOME=<sandbox>" && godot --headless --quit\n')])
        check("a redirect inside a STRING is FLAGGED", len(f), 1)
        # ...and the two forms that legitimately apply must stay clean. `env` is why this
        # cannot simply reject quoted occurrences (tools/deploy_web.sh:427 is this shape).
        f, o, dec, _ = audit([w("g.sh", 'CMD=(env "XDG_DATA_HOME=$X" xvfb-run -a timeout 300 godot --headless --quit)\n')])
        check("...but `env \"VAR=...\"` DOES govern, so it is CLEAN", len(f), 0)
        # ⚠️ the regression arm: a trailing `2>&1 &` carries `&` characters that are a
        # REDIRECTION and a BACKGROUND operator, not command separators. My first version of
        # this fix read them as separators and flagged two correctly-sandboxed real lines
        # (deploy_desktop.sh:675 and :678). A guard that reds on correct code gets deleted.
        f, o, dec, _ = audit([w("h2.sh", 'HOME="$SMOKE_HOME" timeout 600 xvfb-run -a "$BIN" -- --battle-smoke > "tmp/x.log" 2>&1 &\n')])
        check("a trailing `2>&1 &` is NOT a separator", len(f), 0)
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
        # ⛔ REVERSED 2026-09-16. This arm used to assert --export-release was exempt. It is not:
        # an export sandboxed with tools/export_sandbox.sh runs clean, and while it was exempt it
        # was the last thing writing his profile.
        f, o, dec, _ = audit([w("f.sh", 'godot --headless --export-release "$PRESET" "$BIN"\n')])
        check("an UNSANDBOXED export is now FLAGGED", len(f), 1)
        check("...and nothing is declared any more", dec, 0)
        f, o, dec, _ = audit([w("f2.sh", 'XDG_DATA_HOME="$X" godot --headless --export-release "$P" "$B"\n')])
        check("...and a SANDBOXED export passes", len(f), 0)
        # and the exemption is not a blanket one
        f, o, dec, _ = audit([w("g.sh", 'godot --headless --quit "$PRESET"\n')])
        check("a non-export godot line is flagged too", len(f), 1)
        # vacuity floors
        rc = main([w("h.sh", "# nothing but a comment\n")])
        check("a corpus with no invocations is BLOCKED (2)", rc, 2)
        rc = main([os.path.join(d, "does-not-exist.sh")])
        check("a corpus of missing files is BLOCKED (2)", rc, 2)
        # ---- PYTHON ARM. The corpus was shell-only; these are the forms it could not see. ----
        PY_BARE = ('import subprocess\n'
                   'subprocess.run(["godot", "--headless", "--import", "--quit"], timeout=900)\n')
        f, o, dec, _ = audit([w("p_bare.py", PY_BARE)])
        check("python: a list-form godot launch is FLAGGED", len(f), 1)
        check("  ...and the shell matcher alone would have missed it",
              bool(EDITOR_CLASS.search('["godot", "--headless"]')), False)

        f, o, dec, _ = audit([w("p_env.py",
            'import os, subprocess\n'
            'subprocess.run(["godot", "--import"], env={**os.environ, "XDG_DATA_HOME": "sb"})\n')])
        check("python: a per-call env= redirect is CLEAN", len(f), 0)
        check("  ...and is COUNTED rather than skipped", o, 1)

        # `env=` is conventionally the LAST argument, so a fixed-width window misses exactly the
        # thing that clears the finding. Balanced-paren extraction is what makes this arm pass.
        f, o, dec, _ = audit([w("p_multiline.py",
            'import os, subprocess\n'
            'subprocess.run(\n'
            '    ["godot", "--headless", "--audio-driver", "Dummy", "--import", "--quit"],\n'
            '    cwd="/x", capture_output=True, timeout=900,\n'
            '    env={**os.environ, "XDG_DATA_HOME": "sb"},\n'
            ')\n')])
        check("python: env= on a LATER line still governs", len(f), 0)

        f, o, dec, _ = audit([w("p_module.py",
            'import os, subprocess\n'
            'os.environ["XDG_DATA_HOME"] = "sb"\n'
            'subprocess.run(["godot", "--import"])\n')])
        check("python: a module-level os.environ write governs", len(f), 0)

        # Indented => ran only if that function ran first, which this cannot know. Flagging is
        # the safe direction and names the cure.
        f, o, dec, _ = audit([w("p_indented.py",
            'import os, subprocess\n'
            'def setup():\n'
            '    os.environ["XDG_DATA_HOME"] = "sb"\n'
            'subprocess.run(["godot", "--import"])\n')])
        check("python: an INDENTED os.environ write does NOT clear it", len(f), 1)

        f, o, dec, _ = audit([w("p_named.py",
            'import os, subprocess\n'
            'e = dict(os.environ)\n'
            'e["XDG_DATA_HOME"] = "sb"\n'
            'subprocess.run(["godot", "--import"], env=e)\n')])
        check("python: env=NAME resolves one level", len(f), 0)

        # ⛔ THE SHAPE THAT RED tools/boss_ladder_sweep.py:112, WHICH IS SANDBOXED. Resolving only
        # the last hop reported it UNSANDBOXED, and publish_all.sh gate 0a refuses on that.
        f, o, dec, _ = audit([w("p_chain.py",
            'import os, subprocess\n'
            'env = dict(os.environ, XDG_DATA_HOME="sb")\n'
            'e = dict(env, BAL_LEVEL="7")\n'
            'subprocess.run(["godot", "--headless", "-s", "x.gd"], env=e)\n')])
        check("python: env=NAME resolves a dict(base, ...) CHAIN", len(f), 0)

        f, o, dec, _ = audit([w("p_copy.py",
            'import os, subprocess\n'
            'base = dict(os.environ, XDG_DATA_HOME="sb")\n'
            'e = base.copy()\n'
            'subprocess.run(["godot", "--import"], env=e)\n')])
        check("python: env=NAME resolves a .copy() hop", len(f), 0)

        f, o, dec, _ = audit([w("p_splat.py",
            'import os, subprocess\n'
            'base = dict(os.environ, XDG_DATA_HOME="sb")\n'
            'e = {**base, "BAL_GEAR": "1"}\n'
            'subprocess.run(["godot", "--import"], env=e)\n')])
        check("python: env=NAME resolves a {**base} hop", len(f), 0)

        # THE SAFE DIRECTION, and the arm that keeps the chain from licensing anything: a hop
        # whose parent never carries the variable still REDS rather than being assumed clean.
        f, o, dec, _ = audit([w("p_chain_unsandboxed.py",
            'import os, subprocess\n'
            'env = dict(os.environ, BAL_TRIALS="3")\n'
            'e = dict(env, BAL_LEVEL="7")\n'
            'subprocess.run(["godot", "--import"], env=e)\n')])
        check("python: a CHAIN carrying no XDG_DATA_HOME still reds", len(f), 1)

        f, o, dec, _ = audit([w("p_runtests.py",
            'import subprocess\n'
            'subprocess.run(["timeout", "900", "tools/run_tests.sh", "x"])\n')])
        check("python: run_tests.sh in a list is FLAGGED", len(f), 1)

        # ⛔ THE FALSE-POSITIVE CLASSES THAT COST SEVEN LANES A WRONG NUMBER ON 2026-10-15:
        # `.godot` as a FILE EXTENSION and `.godot/imported` as a PATH, both inside data.
        f, o, dec, _ = audit([w("p_fp.py",
            'import subprocess\n'
            'EXTS = ("gd", "json", "tscn", "cfg", "tres", "godot", "sh", "py")\n'
            'dest = "res://.godot/imported/x.ctex"\n'
            'subprocess.run(["git", "ls-files", "project.godot"])\n'
            'print("run godot --import yourself")\n')])
        check("python: an extension list / .godot path / project.godot is NOT a launch", len(f), 0)
        check("  ...and that file yields no invocation at all", o + dec + len(f), 0)

        f, o, dec, _ = audit([w("p_comment.py",
            'import subprocess\n'
            '# subprocess.run(["godot", "--import"])\n')])
        check("python: a COMMENTED-OUT launch is not an invocation", len(f), 0)

        check("the derived corpus now spans BOTH languages",
              all(e in open(__file__).read() for e in ('"*.sh", "*.py"',)), True)


    # ⛔ A DECLARATION NOBODY HAS WATCHED FIRE IS INDISTINGUISHABLE FROM A DEAD ENTRY.
    # This file already lost one to that: the EXEMPT tuple was tested only against `code`, so an
    # entry naming a FILE could never match, and launch.sh silently declared nothing until it was
    # measured. That bug was fixed; the CLASS was not. If launch.sh is sandboxed, renamed, or stops
    # invoking godot, its declaration becomes a permanent silent exemption with nothing to say so.
    # So: every EXEMPT token must still produce a `declared` row on the REAL tree.
    #
    # ⚠️ AND THAT LOOP GOES VACUOUS THE MOMENT THE TUPLE IS EMPTY, which is now the normal
    # state -- zero iterations, zero arms, nothing said. The `if not EXEMPT` arm below is what
    # keeps this section able to fail at all: with no licences issued, the real tree must
    # declare NOTHING, so a declaration that reappears without an entry is caught too.
    # This is the anti-vacuity pair, not a second opinion on the same fact.
    import io as _io
    _out = _sp.run([sys.executable, __file__], capture_output=True, text=True, timeout=120).stdout
    for _token, _reason in EXEMPT:
        _fired = any(line.startswith("  declared ") and _token in line for line in _out.splitlines())
        check("EXEMPT '%s' still fires — else DROP it, do not carry a stale exemption" % _token,
              _fired, True)
    if not EXEMPT:
        _declared = [l for l in _out.splitlines() if l.startswith("  declared ")]
        check("EXEMPT is empty, so the real tree declares NOTHING", len(_declared), 0)

    # ⛔ THE INTERPRETER RULE, BOTH DIRECTIONS. This LOOSENS a safety guard, so the arms that
    # matter are the ones proving it did not stop flagging a real execution. The third is the
    # one that decides it: an interpreter EARLIER in the line must not exempt a binary that is
    # a command after a separator.
    for _code, _want, _label in (
        ('( cd "$OUT_DIR" && timeout 240 "./${ARTIFACT}" --headless --quit )', True,
         "the boot gate RUNS the binary"),
        ('xvfb-run -a "$BIN" --headless', True, "  ...and so does runner + binary"),
        ('python3 prep.py && "$BIN" --headless', True,
         "  ...an interpreter then a REAL exec still flags"),
        ('python3 "$CHECK" "$BIN" --src=src', False,
         "python3 READING the binary is not running it"),
        ('[ -s "$BIN" ] || exit 2', False, "  ...nor is test -s"),
        ('stat -c%s "$BIN"', False, "  ...nor is stat"),
    ):
        check(_label, _runs_the_binary(_code), _want)

    print(f"\n{'FAILED: ' + ', '.join(fails) if fails else 'all arms as expected'}")
    return 1 if fails else 0


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    sys.exit(main(sys.argv[1:]))
