#!/usr/bin/env python3
"""notes_draft.py NNN -- draft the tag message for fold NNN from tmp/fold_args_NNN.txt.

Each non-merge commit of a queued branch goes under PLAYERS if its own files reach what ships
(src/, data/, assets/, project.godot, export_presets.cfg), else under BEHIND THE SCENES.
Player lines carry no hashes. The .803 notes listed fold tooling as a player change and put
hashes on player lines; the devlog copied both. Prints to stdout; ends with GATE_LINE for
tools/gate_line.py --fill. --selftest runs the classifier's arms.
"""
import subprocess, sys

SHIPS = ("src/", "data/", "assets/")
SHIPS_FILES = ("project.godot", "export_presets.cfg")


def ships(paths):
    return any(p.startswith(SHIPS) or p in SHIPS_FILES for p in paths)


def git(*a):
    return subprocess.run(["git", *a], capture_output=True, text=True, check=True).stdout


def commits(sha):
    out = git("log", "--no-merges", "--format=%H %s", f"origin/main..{sha}")
    for row in out.splitlines():
        h, _, subj = row.partition(" ")
        if subj and not subj.startswith("chore: bump"):
            yield subj, git("show", "--name-only", "--format=", h).split()


def main(nnn):
    players, behind = [], []
    for line in open(f"tmp/fold_args_{nnn}.txt"):
        line = line.strip()
        if not line:
            continue
        branch, sha = line.split(":", 1)
        for subj, paths in commits(sha):
            if ships(paths):
                players.append(subj)
            else:
                behind.append(f"{subj} ({branch} {sha})")
    print(f"v3.33.{nnn}-alpha\n\nFor players:")
    print("\n".join(f"- {s}" for s in players) or "- (nothing player-facing)")
    print("\nBehind the scenes:")
    print("\n".join(f"- {s}" for s in behind) or "- (none)")
    print("\nGATE_LINE")


def selftest():
    arms = [
        ("tools only is behind the scenes", ["tools/fold_gate/fold.sh"], False),
        ("a test only is behind the scenes", ["test/unit/test_x.gd"], False),
        ("src ships", ["tools/a.sh", "src/ui/Toast.gd"], True),
        ("data ships", ["data/abilities.json"], True),
        ("an asset ships", ["assets/audio/sfx/x.ogg"], True),
        ("project.godot ships", ["project.godot"], True),
        ("a path merely containing src/ does not", ["tools/src/x.py"], False),
    ]
    fails = 0
    for label, paths, want in arms:
        ok = ships(paths) == want
        fails += not ok
        print(("ok   " if ok else "FAIL ") + label)
    print("notes_draft selftest: " + ("every arm as expected" if not fails else "an arm FAILED"))
    return 1 if fails else 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        sys.exit(selftest())
    if len(sys.argv) != 2 or not sys.argv[1].isdigit():
        sys.exit("usage: notes_draft.py NNN | --selftest")
    main(sys.argv[1])
