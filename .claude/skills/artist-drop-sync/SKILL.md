---
name: artist-drop-sync
description: Pull new artist sprite drops from Google Drive and integrate them into the game. Covers rclone paths, aseprite tag conventions, the 128px magic number, facing, manifest wiring, and the artist-canon rules. Use when the artist drops a sprite, when checking for new drops, or when integrating any .aseprite into the game.
---

# Artist Drop → Game Sprite Sync

End-to-end path for the artist's Google Drive deliveries. Companion to
`aseprite-export` (raw export mechanics); this covers **finding what's new
and wiring it in without silently breaking it.**

## 0. Rules that outrank everything

1. **Artist frames win.** Never substitute gpt-image output for a frame
   the artist drew.
2. **gpt-image gap-fill IS allowed** for animations the artist did NOT
   supply (struktured, 2026-07-25). Anchor identity on the artist frames.
   Fill gaps; never overwrite.
3. **Only permitted transform on artist pixels: integer nearest-neighbour
   scale.** No palette snap, no resampling filter, no recolour.
4. **Never edit the source `.aseprite`.** Read-only.
5. Tag output `tier: "T2"` (artist draft) / `"T3"` (final). Never `T1`.

## 1. Find new drops

> ⚠️ **The Drive root folder is literally named `" cowir"` — LEADING SPACE.**
> `gdrive:cowir/...` fails with `directory not found`. Use
> `rclone lsl "gdrive: cowir"`. The hourly
> `check_for_new_artist_sprites.sh` has the pre-space path baked in and has
> been silently finding nothing — a 646KB Mordaine drop sat unnoticed for
> two days.

```bash
rclone lsl "gdrive: cowir" | sort -k2,3 -r | head -30   # newest first
```

`rclone lsl` is **already recursive**; `--recursive`/`-R` are invalid and error.

Trees: `Game graphics - Characters` (party jobs, `enemies/`, `Samples/`)
and `Game graphics - NPCs` (20 overworld archetypes).

Pull only the new subtree:
```bash
rclone copy "gdrive: cowir/assets/sprites/Game graphics - Characters/enemies/<Name>" \
            "assets/sprites/drive_archive/Game graphics - Characters/enemies/<Name>" -P
```

## 2. Probe tags — never assume names

Tag names are **not standardized**:

| File | Tags |
|---|---|
| fighter | `IDLE`, `Attack`, `Dash` |
| Mordaine (2026-07-23) | `Idle`, `summon 1` — case differs, boss-specific verb |

`--list-tags` alone prints only names. For **frame ranges** you must add
`--data`:
```bash
aseprite -b --list-tags "f.aseprite" --data probe.json --format json-array --sheet probe.png
```
Read `meta.frameTags[].from/to` (0-indexed, inclusive).

> **Gotcha:** `--sheet-pack` silently DROPS `frameTags`. Never combine it
> with a tag probe.

## 3. ⚠️ 128px is a MAGIC NUMBER — do not upscale monster sheets

`BattleScene` does **not** read `tier` to decide if a sheet is artist art.
It infers it from frame height, and that one proxy gates TWO behaviours:

```
BattleScene.gd:45   const ENEMY_SMALL_FRAME_THRESHOLD: int = 128
BattleScene.gd:44   const ENEMY_SCALE_BUMP: float = 2.5
BattleScene.gd:1026     if ftex.get_height() <= ENEMY_SMALL_FRAME_THRESHOLD:
BattleScene.gd:1027         size_bump = ENEMY_SCALE_BUMP
BattleScene.gd:1028         _is_artist_monster = true
BattleScene.gd:1030     sprite.flip_h = _is_artist_monster
```

Export a monster at 256 and it silently loses **both** the 2.5× bump and
the flip → renders small AND facing away from the party. Nothing warns;
sheet, manifest and tier all look correct. This shipped on Mordaine and
struktured caught it in play (fixed `0335f72b` by re-exporting native).

**`--scale 1` for monster sheets.** The 2× upscale is for JOB sheets
(256px frames), not monsters. Slime — the shipped T2 reference — is 128.

## 4. Facing: verify by eye, and know when it's undefined

The flip exists because artist enemies are authored facing LEFT; the flip
turns them toward the party on the right. **A sheet authored facing right
would ship a backwards monster and no test would catch it.**

