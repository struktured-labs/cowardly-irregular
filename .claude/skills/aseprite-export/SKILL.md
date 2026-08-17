---
name: aseprite-export
description: Export tagged animations from artist aseprite files into game-ready PNG strips. Preserves pixel-art integrity via nearest-neighbor scaling — NO ML, NO palette mangling, NO edits to the source .aseprite.
user_invocable: false
---

# Aseprite → Game Sprite Export

Canonical pipeline for converting the artist's `.aseprite` source files in `assets/sprites/drive_archive/Game graphics - Characters/` into the 256×256 frame PNG strips consumed by the game's `sprite_manifest.json`.

## Rules

1. **Never edit the source `.aseprite` file.** Read-only. If animations look wrong, talk to the artist; don't "fix" it in code.
2. **No ML substitutes.** If the artist hasn't supplied an animation, leave the slot alone (keep the existing file, or skip). Do not fill gaps with AI-generated frames.
3. **No palette snap on artist output.** The artist's colors are ground truth — snapping to a "master palette" shifts them. Only 2× nearest-neighbor upscale is allowed.
4. **Tagged aseprite is the canonical source.** Pre-rendered PNGs (`.png` next to `.aseprite`) are only a fallback for files the artist hasn't tagged yet.
5. **Frames are always 128×128** in the artist's source. Game uses 256×256 — always scale 2× nearest-neighbor.

## Standardized aseprite structure (as of 2026-04-23)

Artist deliverables must have **animation tags** defined in the aseprite file:

| Tag | Used for | Frame count |
|-----|----------|-------------|
| `IDLE` | idle.png | 2+ |
| `Attack` | attack.png | 3+ |
| `Dash` | (future — combat-entrance move) | 1+ |

Canvas width = `frame_count × 128`, canvas height = `128`. Verify via `aseprite -b --list-tags <file>`.

## Export a single tag

```bash
aseprite -b --tag <TagName> --sheet out.png "path/to/file.aseprite"
```

Result is a horizontal strip: `(frame_count × 128) × 128`.

Then 2× nearest-neighbor upscale to reach the game's 256×256 frame size:

```python
from PIL import Image
im = Image.open("out.png").convert("RGBA")
up = im.resize((im.width * 2, im.height * 2), Image.NEAREST)
up.save(dest)
```

## Inspect before exporting

```bash
aseprite -b --list-tags  "file.aseprite"   # tag names, one per line
aseprite -b --list-layers "file.aseprite"  # all layers (for debugging)

# For frame ranges per tag, the JSON metadata output is more useful:
aseprite -b --list-tags "file.aseprite" \
  --data /dev/stdout --format json-array \
  --save-as /tmp/probe.png
```

`frameTags[].from/to` are 0-indexed inclusive ranges.

## The reusable embed tool

`tools/embed_artist_idle_attack.py` is the canonical embed script. It has two source-mode lists:

- `ASE_EXPORTS` — tagged-aseprite sources (preferred)
- `PNG_EMBEDS` — pre-rendered PNG fallback for characters not yet tagged

Move entries from `PNG_EMBEDS` into `ASE_EXPORTS` as the artist normalizes each character. Never delete a `PNG_EMBEDS` entry without confirming the aseprite equivalent is tagged and verified.

Run:
```bash
uv run python tools/embed_artist_idle_attack.py
```

Writes directly to `/home/struktured/projects/cowardly-irregular/assets/sprites/jobs/<job>/{idle,attack}.png`. Always commit to a feature branch in the game repo — never directly to main.

## When things look wrong

- **Character appears tiny in battle** → artist drew the figure in a large design canvas (e.g. 630×400 with a 91-tall figure). The 128×128 aseprite frames should already be tight-cropped. If not, ask the artist to re-tag with tight frames; don't fake it with crop/scale in code.
- **Animation is static despite multiple frames** → previous agent probably duped frame 0. Re-run this export.
- **Colors shifted** → somebody snapped the output to a "master palette". Artist output must NOT be palette-snapped. Re-export from aseprite.

## Not in scope (yet)

- Per-frame animation timing — the aseprite file has per-frame `duration` (e.g. 100/180/400ms for fighter attack wind-up/strike/recover), but `sprite_manifest.json` only stores one `fps` per sheet. Add per-animation timing metadata when this becomes blocking.
- `Dash` tag export — artist has it for fighter but the game doesn't use it yet. Wire up when BattleScene has a pre-attack-lunge animation slot.
