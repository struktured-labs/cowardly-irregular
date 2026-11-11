"""Repoint a monster sheet's animations in data/sprite_manifest.json, text-level so the file's formatting survives.

Usage (as a module): repoint({"ghost": ({"idle": (3, 4)}, "why")}). Each entry's reason is appended to its `source`
(created after `path` when absent), so a later regen can see what to swap back. The PNG is never touched.
"""
import json
import re

MANIFEST = "data/sprite_manifest.json"


def repoint(changes, manifest=MANIFEST):
    text = open(manifest).read()
    for sid, (anims, why) in changes.items():
        head = text.index('\n    "%s": {' % sid, text.index('"monster_sheets": {'))
        end = text.index("\n    }", head)
        block = text[head:end]
        for an, (s, e) in anims.items():
            block, n = re.subn(r'("%s": \{\s*"start": )\d+(,\s*"end": )\d+' % an, r"\g<1>%d\g<2>%d" % (s, e), block, count=1)
            assert n == 1, (sid, an)
        note = json.dumps(why, ensure_ascii=False)[1:-1]
        m = re.search(r'\n      "source": "((?:[^"\\]|\\.)*)"', block)
        if m:
            block = block[:m.end(1)] + " " + note + block[m.end(1):]
        else:
            nl = block.index("\n", block.index('"path"'))
            block = block[:nl] + '\n      "source": "%s",' % note + block[nl:]
        text = text[:head] + block + text[end:]
    json.loads(text)
    open(manifest, "w").write(text)
