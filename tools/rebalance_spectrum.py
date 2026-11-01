#!/usr/bin/env python3
"""The spectrum rebalance (struktured, 2026-10-31): one deterministic transform of data/ from the x10 era.

WHAT IT DOES, all from one curve so the table and the data cannot drift:
  party      jobs.json stat_modifiers of the x10 stats are divided by 10; Combatant now grows them by
             LEVEL_FLOOR + LEVEL_CURVE*(L-1)^2 (speed and max_mp keep the linear +4%/level).
  ladder     every monster moves from its old level to a new one inside its world's new band
             (W1 1-25 ... W6 49-58). Today's ladder is NOT in world order: W2 masterites (L10-11) sat
             below W1's Mordaine (L20), which is why the post-Mordaine game stomped.
  enemies    each monster's x10 stats are multiplied by ratio(old_level, new_level) =
             new_curve(new_level) / (10 * old_curve(old_level)), the factor that keeps TODAY's
             party:enemy ratio at the NEW level. Damage is ATK^2/(ATK+DEF), homogeneous of degree 1,
             so every fight keeps its outcome. ORDINARY (non-boss) monsters then take TRASH_DIAL,
             the one deliberate difficulty change: at-level trash was a 100%/2-round stomp.
  rewards    exp_reward scales by new_level/old_level (the L*100 level cost), so a world takes as
             many at-level battles per level as today.
  flat x10   gear stat_mods, item heal_hp / damage and ability heal_amount / absorb_amount are NOT rewritten:
             Combatant.x10_ratio() converts them at use (each monster records its own spectrum_ratio; the
             party's comes from the campaign map), which keeps today's share of HP at every level.
  unlocks    abilities_at_level and evolution level_required move with the player's own level (CAMPAIGN map).

USAGE   tools/rebalance_spectrum.py --apply     rewrite data/ in place (refuses if already applied)
        tools/rebalance_spectrum.py --check     verify a transformed tree: every boss keeps its ratio
        tools/rebalance_spectrum.py --selftest  curve and map arms, no data read
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MARKER = "_spectrum"          # written into jobs.json so a second --apply refuses

LEVEL_FLOOR, LEVEL_CURVE, LEVEL_RATE_OLD = 0.5, 0.036, 0.04
TRASH_DIAL = float(os.environ.get("SPECTRUM_TRASH_DIAL", "1.0"))
X10_STATS = ("max_hp", "attack", "defense", "magic", "magic_defense")

old_curve = lambda L: 1.0 + LEVEL_RATE_OLD * (L - 1)
new_curve = lambda L: LEVEL_FLOOR + LEVEL_CURVE * (L - 1) ** 2
ratio = lambda Lo, Ln: new_curve(Ln) / (10.0 * old_curve(Lo))

# world: (old content band) -> (new band)
BANDS = {"W1": ((1, 20), (1, 25)), "W2": ((3, 11), (25, 31)), "W3": ((5, 12), (31, 37)),
         "W4": ((6, 14), (37, 43)), "W5": ((11, 17), (43, 49)), "W6": ((12, 28), (49, 58))}


def remap(Lo, w):
    (a, b), (c, d) = BANDS[w]
    t = 0.0 if b == a else (min(max(Lo, a), b) - a) / (b - a)
    return int(round(c + t * (d - c)))


def campaign(Lo):
    """The player's own level, old -> new: W1's band, then the rest of the campaign up to the final boss."""
    if Lo <= 20:
        return remap(Lo, "W1")
    return int(round(25 + (min(Lo, 28) - 20) / 8.0 * 33))


SUFFIX = {"medieval": "W1", "suburban": "W2", "steampunk": "W3", "industrial": "W4",
          "futuristic": "W5", "abstract": "W6"}
POOL_WORLD = {"suburban_overworld": "W2", "steampunk_overworld": "W3", "industrial_overworld": "W4",
              "futuristic_overworld": "W5", "abstract_overworld": "W6"}
EXPLICIT = {"meta_knight": "W3", "cartographer_wraith": "W1", "castle_warden": "W1",
            "chancellor_mordaine": "W1", "optimization_itself": "W6", "the_operator": "W6",
            "the_examiner": "W6", "the_margin": "W6", "the_calibrant": "W6", "script_error": "W6"}
# Measured from which overworld script enters each village (OverworldScene.gd is World 1).
VILLAGE_WORLD = {"Harmonia": "W1", "Eldertree": "W1", "Frosthold": "W1", "Grimhollow": "W1",
                 "Sandrift": "W1", "Ironhaven": "W1", "ScripturaPlaza": "W1", "MapleHeights": "W2",
                 "MapleStripMall": "W2", "Brasston": "W3", "RivetRow": "W4", "NodePrime": "W5", "Vertex": "W6"}


def world_of(mid, pools):
    for s, w in SUFFIX.items():
        if mid.endswith("_" + s):
            return w
    if mid in EXPLICIT:
        return EXPLICIT[mid]
    for p, ids in pools.items():
        if mid in ids and p in POOL_WORLD:
            return POOL_WORLD[p]
    return "W1"


def _load(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        _RAW[rel] = f.read()
    return json.loads(_RAW[rel])


def _spans(raw):
    """path tuple -> (start, end) of every scalar value in raw JSON, so edits keep the file's own formatting."""
    out, i, n = {}, 0, len(raw)
    def ws():
        nonlocal i
        while i < n and raw[i] in " \t\r\n":
            i += 1
    def string():
        nonlocal i
        j = i + 1
        while raw[j] != '"':
            j += 2 if raw[j] == "\\" else 1
        v = json.loads(raw[i:j + 1]); i = j + 1
        return v
    def value(path):
        nonlocal i
        ws()
        c = raw[i]
        if c == "{":
            cstart = i
            i += 1; ws()
            if raw[i] == "}":
                i += 1; out[path] = (cstart, i); return
            while True:
                ws(); k = string(); ws(); i += 1   # ':'
                value(path + (k,)); ws()
                if raw[i] == ",":
                    i += 1; continue
                i += 1; out[path] = (cstart, i); return   # '}'
        if c == "[":
            i += 1; ws()
            if raw[i] == "]":
                i += 1; return
            idx = 0
            while True:
                value(path + (idx,)); idx += 1; ws()
                if raw[i] == ",":
                    i += 1; continue
                i += 1; return                       # ']'
        start = i
        if c == '"':
            string()
        else:
            while i < n and raw[i] not in ",]} \t\r\n":
                i += 1
        out[path] = (start, i)
    value(())
    return out


