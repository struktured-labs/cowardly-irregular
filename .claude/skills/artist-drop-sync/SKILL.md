---
name: artist-drop-sync
description: "Pull new artist sprite drops from Google Drive and integrate them into the game. INVOKE THE MOMENT anyone says a sprite/animation 'dropped', 'just landed', 'is in drive', 'suck it in', 'pull it in', 'ingest it', or names a job/monster plus a new pose — the art is ALREADY on Drive under the space-prefixed \" cowir\" remote and nothing checks automatically, so searching the repo first finds nothing and looks like there is no drop. Covers rclone paths, the leading-space gotcha, aseprite tag conventions and tag-shift, the 128px magic number, facing, manifest wiring, the artist sprite ledger, and the artist-canon rules."
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
> `rclone lsl "gdrive: cowir"`. Re-verified 2026-09-19: the bare form still
> errors, the spaced form still works.
>
> 🛑 **NOTHING CHECKS FOR DROPS AUTOMATICALLY. DO NOT WAIT TO BE TOLD.**
> Corrected 2026-09-19: `tools/check_for_new_artist_sprites.sh` **does** have
> the spaced path (line 15) — that half of this warning was stale. The reason
> drops go unnoticed is that **its cron entry is COMMENTED OUT** (since
> 2026-06-14, *"embed script no longer covers enemies, manual ingest for now"*)
> and points at `cowardly-irregular-sprite-gen`, a different checkout.
> So a drop can sit for days with no signal at all — the 2026-09-18 Bard
> Celebration drop sat ~21 hours until struktured mentioned it in chat.
> **When anyone says a sprite "dropped", assume it is already on Drive and
> LOOK, rather than searching the repo and reporting nothing found.**

```bash
rclone lsl "gdrive: cowir" | sort -k2,3 -r | head -30   # newest first
```

`rclone lsl` is **already recursive**; `--recursive`/`-R` are invalid and error.

Trees: `Game graphics - Characters` (party jobs, `enemies/`, `Samples/`)
and `Game graphics - NPCs` (20 overworld archetypes).

Pull only the new subtree — **into gitignored `tmp/`, never into `assets/`**:
```bash
rclone copy "gdrive: cowir/assets/sprites/Game graphics - Characters/<NAME>" \
            "tmp/artist_drops/<NAME>" -P
```
> ⛔ **CORRECTED 2026-09-19 — this used to say `assets/sprites/drive_archive/`.
> That path does NOT exist and is NOT gitignored**, so the pull creates an
> untracked tree inside `assets/` and §8's `git add assets/...` then commits the
> artist's `.aseprite` SOURCE into the repo. `tmp/` is gitignored
> (`.gitignore:64`); the Drive copy is canonical and the local copy is scratch.

## 2. Probe tags — never assume names

Tag names are **not standardized**:

| File | Tags |
|---|---|
| fighter | `IDLE`, `Attack`, `Dash` |
| Mordaine (2026-07-23) | `Idle`, `summon 1` — case differs, boss-specific verb |
| bard (2026-09-18) | `Idle`, `Celebration`, `Dead`, `Weak`, `ATK` |

**`Celebration` is the artist's word for the VICTORY pose.** Their label, the
engine's slot name, and the manifest keeps both — the same way `Dead`/`Weak`
were kept when they split the downed state. Map it, do not rename their tag.

🛑 **A NEW TAG SHIFTS EVERY LATER TAG'S FRAME RANGE.** Inserting `Celebration`
at frame 4 moved `Dead` 4-8 → 15-20, `Weak` 9-13 → 21-25, `ATK` 14-22 → 26-34.
Any hardcoded range silently slices the wrong animation — this is why
`ingest_tagged_aseprite_drop.py` reads ranges from the file, and why it
superseded a predecessor that hardcoded them. **Never carry ranges between
drops.**

📌 **RE-EXPORT EVERYTHING, THEN READ `git status` TO SEE WHAT THE DROP ACTUALLY
CHANGED.** The 09-18 bard drop re-exported idle/weak/cast/attack byte-identical;
only `victory` (new) and `dead` (5→6 frames) moved. The diff is the honest
answer to "what did the artist change", and it costs nothing.

`--list-tags` alone prints only names. For **frame ranges** you must add
`--data`:
```bash
aseprite -b --list-tags "f.aseprite" --data probe.json --format json-array --sheet probe.png
```
Read `meta.frameTags[].from/to` (0-indexed, inclusive).

> **Gotcha — RE-MEASURED 2026-09-19 AND IT NO LONGER REPRODUCES.** This said
> `--sheet-pack` silently DROPS `frameTags`. Tested verbatim on the 09-18 bard
> file with `Aseprite 1.x-dev`: **5 frameTags returned WITH `--sheet-pack`.** Either the
> build changed or the original was a different flag combination.
>
> ✅ **The gotcha that DOES still hold is `--list-tags` itself:** omit it and the
> export succeeds, writes a valid JSON, and reports **zero** tags — a silent
> empty rather than an error. `ingest_tagged_aseprite_drop.read_tags()` raises
> on zero tags for exactly this reason. **Always pass `--list-tags`, and assert
> you got a non-empty list before using any range.**

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

