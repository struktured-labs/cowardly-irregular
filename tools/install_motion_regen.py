"""Install paid regen_s4_motion_frames strips into a T1 monster sheet, so the monster attacks, flinches and dies as itself.
Spends nothing: the strips are the normalised output of calls already on the spend ledger (tmp/gpt2_trial/out/calls.jsonl).

Frame 0 becomes the shipped idle (the manifest's idle start, which is not always 0), kept byte for byte, soft edge included (cowir-main 26252). Frame 1 = the idle strip's breath panel, 2-3 attack, 4-5 hit, 6-7 dead, and any frame
past 7 (the Rat King's royal_spite) is kept. The ranges go back to idle 0-1 / attack 2-3 / hit 4-5 / dead 6-7.
Refuses a sheet whose tier is not T1, and a strip that is not two 256 px frames with binary alpha.
Prints, per monster, the EYE_REVIEWED pins test_a_monster_stays_one_creature needs, so a look is pinned to those pixels.

Usage: uv run python tools/install_motion_regen.py <strips_dir> <monster|tag-map.json> [--write]
       python3 tools/install_motion_regen.py --selftest
<tag-map.json> maps "monster|anim" -> strip filename (a strip is <tag>__strip.png). --selftest is in memory only."""
import hashlib, json, sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent.parent))
from tools.artist_guard import tier_refusal

MANIFEST = "data/sprite_manifest.json"
FW = 256
LAYOUT = {"idle": (0, 1), "attack": (2, 3), "hit": (4, 5), "dead": (6, 7)}
# Which strip panel fills each frame; frame 0 stays the shipped idle.
FILL = {1: ("idle", 1), 2: ("attack", 0), 3: ("attack", 1), 4: ("hit", 0), 5: ("hit", 1), 6: ("dead", 0), 7: ("dead", 1)}


def strip_refusal(strip: np.ndarray) -> str:
    if strip.shape != (FW, 2 * FW, 4):
        return f"strip is {strip.shape[1]}x{strip.shape[0]}, not two {FW} px frames"
    if not np.isin(strip[..., 3], (0, 255)).all():
        return "strip alpha is not binary (not the normalised output)"
    for k in range(2):
        if (strip[:, k * FW:(k + 1) * FW, 3] == 255).sum() < 200:
            return f"strip panel {k} is empty"
    return ""


STRAY_SHARE, STRAY_GAP = 0.02, 12


def drop_strays(frame: np.ndarray) -> list:
    """Clear detached chips the panel split left behind: under STRAY_SHARE of the body AND over STRAY_GAP px from every
    piece that is not itself small, so a pair of chips cannot vouch for each other. A splash or trail by a real part stays. Returns the cleared pieces' sizes."""
    from scipy import ndimage
    solid = frame[..., 3] >= 128
    lab, n = ndimage.label(solid, np.ones((3, 3)))
    if n < 2:
        return []
    sizes = np.bincount(lab.ravel())[1:]
    cleared = []
    keep = np.isin(lab, 1 + np.flatnonzero(sizes >= STRAY_SHARE * sizes.max()))   # the body and every real part
    gap = ndimage.distance_transform_edt(~keep)
    for j in range(1, n + 1):
        if sizes[j - 1] >= STRAY_SHARE * sizes.max():
            continue
        if gap[lab == j].min() > STRAY_GAP:
            frame[lab == j] = 0
            cleared.append(int(sizes[j - 1]))
    return cleared


def build(sheet: np.ndarray, strips: dict, log=None, idle_at: int = 0) -> np.ndarray:
    """sheet: H x W x 4 with W >= 8 frames; strips: anim -> 256x512x4; idle_at: the shipped idle's frame. Returns the new sheet."""
    out = sheet.copy()
    out[:, :FW] = sheet[:, idle_at * FW:(idle_at + 1) * FW]   # the shipped idle, byte for byte, moves to frame 0
    for f, (anim, k) in FILL.items():
        fr = strips[anim][:, k * FW:(k + 1) * FW].copy()
        gone = drop_strays(fr)
        if gone and log is not None:
            log.append(f"frame {f}: cleared {gone}")
        out[:, f * FW:(f + 1) * FW] = fr
    return out


def range_hash(sheet: np.ndarray, a: int, b: int) -> str:
    """The guard's _range_hash: frames a..b, transparent pixels' RGB zeroed (the import rewrites them)."""
    h = hashlib.sha256()
    for i in range(a, b + 1):
        f = sheet[:, i * FW:(i + 1) * FW].copy()
        f[f[..., 3] == 0, :3] = 0
        h.update(f.tobytes())
    return h.hexdigest()


SOURCE = ("idle 0 shipped; idle 1, attack 2-3, hit 4-5, dead 6-7 from the paid S4 motion regen ({model}, strips {tags}), "
          "installed by tools/install_motion_regen.py at $0. Replaces the 2026-11-11 idle repoint (ruling 23683): the legacy "
          "frames held other creatures; these were drawn from this sheet's own idle and are the same creature.")


