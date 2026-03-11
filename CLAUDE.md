# Cowardly Irregular

A meta-aware JRPG where automation isn't cheating — it's enlightenment.

## Project Status: Early Prototype

Working battle system with CTB combat, 4-party system, autobattle scripting UI.

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

### Group Attacks (Planned)
Entire party can pool their Advance Points for combined attacks:
- **Requirements**: All party members must have AP to contribute
- **AP Cost**: Sum of individual costs (e.g., 4 members × 2 AP = 8 total AP spent)
- **Power Scaling**: Damage/effect scales exponentially with participants
- **Types**:
  - **All-Out Attack**: Physical damage, all party members strike together
  - **Combo Magic**: Elemental fusion (Fire + Ice = Steam, etc.)
  - **Formation Specials**: Unlocked by specific party compositions
  - **Limit Breaks**: Ultimate attacks requiring full AP from all members
- **Strategic tradeoff**: Powerful but leaves entire party vulnerable next turn

### Critical Hits
- Physical attacks can crit based on Luck/Speed stats
- Magic does NOT crit by default (can be enabled by specific abilities/equipment)
- Crit multiplier: 1.5x base, modified by equipment
- Visual: Screen flash, enhanced hit sound, damage number shake

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
- Unit tests in `test/unit/` using GUT framework
- Run tests via: `godot --headless -s test/run_tests.gd`
- All tests should pass before committing changes
- **Godot headless commands are always safe** - use liberally for validation
  - `godot --headless --check-only --script <file>` - Check syntax
  - `godot --headless -s test/run_tests.gd` - Run unit tests
  - Output to local `tmp/` folder (gitignored), never `/tmp`

**Regression Prevention Rule:**
- **Every time a bug is fixed, add a regression test**
- If a bug made it to runtime, write a test that would have caught it
- This prevents the same bug from reoccurring
- Test file naming: `test_<feature>_regression.gd` for regression-specific tests
- Include bug reference in test comments (e.g., "Regression test for gray screen battle transition")

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
│   ├── battle/        # Combat system, CTB mechanics
│   ├── jobs/          # Job definitions, abilities
│   ├── autobattle/    # Scripting engine, conditionals
│   ├── autogrind/     # Risk system, interrupts (future)
│   ├── meta/          # Save manipulation, corruption
│   └── ui/            # Menus, battle UI, Win98 style
│       └── autobattle/  # Grid editor components
├── assets/
│   ├── sprites/
│   ├── audio/
│   └── fonts/
└── data/
    ├── jobs.json
    ├── abilities.json
    └── monsters.json
```

## Key Design Principles

1. **Automation is core gameplay** - Not a shortcut, but the point
2. **Exploitation is rewarded** - Clever abuse is celebrated
3. **Stakes must be real** - Consequences make choices meaningful
4. **Meta is diegetic** - Fourth-wall breaks are in-universe mechanics
5. **Prototype fast, validate early** - Prove fun before polish
6. **Controller-first design** - Everything works on gamepad

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

## Author

Carmelo Piccione ("struktured")
Struktured Labs — 2025