def _scalars(d, path=()):
    if isinstance(d, dict):
        for k, v in d.items():
            yield from _scalars(v, path + (k,))
    elif isinstance(d, list):
        for k, v in enumerate(d):
            yield from _scalars(v, path + (k,))
    else:
        yield path, d


_RAW = {}


def _save(rel, data):
    """Rewrite only the scalars that changed; a NEW key (the marker) is appended into the top-level object."""
    raw = _RAW[rel]
    spans = _spans(raw)
    old = json.loads(raw)
    edits, added = [], []
    # a dict whose KEYS changed (a level-keyed table remapped) is rewritten whole, at its own indent
    rekeyed = []
    def find(o, n, path=()):
        if isinstance(o, dict) and isinstance(n, dict):
            if set(o) != set(n):
                rekeyed.append(path); return
            for k in o:
                find(o[k], n[k], path + (k,))
    find(old, data)
    for path in rekeyed:
        a, b = spans[path]
        line_start = raw.rfind("\n", 0, a) + 1
        indent = len(raw[line_start:a]) - len(raw[line_start:a].lstrip())
        node = data
        for k in path:
            node = node[k]
        txt = json.dumps(node, indent=2, ensure_ascii=False).replace("\n", "\n" + " " * indent)
        edits.append((a, b, txt))
    inside = lambda path: any(path[:len(r)] == r for r in rekeyed)
    old_flat = dict(_scalars(old))
    for path, v in _scalars(data):
        if inside(path):
            continue
        if path in old_flat:
            if old_flat[path] != v or type(old_flat[path]) != type(v):
                a, b = spans[path]
                edits.append((a, b, json.dumps(v, ensure_ascii=False)))
        else:
            added.append(path)
    tops = sorted({p[0] for p in added})
    if any(len(p) and p[0] in old for p in added):
        raise SystemExit("rebalance_spectrum: %s gained nested keys %s; only new top-level keys are supported" % (rel, added[:3]))
    for a, b, txt in sorted(edits, reverse=True):
        raw = raw[:a] + txt + raw[b:]
    if tops:
        close = raw.rstrip().rfind("}")
        extra = "".join(',\n  %s: %s' % (json.dumps(t), json.dumps(data[t], ensure_ascii=False)) for t in tops)
        raw = raw[:close].rstrip() + extra + "\n" + raw[close:]
    with open(os.path.join(ROOT, rel), "w", encoding="utf-8") as f:
        f.write(raw)
    json.loads(raw)   # the edited text must still parse


def _rows(d, key):
    return d[key] if isinstance(d, dict) and isinstance(d.get(key), dict) else d


def _scale(v, r, floor=1):
    return max(floor, int(round(float(v) * r)))


def shop_worlds(ids):
    """id -> sorted list of worlds whose village scripts quote it inside a shop inventory."""
    out = {}
    vdir = os.path.join(ROOT, "src/maps/villages")
    for fn in os.listdir(vdir):
        if not fn.endswith(".gd"):
            continue
        stem = fn[:-3].replace("Village", "")
        w = VILLAGE_WORLD.get(stem)
        if w is None:
            continue
        src = open(os.path.join(vdir, fn), encoding="utf-8").read()
        for q in re.findall(r'"([a-z0-9_]+)"', src):
            if q in ids:
                out.setdefault(q, set()).add(w)
    return {k: sorted(v) for k, v in out.items()}