> ⚠️ **`animations` HAS TWO SHAPES IN THIS MANIFEST AND BOTH ARE LIVE** —
> measured 2026-09-19: **dict in 173 entries, list in 18**. Monsters use the
> dict-of-ranges above; party job sheets (`sheets/bard`) use a flat LIST of
> animation names, with frame counts implied by the exported strip width.
> **Code that assumes either shape crashes on the other** — check
> `isinstance(..., dict)` before `.get()`.

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

### 6a. PARTY JOBS (tag-driven) — `ingest_tagged_aseprite_drop.py`

This is the path for bard/mage/fighter/rogue/cleric. It reads ranges from the
file, so a tag shift cannot mis-slice it, and it backs up what it replaces to
`<anim>.pre_artist.png` (a TRACKED convention — commit those too).

```bash
export DROP_DIR="$PWD/tmp/artist_drops/<NAME>"       # dir holding the .aseprite
uv run python tools/ingest_tagged_aseprite_drop.py --target bard --dry-run
uv run python tools/ingest_tagged_aseprite_drop.py --target bard
```
A NEW artist tag needs one line in that file's `map` for the target — e.g.
`"victory": ("Celebration", 0, 0)`. `(tag, 0, 0)` = the whole tag;
`(tag, lo, hi)` = a tag-relative sub-range. **Dry-run first and read the
printed ranges against §2's probe.**

### 6b. MONSTERS — `export_artist_monster.py`

```bash
uv run python tools/export_artist_monster.py \
  --aseprite "tmp/artist_drops/<NAME>/<file>.aseprite" \
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
XDG_DATA_HOME=$PWD/tmp/xdg godot --headless --audio-driver Dummy --import --quit
XDG_DATA_HOME=$PWD/tmp/xdg ./tools/run_tests.sh <name> [<name>...]
```
> 🛑 **`XDG_DATA_HOME` IS THE CALLER'S JOB.** `run_tests.sh` *honours* it
> (`:45`) but does not SET it — unsandboxed, `user://` resolves by APPLICATION
> NAME, so every worktree shares one real path and a run can write over
> struktured's live save data.
>
> ✅ `run_tests.sh` now bounds its own godot (`:182`, plain `timeout`, no
> `--kill-after` — this binary cannot deliver SIGKILL). Passing test NAMES runs
> them in ONE godot process; the bare form runs everything.

> A test reading a sprite through `load()` sees the cached `.ctex`, not the
> PNG. A file `git hash-object` proves identical to main can still measure
> stale pixels. **Always `--import` before trusting an asset test.**

## 7b. 🛑 THE ARTIST SPRITE LEDGER WILL BLOCK YOU — THAT IS ITS JOB

`test_artist_sprite_ledger_regression` pins the bytes of every artist sprite.
Any ingest changes those bytes, so the guard **fails by design** and names each
file:

```
assets/sprites/jobs/bard/victory.png: content changed without a ledger update
```

It is not a regression and it is not the drop being wrong. If the change is
deliberate — an ingest always is — regenerate the ledger and commit the diff:

```bash
uv run python tools/update_artist_ledger.py     # writes data/artist_sprite_ledger.json
```

⛔ **Do NOT skip, exempt, or weaken the guard to get green.** It exists so that a
fold which silently regresses artist pixels is loud, and today it correctly
caught both files a real ingest touched. Re-run the corpus after the ledger
update; it should go green with no other change.

## 8. Ship

```bash
git checkout -b lane/<what-changed> origin/main   # fresh off main, never rebase a folded branch
git add assets/sprites/jobs/<job>/ data/sprite_manifest.json data/artist_sprite_ledger.json
#  ^ name the DIRS you changed. A bare `git add assets/...` after a mis-targeted
#    pull stages the artist's .aseprite source (see §1).
git push origin HEAD                                     # explicit refspec, never bare push
```

## Quick reference

```bash
rclone lsl "gdrive: cowir" | sort -k2,3 -r | head -30
aseprite -b --list-tags "f.aseprite" --data tmp/p.json --format json-array --sheet tmp/p.png
uv run python tools/export_artist_monster.py --aseprite "..." --monster-id <id> \
    --map idle=<Tag> --map attack=<Tag> --scale 1 --tier T2 --write-manifest
XDG_DATA_HOME=$PWD/tmp/xdg godot --headless --audio-driver Dummy --import --quit \
  && XDG_DATA_HOME=$PWD/tmp/xdg ./tools/run_tests.sh <names>
```
