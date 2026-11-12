# Ability sequence authoring guide

How to give an ability a multi-phase animation. Fire, Fira and Firaga
(`fire_battle`, `fira_battle`, `glory_firaga` in `data/vfx_sequences.json`) are
the reference: read them beside this page.

struktured's brief (2026-11-07 and 2026-11-11): every ability a player sees
should be "over the top", in its own visual language, bigger at each tier, and
still readable at every battle speed.

## 1. What a sequence is

A sequence is data. It lives in `data/vfx_sequences.json` under `sequences`,
and an ability names it in `data/abilities.json`:

| The ability is | It names the sequence with | Who plays it |
|---|---|---|
| a cast (magic, heal, buff, song) | `"vfx": {"sequence": "<id>"}` | `BattleScene._play_ability_sequence` |
| a party tier-3 showcase | `"vfx": {"glory": "<id>"}` | `BattleScene._play_signature` (card, then the sequence) |
| a boss's signature | `fx_signature` on the monster row | `BattleScene._play_signature` |
| a physical move (cowir-sprites' tip, .792) | `"vfx": {"melee": "<id>"}` (plus `melee_each`, `melee_crit`) | drawn around `_animate_melee_attack`'s own lunge |

```json
"fire_battle": {
  "label": "one line: what the player sees",
  "start": 0.15,
  "impact": 0.88,
  "phases": [
    {"kind": "gather", "origin": "hand", "at": 0.0, "dur": 0.60, "count": 18, "palette": "flame"},
    {"kind": "bolt", "at": 0.60, "dur": 0.28, "palette": "flame", "sfx": "beat_fire_burst"},
    {"kind": "eruption", "at": 0.88, "element": "fire", "power": 1.0, "boost": 1.6, "sfx": "beat_fire_impact"},
    {"kind": "fall", "at": 1.00, "dur": 0.60, "count": 18, "palette": "ember"}
  ]
}
```

All times are **battle seconds**. They scale with battle speed like every other
battle animation, so nothing here is a wall-clock number.

- `start` is the delay from the action's start to the sequence's first phase.
  **The wind-up starts WITH the cast pose** (`start` about 0.15), and the
  launch lands on the pose's release frame (the Mage's cast releases on frame
  6, 0.75 s after the action). A sequence that waits for the release before
  drawing anything leaves 2 real seconds of nothing at the default speed. For
  a melee overlay `start` is the lunge's contact, passed in by the engine.
- A showcase with a title card may name a sequence-level `windup` phase (a
  `gather` at the caster): it plays under the card, for the card's length.
- The ability's cast sound plays at the **action's** start, `start` seconds
  before your first phase. A phase at `at: 0.0` is not doubled by it.
- `impact` is when the hit lands, measured from `start`. See rule 1 below.

## 2. The shape of a sequence

Author five beats. A small ability may merge two; a showcase may repeat one.

| Beat | What it is for | Typical kinds |
|---|---|---|
| wind-up | the caster charges; the player reads who is acting | `gather` at the caster |
| launch | the effect leaves the caster | `bolt`, `streak`, `arc` |
| **impact** | the hit. Damage, the number and the death land here | `eruption`, `flash`, `ring`, `shake` |
| bloom | the payoff a higher tier adds | `pillar`, a second `eruption`, a wide `ring` |
| aftermath | what lingers, overlapping the next action | `fall`, `rise`, `puff` |

**Tiers add phases, they do not only scale.** Fire is four beats, Fira adds a
pillar, Firaga adds a second detonation with a screen flare. Use `boost` and
counts for size, and a new phase for each tier.

## 3. Phase kinds

Every phase takes: `kind`, `at`, `dur`, `origin`, `offset` `[x, y]`, `sfx`,
`min_tier` (1-3), `palette` and `palette_t3` (the palette at intensity tier 3).

`origin` is one of three points, all measured on the battler's FIGURE, not on
its frame (a hero can stand 95 px off the centre of their frame):