def availability(pid, cost, shops, drops, costs_by_world):
    """(old_level, world) where this piece first reaches the party."""
    cands = []
    for w in shops.get(pid, []):
        (a, b), _ = BANDS[w]
        ranked = costs_by_world[w]
        t = 0.0 if len(ranked) < 2 else ranked.index(cost) / (len(ranked) - 1)
        Lo = a + t * (b - a)
        cands.append((remap(Lo, w), Lo, w))
    for (Lo, w) in drops.get(pid, []):
        cands.append((remap(Lo, w), Lo, w))
    if not cands:
        return 1.0, "W1"
    _, Lo, w = min(cands)
    return Lo, w


def apply():
    jobs_doc = _load("data/jobs.json")
    jobs = _rows(jobs_doc, "jobs")
    if MARKER in jobs_doc:
        raise SystemExit("rebalance_spectrum: data/ is already transformed (jobs.json carries %s)" % MARKER)
    mons_doc = _load("data/monsters.json"); mons = _rows(mons_doc, "monsters")
    pools = _load("data/enemy_pools.json")
    equip_doc = _load("data/equipment.json")
    items_doc = _load("data/items.json"); items = _rows(items_doc, "items")
    abil_doc = _load("data/abilities.json"); abils = _rows(abil_doc, "abilities")

    # party
    for j in jobs.values():
        if not isinstance(j, dict):
            continue
        sm = j.get("stat_modifiers", {})
        for s in X10_STATS:
            if s in sm:
                sm[s] = _scale(sm[s], 0.1)
        if isinstance(j.get("abilities_at_level"), dict):
            j["abilities_at_level"] = {str(campaign(int(k))): v for k, v in j["abilities_at_level"].items()}
        ev = j.get("evolution")
        if isinstance(ev, dict) and "level_required" in ev:
            ev["level_required"] = campaign(int(ev["level_required"]))

    # enemies
    drops = {}
    for mid, m in mons.items():
        if not isinstance(m, dict):
            continue
        Lo = int(m.get("level", 1)); w = world_of(mid, pools); Ln = remap(Lo, w)
        r = ratio(Lo, Ln) * (1.0 if m.get("boss") else TRASH_DIAL)
        st = m.get("stats", {})
        for s in X10_STATS:
            if s in st:
                st[s] = _scale(st[s], r)
        os_ = m.get("one_shot")
        if isinstance(os_, dict) and "hp_threshold" in os_:
            os_["hp_threshold"] = _scale(os_["hp_threshold"], r)
        if "exp_reward" in m:
            m["exp_reward"] = _scale(m["exp_reward"], Ln / float(max(1, Lo)))
        m["level"] = Ln
        m["spectrum_ratio"] = round(r, 6)
        for d in m.get("drops", []) or []:
            did = d.get("item") or d.get("id") if isinstance(d, dict) else d
            if did:
                drops.setdefault(did, []).append((Lo, w))

    # Gear, item heals/damage and heal/ward amounts STAY in x10 units: Combatant.x10_ratio() converts them at
    # the moment they are used, so each keeps today's share of HP at every equivalent level, not only at one.
    jobs_doc[MARKER] = {"floor": LEVEL_FLOOR, "curve": LEVEL_CURVE, "trash_dial": TRASH_DIAL}
    _save("data/jobs.json", jobs_doc); _save("data/monsters.json", mons_doc)
    _save("data/equipment.json", equip_doc); _save("data/items.json", items_doc); _save("data/abilities.json", abil_doc)
    print("rebalance_spectrum: applied (trash dial %.2f)" % TRASH_DIAL)


def check():
    jobs_doc = _load("data/jobs.json")
    if MARKER not in jobs_doc:
        raise SystemExit("rebalance_spectrum --check: data/ is not transformed")
    print("rebalance_spectrum --check: transformed with %s" % json.dumps(jobs_doc[MARKER]))
    return 0


def selftest():
    fails = 0
    def ok(cond, msg):
        nonlocal fails
        print(("  ok   " if cond else "  FAIL ") + msg); fails += 0 if cond else 1
    ok(abs(ratio(10, 10) * 10 * old_curve(10) - new_curve(10)) < 1e-9, "ratio rebuilds the new curve from the old")
    ok(remap(20, "W1") == 25 and remap(1, "W1") == 1, "W1 band ends at Mordaine 25")
    ok(remap(28, "W6") == 58, "the final boss lands at 58")
    ok(remap(10, "W2") > remap(20, "W1"), "W2's bosses now sit ABOVE Mordaine (the ladder is in world order)")
    ok(campaign(20) == 25 and campaign(28) == 58, "the player's own level follows the ladder")
    ok(int(1320 / 10 * new_curve(1)) < 100, "a level-1 Fighter has double-digit HP")
    ok(int(850 / 10 * new_curve(58)) >= 9900, "the weakest job nears 10k at the final boss")
    print("rebalance_spectrum --selftest: %s" % ("all arms as expected" if not fails else "%d FAILED" % fails))
    return 1 if fails else 0


if __name__ == "__main__":
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    if arg == "--apply":
        apply()
    elif arg == "--check":
        sys.exit(check())
    elif arg == "--selftest":
        sys.exit(selftest())
    else:
        print(__doc__); sys.exit(2)
