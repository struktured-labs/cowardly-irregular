# Cowardly Irregular

A meta-aware JRPG where automation isn't cheating — it's enlightenment.

## Project Status: Advanced Prototype (v3.30-alpha-track, undeployed work ahead)

Playable end-to-end through World 1:

- **Battle system**: CTB + AP, 5-party, Advance/Defer mechanics, group attacks, formation specials, per-job Free Move command (Channel/Pray/Riff/Strike), Mode 7 perspective floor
- **Autobattle**: per-character rule editor with full keyboard/gamepad nav
- **Worlds**: 6 worlds wired (medieval / suburban / steampunk / industrial / futuristic / abstract); W1 fully playable. W2-W6 use visible roaming monsters only (step-based random encounters disabled when MonsterSpawner is active — fix shipped 2026-06-19).
- **Bosses**: Cave Rat King, 4 elemental dragons (Pyrroth/Glacius/Voltharion/Umbraxis), Chancellor Mordaine (W1 final)
- **LLM integration**:
  - Opt-in dynamic NPC dialogue (Theron / Milo / Boris in Harmonia) + jailbreakable boss dialogue
  - **Boss Strategic Intent** for all 5 W1 bosses (Settings → LLM Boss Strategy). LLM picks intent/posture per phase, deterministic ladder still owns ability choice.
  - **Party Combat Dialogue** for all 5 starter jobs (Settings → LLM Party Dialogue). Personas drafted via workflow. Triggers: turn_start, low_hp (cross-25%), big_hit_taken (crit or >30% max HP), used_signature_ability (per-job iconic move), victory. Per-character 8-round cooldown. Scripted `trigger_voices` fallback per job when LLM off.
  - Ollama / OpenAI-compat backends via HTTPBackend. DialogueChoiceMenu CanvasLayer-anchored top-centre.
- **Data**: 14 jobs, 286 abilities, 88 monsters (now with artist art for slime, bat, goblin), 117 items, 43 passives, 33 encounter pools, 166 cutscenes, 150+ music tracks
- **Tests**: 1862 passing / 0 failing in GUT (suite ~18s headless)
- **Save**: Full JSON save with typed-array roundtrip protection, MRU/pin ability persistence, permanent injuries, corruption effects, story-flag gates
- **Deployment**: `v3.30.0-alpha` live on itch.io (web/Brave-mobile black-screen-after-battle fix). Many commits since waiting for next user-approved deploy.

Deployed via butler to itch.io `:web` channel at every milestone tag.

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
- Castle Harmonia accessible via TeleportMenu under W1 (overworld portal placement TBD)

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
- **Critical pattern — typed-array roundtrip protection**: `JSON.parse` returns generic `Array`. Assigning to a typed `Array[String]` / `Array[Dictionary]` field is a SCRIPT ERROR (silent — no crash, field silently keeps default `[]`). Combatant.from_dict and GameState.from_dict use explicit `for x in data[key]: typed.append(str(x))` coercion for these fields:
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
- Unit tests in `test/unit/` using GUT framework — currently 1099+ tests, ~12s headless
- **Canonical test command** (works reliably, used throughout session):
  ```bash
  godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gprefix=test_ -gsuffix=.gd -gexit
  ```
- Single-file run:
  ```bash
  godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_<name>.gd -gexit
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
- **New GDScript files** need `godot --headless --import` before `class_name` is globally available
- **Launch godot** with `setsid godot < /dev/null > tmp/godot.stdout 2>&1 &` (fully detached) — bare `godot &` can break Wayland window visibility
- **Check `"active_buffs" in combatant`** before accessing buff arrays — not all objects are Combatants
- **Typed-array assignment from JSON** (`Array[String] = data["x"].duplicate()`) silently fails — use explicit loop with `str()` coercion
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
| Change battle speed | +/- on D-pad | +/- keys |

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
│   └── cutscenes/          # 166 cutscene JSON files
└── test/
    └── unit/            # GUT tests (1099+, runs ~12s headless)
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
- **CutsceneDirector** (autoload, layer 95) orchestrates story cutscenes from `data/cutscenes/*.json`
- **CutsceneDialogue** (CanvasLayer) renders the dialogue panel — screen-anchored, gamepad-friendly
- **NPCDialogue** is a thin wrapper around CutsceneDialogue used by overworld NPCs (avoids the cut-off bug local panels had)
- **Story flow gating**: `GameLoop._get_pending_story_cutscene()` is the single source of truth for which cutscene plays next. Each gate is a flag-pair: `if X happened AND not <cutscene>_complete: return "<cutscene_id>"`
- **Completion flag wiring**: `_CUTSCENE_COMPLETION_FLAGS` const maps id → flag; `_play_story_cutscene` writes the flag when CutsceneDirector emits `cutscene_finished`. Without this, cutscenes loop forever (was the Elder Theron bug).
- **Boss intro cutscenes**: dungeons set `boss_cutscene_id` (DragonCave base reads it before emitting `battle_triggered`)
- 166 cutscene files on disk; 76 actively triggered; remaining are planned content / event chats / party chats

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
- HybridSpriteLoader priority: T3 > T2 > T1 > T0
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
- Itch push: `./butler-bin/butler push builds/web/ struktured/cowardly-irregular:web --userversion <tag>` (channel is `:web`, NOT `:html5`)
- **NEVER deploy to itch.io without explicit user approval** — always ask first before pushing builds
- Music OGGs compressed to 96kbps mono for web (~137 MB total, fits itch.io limits)
- All *.ogg files tracked via Git LFS

## Author

Carmelo Piccione ("struktured")
Struktured Labs — 2025
