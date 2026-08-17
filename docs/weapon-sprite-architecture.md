# Weapon Sprite Layer Architecture

## Context

The artist has delivered fighter sprites as two separate sprite sheets: character body (no weapon) and weapon (sword/shield). This document specifies how to integrate this into the existing rendering and manifest systems without breaking existing procedural fallbacks.

---

## 1. Manifest Schema Extension

Add a top-level `weapon_sheets` key to `data/sprite_manifest.json`, parallel to the existing `sheets` and `monster_sheets` keys.

### Weapon sheet entry structure

```json
"weapon_sheets": {
  "iron_sword": {
    "path": "res://assets/sprites/weapons/iron_sword",
    "frame_width": 128,
    "frame_height": 128,
    "fps": 8,
    "weapon_type": "sword",
    "animations": ["idle", "slash", "thrust", "dash", "sheathed"],
    "anchor_offsets": {
      "idle":    [0, -10],
      "slash":   [8, -14],
      "thrust":  [12, -10],
      "dash":    [10, -12],
      "sheathed": [0, -8]
    },
    "z_front_during": ["slash", "thrust", "dash"]
  },
  "wood_staff": {
    "path": "res://assets/sprites/weapons/wood_staff",
    "frame_width": 128,
    "frame_height": 128,
    "fps": 8,
    "weapon_type": "staff",
    "animations": ["idle", "cast", "strike", "sheathed"],
    "anchor_offsets": {
      "idle":   [0, -20],
      "cast":   [4, -22],
      "strike": [6, -18],
      "sheathed": [0, -16]
    },
    "z_front_during": ["strike"]
  }
}
```

### Field definitions

| Field | Type | Purpose |
|---|---|---|
| `path` | String | Directory containing per-animation PNGs, same convention as character `sheets` |
| `frame_width/height` | int | Per-frame dimensions. Does not need to match the body sheet. |
| `fps` | int | Default playback speed. Overridden per-animation if needed. |
| `weapon_type` | String | Semantic tag: `sword`, `staff`, `dagger`, `axe`, `bow`, `unarmed`. Used by job abilities to query what is equipped. |
| `animations` | Array[String] | List of animation PNGs present on disk. Missing files are silently skipped. |
| `anchor_offsets` | Dict | Per-animation [x,y] offset in pixels relative to the body sprite's origin. Compensates for hand position differences across frames. These are fixed offsets, not per-frame; per-frame data would require an external atlas editor. Start with one offset per animation, refine per-frame later if needed. |
| `z_front_during` | Array[String] | Animations where the weapon renders in front of the body. All others render behind. |

### Linking weapons to characters

Weapons are already referenced by `Combatant.equipped_weapon` (a String ID) and passed into `HybridSpriteLoader.load_sprite_frames()`. The `weapon_id` parameter already exists in that function's signature — it is currently forwarded to `SnesPartySprites` for procedural rendering but otherwise unused for artist sheets. The new architecture reads `weapon_id` to look up an entry in `weapon_sheets`.

No changes to jobs.json or the Combatant schema are required. The equipment string `"iron_sword"` on the combatant becomes the lookup key into `weapon_sheets`.

---

## 2. Rendering Architecture

### Node structure per combatant

Each party member's current single `AnimatedSprite2D` becomes a small sub-tree:

```
Node2D  [CharacterRoot]
  AnimatedSprite2D  [BodySprite]       z_index = 0
  AnimatedSprite2D  [WeaponSprite]     z_index = 1 (front) or -1 (behind)
  Node2D            [TrailLayer]       z_index = 2  (slash trail effect)
```

`CharacterRoot` is what `party_sprite_nodes[i]` should store — or alternatively keep storing the `BodySprite` and track `weapon_sprite_nodes` as a parallel array. The parallel array is less intrusive to the existing codebase since `party_sprite_nodes` is read in many places.

Recommended: keep `party_sprite_nodes` pointing to `BodySprite`, add `party_weapon_sprite_nodes: Array[AnimatedSprite2D]` as a new parallel array following the exact same index convention. `BattleScene._create_battle_sprites()` creates both; all existing code that touches `party_sprite_nodes[i]` continues to work unchanged.

### Z-ordering

Godot's `z_index` on `AnimatedSprite2D` is relative to siblings. Both body and weapon are children of the same `Node2D` parent that sits inside `$BattleField/PartySprites`, so their z_index values are sibling-relative:

- Weapon behind body: `weapon_sprite.z_index = -1`
- Weapon in front of body: `weapon_sprite.z_index = 1`
- Trail layer always in front: `trail_node.z_index = 2`

The weapon z_index is toggled at the start of each animation based on the `z_front_during` list from the manifest.

### Scale and position

