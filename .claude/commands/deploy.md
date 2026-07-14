# /deploy — Export and push to itch.io

**IMPORTANT: Always ask the user for confirmation before pushing to itch.io.**

## Canonical path — use the gated script

```
tools/deploy_web.sh <tag>
```

The script IS the deploy: unit suite → web export → **pck size gate
(hard-fails ≥ 200 MB — itch.io refuses HTML5 embeds past that; the
2026-07-03 226 MB pck broke the live page)** → render smoke → butler
push → status verify. Do NOT hand-compose export+push chains; bypassing
the script is how the size regression shipped unnoticed.

Size strategy lives in `export_presets.cfg` `exclude_filter` (sprite
intermediates + W4-W6 music, which falls back to procedural on web).
Never fix size by lossy in-place asset mangling.

## Steps

1. **Get version tag** from the latest git tag, or ask user for one.
2. **Confirm with user** before pushing. Show them the tag and what's changed since last deploy.
3. Run `tools/deploy_web.sh <tag>` and report the gate results.
4. Report success with the itch.io URL: https://struktured.itch.io/cowardly-irregular

Note: `:web` is the active channel (served by itch.io). `:html5` is legacy/unused — do not push there.

## Input

Optional version tag as argument (e.g., `/deploy v0.21.0`). If omitted, derive from latest git tag or ask.
