#!/usr/bin/env python3
# check_ambient_is_unpitched.py — an ambient bed plays UNDER music, so it must not carry a pitch.
#
# 2026-10-30, struktured in Harmonia: "I hear a 2nd melody behind the main village melody." The W1
# village ambient layer was "Market Morning", a Suno track prompted as "village ambient loop... market
# chatter" -- and Suno wrote a SONG. Two songs in two keys played under every W1 village.
#
# METRIC: pitch-class clarity. Chroma (110 Hz - 2 kHz, 12 bins) per 4096-sample frame at 22.05 kHz,
# clarity = max/mean of the bins, median over the first 60 s. Calibrated on this repo, 2026-10-30:
#     every real ambience (18 ElevenLabs ambient_/weather_ in sfx_manifest)   max 4.99
#     the melodic Suno "ambient" beds (village/forest/cave/ocean)            7.49 - 7.71
# ⚠️ ONE-SIDED. Songs span 2.4 - 9.6 (percussive industrial bosses sit at 2.4-3.2), so a LOW score
# does not prove "not a song" -- this catches PITCH, which is what is heard against the music's key.
# A steady pitched drone fails too, deliberately: a drone in one key under a song in another clashes.
#
# Corpus: every `ambient_*` / `weather_*` key in BOTH manifests. A key may be HELD below with a reason,
# and a held key that now measures clean reds (the hold has expired).
#
# SECOND LEG, LOUDNESS (2026-10-31, with cowir-sfx): data/ambient_recipes.json sets each soundscape bed by
# MEASURED loudness -- places.<id>.music_lufs and phases.<p>.bed_lufs, EBU R128 integrated over the first
# 60 s -- and the game derives the trim from them. A re-rendered bed or re-mastered track would keep its
# old number and be trimmed for audio that no longer exists, so each is re-measured here, red past 1 LU.
# Corpus BY THE RECIPE, not by prefix (night_crickets_wind is a bed). The track is the recipe's own
# `music_key`; that it is the track the village really plays is cowir-sfx's engine-side guard.
# Exit 0 clean · 1 a pitched bed, an expired hold or a stale loudness · 2 could not measure
import json, os, subprocess, sys

CEILING = 6.0
SR, N, SECS = 22050, 4096, 60.0
## village/forest/cave measured 7.5-7.7; 2026-10-30 they became suno_* Jukebox rows, out of this corpus.
HELD = {
    "ambient_ocean": "music store: unreachable (test_unreachable_music_is_pinned); must not be wired as it is",
    "ambient_industrial": "music store: unreachable (test_unreachable_music_is_pinned); must not be wired as it is",
}


def clarity(path, np):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-t", str(SECS), "-ac", "1", "-ar", str(SR),
                          "-f", "f32le", "-"], capture_output=True, check=True).stdout
    x = np.frombuffer(raw, dtype=np.float32)
    fr = np.fft.rfftfreq(N, 1 / SR)
    band = (fr >= 110) & (fr <= 2000)
    pc = (np.round(12 * np.log2(fr[band] / 440.0)) % 12).astype(int)
    w = np.hanning(N)
    vals = []
    for i in range(0, len(x) - N, N):
        f = x[i:i + N]
        if np.sqrt(np.mean(f * f)) < 1e-4:
            continue
        c = np.bincount(pc, weights=np.abs(np.fft.rfft(f * w))[band] ** 2, minlength=12)
        vals.append(c.max() / c.mean())
    if not vals:
        raise ValueError("no audible frames")
    return float(np.median(vals))


LUFS_TOL = 1.0
RECIPES = "data/ambient_recipes.json"


def lufs(path):
    out = subprocess.run(["ffmpeg", "-nostats", "-v", "info", "-i", path, "-t", str(SECS), "-af", "ebur128",
                          "-f", "null", "-"], capture_output=True, text=True, errors="replace")
    if out.returncode != 0:
        raise ValueError("ffmpeg EC=%d" % out.returncode)
    vals = [l.split()[1] for l in out.stderr.splitlines() if l.strip().startswith("I:") and "LUFS" in l]
    if not vals:
        raise ValueError("no integrated loudness in ffmpeg output")
    return float(vals[-1])


