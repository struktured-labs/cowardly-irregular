# Cowardly Irregular - Game Engine

A meta-aware JRPG where automation isn't cheating — it's enlightenment.

## Status: Prototype v0.1

The core game engine is now functional! This includes:

✅ Brave/Default turn-based combat system
✅ AP (Action Points) mechanics (-4 to +4 range)
✅ Job system with starter and meta jobs
✅ Battle state management
✅ Save/load system with corruption mechanics
✅ Game constant modification (Scriptweaver powers)
✅ Basic battle UI
✅ Data-driven jobs, abilities, and monsters

## Quick Start

### Requirements
- [Godot 4.3+](https://godotengine.org/download)

### Running the Game

1. **Clone the repository** (or you already have it)
   ```bash
   cd cowardly-irregular
   ```

2. **Open in Godot**
   - Launch Godot 4
   - Click "Import"
   - Navigate to this directory and select `project.godot`
   - Click "Import & Edit"

3. **Run the game**
   - Press F5 or click the Play button in Godot
   - You'll see a test battle with the core combat system

## Project Structure

```
cowardly-irregular/
├── project.godot          # Godot project configuration
├── CLAUDE.md             # Design document
├── README.md             # This file
│
├── src/                  # Source code
│   ├── battle/          # Combat system, AP mechanics
│   │   ├── BattleManager.gd    # Singleton managing battle flow
│   │   ├── Combatant.gd        # Base class for all fighters
│   │   ├── BattleScene.gd      # Battle UI controller
│   │   └── BattleScene.tscn    # Battle UI layout
│   │
│   ├── jobs/            # Job system
│   │   └── JobSystem.gd        # Job/ability management singleton
│   │
│   ├── meta/            # Meta-game systems
│   │   └── GameState.gd        # Save/load, corruption, constants
│   │
│   ├── autobattle/      # Autobattle scripting (TODO)
│   ├── autogrind/       # Autogrind system (TODO)
│   └── ui/              # UI components (TODO)
│
├── data/                # Game data (JSON)
│   ├── jobs.json        # Job definitions
│   ├── abilities.json   # Ability definitions
│   └── monsters.json    # Monster definitions
│
└── assets/              # Art, audio, fonts
    ├── sprites/
    ├── audio/
    └── fonts/
```

## Core Systems

### 1. Brave/Default Combat

The battle system is inspired by *Bravely Default*:

- **Attack**: Basic physical attack
- **Abilities**: Job-specific skills (costs MP)
- **Items**: Use consumables (TODO)
- **Default**: Skip turn, gain +1 AP, reduce damage by 50%
- **Brave**: Spend AP to take multiple actions in one turn

**AP (Action Points)**:
- Range: -4 to +4
- Start each battle at 0
- Default gives +1 AP
- Brave spends AP (can go into debt)
- If AP is negative, you skip turns to pay it back

### 2. Job System

Jobs define a character's stats and abilities:

**Starter Jobs**:
- **Fighter**: High HP/Attack, physical damage dealer
- **White Mage**: Healer, support magic
- **Black Mage**: Offensive magic damage
- **Thief**: Fast, can steal items/gold

**Meta Jobs** (the unique twist):
- **Scriptweaver**: Edit damage formulas, EXP rates, game constants
- **Time Mage**: Save manipulation, rewind, undo permadeath
- **Necromancer**: Powerful dark magic, can corrupt/wipe saves

### 3. Meta-Mechanics

**Save Corruption**:
- Using meta abilities increases corruption (0.0 to 1.0)
- High corruption causes random effects when saving/loading
- Effects: stat drain, HP corruption, AP instability, etc.

**Game Constants** (modifiable by Scriptweaver):
- `exp_multiplier`: Change experience gain rate
- `damage_multiplier`: Modify all damage
- `gold_multiplier`: Adjust gold drops
- `encounter_rate`: Control random encounters
- And more!

**Time Mage Powers** (when unlocked):
- Autosave functionality
- Rewind to previous saves
- Create restore points
- Undo permadeath

### 4. Battle Manager

The `BattleManager` singleton (`src/battle/BattleManager.gd`) handles:
- Turn order calculation (based on Speed stat)
- Action execution and resolution
- Victory/defeat conditions
- AI for enemies
- Autobattle mode (TODO)

### 5. Combat Flow

```
Battle Start
  ↓
Calculate Turn Order (by Speed)
  ↓
Round Start
  ↓
For each combatant in turn order:
  - If AP < 0: skip turn, gain +1 AP
  - If Player: show action menu
  - If Enemy/Autobattle: execute AI
  - Execute action
  - Check victory/defeat
  ↓
Round End → Next Round
```

## Current Test Battle

When you run the game, you'll see a test battle:
- **Hero** (Fighter) vs **Slime** (Enemy)
- Try the different action buttons:
  - **Attack**: Basic attack
  - **Default**: Gain AP and defend
  - **Brave (x2 Attack)**: Attack twice, spend 1 AP

Watch the battle log and character stats update in real-time!

## What's Next?

### Phase 1 (Current)
- [x] Core battle system
- [x] AP mechanics
- [x] Job system foundation
- [x] Basic UI
- [ ] **Ability system** (expand beyond basic attack)
- [ ] Item system
- [ ] Enemy AI improvements

### Phase 2 (Next)
- [ ] Autobattle scripting UI
- [ ] Conditional logic (`if HP < 25%`, etc.)
- [ ] Save/load autobattle scripts
- [ ] Job-specific scripting verbs

### Phase 3
- [ ] Autogrind system
- [ ] Risk/reward mechanics
- [ ] Adaptive enemies
- [ ] Meta-bosses from corruption

### Phase 4
- [ ] World map
- [ ] Town → Dungeon progression
- [ ] Character progression
- [ ] Story integration

## Development Notes

### Adding a New Job

1. Edit `data/jobs.json`
2. Define stat modifiers and abilities
3. Restart the game to reload data

### Adding a New Ability

1. Edit `data/abilities.json`
2. Define type, MP cost, effects
3. Add execution logic in `BattleManager._execute_ability()` if needed

### Adding a New Monster

1. Edit `data/monsters.json`
2. Define stats, abilities, rewards
3. Create an instance in battle setup

## Design Philosophy

From `CLAUDE.md`:

1. **Automation is core gameplay** - Not a shortcut, but the point
2. **Exploitation is rewarded** - Clever abuse is celebrated
3. **Stakes must be real** - Consequences make choices meaningful
4. **Meta is diegetic** - Fourth-wall breaks are in-universe mechanics
5. **Prototype fast, validate early** - Prove fun before polish

## Contributing

This is currently a solo project by Carmelo Piccione (struktured), but the design is documented in `CLAUDE.md` for reference.

## License

Not yet determined. Currently in prototype phase.

---

**Struktured Labs - 2025**
