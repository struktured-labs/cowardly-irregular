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

## Meta Jobs

| Job | Function |
|-----|----------|
| Scriptweaver | Edit damage formulas, EXP rates, game constants via debug console |
| Time Mage | Save manipulation, rewind, undo permadeath |
| Necromancer | Dual-edged spells that can wipe saves |
| Bossbinder | Swap control with boss mid-battle; boss victory corrupts saves |
| Skiptrotter | Warp to next quest/boss, bypass dungeons |
| Ninja | Speedrun functions, overworld shortcuts |
| Summoner | Recursive summoning (summon other summoners) |

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
**IMPORTANT: Always run godot-mcp tool suite before launching the game.**

Before running the game after making code changes:
1. **Run GDScript validator** via godot-mcp to catch syntax errors
2. **Check for script errors** in recently modified files
3. **Run unit tests** if available (via `godot --headless -s test/run_tests.gd`)
4. **Then launch** the game

This prevents runtime errors and saves debugging time by catching issues early.

Example godot-mcp validation workflow:
```bash
# Use godot-mcp to validate scripts before launch
# Check syntax, validate scene references, etc.
# Only proceed to game launch if validation passes
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

## Author

Carmelo Piccione ("struktured")
Struktured Labs — 2025