def loudness_audit(root):
    """[(label, stored, measured)] for every number the recipe stores; stale and unmeasurable lists."""
    rp = os.path.join(root, RECIPES)
    if not os.path.exists(rp):
        return None
    music = json.load(open(os.path.join(root, "data/music_manifest.json"))).get("tracks", {})
    sfx = json.load(open(os.path.join(root, "data/sfx_manifest.json"))).get("sfx", {})
    rows, stale, fails = [], [], []
    for place, pl in sorted(json.load(open(rp)).get("places", {}).items()):
        checks = [("%s music %s" % (place, pl.get("music_key")), music.get(pl.get("music_key"), {}), pl.get("music_lufs"))]
        for ph, x in sorted(pl.get("phases", {}).items()):
            checks.append(("%s %s bed %s" % (place, ph, x.get("bed")), sfx.get(x.get("bed"), {}), x.get("bed_lufs")))
        for label, entry, stored in checks:
            f = entry.get("file") if isinstance(entry, dict) else None
            if not f or stored is None:
                fails.append("%s: %s" % (label, "no file in its manifest" if not f else "no stored loudness"))
                continue
            try:
                m = lufs(os.path.join(root, f))
            except Exception as e:
                fails.append("%s: %s" % (label, e))
                continue
            rows.append((label, float(stored), m))
            print("  %-6s %-46s stored %6.1f  measured %6.1f LUFS" % ("ok" if abs(m - float(stored)) <= LUFS_TOL else "STALE", label, float(stored), m))
            if abs(m - float(stored)) > LUFS_TOL:
                stale.append("%s stored %.1f, measures %.1f" % (label, float(stored), m))
    return rows, stale, fails


def corpus(root):
    out = {}
    music = json.load(open(os.path.join(root, "data/music_manifest.json"))).get("tracks", {})
    sfx = json.load(open(os.path.join(root, "data/sfx_manifest.json"))).get("sfx", {})
    for store, table in (("music", music), ("sfx", sfx)):
        for k, v in table.items():
            if (k.startswith("ambient_") or k.startswith("weather_")) and isinstance(v, dict) and v.get("file"):
                out[(store, k)] = os.path.join(root, v["file"])
    return out


def audit(root, held, np):
    bad, expired, fails, n = [], [], [], 0
    for (store, key), path in sorted(corpus(root).items()):
        try:
            c = clarity(path, np)
        except Exception as e:
            fails.append("%s/%s: %s" % (store, key, e))
            continue
        n += 1
        hold = held.get(key) if store == "music" else None
        tag = "HELD" if hold else ("ok" if c <= CEILING else "PITCHED")
        print("  %-8s %-6s %-26s clarity %5.2f" % (tag, store, key, c))
        if c > CEILING and not hold:
            bad.append("%s/%s %.2f" % (store, key, c))
        if hold and c <= CEILING:
            expired.append("%s/%s %.2f now measures clean -- remove its HELD entry (%s)" % (store, key, c, hold))
    return n, bad, expired, fails


