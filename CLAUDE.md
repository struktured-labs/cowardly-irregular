# Cowardly Irregular

A meta-aware JRPG where automation isn't cheating — it's enlightenment.

## Project Status: Pre-Prototype

Currently in design/planning phase. No code written yet.

## Core Vision (Scoped)

A darkly comedic, self-referential RPG inspired by *Bravely Default*, *EarthBound*, and *Undertale*. The player doesn't just play the game — they automate it, exploit it, and occasionally break it.

**What makes this unique:**
- Autobattle and autogrind as first-class design pillars
- Meta jobs that manipulate game rules, saves, and reality
- Real stakes: permanent injuries, save corruption, permadeath staking
- Rewards exploitation and creativity equally

## Design Decisions (Locked)

### Combat System
- **Brave/Default turn-based combat only** (no combat system evolution)
- BP (Brave Points) system: -4 to +4 range
- Default: skip turn, gain +1 BP, reduce damage
- Brave: spend BP for extra actions, can go into debt

### Autobattle System
- Fully scriptable with conditional logic (`HP < 25%`, `If poisoned`, etc.)
- Each job adds new scripting verbs and conditionals
- Save/load/share automation setups
- Controller-friendly UI

### Autogrind System
- Risk/reward automation with escalating stakes
- Efficiency multiplier increases danger (monster adaptation, meta corruption)
- Configurable interrupt rules (HP threshold, party death, glitch fights)
- Optional permadeath staking for extreme rewards
- System collapse spawns unpredictable meta-bosses

### Meta Jobs (Core Examples)
| Job | Function |
|-----|----------|
| Scriptweaver | Edit damage formulas, EXP rates, game constants |
| Time Mage | Save manipulation, rewind, undo permadeath |
| Necromancer | Dual-edged spells that can wipe saves |
| Bossbinder | Swap control with boss mid-battle |

### Stakes & Consequences
- Permanent injuries affect stats forever
- Save corruption as actual mechanic
- Time Mage unlocks save evolution (autosave, rewind, restore points)

## Tech Stack

**Primary:** Godot 4 with GDScript
- Rapid prototyping and iteration
- Built-in expression parsing for autobattle scripting
- Scene composition for battle system
- Easy save serialization for meta-manipulation

**Future (Deferred):** Rust + GBA target
- Only after core design is proven
- Would be scoped-down "Origins" version

## Art Style

8-16 bit pixel art. Single consistent style for prototype (no era-hopping yet).

## Prototype Scope (Phase 1)

Target: Minimal vertical slice demonstrating core loop

```
Must Have:
├── Brave/Default combat system
├── 2-3 starter jobs + 1 meta job (Scriptweaver)
├── Basic autobattle scripting UI
├── 1 town → 1 dungeon → 1 adaptive boss
├── 1 meta-save event (taste of corruption)
└── Basic autogrind with risk escalation

Explicitly Deferred:
├── Combat system evolution/mutation
├── Era-hopping visuals
├── Recursive summons
├── Multiplayer/co-op
├── Hall of Fame system
├── Full job roster
└── GBA target
```

## File Structure (Planned)

```
cowir/
├── project.godot
├── CLAUDE.md
├── src/
│   ├── battle/        # Combat system, BP mechanics
│   ├── jobs/          # Job definitions, abilities
│   ├── autobattle/    # Scripting engine, conditionals
│   ├── autogrind/     # Risk system, interrupts
│   ├── meta/          # Save manipulation, corruption
│   └── ui/            # Menus, battle UI
├── assets/
│   ├── sprites/
│   ├── audio/
│   └── fonts/
└── data/
    ├── jobs.json
    ├── abilities.json
    └── monsters.json
```

## Controls & Input

**This game is designed for SNES-style gamepad. NO MOUSE/CLICKING required.**

All UI must be fully navigable via gamepad or keyboard. Never add click-only interactions.

### Battle Controls (Gamepad / Keyboard)
| Action | Gamepad | Keyboard |
|--------|---------|----------|
| Navigate menu | D-pad | Arrow keys |
| Confirm/Select | A / D-pad Left | Enter/Space/Z |
| Cancel/Back | B / D-pad Right | Escape/X |
| Queue action (Advance) | R shoulder | R key |
| Undo queue / Defer | L shoulder | L key |
| Change battle speed | Start/Select | +/- keys |
| Switch party member | L/R shoulder | L/R keys |

### Menu Navigation
- All menus expand LEFT (tree-style, like classic JRPGs)
- D-pad Left = confirm/enter submenu
- D-pad Right = back/cancel
- Submenus auto-expand on hover

### Post-Battle Menu
- Same controls as battle menu
- L/R to switch party member being viewed

## Key Design Principles

1. **Automation is core gameplay** - Not a shortcut, but the point
2. **Exploitation is rewarded** - Clever abuse is celebrated
3. **Stakes must be real** - Consequences make choices meaningful
4. **Meta is diegetic** - Fourth-wall breaks are in-universe mechanics
5. **Prototype fast, validate early** - Prove fun before polish

## Author

Carmelo Piccione ("struktured")
Struktured Labs — 2025
