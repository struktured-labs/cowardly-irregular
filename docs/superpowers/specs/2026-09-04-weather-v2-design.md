# Weather v2 — Design

**Origin:** Philly demo-night attendee suggested weather effects; struktured agreed (2026-09-03).
Direction chosen via AskUserQuestion: extend into villages + reach battle + gameplay-affecting,
with weather **scriptable from autobattle** (the automation-pillar variant).

## What exists

`src/exploration/WeatherSystem.gd` already renders per-world weather on the five overworlds
(W1 cycling rain, fog-breathe, W5 glitch flashes) but rolls its state privately per scene.
Villages, battle, and saves cannot see it. W1 rain is off up to 80s at a stretch, so short
sessions read as "no weather" — the demo feedback in a nutshell.

## Architecture

**Weather becomes GameState, mirroring the day/night clock** (same lifecycle: advances with
playtime, persists in saves, resets on New Game, emits a signal on change).

### 1. GameState weather core
- `signal weather_changed(condition: String)`
- `var weather_condition: String` + `var weather_timer: float` (seconds remaining)
- `WEATHER_VOCAB: Dictionary` keyed by world number 1-6, each entry a weighted list of
  `{id, weight, min_s, max_s}`:
  - W1 medieval: clear 55 / rain 30 / storm 15
  - W2 suburban: clear 70 / drizzle 30
  - W3 steampunk: clear 40 / fog 60
  - W4 industrial: clear 30 / smog 70
  - W5 futuristic: clear 50 / glitchstorm 50
  - W6 abstract: clear 100 (weatherless BY DESIGN, like Vertex's single room)
- `_advance_weather(delta)` runs in `_process` beside `_advance_day_phase` (already gated on
  `playtime_paused`). On expiry, weighted re-roll from the current world's vocabulary.
  A world change is detected inside the advance (`_weather_world != current_world`) and
  forces an immediate re-roll — no dependency on hunting every `current_world` writer.
- `get_weather() -> String`, `set_weather(condition, duration)` (debug/quests/Scriptweaver later).
- Save: `weather_condition`/`weather_timer` in save data; absent keys (old saves) fall back to
  a fresh roll. New Game reset alongside `current_world = 1`.

### 2. Renderer (WeatherSystem, demoted to view)
`WeatherSystem` stops rolling dice: every `process()` it polls `GameState.get_weather()` and
renders the matching effect. Condition → effect map:
- `rain`/`drizzle`: existing rain emitter (drizzle = fewer, slower particles)
- `storm`: heavier rain + darker overlay + occasional lightning flash
  (white flash, gated on `reduce_flashes` like every flash in the game)
- `fog`/`smog`: existing overlay-breathe with per-world tint
- `glitchstorm`: existing glitch flashes
- `clear`: everything off, base tint only
Ambient audio toggles on transitions (existing `weather_*` SoundManager keys).

### 3. Villages inherit weather
`BaseVillage` instantiates the same `WeatherSystem` (outdoor scenes only — interiors skip it),
composing with the existing `VillageLighting` CanvasModulate. Rain over Harmonia at dusk.

### 4. Battle reflects and obeys
- **Presentation:** BattleScene gets a weather layer (rain/fog overlay above the Mode 7 floor,
  storm lightning gated on `_flashes_suppressed()`), plus a small always-visible weather tag
  so the modifier is never invisible.
- **Mechanics** (twin of the existing terrain-modifier seam in BattleManager):
  - `get_weather_damage_modifier(element)` applied beside `terrain_mod`:
    storm → lightning ×1.25 · rain/drizzle → fire ×0.75, water & ice ×1.15
  - fog/smog → `base_miss_rate += 0.15` in the physical-attack miss check (both sides)
  - glitchstorm: **visual only in v1** (W5 content is inert by design; noted for later)
- **Encounters:** fog/smog multiply per-step encounter chance ×1.5 in EncounterSystem
  (no ambush mechanic exists; not inventing one in v1).

### 5. Autobattle sees it (the point)
- `CONDITION_TYPES["weather"] = "Weather Is"`; condition shape `{type:"weather", weather:"storm"}`
  — parameterized like `has_status`, value validated against the flat vocabulary in
  `validate_rule` (an LLM-composed bad value fails decode, per the is_night grammar ruling).
- Evaluation: `GameState.get_weather() == condition.weather`. Headless parity is free —
  HeadlessBattleResolver routes through `execute_grid_autobattle`.
- Grid editor: type picker entry, default seed `rain` on type change, shoulder-button cycling
  through the vocabulary in `_adjust_condition_value`, display `"Weather: Storm"`.
- Share codes: `COWIR1:` decode validates via `validate_rule` — no grammar change needed.

## Not building (recorded, deliberate)
Forecasting NPCs · weather-changing abilities (future Time Mage/Scriptweaver flavor) ·
W6 weather · glitchstorm mechanics · per-village microclimates.

## Testing
- `test_weather_state_regression` — vocabulary integrity, weighted roll, world-change re-roll,
  save roundtrip, New Game reset, old-save fallback.
- `test_weather_battle_modifiers_regression` — modifier table values, fog miss contribution,
  encounter multiplier, and the seam actually consulted (mutation-guarded like terrain).
- `test_weather_autobattle_condition_regression` — catalog entry, evaluation truth table,
  bad-value rejection at validate/decode, editor seed/cycle vocabulary sync.
- Renderer smoke — WeatherSystem renders every condition without error; village layer present.
