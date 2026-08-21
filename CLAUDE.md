# Cowardly Irregular

A meta-aware JRPG where automation isn't cheating — it's enlightenment.

## Project Status: Advanced Prototype (v3.33-alpha track, continuous deploys through 2026-07-11)

Playable end-to-end through World 1:

- **Battle system**: CTB + AP, 5-party, Advance/Defer mechanics (queue unwind surfaced in the hint bar), group attacks, formation specials, per-job Free Move command (Channel/Pray/Riff/Strike), Mode 7 perspective floor, execution stall watchdog (wall-clock, armed start↔end_battle)
- **Spotlight Duels**: every W1 starter unlock is a solo 1v1 miniboss showcasing that PC's kit (cutscene `battle` step → GameLoop.start_solo_battle → retry-on-defeat with full restore). Custom win conditions: survive_turns (Cleric), status_threshold swayed (Bard), hp_zero (rest). Dual-source win_condition (step overrides monsters.json). Duelist plays their OWN duel manually (both the routing gate and the command-menu gate carry a solo-duel override); clutch floor: a full-HP duelist can never die to one action (struktured ruling 2026-07-11); menu watchdog self-heals + terminal autobattle fallback so battles cannot wedge.
- **Autobattle**: per-character rule editor with full keyboard/gamepad nav + Defensive/Balanced/Aggressive preset catalog (data/autobattle_rule_templates.json, level-1-safe) + LLM Rule Composer
- **Side quests (QuestSystem v1)**: data/quests/*.json, GameState.quests dict + flag mirrors, talk/custom/fetch objectives (fetch supports `consume: true`), giver dialogue with accept/decline, "!"/"?" NPC markers (markerless opt-out), reward announcements, Quest Log section + HUD tracker. 11 W1 quests of 33 total; Milo's thesis quest wired to battle telemetry.
- **Worlds**: 6 worlds wired (medieval / suburban / steampunk / industrial / futuristic / abstract); W1 fully playable incl. Castle Harmonia placed on the overworld (post-Rat-King) and the W2 portal (post-Mordaine). W2-W6 use visible roaming monsters only.
- **Bosses**: Cave Rat King, 4 elemental dragons (Pyrroth/Glacius/Voltharion/Umbraxis), Chancellor Mordaine (W1 final)
- **Progression (item 18)**: lean starting kits — Mage fire/blizzard/thunder, Cleric cure/protect; the rest level-gated via `abilities_at_level`, purchasable early at Harmonia's magic shops (full W1 tier-2 shelves; `purchased_abilities` marker protects bought spells). Settings → "Dev: Full Job Kits" grants/strips for testing. Pre-pare saves grandfathered on load.
- **LLM integration**:
  - Opt-in dynamic NPC dialogue (Theron / Milo / Boris in Harmonia) + jailbreakable boss dialogue. Interact routing: quest > dynamic > scripted.
  - **Boss Strategic Intent** for all 5 W1 bosses (Settings → LLM Boss Strategy). LLM picks intent/posture per phase, deterministic ladder still owns ability choice.
  - **Party Combat Dialogue** for all 5 starter jobs, rendered as speech bubbles anchored to the speaker (suppressed only at ≥4x speed); `voice_<job>_<trigger>` audio-handle convention ready for the voice pack. Scripted `trigger_voices` fallback per job when LLM off.
  - Rebalance daemon (opt-in), LLM Rule Composer, Learning Monsters. Ollama / OpenAI-compat backends via HTTPBackend; BYOK desktop-only (settings.json) pending field-input UI.
- **Data**: 14 jobs, 288 abilities, 98 monsters (artist art for slime/bat/goblin + 5 duel minibosses T2), 172 items, 34 encounter pools, 193 cutscenes (44 party/event chats, guarded: every registry chat needs its JSON + a live emitter), 153 music tracks, 259 SFX
- **Tests**: ~7390 passing / 0 failing in GUT. **Full suite takes ~5-10 MINUTES headless (measured 268-689s across 14 runs / 6 lanes, 2026-07-30 — one run cleared the 600s ceiling by 89s), NOT the "~40s" this line claimed for months — BACKGROUND the gate.** A foreground run can cross a 10-minute harness ceiling, and the SIGTERM skips the export restore; that stale number is the first link in the chain that produced four orphaned snapshots and three "the export dir is clean" reports that each undid the last. The error was invisible because it is intermittent: on a quiet box the suite finishes ~380s and confirms the doc to you, at load it reaches 689s and dies. The 268s low end is as much of the cause as the 689s high end: a lane on a quiet box measures 4.5 minutes, stays inside every ceiling, and concludes the doc is roughly right. Gate on the [Failed] count. Campaign-scale integration: the story spine walks New Game → world6_ending under test (incl. a mid-campaign save/load), battle mini-fuzz every run, live/headless group-attack parity-by-construction.
- **Sharing (pillar complete)**: autobattle scripts AND autogrind rule sets travel as `COWIR1:` clipboard codes (Shift+E copy / Shift+I paste in grid editor + autogrind console), grammar-validated at decode; file-based E/I flows unchanged
- **Meta jobs (all five REAL)**: Scriptweaver turns a bounded game-constant dial (⚠️ "+ reveals execution order" was listed here as SHIPPED and is NOT — `formula_sight`'s `show_formulas` key and `autobattle_verbs`' `autobattle_advanced` key each occur exactly ONCE in `src/`, in their own declaration inside PassiveSystem's hardcoded fallback copy of passives.json, and the ids appear only in JobSystem's `passive_abilities` roster. Both are equippable today and do nothing. Confirmed by 4 independent methods 2026-07-30 after a count that moved 13→0→1→3→2 as five lanes each hit a different consumption shape); Necromancer permakill EXTERMINATES species from all three spawn paths (encounter pools, autogrind roster, roaming — save-persisted, New-Game-reset, live roamers dissolve); Time Mage full (quicksave/restore/temporal shield/undo_death); Skiptrotter Bypass Puzzle concedes the chicken roundup; Bossbinder controlled/mind-swapped enemies fight their own side
- **Corruption (fully wired)**: visual_glitch, stat_drain (1%/round erosion), encounter_surge, bp_instability (player AP-gain jitter 0/+1/+2), ability_corruption (10% player-cast misfire within the learned kit) — every roster entry has a live consumer, ratcheted
- **Reference pages**: Formations (live party-qualification checks) + Records (nine live-read stats with editorial quips) in the overworld menu; both in the deploy render smoke
- **Interiors**: every W1 dragon village has 2+ interiors (test-enforced), W2-W5 expansion villages have 2 each, Vertex stays single-room BY DESIGN (pinned) — most rooms read real game state (crystals, playtime, battles_won, injuries, saves, inventory, bestiary)
- **Village elevation (CrossCode pass, 2026-08-21)**: villages carry an optional `height_data` digit grid beside `map_data`; cliff faces/edge colliders are DERIVED (`HeightGrid`), `^`/`/` are the only tier connectors and slow the walk to 0.6 through `BaseVillage.get_terrain_speed_at`; `_is_cell_walkable` stays the authority, `_can_step` carries the height rule; Y-sorted `VillageProp`s with footprints; per-scene `VillageLighting` (CanvasModulate + lamps) replaces the overlay tint for villages (GameLoop asks `has_scene_lighting()`). Harmonia = 3 tiers (castle approach / town / market, 8 stair cells). `tools/village_screenshot.sh <village>` renders dawn/noon/dusk via xvfb. Artist seam: `data/sprite_manifest.json` → `tile_sheets.<world>` (`TileSheetManifest`; regions in tile units; anything unnamed stays procedural; `test_tile_sheet_manifest_regression` validates names/bounds/paths; brief for the sprite lane in `docs/art/tile-sheet-brief-medieval.md`). Spec: `docs/superpowers/specs/2026-08-21-crosscode-environment-design.md`; phase 4 (W2-W6 generators + dungeon lights) pending.
- **Save**: Full JSON save with typed-array roundtrip protection, quests/crystals reset on New Game AND on old-save load (leak fixes 2026-07-02), MRU/pin ability persistence, permanent injuries, corruption effects (menu readout), story-flag gates. Real-save hydration smoke runs against local saves.
- **Version**: `Version.SEMVER` is the single source; bump at every deploy (tag-aware ratchet test). Title screen shows the git short-hash in dev runs.
- **Deployment**: continuous per-fix deploys during authorized windows; `v3.33.x-alpha` line live on itch.io. Desktop targets ship too: `tools/deploy_linux.sh` / `tools/deploy_windows.sh`, both wrapping `tools/deploy_desktop.sh` — same gates plus a BOOT gate (the exported binary must reach "[GAME] Started"; Windows via wine), and publishing is opt-in behind `--publish`. Web pipeline: `tools/deploy_web.sh <tag>` (suite → export → 199MB pck gate → muted render smoke w/ auto-retry → 4-stage WASM web smoke w/ auto-retry → butler push :web). Web smoke drives the REAL build in headless chromium: boot → New Game → overworld menu → save/reload/Continue (IndexedDB persistence proof), screenshots each stage, and prints a non-fatal console-error budget; its screenshots have caught 10+ real bugs.
- **Staged cutscenes (FF6/CT-style)**: `presentation:"staged"` cutscenes play on the LIVE map — CutsceneActor puppets walk/face/emote/hop, camera pans, real player+HUD hidden and restored. 35 step types in CutsceneDirector (derived from the `match step_type` arms — the doc said 8 for months, hiding branch/choice/battle/start_timer/grant_item/roll_credits and two dozen more from anyone authoring from it); world1_chapter1 is the proof scene. Named-NPC overworld sheets (theron/milo/phil/bram/marta) + provenance-tier ledger for ALL overworld sheets (bidirectional disk<->manifest ratchet).
- **UI fonts**: FontFallbacks autoload chains 4 subset Noto fonts (OFL, ~540KB) behind the default font — symbol/emoji glyphs render on web (they were tofu). Chain proof test pins every authored glyph.
- **Battle speed scale (v3)**: engine 0.25 = "1x" = the default (struktured 2026-07-11 ruling: the old 0.5x pacing is correct). Ladder labels = engine*4 everywhere (BattleScene + Settings); `speed_scale_v3` one-time settings migration; New Game resets per-run pacing (speed, encounter rate) while system settings persist.
- **Input locking**: cutscenes push/pop the canonical InputLockManager lock (interacts can't leak to save points / NPC / LLM dialogue mid-scene); living holders heartbeat so the 10s stale-expiry only reaps true leaks; story cutscenes outrank dynamic-LLM dialogue in NPC interact routing.

Deployed via butler to itch.io `:web` channel (NEVER without user approval — 2026-07-02 window was explicitly granted).

## Core Vision

A darkly comedic, self-referential RPG inspired by *Bravely Default*, *EarthBound*, and *Undertale*. The player doesn't just play the game — they automate it, exploit it, rewrite it, and occasionally destroy it.

**What makes this unique:**
- Autobattle and autogrind as first-class design pillars
- Meta jobs that manipulate game rules, saves, and reality
- Real stakes: permanent injuries, save corruption, permadeath staking
- Rewards exploitation and creativity equally
- Combat system mutation: unlock different battle modes via jobs

## Tone & Aesthetic

- **Visual progression** (future): 8-bit medieval → 16-bit suburban → 32-bit steampunk → minimalist existential
- **Style**: Sarcastic, satirical, occasionally philosophical
- **Goal**: Reward creativity and chaos equally

## Combat System

### Current: CTB (Conditional Turn-Based) with AP
- AP (Action Points) system: -4 to +4 range
- **Defer**: Skip turn, gain +1 AP, reduce damage taken
- **Advance**: Queue up to 4 actions, each costs 1 AP (can go into debt)
- Selection phase → Execution phase (speed-sorted)
- Natural +1 AP gain per turn

### Future: Combat System Mutation
Different jobs unlock alternative combat modes (switchable mid-battle with cooldown):
| Job | Combat Mode |
|-----|-------------|
| (Default) | CTB with AP |
| Time Mage | Active Time Battle |
| Guardian | Brave/Default BP stacking |
| Vanguard | Action RPG Mode |
| Tactician | Auto-Chess Mode |

### Group Attacks (Implemented)
Entire party can pool their Advance Points for combined attacks:
- **Requirements**: All party members must have AP to contribute
- **AP Cost**: Sum of individual costs (e.g., 4 members × 2 AP = 8 total AP spent)
- **Power Scaling**: Damage/effect scales exponentially with participants
- **Types**:
  - **All-Out Attack**: Physical damage, all party members strike together
  - **Combo Magic**: Elemental fusion (Fire + Ice = Steam, etc.)
  - **Formation Specials**: Unlocked by specific party compositions (six formations defined in `HeadlessBattleResolver.FORMATIONS`)
  - **Limit Breaks**: Ultimate attacks requiring full AP from all members
- **Strategic tradeoff**: Powerful but leaves entire party vulnerable next turn

### Free Move (Per-Job)
Each starter job has a free 0-cost AP action available in the command menu:
| Job | Free Move | Effect |
|-----|-----------|--------|
| Fighter | Strike | Bonus melee swing (physical fallback animation) |
| Cleric | Pray | Restores MP to a party member (green heal popup + sparkle FX) |
| Mage | Channel | Restores MP to self |
| Rogue | Strike | Bonus melee (falls back to attack anim, not cast) |
| Bard | Riff | Restores MP to whole party |

- MP-restore variants emit `healing_done` (green popup) not `damage_dealt` (would show as crit damage)
- Free Move abilities are NOT recorded in the MRU quick-slot list (each job has its own dedicated slot)

### Critical Hits
- Physical attacks can crit based on Luck/Speed stats
- Magic does NOT crit by default (can be enabled by specific abilities/equipment)
- Crit multiplier: 1.5x base, modified by equipment
- Visual: Screen flash, enhanced hit sound, damage number shake

### Battle UX
- **Permanent input hint bar** at bottom-center of battle screen: `[L] Defer · [R] Advance · [+/-] Speed · [Select] Auto`
- Hidden during autogrind console mode
- Inter-action delays scale with `Engine.time_scale` so 2x/4x speed actually plays faster (regression-tested)
- Tutorial hints (TutorialHints catalog) fire once per session — the hint bar covers the long-term reference need

### W1 Boss Roster
| Boss | Location | Level | Notes |
|------|----------|-------|-------|
| Cave Rat King | Whispering Cave | 10 | Tutorial boss, "boss_rat_king" theme |
| Pyrroth, the Ember Wyrm | Fire Dragon Cave | 14 | Fire-element dragon |
| Glacius, the Frozen Sovereign | Ice Dragon Cave | 15 | Ice-element dragon |
| Voltharion, the Storm's Edge | Lightning Dragon Cave | 16 | Lightning-element dragon |
| Umbraxis, the Void Render | Shadow Dragon Cave | 18 | Dark dragon, philosophical boss |
| **Chancellor Mordaine** | **Castle Harmonia** | **20** | **W1 final boss; defeat unlocks W2. Theme: "The Usurper's Shadow" (boss_medieval). One face of the Calibrant.** |

- Mordaine's intro plays `world1_mordaine_intro` cutscene before battle (CastleHarmonia extends DragonCave)
- Defeat sets BOTH `dungeon_flags["world1_mordaine_defeated"]` AND `game_constants["cutscene_flag_world1_mordaine_defeated"]` via the `defeat_cutscene_flags` bridge declared in the subclass
- Sprite is `shadow_knight` placeholder (tier T1) pending artist sheet
- Castle Harmonia placed on the W1 overworld (revealed post-Rat-King; tick 335 dual-namespace gate) + reachable via TeleportMenu

## Autobattle System

**Philosophy**: Autobattle is a first-class game mechanic, not a convenience feature. Mastering autobattle scripting IS the game.

### Current Implementation
- 2D Grid Editor: Conditions (AND chain) → Actions (up to 4)
- Per-character scripts stored in JSON
- Rule-based evaluation (first match wins, top-to-bottom)
- Multiple actions = Advance mode
- Defer as explicit action (blocks remaining slots)
- Cycle display for repeated actions (Attack ×3)

### Autobattle Editor Controls
| Action | Gamepad | Keyboard |
|--------|---------|----------|
| Open editor | L+R together | F5 |
| Toggle ALL autobattle | Select | F6 |
| Navigate grid | D-pad | Arrow keys |
| Edit cell | A | Z |
| Delete cell | Start / Y | Escape |
| Add condition | L trigger | L key |
| Add action | R trigger | R key |
| Close editor | B | X |

### Future Vision
- Jobs add new condition types and action verbs
- Scriptweaver job unlocks text-based expression mode
- Share/export scripts between players
- Hall of Fame for novel strategies

## Autogrind System (Future)

Risk/reward automation with escalating stakes:
- Longer automation = higher EXP multipliers BUT increased danger
- Monster adaptation: enemies learn and counter repeated strategies
- System fatigue spawns unpredictable meta-bosses
- Configurable interrupt rules (HP threshold, party death, corruption level)
- Optional permadeath staking for extreme rewards
- "System collapse" events punish perfect optimization

## Job System

**14 jobs total: 5 Starter, 4 Advanced, 5 Meta**

### Starter Jobs (type 0)
| Job | Role |
|-----|------|
| Fighter | Physical damage dealer |
| Cleric | Healer/support (renamed from White Mage) |
| Mage | Offensive magic (renamed from Black Mage) |
| Rogue | Speed/crits/utility (renamed from Thief) |
| Bard | Party buffs, debuffs, morale |

### Advanced Jobs (type 1, gated behind debug mode)
| Job | Function |
|-----|----------|
| Guardian | Tank, brave/default mechanics |
| Ninja | Speedrun functions, overworld shortcuts |
| Summoner | Recursive summoning (summon other summoners) |
| Speculator | Market/risk-based abilities |

### Meta Jobs (type 2, gated behind debug mode)
| Job | Function |
|-----|----------|
| Scriptweaver | Edit damage formulas, EXP rates, game constants via debug console |
| Time Mage | Save manipulation, rewind, undo permadeath |
| Necromancer | Dual-edged spells that can wipe saves |
| Bossbinder | Swap control with boss mid-battle; boss victory corrupts saves |
| Skiptrotter | Warp to next quest/boss, bypass dungeons |

### Job ID Migration
Old IDs (white_mage, black_mage, thief) are aliased to new IDs (cleric, mage, rogue) via `data/job_aliases.json` for save compatibility.

### Sprite System
- **HybridSpriteLoader**: Checks `data/sprite_manifest.json` for artist sprite sheets, falls back to procedural SnesPartySprites
- **SnesPartySprites**: Procedural 32x48 SNES-style sprites with composable layers (body→hair→face→outfit→headgear→weapon)
- Each job maps to an outfit type and headgear type via OUTFIT_MAP/HEADGEAR_MAP
- All 5 starters (fighter, mage, cleric, rogue, bard) ship with artist-made sheets in `assets/sprites/jobs/<job_id>/`
- Bard added 2026-05-22 (commit 0b53f19) — idle/cast/attack done; other animations pending
- Monster sheets: 90 entries in `monster_sheets` section, mostly 256x256 frames, AI-generated (T1) with artist passes pending
- Per-world monster variants supported: lookup `<monster>_<world_suffix>` first, fallback to base (e.g., `slime_suburban`)

### Save System Architecture
- **Format**: JSON, persisted via SaveSystem autoload
- **Critical pattern — typed-array roundtrip protection**: `JSON.parse` returns generic `Array`. Assigning to a typed `Array[String]` / `Array[Dictionary]` field is a SCRIPT ERROR — and **the assignment ABORTS the enclosing function; the surviving default is a symptom, not the extent.** Every line after the assignment never runs. (Read only as "field keeps default `[]`", this sentence mis-triaged two lanes in one hour on 2026-08-06 — a test with this bug at line 69 scored green while its subject-assert was never reached. Discriminator: `executed < authored` assert counts.) Combatant.from_dict and GameState.from_dict use explicit `for x in data[key]: typed.append(str(x))` coercion for these fields:
  - `status_effects`, `permanent_injuries`, `learned_passives`, `equipped_passives`, `pinned_abilities`, `recent_abilities` (Combatant)
  - `player_party`, `corruption_effects` (GameState)
- **Persisted ability slots**: MRU `recent_abilities` (size 2) + `pinned_abilities` (player-selected)
- **Cutscene completion flags**: `_CUTSCENE_COMPLETION_FLAGS` const in GameLoop maps every story-cutscene id → its `cutscene_flag_*_complete` key, set on cutscene finish to prevent the loop bug
- **Boss defeat bridge**: Subclasses of DragonCave can declare `defeat_cutscene_flags: Array[String]` to push flags into `game_constants` on victory (not just per-character `dungeon_flags`)

### Data Integrity Tests
Source-level + runtime guards in `test/unit/`:
- `test_monster_data_integrity.gd` — every drop / one_shot reward / ability / element tag must resolve
- `test_mordaine_runtime.gd` — Mordaine instantiates from JSON, abilities resolve in JobSystem, drops resolve in ItemSystem
- `test_mordaine_battle_integration.gd` — end-to-end battle via HeadlessBattleResolver
- `test_save_party_roundtrip_regression.gd` — typed-array JSON-roundtrip preservation
- `test_cutscene_completion_flag_regression.gd` — flag map covers W1 critical cutscenes
- These catch the silent-failure class that source review misses (typo'd IDs, broken cross-file refs)

## Stakes & Consequences

- **Permanent injuries**: Irreversibly affect stats
- **Save corruption**: Actual mechanic, not just flavor
- **Save evolution**: Manual saves → autosave → rewind → immunity (unlocked via Time Mage)
- **Permadeath staking**: Bet character lives for massive bonuses

## Tech Stack

**Primary:** Godot 4 with GDScript
- Rapid prototyping and iteration
- Built-in expression parsing for autobattle scripting
- Scene composition for battle system
- Easy save serialization for meta-manipulation

**Future (Deferred):** Rust + GBA target
- Only after core design is proven
- Would be scoped-down "Origins" version

## Development Workflow

### Branch Hygiene
**CRITICAL: Always merge latest main before starting new work.**
```bash
git fetch origin && git merge origin/main --no-edit
```
Do this at the start of every session, before creating new branches, and before any significant feature work. Stale branches cause merge hell.

### Pre-Launch Validation
**CRITICAL: Always use godot-mcp MCP tools before launching the game.**

The `mcp/godot-mcp` submodule provides MCP tools for safe validation:

**Before running the game after making code changes:**
1. **Check for errors**: Use `godot_check_errors` tool to catch syntax/parse errors
2. **Run tests**: Use `godot_run_tests` tool to run GUT unit tests
3. **Review output**: Fix any issues found
4. **Then launch**: Use `godot_run_scene` tool to run the game

**Available godot-mcp tools:**
- `godot_check_errors` - Check GDScript syntax without running game
- `godot_run_tests` - Run GUT unit tests with structured output
- `godot_run_scene` - Run the game (specific scene or main)
- `godot_import` - Import/reimport assets
- `godot_export` - Export project to platform

**Why use MCP tools instead of direct Bash:**
- Structured output (parsed, not raw console)
- Automatic error detection and reporting
- Safe headless execution
- Better integration with AI workflow

**Fallback:** Godot headless commands via Bash are always safe:
```bash
godot --headless --check-only --script <file>  # Check syntax
godot --headless -s test/run_tests.gd          # Run tests
```

### Testing
- Unit tests in `test/unit/` using GUT framework — ~7390 tests across 1157 files. **~5-10 min headless, not seconds** (see the Tests bullet above; this line said "~30s" and two other sites said "~40s", all three ~10x low and drifted independently)
- **Canonical test command** — use the wrapper (mutes audio AND writes its own --log-file so test runs never rotate the game's user://logs crash trace away):
  ```bash
  tools/run_tests.sh                # full unit suite
  tools/run_tests.sh <name>         # single file (test_<name>.gd)
  tools/run_tests.sh --isolated     # quarantined suite (test/isolated/, own process by design)
  ```
- **Exit codes: `0` pass · `1` test failures · `2` bad invocation · `3` NOTHING RAN.** Codes 2 and 3 were added 2026-07-29 because GUT **exits 0 when it runs no tests at all**, which no exit code could distinguish from a real pass. Measured: a nonexistent name gave `exit 0 · Scripts 1 · Tests 5`-shaped success with zero `Tests` lines. It cost the fleet four vacuous verification runs and two wrong diagnoses in one evening — cowir-ai briefly measured a known-red branch as green, and cowir-sfx took three attempts to get a real run. The causes are open-ended (absent file · empty `-gdir` · **fresh unimported worktree**, where `res://` does not resolve while the file sits on disk · a parse error that drops the script), so the wrapper does **not** enumerate them: it asserts the OUTCOME — a real run always prints a Totals block, a vacuous one never does — and exits 3 if none appeared. That vacuity check lives in the wrapper rather than in `tools/gate.sh` because `gate.sh` runs the full suite only — a single-file run never goes through it.
- **The suite writes over the player's exported scripts, and your protection is a property of YOUR checkout.** `test/unit` writes fixtures to `user://script_exports/` under the same filenames the shipped Shift+E export and `export_autogrind_rules()` use, so a plain full-suite run overwrote real player data — for nine deploys, the same defect class as the 2026-07-24 save-eating one. `run_tests.sh` snapshots and restores that directory around every run. It lived in `gate.sh` until 2026-07-30, which protected only the runs that typed `gate.sh` while the docs said `run_tests.sh`; **a tree predating that move has no net whatever main contains** — cowir-battle measured their own checkout 42 commits behind, gating faithfully through `gate.sh`, with zero snapshot machinery in it. Verify your tree, not the repo: `grep -c 'PLAYER-DATA NET' tools/run_tests.sh` (`0` = unprotected, rebase). The net is a backstop, not the fix: the real one is per-test, overriding the export path in your own fixture so no run writes production regardless of which tooling it went through.
- **Gate on the EXIT CODE, captured before you shape the output.** `run_tests.sh` propagates failure correctly (verified independently by 5 lanes, 2026-07-29); every gate that ever passed a red tree broke the signal downstream:
  ```bash
  tools/run_tests.sh > tmp/gate.log 2>&1; EC=$?   # capture BEFORE piping
  grep -E "^  (Passing|Failing)" tmp/gate.log     # then look
  test $EC -eq 0 || exit 1                        # then decide
  ```
  - `suite | grep … && commit` tests **grep's** exit code, not the suite's. `suite ; commit ; push` in one block never checks at all — the gate runs and does not gate.
  - Counting `[Failed]` is wrong twice: `grep -cE '^\s+\[Failed\]'` returns a clean **0** on a red tree (Godot colours stdout, so the ANSI escape precedes the whitespace; `\s*` does not save you — `--log-file` is ANSI-free and immune), and `grep -cF '[Failed]'` is a **valid boolean and never a count** — it equals 2 × failing *asserts*, a quantity GUT never prints, so nothing on screen can catch it being wrong. Measured: 1 failing test with 3 failing asserts → `Failing 1`, `grep -cF` **6**; 2 tests × 1 assert → 4. The ratio to `Failing N` is unbounded. Report `Failing N` (the only exact cardinal GUT prints) or `$?`.
- **`cowir-ai-intent-kit-ratchet` @ `b50a90f6` is a permanent known-RED branch, kept deliberately — do not fold or delete it.** It is an executable bug report (boss intents that reach no bias arm) and doubles as the fleet's gate control: point a gate at it, and if it reports green the detector is broken. A real coloured multi-line failure catches parse bugs a planted one-line assert does not.
  - **Run it in a worktree AT that SHA, and import first** — the naive form gives a false green twice over. From your own branch the file does not exist, so nothing runs; in a fresh worktree the import cache is absent, so `res://` does not resolve. Both used to exit 0 and read as "my detector is broken" when it was fine. `run_tests.sh` now refuses them (2 and 3), but the procedure still needs both lines:
    ```bash
    git worktree add --detach <dir> b50a90f6
    cd <dir> && godot --headless --audio-driver Dummy --import --quit   # REQUIRED — every fresh worktree is unimported
    tools/run_tests.sh > log 2>&1; echo $?                              # expect 1 · Failing 2
    ```
  - It is a **subset** of main (157 commits behind, 14 fewer test files). Valid as a detector control; it certifies **nothing** about main's corpus. Self-consistent is not current.
- Raw equivalent if the wrapper is unavailable (add `--log-file tmp/gut.log`):
  ```bash
  godot --headless --audio-driver Dummy --log-file tmp/gut.log -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gprefix=test_ -gsuffix=.gd -gexit
  ```
- Syntax-only check (autoloads not initialized; SoundManager / JobSystem refs will appear missing):
  ```bash
  godot --headless --check-only --script <file>
  ```
- Full import (autoloads available, catches more issues; ~10s):
  ```bash
  godot --headless --import
  ```
- All tests should pass before committing changes
- Output to local `tmp/` folder (gitignored), never `/tmp`

**Regression Prevention Rule:**
- **Every time a bug is fixed, add a regression test**
- If a bug made it to runtime, write a test that would have caught it
- This prevents the same bug from reoccurring
- Test file naming: `test_<feature>_regression.gd` for regression-specific tests
- Include bug reference in test comments (e.g., "Regression test for gray screen battle transition")

### Common Pitfalls (verified, recurring)
- **Combatant uses `job_level` NOT `level`** — accessing `.level` silently crashes `_build_ui()`
- **Godot's Input singleton leaks across GUT tests** — a stuck `ui_down` from one test drags "stationary" players in later physics tests (24px drift observed 2026-07-18); the shared default World2D also lets leaked bodies overlap unrelated triggers. Physics-sensitive tests: dedicated SubViewport/World2D + `Input.action_release` in before/after_each.
- **AreaTransition `_triggered` re-arms on body_exited (2026-07-18)** — it guards double-fires within one overlap ONLY; if you need a true one-shot door, add your own flag, don't rely on the latch
- **`await` in a loop SERIALIZES what should be simultaneous (2026-07-25)** — `for a in actors: await a.walk_to(...)` makes a crowd shuffle aside single-file over N × duration instead of parting at once. This reads perfectly fine in code and only fails on screen, so review won't catch it. For parallel motion: start every tween unawaited, track the longest duration, `await` that once. Applies to any staged-cutscene group action (scatter, group emote, simultaneous turn) — pinned by test in `test_conscript_nearby_regression`
- **Staged-cutscene coords are only valid for the map they were authored against (2026-07-25)** — a mark can be inside the map rect, on a walkable tile, and still wrong: `walk_to` tweens in a STRAIGHT LINE, so two legal marks can route an actor straight through a building. Village resizes shift every `.gd` `Vector2` but never touch cutscene JSON. `test_staged_scene_live_geometry_smoke` instantiates the real village and samples each walk segment against `_is_cell_walkable`; run it after any map edit
- **Git metadata describes PROVENANCE, not CONTENT (2026-07-25, hit independently by 3 lanes)** — verify the artifact, never the pointer. A branch tip failing `merge-base --is-ancestor` does NOT mean unlanded work (content reaches main via cherry-pick/reland). **The failure is ONE-DIRECTIONAL: a tip-side MERGED is trustworthy alone** (nothing moves a tip forward without its content) — only the NEGATIVES need content-side follow-up; a stash's label is the branch HEAD's commit subject at stash time, NOT its diff (5 of 7 "feature" stashes held only `.import` churn). Check the symbol/key exists on main, or `git stash show --name-only`, before concluding anything. **One layer deeper for imported assets: the file on disk is ALSO a pointer.** A test that reads a PNG/OGG through Godot's `load()` sees the cached `.ctex`/import artifact, not the bytes — so a file that `git hash-object` proves identical to main can still measure six-day-old pixels and fail a ratchet. After any fold touching assets, `--import` BEFORE trusting an asset-reading test (2026-07-25: nearly filed a phantom sprite regression this way)
- **Two data sources feeding one surface — one silently wins (2026-07-25)** — a dialogue rewrite can ship, diff clean, review fine, pass the suite, and be a runtime NO-OP because a *second* file overwrites it at `_ready` (`OverworldNPC._setup_persona_data` replaces constructor `dialogue_lines` with the persona JSON's `fallbacks[]`; bit Theron and Boris). Unlike every other trap here, NO git-side check finds it: the other failures are *pointer disagrees with content*, this is **two contents that are both correct where only the consumer's choice is wrong** — findable only by reading the consumer. When editing authored content, confirm which source the runtime actually reads.
  **Which guard is right depends on ONE axis — are the sources supposed to agree, and if not, can the author see which wins?** (a) *Redundant* (`monsters.json` ↔ cutscene `win_condition`): assert AGREEMENT — never model precedence, if both agree the question is moot. (b) *Divergent + invisible at authoring* (`fallbacks[]` ↔ `quest_state_lines`): guard the INVISIBILITY, not the collision — require an annotation naming what outranks it. (c) *Divergent + already documented* (`SOUNDS` ↔ `sfx_manifest`, manifest-wins-by-contract): NO ratchet, comment only.
  **Corollary — a check whose CORRECT case requires a suppression flag is not a check.** 40 allowlist entries on day one, or an `"_shadow_ok": true` that's muscle memory by the second NPC, is rot arriving dressed as diligence. When a guard IS warranted, require the DELIVERABLE (the note explaining precedence), never permission to skip — you can't silence it green, only explain it green, and the explanation is the fix
- **Ratchets pinned to a COINCIDENTAL value go red on a correct change and green on a wrong one (2026-07-25)** — e.g. asserting a flame sits at `x=4.5 tiles` (true, but only because that's where the fireplace happened to be) fails a correct relocation while permitting a genuinely misaligned flame. Assert the RELATIONSHIP (flame shares the surround's X, light tracks flame) not the coordinate. Tell: an absolute coordinate or magnitude in an assertion where the relationship is what's being defended
- **New GDScript files** need `godot --headless --import` before `class_name` is globally available
- **Launch godot** with `setsid godot < /dev/null > tmp/godot.stdout 2>&1 &` (fully detached) — bare `godot &` can break Wayland window visibility
- **Check `"active_buffs" in combatant`** before accessing buff arrays — not all objects are Combatants
- **Typed-array assignment from JSON** (`Array[String] = data["x"].duplicate()`) silently fails AND **aborts the enclosing function** — everything after the line is skipped, so a test containing one passes vacuously. Use explicit loop with `str()` coercion
- **Channel delivery requires the launch flag** — `claude --dangerously-load-development-channels server:session-intercom`. Without it, intercom tools work but inbound DMs never inject as `<channel>` tags
- **`HybridSpriteLoader._manifest_loaded`** is a static var — after editing sprite_manifest.json, restart Godot for changes to take effect
- **Submenu pattern**: create Control, PRESET_FULL_RECT, call setup(), add_child, hide parent UI (`_submenu_open` flag prevents OverworldMenu input consumption while submenus active)
- **OverworldMenu** lives inside CanvasLayer(layer=50) in GameLoop
- **InputLockManager** is the canonical input-pause mechanism — use `push_lock("name")` / `pop_lock("name")` for transient blocks (dialogue, transitions). `OverworldPlayer._can_move()` checks GameLoop state + InputLockManager + legacy `can_move` flag

## Controls & Input

**This game is designed for SNES-style gamepad. NO MOUSE/CLICKING required.**

All UI must be fully navigable via gamepad or keyboard.

### Battle Controls
| Action | Gamepad | Keyboard |
|--------|---------|----------|
| Navigate menu | D-pad | Arrow keys |
| Confirm/Select | A | Z/Enter |
| Cancel/Back | B | X/Escape |
| Queue action (Advance) | R shoulder | R key |
| Defer | L shoulder | L key |
| Change battle speed | X (top face button) | ` (backtick) |

### Menu Navigation
- All menus expand LEFT (tree-style, like classic JRPGs)
- D-pad Left = confirm/enter submenu
- D-pad Right = back/cancel

## File Structure

```
cowardly-irregular/
├── project.godot
├── CLAUDE.md
├── src/
│   ├── battle/          # CTB combat, BattleManager, BattleScene, EffectSystem
│   │   └── sprites/     # MonsterSprites, PartySprites, HybridSpriteLoader, SpriteUtils
│   ├── jobs/            # JobSystem, EquipmentSystem, PassiveSystem
│   ├── items/           # ItemSystem
│   ├── autobattle/      # AutobattleSystem, ScriptShareManager
│   ├── autogrind/       # AutogrindController, HeadlessBattleResolver
│   ├── meta/            # GameState, save state, corruption
│   ├── save/            # SaveSystem, ChapterTitles
│   ├── cutscene/        # CutsceneDirector, CutsceneDialogue, NPCDialogue, PartyChatSystem
│   ├── encounters/      # EncounterSystem
│   ├── audio/           # SoundManager, InputProfileManager
│   ├── transitions/     # SceneTransition, BattleTransition
│   ├── character/       # CharacterCustomization
│   ├── bestiary/        # BestiarySystem
│   ├── exploration/     # OverworldController, OverworldPlayer, OverworldNPC, WanderingNPC, AreaTransition, ShopScene, VillageShop, OverworldScene + per-world variants
│   ├── maps/            # MapSystem
│   │   ├── villages/    # BaseVillage + 10 named villages
│   │   ├── interiors/   # TavernInterior + others
│   │   └── dungeons/    # DragonCave base + 4 dragon caves + CastleHarmonia + WhisperingCave + NullChamber + RootProcess + AssemblyCore + SteampunkMechanism + SuburbanUnderground
│   └── ui/              # OverworldMenu, MenuScene, Win98Menu, TitleScreen, TeleportMenu, JukeboxMenu, BestiaryMenu, WorldMapMenu, etc.
│       └── autobattle/  # Grid editor (AutobattleGridEditor + AutobattleToggleUI)
├── assets/
│   ├── sprites/
│   │   ├── jobs/        # Per-job artist sheets (fighter/cleric/mage/rogue/bard)
│   │   ├── monsters/    # Per-monster sheets (90+ entries)
│   │   └── portraits/   # Cutscene character portraits
│   ├── audio/
│   │   ├── music/       # 150+ OGG tracks (Suno-generated, Git LFS)
│   │   └── sfx/         # SFX bank
│   └── fonts/
├── data/                # ALL game data is JSON, hot-reloadable
│   ├── jobs.json
│   ├── abilities.json
│   ├── passives.json
│   ├── monsters.json
│   ├── items.json
│   ├── equipment.json
│   ├── bestiary.json
│   ├── enemy_pools.json
│   ├── sprite_manifest.json
│   ├── music_manifest.json
│   ├── job_aliases.json    # white_mage→cleric, black_mage→mage, thief→rogue
│   └── cutscenes/          # 193 cutscene JSON files
└── test/
    └── unit/            # GUT tests (~7390 in 1157 files, ~5-10 min headless — background it)
```

## Key Design Principles

1. **Automation is core gameplay** - Not a shortcut, but the point
2. **Exploitation is rewarded** - Clever abuse is celebrated
3. **Stakes must be real** - Consequences make choices meaningful
4. **Meta is diegetic** - Fourth-wall breaks are in-universe mechanics
5. **Prototype fast, validate early** - Prove fun before polish
6. **Controller-first design** - Everything works on gamepad
7. **Silent failures are worse than crashes** - Always add a runtime test that would have caught the bug (see Data Integrity Tests section). The 180-broken-drops audit and the typed-array save-load bug are canonical examples.

## Cutscene System
- **CutsceneDirector** (GameLoop-owned CanvasLayer, layer 95 — NOT an autoload; reach it via `GameLoop.get_cutscene_director()`) orchestrates story cutscenes from `data/cutscenes/*.json`
- **CutsceneDialogue** (CanvasLayer) renders the dialogue panel — screen-anchored, gamepad-friendly
- **NPCDialogue** is a thin wrapper around CutsceneDialogue used by overworld NPCs (avoids the cut-off bug local panels had)
- **Story flow gating**: `GameLoop._get_pending_story_cutscene()` is the single source of truth for which cutscene plays next. Each gate is a flag-pair: `if X happened AND not <cutscene>_complete: return "<cutscene_id>"`
- **Completion flag wiring**: `_CUTSCENE_COMPLETION_FLAGS` const maps id → flag; `_play_story_cutscene` writes the flag when CutsceneDirector emits `cutscene_finished`. Without this, cutscenes loop forever (was the Elder Theron bug).
- **Boss intro cutscenes**: dungeons set `boss_cutscene_id` (DragonCave base reads it before emitting `battle_triggered`)
- 193 cutscene files on disk; 76 actively triggered; remaining are planned content / event chats / party chats

## Artist Collaboration & Sprite Pipeline Rules

**Pioneering a fair AI-artist collaboration model. We may be the first game to do this right — AI as the artist's force multiplier, not their replacement. The artist stays in the creative loop AND the financial loop.**

### Core Principles
1. **Artist-first hierarchy**: When artist-made sprites exist, they take priority. AI sprites may supplement or eventually replace, but that decision is always deliberate — never silent or accidental.
2. **Protect existing artist work**: AI sprite generation must NEVER overwrite, modify, or degrade existing artist-made assets without explicit approval. Fighter sprites (tagged `v0.15.0`) are the baseline example.
3. **AI can ship**: AI-generated sprites may end up as final art if quality is sufficient. The key is intentionality — every AI-to-production decision should be conscious, documented, and paired with fair artist compensation.
4. **Artist compensation model**: The artist gets paid regardless of how much AI generates. Possible structures:
   - **Style licensing**: Artist's originals train/guide the pipeline → ongoing royalty or flat license fee
   - **Art direction fees**: Artist reviews, approves, and course-corrects AI output → paid for curation
   - **Cleanup rates**: Artist polishes AI sprites to ship quality → per-asset or hourly
   - **Revenue share**: Artist participates in game revenue since their style is the foundation
   - **Retainer**: Ongoing relationship, not per-sprite piecework
   - The model should be documented and agreed upon — this is new territory worth getting right publicly.
5. **Attribution & transparency**: AI-generated sprites must be tracked (tier labels in manifest). The artist always knows what's AI-generated vs hand-drawn. They have approval rights on what ships. Consider publishing the collaboration model as part of the game's story — this transparency IS the innovation.
6. **Budget-conscious prototyping**: Use AI/proc-gen freely for jobs and animations the artist hasn't reached yet. This lets us feel out the full game without blocking on art delivery. The artist cleans up, approves, or replaces at their pace.

### Sprite Pipeline Tiers
| Tier | Source | Quality | Permanence |
|------|--------|---------|------------|
| T0 - Procedural | SnesPartySprites (GDScript) | Functional placeholder | Temporary |
| T1 - AI-Generated | Python sprite gen scripts (tools/) | Stylistically consistent prototype | Temporary until artist review |
| T2 - Artist Draft | Artist sprite sheets (per-animation PNGs) | Production candidate | Semi-permanent |
| T3 - Artist Final | Artist-approved, cleaned, palette-locked | Ship quality | Permanent |

### Workflow
- AI agents generating sprites must tag output as `tier: "T1"` in sprite_manifest.json
- Artist sprites are `tier: "T2"` or `tier: "T3"`
- **`tier` is provenance metadata. NOTHING IN THE GAME READS IT.** This line
  used to say "HybridSpriteLoader priority: T3 > T2 > T1 > T0", which described
  a resolution order the loader has never had. Verified 2026-07-29:
  `HybridSpriteLoader` contains zero references to `tier`. Its actual logic is
  binary — `_manifest.has(id)` loads that sheet, absence falls back to
  procedural — and **`sprite_manifest.json` holds exactly one entry per id
  per section**, so a lookup never has two candidates to rank. (An id may
  appear in two *different* sections for two different sheets —
  `chancellor_mordaine` has both a `monster_sheets` battle sheet and an
  `overworld_npc_sheets` overworld sheet — but those are separate lookups by
  separate functions, not competing candidates. I wrote "exactly one entry per
  id" first; the check caught it before it reached this file.)
- **Why the wrong version was dangerous, not just inaccurate:** it implied that
  registering a T1 sheet alongside artist work is safe because the higher tier
  wins. There is no "alongside" — registering T1 under an existing id
  **replaces** the artist sheet, silently, at load time. The documented rule
  would have caused the exact loss it appeared to prevent.
- **What actually protects artist work** is refusal at generation time, not
  resolution at load time: `regen_monster_artist_style.artist_write_refusal()`
  (refuses T2/T3 targets, and refuses unregistered sheets whose provenance is
  unknown) and `gen_full_sweep._protected_anims()` (derived from git, unioned
  with a legacy floor so protection can only grow). Both live in cowir-sprites.
  `tools/audit_sprite_tiers.py` catches tier lies by checking git rather than
  the manifest — the manifest cannot audit its own provenance, and on
  2026-07-29 all four starter job sheets were labelled T1 while holding artist
  pixels, with tier and generator agreeing perfectly because both were written
  in one edit and neither revisited.
- When generating new job sprites, reference the artist's existing palette and proportions from fighter/cleric/mage/rogue
- Keep all gen scripts in `tools/` with clear naming: `gen_<job>_sprites.py`
- Generated sprites go in `assets/sprites/jobs/<job_id>/` following the per-animation PNG convention

### What AI Sprite Agents MUST Do
- Match the artist's established 256x256 frame size and 16-bit aesthetic
- Use consistent palettes derived from existing artist work
- Generate all 9 standard animations: idle, walk, attack, hit, dead, cast, defend, item, victory
- Register output in sprite_manifest.json
- Log what was generated vs what exists as artist work

### What AI Sprite Agents MUST NOT Do
- Overwrite any file in a directory containing artist-made sprites without explicit approval
- Generate sprites that clash stylistically with artist-established look
- Claim AI sprites are final art
- Skip the cleanup step — flag areas needing artist attention

## Multi-Agent Coordination

This project uses parallel Claude Code sessions coordinated via the `session-intercom` MCP server (SQLite-backed DB at `~/.local/share/session-intercom/intercom.db`).

**Fleet norms (2026-07-11):** (1) NEVER work inside another agent's checkout — cowir-main's tree is the live deploy tree; use your own repo/worktree and push branches to origin. (2) Teammate PRs fold ONLY through cowir-main: full diff review + local full-suite gate (0 failures, claims re-verified) per struktured's standing grant; run the FULL suite before pinging ready. (3) .gd comments 1 line max. (4) NEVER `git stash` in shared worktrees (2026-07-16 incident): stash storage is repo-global across worktrees — parallel push/pop silently swaps or drops other agents' stashes with no warning; use a scratch branch or fresh worktree for diagnostic snapshots. (5) After pulling a fold that adds new `class_name` files, run `godot --headless --audio-driver Dummy --import` BEFORE gating — else expect a phantom parse-error cascade in GameLoop-dependent tests.

Named sessions (one-call `intercom_register(name=<name>)` — channels API, no team_name, no TeamCreate):
- **cowir-main** — game engine, integration, releases (this session usually)
- **cowir-sprites** — sprite generation (cowardly-irregular-sprite-gen repo)
- **cowir-music** — music generation (cowardly-irregular-music repo, Suno pipeline)
- **cowir-sfx** — SFX (cowir-sfx repo, ElevenLabs + LMMS MCP)
- **cowir-story** — narrative content (cowardly-irregular-story repo)
- **cowir-battle** — combat system specialization (when active)

Channel delivery requires the host launched with `--dangerously-load-development-channels server:session-intercom`. If `<channel>` tags never arrive when other sessions DM you, that flag is the first thing to check. Manual fallback: `intercom_poll()`.

## Deployment

- Tag at every meaningful milestone (`vMAJOR.MINOR.PATCH-alpha` convention)
- Web export: `godot --headless --export-release "Web" builds/web/index.html`
- Itch push: `butler push builds/web/ struktured/cowardly-irregular:web --userversion <tag>` (channel is `:web`, NOT `:html5`). Was documented as `./butler-bin/butler`. That directory is **gitignored** (`.gitignore:61`, 0 files tracked on main), so it exists only where somebody unpacked it by hand — one legacy checkout — and can never arrive by clone or `git worktree add`, because a worktree materialises only tracked files. It is absent from *this* tree, the one deploys run from. Five lanes measured it and gave four different answers before anyone ran `grep butler .gitignore`: `ls` answers about the checkout you're standing in, and `git check-ignore butler-bin` (no trailing slash) reports no match against a directory rule, which reads exactly like "no rule exists." The scripts were never at risk — `deploy_web.sh:42` resolves `$(command -v butler || echo ./butler-bin/butler)` and finds the PATH copy first everywhere — so only the human-facing instruction was broken, which is the half nothing tests. Do NOT "fix" this by committing the 22MB binary; the ignore rule is deliberate.
- **NEVER deploy to itch.io without explicit user approval** — always ask first before pushing builds
- Music OGGs 96kbps mono; W4-W6 tracks are WEB-EXCLUDED via export_presets exclude_filter (procedural fallback) — itch.io HTML5 embeds cap single files at 200 MB; pipeline hard-fails on pck ≥ 190 MB
- All *.ogg files tracked via Git LFS

## Author

Carmelo Piccione ("struktured")
Struktured Labs — 2025