Check every ≤128px monster sheet before shipping. And know the limit:
facing is only well-defined **in profile**. `bat`, `slime` and
`chancellor_mordaine` are clearly left-facing. `goblin` is front-facing
three-quarter with his weapon extending right — "authored facing" is
genuinely ambiguous there. **Don't assert a facing value for a
front-facing sprite; say it's ambiguous and flag it.**

## 5. Frame mapping

Game wants `idle`/`attack`/`hit`/`dead`. `BattleScene` guards every play
with `has_animation()`, so a missing anim degrades safely — the monster
just won't react.

Precedent — **slime**, the shipped T2 reference:
```json
"animations": {"idle":{"start":0,"end":3}, "attack":{"start":4,"end":10},
               "hit":{"start":8,"end":10},  "dead":{"start":10,"end":10}}
```
i.e. artist frames **reused** for un-authored anims.

When the artist didn't author `hit`/`dead`, in order of preference:
1. **Reuse an artist sub-range** (slime precedent; free, always on-model)
2. **Ask the artist** — for reaction poses this is the real answer, see below
3. Omit — safe, the monster just won't react
4. gpt-image gap-fill — works for *standing* poses, **not** for reactions

Record which in the manifest `source` string, and say plainly when a
mapping is a REUSE rather than authored art. "Registered" and "authored"
are different facts and only the first is machine-visible.

> ### ⛔ gpt-image CANNOT do reaction poses. Three for three.
> ```
> Mordaine hit/dead   attempt 1              → rotated 90°, sprawled horizontally
> Mordaine hit/dead   attempt 2, explicit
>                     "upright, head at top,
>                      never lying flat"     → rotated, sprawled again
> goblin hit/dead     attempt 1              → rotated, sprawled
> ```
> The model reads "recoiling" / "collapsed" / "defeated" as *a horizontally
> oriented figure* and prompt constraints do not override it. Costume and
> palette come back correct every time, which makes the output look
> salvageable until you actually view it.
>
> **So budget reaction frames as an ARTIST ASK, not a gap-fill.** And when
> you do ask, ask for the right thing — for Mordaine, story canon is that
> she *dissolves* ("the way a thought dissolves"), so a per-frame
> alpha/scatter over existing frames is both more canonical and far more
> likely to succeed than a drawn collapse.
>
> Standing/idle-adjacent poses (portraits, overworld chibi, a boss simply
> present) generate fine. It is specifically *bodies in motion away from
> vertical* that fail.

## 6. Export + wire

```bash
uv run python tools/export_artist_monster.py \
  --aseprite "assets/sprites/drive_archive/.../<file>.aseprite" \
  --monster-id <id> --map idle=<Tag> --map attack=<Tag> \
  --map "hit=<Tag>:0-0" --map "dead=<Tag>:0-0" \
  --scale 1 --tier T2 --write-manifest
```
`--map anim=Tag` = whole tag; `--map anim='Tag:lo-hi'` = tag-relative
sub-range (the reuse case). `--dry-run` prints the plan.

### The wiring step is NOT optional

> **A monster PNG with no `monster_sheets` entry is INERT.**
> `HybridSpriteLoader.load_monster_sprite_frames()` returns `null` for an
> unregistered id and the caller silently falls back to procedural. File on
> disk, clean commit, never read. This happened to `chancellor_mordaine` —
> shipped 2026-07-17, inert until caught 2026-07-25.

## 7. Reimport, then verify

```bash
godot --headless --audio-driver Dummy --import --quit
./tools/run_tests.sh
```

> A test reading a sprite through `load()` sees the cached `.ctex`, not the
> PNG. A file `git hash-object` proves identical to main can still measure
> stale pixels. **Always `--import` before trusting an asset test.**

## 8. Ship

```bash
git checkout -b feature/<name>-artist-drop origin/main   # fresh off main, never rebase a folded branch
git add assets/... data/sprite_manifest.json
git push origin HEAD                                     # explicit refspec, never bare push
```

## Quick reference

```bash
rclone lsl "gdrive: cowir" | sort -k2,3 -r | head -30
aseprite -b --list-tags "f.aseprite" --data /tmp/p.json --format json-array --sheet /tmp/p.png
uv run python tools/export_artist_monster.py --aseprite "..." --monster-id <id> \
    --map idle=<Tag> --map attack=<Tag> --scale 1 --tier T2 --write-manifest
godot --headless --audio-driver Dummy --import --quit && ./tools/run_tests.sh
```