def _selftest(np):
    import tempfile
    t = tempfile.mkdtemp(dir=os.path.join(os.getcwd(), "tmp"))
    os.makedirs(os.path.join(t, "data"))
    rng = np.random.default_rng(7)
    sec = np.arange(int(SR * 12)) / SR
    notes = [261.6, 329.6, 392.0, 440.0, 349.2, 293.7]
    melody = np.concatenate([0.3 * np.sin(2 * np.pi * notes[i % 6] * sec[:SR]) for i in range(12)])
    noise = 0.3 * rng.standard_normal(len(sec))

    def wav(name, sig):
        p = os.path.join(t, name)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", p],
                       input=sig.astype(np.float32).tobytes(), check=True)
        return name

    def man(music, sfx):
        json.dump({"tracks": music}, open(os.path.join(t, "data/music_manifest.json"), "w"))
        json.dump({"sfx": sfx}, open(os.path.join(t, "data/sfx_manifest.json"), "w"))

    m, z = wav("melody.wav", melody), wav("noise.wav", noise)
    arms, fails = 0, 0

    def arm(name, ok):
        nonlocal arms, fails
        arms += 1
        if not ok:
            fails += 1
            print("FAIL %s" % name)
    man({"ambient_x": {"file": m}}, {"weather_y": {"file": z}})
    n, bad, exp, f = audit(t, {}, np)
    arm("a melody under an ambient key reds, naming it", n == 2 and bad == ["music/ambient_x %s" % bad[0].split()[-1]] if bad else False)
    arm("noise under a weather key stays clean", not any("weather_y" in b for b in bad))
    n, bad, exp, f = audit(t, {"ambient_x": "held for a reason"}, np)
    arm("a HELD melody is not a defect", bad == [] and exp == [])
    man({"ambient_x": {"file": z}}, {})
    n, bad, exp, f = audit(t, {"ambient_x": "held for a reason"}, np)
    arm("a hold over a bed that now measures clean expires (reds)", len(exp) == 1)
    man({"ambient_x": {"file": "missing.ogg"}, "battle_z": {"file": m}}, {})
    n, bad, exp, f = audit(t, {}, np)
    arm("an unmeasurable file is a failure, not a pass", len(f) == 1 and n == 0)
    arm("a non-ambient key is outside the corpus", not any("battle_z" in b for b in bad))
    ## The loudness leg, on a recipe pointing at the noise file it measures.
    man({"village_x": {"file": z}}, {"bed_y": {"file": z}})
    real = lufs(os.path.join(t, z))
    def recipe(music_lufs, bed_lufs, bed="bed_y"):
        json.dump({"places": {"p": {"music_key": "village_x", "music_lufs": music_lufs,
                                    "phases": {"day": {"bed": bed, "bed_lufs": bed_lufs}}}}},
                  open(os.path.join(t, RECIPES), "w"))
    recipe(real, real)
    rows, stale, f = loudness_audit(t)
    arm("a recipe whose numbers match its files is clean", len(rows) == 2 and stale == [] and f == [])
    recipe(real, real + 3.0)
    rows, stale, f = loudness_audit(t)
    arm("a stale bed_lufs reds, naming the bed", len(stale) == 1 and "bed bed_y" in stale[0])
    recipe(real - 3.0, real)
    rows, stale, f = loudness_audit(t)
    arm("a stale music_lufs reds, naming the track", len(stale) == 1 and "music village_x" in stale[0])
    recipe(real, real, bed="bed_missing")
    rows, stale, f = loudness_audit(t)
    arm("a bed the sfx manifest does not name is unmeasurable, not clean", len(f) == 1 and stale == [])
    subprocess.run(["rm", "-rf", t])
    print("check_ambient_is_unpitched selftest: %d/%d arms as expected" % (arms - fails, arms))
    return 1 if fails else 0


def main():
    try:
        import numpy as np
    except ImportError:
        print("check_ambient_is_unpitched: numpy unavailable -- NOTHING MEASURED", file=sys.stderr)
        return 2
    if "--selftest" in sys.argv[1:]:
        return _selftest(np)
    root = os.getcwd()
    n, bad, expired, fails = audit(root, HELD, np)
    print("[ambient-pitch] %d bed(s) measured · ceiling %.1f · %d pitched · %d expired hold(s) · %d unmeasurable"
          % (n, CEILING, len(bad), len(expired), len(fails)))
    for line in bad:
        print("  PITCHED %s -- an ambient bed with a pitch sounds a second key under the music" % line)
    for line in expired + fails:
        print("  %s" % line)
    lo = loudness_audit(root)
    stale, lfails = [], []
    if lo is None:
        print("[ambient-loudness] no %s -- nothing to measure" % RECIPES)
    else:
        rows, stale, lfails = lo
        print("[ambient-loudness] %d stored loudness value(s) re-measured · tolerance %.1f LU · %d stale · %d unmeasurable"
              % (len(rows), LUFS_TOL, len(stale), len(lfails)))
        for line in stale:
            print("  STALE %s -- the game trims this bed for audio that is no longer in the file" % line)
        for line in lfails:
            print("  %s" % line)
    if fails or n == 0 or lfails:
        return 2
    return 1 if (bad or expired or stale) else 0


if __name__ == "__main__":
    sys.exit(main())