| `origin` | Point | Use it for |
|---|---|---|
| `"target"` (default) | the target's body | the hit, anything that lands |
| `"caster"` | the caster's body | an aura, a swell, life returning |
| `"hand"` | the caster's leading edge, a little above the middle | a charge, a mouth, where a `bolt` leaves from |

Do not correct a position with a per-job `offset`: if an effect lands beside a
figure, the anchor is wrong, and that is fixed once in `BattleScene._figure_anchor`.

| Kind | Draws | Own fields |
|---|---|---|
| `gather` | motes drawn in to a point: a charge | `count` |
| `bolt` | an arc from caster to target with a trail | `arc_height`, `size`, `trail_palette`, `trail_spacing`, `reverse` |
| `eruption` | the element's ORIGINAL burst | `element` (fire, ice, lightning, holy, dark, heal), `power`, `boost` |
| `pillar` | a rising column | `height` |
| `fall` | motes drifting down, with a ground glow | `count`, `ground_glow` |
| `rise` | motes drifting up | `count` |
| `ring` | an expanding ring | `scale` |
| `flash` | a soft flash at a point | `size` |
| `shake` | camera shake | `intensity` |
| `slash` | cut lines | see `strike_impact` |
| `arc` | a swept blade crescent | `radius`, `from`, `to`, `width`, `life` |
| `streak` | a dash line between two points | `a`, `b`, `a_offset`, `b_offset`, `life` |
| `puff` | soft smoke that covers what is behind it | `count`, `spread`, `drift`, `size` |
| `plates` | flat panes that assemble and hold: a ward | `shape` (wall or dome), `count` (a dome's plates; a wall is always 7), `radius`, `hold` |
| `ribbon` | a waving band between two points: a song | `a`, `b`, `a_offset`, `b_offset`, `wave`, `width`, `lines`, `gap` (px between staff lines), `jagged`, `life` |
| `glyphs` | drifting symbols (notes, Zs) | `glyph`, `count`, `size`, `spread`, `drift`, `to_target` |
| `emit`, `spin_fling` | the recursive fractal (Edit Formula's look) | see `edit_formula_battle` |
| `lunge`, `knockback`, `hitstop`, `impact_frame` | move or freeze the SPRITES (first target only) | see `strike_impact` |
| `cue` | nothing: a sound-only beat | `sfx` |

A sequence may also set `travel` (seconds per 100 px): a farther target is
reached later, so a song washes down the party line instead of landing on all
five at once. The damage hold follows it.

`eruption`, `pillar`, `gather`, `fall` and `rise` are drawn by
`EffectSystem.run_element_phase`; the rest by `FractalFX`. To add a kind, add
its arm in `FractalFX._run` and its length in `FractalFX.phase_duration`, with
the common fields above. One vocabulary: do not fork a kind, add a field.

**Palettes** are rows in `FractalFX.PALETTES`: fire, flame, ember, spark,
steel, frost, void, rot, verdict, glitch, holy, nature, mana, smoke, taunt,
hymn, ward.
Add a row there. Never put a colour in a phase.

## 4. Rules the engine holds for you

1. **Damage lands at the impact.** The number, the HP drop, the death and
   victory all wait for it (#763). The impact is the sequence's `impact` if
   set, else the end of its `bolt`, else its first phase at the target. Put a
   phase AT the impact time, so there is something to see when the hit lands.
2. **Turbo and the grind console play only the impact.** The phases at the
   impact time run at once and nothing else does, so a sequence adds no time
   to a grind. This is why rule 1's "a phase at the impact" matters.
3. **Phase sounds are muted by the battle's own gate** (turbo, the console).
   A missing cue key is silent, not an error, so you can name a cue before
   cowir-sfx authors it.
4. **Scale comes from the caster.** `power` (the ability's tier: 1.0, 1.3 for
   -ra, 1.8 for -aga) and the caster's intensity tier (1-3, from level and
   stat) reach every phase. Author the tier-1 look, then add `min_tier` phases
   and `palette_t3` for a stronger caster.

## 5. Timing budgets

The battle holds until 0.35 s after the impact, then the next action starts while your
aftermath finishes. Keep the impact inside these:

Measured from the action's start (`start` + `impact`):

| Tier | Phases | Impact by | Example |
|---|---|---|---|
| 1 | 3-4 | 1.35 s | Fire 1.03 |
| 2 | 4-5 | 1.40 s | Fira 1.03 |
| 3 / showcase | 5-6+ | 1.45 s after its card | Firaga 1.03, second blast at 1.35 |

A free or 0-MP move (Pray, Channel, Riff) stays small: two or three phases,
impact within 0.40 s of its release.

## 6. Outcomes read apart

Do not draw a status landing inside the ability's own sequence: the status
may be resisted. The Fighter/Rogue tip (cowir-sprites, .792) adds the shared
mechanism: a landed status plays its own beat at the target
(`BattleScene.LANDED_BEATS`: stun, blind, taunt, and rows other lanes add), and
a resist or a failed steal plays the grey `fizzle`.

## 7. Monsters: families, not one-offs

208 abilities are monster-only. Most are bites, claws and breaths, so they
share sequences by FAMILY rather than getting one each. A monster has no cast
pose to wait for: a family starts at 0.1 and lands within 0.8 s.

| Family | Sequence | Covers | Shape |
|---|---|---|---|
| bite, claw, slam, spit | `family_bite` … (cowir-sprites) | physical moves, and a plain attack through the monster row's `hit_spark` | an overlay AROUND the lunge, sized to the monster |
| breath | `family_breath_ice` / `_lightning` / `_dark` | an all-party elemental | `gather` at the mouth, a flat `bolt` to each foe, the element's `eruption` |
| cloud | `family_cloud` | poison, spores, acid | a lobbed `bolt`, a `puff` that billows over each foe |
| dust | `family_dust` | sand, roots | grit `rise`s at the feet, is thrown, `fall`s back |
| drain | `family_drain` | life and mana drains | a dark `bolt`, the burst, then `bolt` with `reverse` and a `rise` on the caster |
| screech | `family_screech` | screech, rattle | three `ring`s from the mouth, a small `shake` |
| buff-self | `family_buff_self` | enrage, howl, harden | `gather` and one pulse; the stat beat that follows is the shared landing |
| heal-self | `family_heal_self` (cowir-cutscenes) | repair, reconstruct | sparks drawn in, a pulse, light rising |

How a row names its family:

- A **cast** (magic, support, healing) names the sequence directly:
  `"vfx": {"sequence": "family_breath_ice"}`. A single-target cast of an
  element the Mage has plays the Mage's own tier-1 spell (`blizzard_battle`).
- A **physical** move names `"vfx": {"family": "bite"}` and is drawn around its
  lunge. The top-level `"family"` key is the SPELL LINE the shops sell by; do
  not reuse it.
- `test_a_w1_monster_casts_in_its_family` holds the census: every cast a W1
  monster has plays a sequence or is DECLARED there with the reason.

A buff, a debuff or a status LANDING is not yours to draw: one shared beat per
kind plays at the target (`LANDED_BEATS`, `stat_up_<stat>`, `wore_off`). Author
the delivery and stop at the impact.

## 8. Checklist before READY

- The ability names its sequence, and a test pins that it resolves.
- A phase sits at the impact time, and the impact is inside the tier's budget.
- A higher tier has more phases than the tier below it, and is bigger.
- Palettes are `FractalFX.PALETTES` rows.
- A mutation that removes the tier's extra phase reds your tier arm.
- **A clip with sound, before and after**, for struktured:

```bash
tools/cast_clip.sh <label> --ability=<id> [--job=mage] [--foes=3] [--level=16]
```

It records the ability cast in a real battle through the game's own execution
path, with the game's audio mix, to `tmp/cast_clip/<label>.mp4`. Run the same
command on the previous tag for the "before".
