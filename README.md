# Cowardly Irregular

A meta-aware JRPG where automation isn't cheating — it's enlightenment.

## Status: Advanced Prototype (v3.33-alpha track)

The canonical version string is `src/meta/Version.gd` (`Version.SEMVER`); the
living, detailed status list is the top of [`CLAUDE.md`](CLAUDE.md). This README
is a quick orientation only — when it disagrees with the code, the code wins.

Shipped systems include:

- CTB battle system with AP and **Advance / Defer** (5-member party, group attacks, formation specials)
- AP range **-4 to +4** (`Combatant.AP_FLOOR` / `AP_CEILING`)
- 14 jobs (5 starter, 4 advanced, 5 meta), data-driven from `data/jobs.json`, with per-world job names (`data/job_world_names.json`)
- Autobattle rule scripting (`src/autobattle/`) and Autogrind (`src/autogrind/`)
- Six worlds (Medieval, Suburban, Steampunk, Industrial, Futuristic/Digital, Abstract) with overworlds, villages and dungeons
- Save system with corruption mechanics, Scriptweaver game-constant edits
- Optional LLM-driven dialogue (`src/llm/`, off by default; scripted fallback)

## Quick Start

### Requirements
- [Godot 4.4+](https://godotengine.org/download) (`project.godot` declares feature `4.4`, Forward Plus)

### Running
- Open `project.godot` in Godot and press F5 (main scene: `src/GameLoop.tscn`), or run `./launch.sh`.
- Headless tests: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit` (see `test/README.md`).

## Battle Controls (keyboard)

| Action | Key | Pad |
|---|---|---|
| Advance (queue an action, costs 1 AP) | W | R shoulder |
| Defer (skip, +1 AP, reduced damage) | Q | L shoulder |
| Battle speed (tap faster / hold slower) | ` (backtick) | top face button |

Full table and the in-battle hint bar rules: `CLAUDE.md` (Controls section).

### Battle speed
Ladder: **1x / 1.5x / 2x / 4x / 8x / 16x / 32x / 64x**, default **1.5x**
(`BattleScene.BATTLE_SPEED_LABELS`, `DEFAULT_BATTLE_SPEED_INDEX`).

## Jobs

| Type | Jobs |
|---|---|
| Starter | Fighter, Cleric, Mage, Rogue, Bard |
| Advanced | Guardian, Ninja, Summoner, Speculator |
| Meta | Scriptweaver, Time Mage, Necromancer, Bossbinder, Skiptrotter |

Old IDs `white_mage` / `black_mage` / `thief` alias to `cleric` / `mage` / `rogue`
via `data/job_aliases.json`. Per-world names: `docs/job_evolutions_by_world.md`.

## Project Structure (top level)

```
project.godot        Godot project (main scene src/GameLoop.tscn)
CLAUDE.md            Living design + status document (authoritative for agents)
src/                 battle/, jobs/, autobattle/, autogrind/, exploration/, maps/,
                     meta/ (GameState, Version), save/, llm/, ui/, audio/, cutscene/, quests/ ...
data/                JSON data: jobs, abilities, monsters, items, equipment, locations,
                     music_manifest, job_world_names, cutscenes/, quests/, maps/ ...
assets/              sprites, audio, fonts
docs/                design canon, story bible, specs, design proposals
test/                headless test runner (unit/, smoke/, isolated/)
tools/, scripts/     build, screenshot and asset tooling
```

## Design Philosophy

1. **Automation is core gameplay** - Not a shortcut, but the point
2. **Exploitation is rewarded** - Clever abuse is celebrated
3. **Stakes must be real** - Consequences make choices meaningful
4. **Meta is diegetic** - Fourth-wall breaks are in-universe mechanics

## Contributing

Solo project by Carmelo Piccione (struktured). Design lives in `CLAUDE.md` and `docs/`.

## License

Not yet determined.

---

**Struktured Labs**