def install(monster: str, files: dict, strips_dir: Path, write: bool) -> dict:
    man = json.load(open(MANIFEST))
    entry = man["monster_sheets"].get(monster)
    if entry is None:
        raise SystemExit(f"{monster}: not a registered monster_sheet")
    why = tier_refusal(entry.get("tier"), monster)
    if why:
        raise SystemExit(why)
    path = entry["path"].replace("res://", "")
    sheet = np.array(Image.open(path).convert("RGBA"))
    if sheet.shape[1] < 8 * FW or sheet.shape[0] != FW:
        raise SystemExit(f"{monster}: sheet is {sheet.shape[1]}x{sheet.shape[0]}, needs >= 8 frames of {FW}")
    strips = {}
    for anim in LAYOUT:
        s = np.array(Image.open(strips_dir / files[anim]).convert("RGBA"))
        why = strip_refusal(s)
        if why:
            raise SystemExit(f"{monster} {anim}: {why}")
        strips[anim] = s
    log = []
    new = build(sheet, strips, log, idle_at=int(entry["animations"]["idle"]["start"]))
    for line in log:
        print(f"  {monster} {line}")
    pins = {f"{monster}/{a}": range_hash(new, s, e) for a, (s, e) in LAYOUT.items()}
    if write:
        Image.fromarray(new).save(path)
        raw = open(MANIFEST).read()
        anims = dict(entry["animations"])
        for a, (s, e) in LAYOUT.items():
            anims[a] = {"start": s, "end": e}
        entry["animations"] = anims
        prior = entry.get("source", "")
        if "install_motion_regen" not in prior:   # a re-run keeps the note it already wrote, history included
            entry["source"] = SOURCE.format(model="gpt-image-2.6-sunburst",
                                            tags=", ".join(files[a].replace("__strip.png", "") for a in LAYOUT))
            if prior:
                entry["source"] += " EARLIER (kept for its history; its ranges no longer apply): " + prior
        man["monster_sheets"][monster] = entry
        indent = 2 if '\n  "' in raw else None
        open(MANIFEST, "w").write(json.dumps(man, indent=indent, ensure_ascii=False) + ("\n" if raw.endswith("\n") else ""))
    return pins


def selftest() -> int:
    fails = []
    sheet = np.zeros((FW, 10 * FW, 4), np.uint8)
    sheet[..., 3] = 255; sheet[..., 0] = np.arange(10 * FW)[None, :] // FW   # each frame tagged by its index in R
    strips = {}
    for n, a in enumerate(LAYOUT):
        s = np.zeros((FW, 2 * FW, 4), np.uint8); s[..., 3] = 255; s[..., 1] = 100 + n
        s[:, FW:, 2] = 1   # panel 1 tagged in B
        strips[a] = s
    out = build(sheet, strips)
    if out[0, 0, 0] != 0 or out[0, 0, 1] != 0:
        fails.append("frame 0 must stay the shipped idle")
    soft = sheet.copy(); soft[0, 0, 3] = 7; soft[0, 1, 3] = 128
    o2 = build(soft, strips)
    if o2[0, 0, 3] != 7 or o2[0, 1, 3] != 128:
        fails.append("frame 0 is what ships today: its soft edge must be left alone (cowir-main 26252)")
    o3 = build(sheet, strips, idle_at=3)
    if o3[0, 0, 0] != 3 or o3[0, 0, 1] != 0:
        fails.append("an idle shipped at frame 3 (ironback_beetle) must become frame 0, not the other creature at frame 0")
    if not (out[0, 8 * FW, 0] == 8 and out[0, 9 * FW, 0] == 9):
        fails.append("frames past 7 (royal_spite) must be kept")
    for f, (a, k) in FILL.items():
        px = out[0, f * FW]
        if px[1] != 100 + list(LAYOUT).index(a) or px[2] != k:
            fails.append(f"frame {f} should be {a} panel {k}, got G={px[1]} B={px[2]}")
    if strip_refusal(np.zeros((FW, FW, 4), np.uint8)) == "":
        fails.append("CONTROL: a one-frame strip must be refused")
    soft = strips["idle"].copy(); soft[0, 0, 3] = 128
    if "binary" not in strip_refusal(soft):
        fails.append("a strip with soft alpha must be refused")
    t = np.zeros((FW, FW, 4), np.uint8); t[0, 0] = (9, 9, 9, 0)
    if range_hash(t, 0, 0) != range_hash(np.zeros((FW, FW, 4), np.uint8), 0, 0):
        fails.append("a transparent pixel's RGB must not move the hash")
    f = np.zeros((FW, FW, 4), np.uint8); f[50:150, 50:150, 3] = 255
    f[100:104, 200:204, 3] = 255   # a 16 px chip 50 px away: a stray
    f[100:104, 152:156, 3] = 255   # a 16 px chip 2 px away: a splash
    if drop_strays(f) != [16] or f[101, 201, 3] != 0 or f[101, 153, 3] != 255:
        fails.append("drop_strays must clear the far chip and keep the near one")
    f = np.zeros((FW, FW, 4), np.uint8); f[50:150, 50:150, 3] = 255
    f[200:204, 200:204, 3] = 255; f[200:204, 206:210, 3] = 255   # two far chips 2 px apart
    if sorted(drop_strays(f)) != [16, 16]:
        fails.append("two far chips must not keep each other alive")
    print("\n".join(fails) or "selftest: ok")
    return 1 if fails else 0


def main() -> int:
    if "--selftest" in sys.argv:
        return selftest()
    strips_dir, which = Path(sys.argv[1]), sys.argv[2]
    write = "--write" in sys.argv
    tagmap = json.load(open(which))
    monsters = list(dict.fromkeys(k.split("|")[0] for k in tagmap))
    allpins = {}
    for m in monsters:
        files = {a: Path(tagmap[f"{m}|{a}"]).name for a in LAYOUT}
        allpins.update(install(m, files, strips_dir, write))
        print(f"{'wrote' if write else 'would write'} {m}")
    print(json.dumps(allpins, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
