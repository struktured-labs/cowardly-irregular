#!/usr/bin/env python3
"""Keys main HAS that the branch lacks or differs on, compared as PARSED objects.

fold_safety's line diff is true of how a file is WRITTEN; this is true of the thing
(cowir-sfx's rule). cowir-battle hit the failure: 15 "missing" lines on monsters.json
were pure em-dash re-escaping — identical content, different encoding. A textual rung
cannot distinguish a lost value from a re-serialised one.

Exits 2 if either side does not parse, so the caller falls back to the line diff.
"""
import json, subprocess, sys

branch, main, path = sys.argv[1], sys.argv[2], sys.argv[3]

def load(ref):
    return json.loads(subprocess.check_output(["git", "show", f"{ref}:{path}"]))

def flat(o, pre=""):
    out = {}
    if isinstance(o, dict):
        for k, v in o.items():
            out.update(flat(v, f"{pre}.{k}"))
    elif isinstance(o, list):
        for i, v in enumerate(o):
            out.update(flat(v, f"{pre}[{i}]"))
    else:
        out[pre] = o
    return out

try:
    b, m = flat(load(branch)), flat(load(main))
except Exception:
    sys.exit(2)

lost = [k for k in m if k not in b or m[k] != b[k]]
print(len(lost))
for k in lost[:4]:
    print(f"      {k} = {m[k]!r}")