The weapon sprite is positioned as a child of the same parent as the body, at the same origin. The `anchor_offsets` value for the current animation is applied as a pixel offset before scaling. Scale the weapon by the same factor used for the body (`_sprite_scale`) so they remain matched regardless of artist sheet resolution.

If the weapon sheet is a different resolution from the body sheet (e.g., 128x128 weapon on a 256x256 body), compute a relative scale factor:

```
weapon_display_scale = _sprite_scale * (body_frame_height / weapon_frame_height)
```

This keeps the weapon visually proportional regardless of source resolution.

### Procedural fallback

If `weapon_id` is empty or has no entry in `weapon_sheets`, no weapon sprite node is created. The body renders alone exactly as today. Procedural SnesPartySprites continue to composite the weapon into the body sheet at generation time — that path is unchanged.

---

## 3. Animation Synchronization

### Body drives timing

The body animation is the authority. The weapon animation is driven to match:

- Both sprites call `play(animation_name)` with the same string at the same time.
- Both sprites are set to the same `speed_scale` when battle speed changes.
- `animation_finished` is only listened to on the body sprite; the weapon is a follower.

### Frame count mismatch

Body and weapon do not need the same frame count. The body plays its animation at its own fps; the weapon plays at its own fps. They share a start signal (the `play()` call) but run independently. This is acceptable because:

- Idle animations loop — drift is invisible.
- Attack/slash animations are short (2-4 frames each). Slight timing differences at this scale are undetectable.
- If tight sync is required for a specific animation (e.g., the exact frame where the blade connects), use `frame_changed` on the body sprite and call `weapon_sprite.set_frame()` directly for that animation only. Reserve this for boss-tier fighter attacks.

### Sync point convention

For animations where the hit frame matters (`slash`, `thrust`), define a `sync_frame` in the manifest entry (optional integer). `BattleAnimator` reads this and emits a signal at that body frame for damage application. The weapon sprite is not involved in damage timing — that is purely a battle logic concern.

---

## 4. Implications for AI Sprite Generation

### Body-only generation is strictly easier

The current pipeline asks AI to generate a full character including their weapon. Removing the weapon from the body sheet:

- Eliminates the most geometrically complex element (foreshortening, perspective matching across frames)
- Removes the hardest consistency problem (weapon stays the same across all animations)
- Shrinks the number of things that can go wrong per frame

All existing generation scripts (`tools/gen_*_sprites.py`) should be updated to explicitly specify "no weapon, empty right hand, weapon-free" in their prompts and negative prompts. The fighter body sheets in `assets/sprites/jobs/fighter/` should be regenerated weapon-free once the architecture is in place; existing sheets can serve as-is until then.

### Weapons as standalone assets

Weapons are small, geometrically simple, and view-direction-independent (they always appear from the same camera angle). This makes them candidates for:

- Hand-drawing directly at 128x128 (a few hours of work per weapon type)
- A much simpler AI generation task (object-only, clean background, consistent angle)
- Reuse across jobs: `iron_sword` equipped by a fighter and a guardian uses the same sheet

A small weapon library (8-10 weapons) covers the entire starter roster. Weapons are shared resources, not job-specific.

### Slash trail as a post-process layer

The trail/streak effect on attack animations is not part of the weapon sheet. It is a runtime-generated `Line2D` or `GPUParticles2D` node in `TrailLayer`, driven by the weapon sprite's position delta per frame. This approach:

- Requires zero artist input
- Scales with any weapon regardless of how it was produced
- Can be tuned per weapon type via `weapon_type` in the manifest

### Pipeline order

1. Generate or draw body sheet (weapon-free) → place in `assets/sprites/jobs/<job_id>/`
2. Generate or draw weapon sheet → place in `assets/sprites/weapons/<weapon_id>/`
3. Register both in `sprite_manifest.json`
4. Set `equipped_weapon` on the Combatant to the weapon ID
5. Engine composites at runtime; no offline compositing step needed

This replaces the current practice of baking the weapon into the body sheet at generation time, which was the source of consistency problems across animation frames.

---

## Open Questions

- **Per-frame anchor offsets**: The manifest specifies one offset per animation. If the artist's hand position shifts significantly across frames within a single animation, a per-frame offset array will be needed. Defer until the first real weapon sheet reveals whether this is a problem.
- **Shield/off-hand slot**: The same architecture extends naturally — a `shield_id` lookup in `weapon_sheets` with its own sprite node. Not needed until a guardian or paladin job is implemented.
- **Weapon visibility during non-combat animations**: `victory`, `dead`, `item` animations on the body may look odd with a floating weapon. For `dead`, hide the weapon sprite entirely. For `victory` and `item`, leave it visible unless the artist delivers specific guidance.
