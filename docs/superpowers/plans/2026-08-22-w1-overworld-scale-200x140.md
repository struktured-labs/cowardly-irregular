# W1 Overworld Scale + Biome Encounters + W2-W6 PNG Migration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-author W1's overworld from 100x140 tiles to 200x140 with composition that forces routing, make encounter zones read the painted biome instead of hardcoded rectangles, and migrate W2-W6 from procedural generation to the PNG pipeline.

**Architecture:** The PNG map pipeline already landed (train A). W1 loads `data/maps/overworld_w1.png` through `MapImageLoader.load_rows()`, one pixel per tile, decoded against `data/maps/map_palette.json`. This plan grows that image to 200x140, and replaces `_get_zone_for_tile`'s absolute-coordinate quadrant rects with a lookup on the painted terrain character — so biome and encounter zone become the same authored fact. W2-W6 then adopt the same loader.

**Tech Stack:** Godot 4 / GDScript · GUT tests via `tools/run_tests.sh` · Python 3 + Pillow for `tools/map_ascii_to_png.py`

**Spec:** No separate spec doc. This plan argues from struktured's ruling, recorded verbatim below so it does not live only in intercom — the failure that made this item invisible for six days.

## The Ruling (verbatim, recorded here so it survives)

Source: struktured, directly to cowir-main (cowir-main session, 2026-08-21 ~02:50 local), via an AskUserQuestion whose options were cowir-overworld's msg-5099 ladder. Relayed to this lane in intercom msg 6731/6732 with source, timestamp, mechanism and option text named.

- **Label he picked:** `4x — 200x140 (Recommended)`
- **Option text he saw:** *"28,000 tiles, ~27s to cross. Re-author composition (mountains/rivers force routing), biome-driven encounter zones, then W2-W6 to PNG."*
- **His framing, an hour earlier:** *"I had a conversation about making the overworld larger and richer but I feel like that never dropped."*
- **Earlier, on W2+:** *"it's also a mess in overworld 2+"*
- **Earlier, on scale:** *"like overworld is walkable in like 1 minute"* / *"Think of the size overworld 1 in FF6"* / *"not saying we need to get that large given we have several worlds, but closer to that"*

## Global Constraints

- **DO NOT touch `MODE7_GROUND_DISPLACEMENT_PX = 140.6`.** Playtested; the derivation says 137.08 and the constant wins. #16 (collision rework) stays PARKED.
- **Comments in `.gd` files: 1 line maximum.** Project rule.
- **Never `git stash`** in this repo — storage is repo-global across ~30 worktrees.
- **Gate with `tools/run_tests.sh`, capture `$?` BEFORE shaping output.** Full suite is 5-12 min; background it.
- **Single-file runs: gate on the presence of a `Passing N` line, not on `$?`** — the wrapper exits 0 with `Tests 0` when a named script parse-errors.
- **Sandbox every gate:** `export XDG_DATA_HOME="$PWD/tmp-xdg"` before `tools/run_tests.sh`.
- **Feature branch only** (`lane/w1-scale-200x140`); never commit to main. Push early and often.
- **Landmark spawn points derive from PNG pixel positions** through a single `_register_spawn_point` call site and follow the re-author for free. Only `spawn_points["default"]` is hardcoded.

## Measured Starting State (verified on origin/main `56e7c108`, 2026-08-22)

| Fact | Value | Location |
|---|---|---|
| Map size | 100 x 70 | `OverworldScene.gd:22-23` |
| Golden test fixture | `GOLDEN_W 100` / `GOLDEN_H 70` | `test_map_image_roundtrip.gd:23-24` |
| Default spawn (only hardcoded coord) | `Vector2(40*TILE+16, 25*TILE+16)` | `OverworldScene.gd:257` |
| Zone selection | 7 absolute tile rects | `OverworldScene.gd:495-516` |
| Zone → pool map | 7 entries | `OverworldScene.gd:520-528` |
| Pools defined in data | **8** | `data/enemy_pools.json` |
| **Orphaned pool** | `overworld_plains` — defined, mapped by nothing | — |
| Char grid after load | **local `var map_data`**, discarded | `OverworldScene.gd:229` |
| Terrain palette | 12 chars | `data/maps/map_palette.json` |
| Landmark palette | 13 chars | same |
| PNG-driven worlds | W1 only | `MapImageLoader` used by `OverworldScene.gd` alone |

**Correction to the earlier costing:** msg-6332 said "the code cost is 3 values." It is **5** — `MAP_WIDTH`, `MAP_HEIGHT`, `spawn_points["default"]`, `GOLDEN_W`, `GOLDEN_H`. The two test constants were not counted.

**Why the zone rects break at 200x140:** they are absolute, not proportional. `ty >= 50` selects the bottom 28% of a 70-row map and the bottom **64%** of a 140-row map, so desert and volcanic swallow most of the world; `tx >= 85` puts the coast band at 42% across instead of 85%. The map does not merely lose zones — it gets a badly wrong distribution.

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `src/exploration/OverworldScene.gd` | W1 scene: constants, spawn registry, zone selection | Modify — constants, default spawn, promote `map_data` to a member, replace `_get_zone_for_tile` |
| `data/maps/overworld_w1.png` | The authored map, 1px per tile | Replace — 200x140 |
| `data/maps/overworld_w1.txt` | ASCII source the PNG is generated from | Create/replace — the authoring surface |
| `test/unit/test_map_image_roundtrip.gd` | Golden size + palette census | Modify — `GOLDEN_W/H`, census expectations |
| `test/unit/test_biome_encounter_zones.gd` | Zone selection reads the biome char; every pool reachable | **Create** |
| `tools/map_ascii_to_png.py` | ASCII ⇄ PNG conversion | Reuse; extend only if the composition pass needs it |
| `src/exploration/{Suburban,Steampunk,Industrial,Futuristic,Abstract}Overworld.gd` | W2-W6 scenes | Modify — adopt `MapImageLoader` (Phase 3) |
| `data/maps/overworld_w{2..6}.png` | W2-W6 authored maps | Create (Phase 3) |

## Phasing

- **Phase 1 (Tasks 1-4):** biome-driven zones at the CURRENT 100x70 size. Ships a real fix (orphaned pool, distortion-proof zones) independently of any re-author, and de-risks the scale change.
- **Phase 2 (Tasks 5-7):** the 200x140 re-author.
- **Phase 3 (Tasks 8+):** W2-W6 PNG migration. Planned separately once Phase 2 lands — do not start it from this document.

---

### Task 1: Expose the painted character grid to the zone selector

**Files:**
- Modify: `src/exploration/OverworldScene.gd:229` (promote local `map_data` to a member), `:239-242` (read from the member)
- Test: `test/unit/test_biome_encounter_zones.gd` (create)

**Interfaces:**
- Produces: `var map_rows: Array[String]` — member on `OverworldScene`, one string per map row, each `MAP_WIDTH` characters, populated during `_generate_map()`. Empty until generation runs.
- Produces: `func biome_char_at(tx: int, ty: int) -> String` — returns the single painted character at that tile, or `""` when out of bounds or before generation.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

const SceneScript = preload("res://src/exploration/OverworldScene.gd")

func test_biome_char_at_returns_the_painted_character() -> void:
	var scene = SceneScript.new()
	add_child_autofree(scene)
	await wait_frames(2)
	assert_gt(scene.map_rows.size(), 0, "map_rows must be populated after generation -- otherwise every assert below is vacuous")
	assert_eq(scene.map_rows.size(), scene.MAP_HEIGHT, "one row per map row")
	var c: String = scene.biome_char_at(0, 0)
	assert_eq(c.length(), 1, "a single painted character, got %s" % [c])
	assert_eq(scene.biome_char_at(-1, 0), "", "out of bounds west returns empty")
	assert_eq(scene.biome_char_at(scene.MAP_WIDTH, 0), "", "out of bounds east returns empty")
	assert_eq(scene.biome_char_at(0, scene.MAP_HEIGHT), "", "out of bounds south returns empty")
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `cd <repo> && export XDG_DATA_HOME="$PWD/tmp-xdg" && tools/run_tests.sh biome_encounter_zones > tmp/t1.log 2>&1; echo "EC=$?"; grep -aE '^  (Tests|Passing|Failing)' tmp/t1.log`

Expected: a `Passing` line IS present (proving the script parsed and ran — the wrapper exits 0 with `Tests 0` on a parse error) and `Failing 1`, on `map_rows` not existing.

- [ ] **Step 3: Promote the grid to a member**

In `OverworldScene.gd`, replace the local declaration at `:229`:

```gdscript
# was: var map_data: Array[String] = []
map_rows.clear()
for row in MapImageLoaderScript.load_rows(MAP_IMAGE):
	map_rows.append(str(row))
```

Declare beside the other members (near `MAP_WIDTH`):

```gdscript
## The painted character grid, kept so encounter zones can read the authored biome
var map_rows: Array[String] = []
```

Replace every remaining `map_data` reference in `_generate_map()` with `map_rows`, and add:

```gdscript
func biome_char_at(tx: int, ty: int) -> String:
	if ty < 0 or ty >= map_rows.size():
		return ""
	var row: String = map_rows[ty]
	if tx < 0 or tx >= row.length():
		return ""
	return row[tx]
```

Note the `str(row)` coercion is load-bearing: assigning a generic Array to `Array[String]` is a script error that ABORTS the enclosing function.

- [ ] **Step 4: Run the test and confirm it passes**

Run the Step 2 command. Expected: `Passing 1`, no `Failing` line.

- [ ] **Step 5: Commit**

```bash
git add src/exploration/OverworldScene.gd test/unit/test_biome_encounter_zones.gd
git commit -m "feat(overworld): keep the painted grid so zones can read the authored biome"
```

---

### Task 2: Map every terrain character to a zone, and give `overworld_plains` a consumer

**Files:**
- Modify: `src/exploration/OverworldScene.gd:495-516` (replace `_get_zone_for_tile` body), `:520-532` (extend `pool_id_map` and `rate_map`)
- Test: `test/unit/test_biome_encounter_zones.gd`

**Interfaces:**
- Consumes: `biome_char_at(tx, ty) -> String` from Task 1.
- Produces: `const BIOME_ZONES: Dictionary` — painted char → zone name.
- Produces: `_get_zone_for_tile(tx: int, ty: int) -> String` — unchanged signature, coordinate-free implementation; returns `"central"` for any char with no explicit zone.

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_zone_follows_the_painted_char_not_the_coordinates() -> void:
	var scene = SceneScript.new()
	add_child_autofree(scene)
	await wait_frames(2)
	var seen := {}
	for ty in range(scene.MAP_HEIGHT):
		for tx in range(scene.MAP_WIDTH):
			var c := scene.biome_char_at(tx, ty)
			if c == "":
				continue
			var z: String = scene._get_zone_for_tile(tx, ty)
			if seen.has(c):
				assert_eq(z, seen[c], "char %s gave zone %s here and %s elsewhere -- zone must follow the char alone" % [c, z, seen[c]])
			else:
				seen[c] = z
	assert_gt(seen.size(), 3, "only %d distinct chars sampled -- the map scan did not run" % seen.size())

func test_every_defined_pool_is_reachable_from_some_zone() -> void:
	var scene = SceneScript.new()
	add_child_autofree(scene)
	await wait_frames(2)
	var raw := FileAccess.get_file_as_string("res://data/enemy_pools.json")
	var parsed = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "enemy_pools.json must parse")
	var defined := []
	for k in (parsed as Dictionary).keys():
		if str(k).begins_with("overworld_"):
			defined.append(str(k))
	assert_gt(defined.size(), 4, "only %d overworld pools found -- the scan broke" % defined.size())
	var mapped := scene._zone_pool_ids()
	for p in defined:
		assert_true(p in mapped, "pool %s is defined in data but no zone maps to it" % p)
	assert_false("overworld_zz_fabricated" in mapped, "a fabricated pool id is absent, so membership means something")
```

- [ ] **Step 2: Run and confirm both fail**

Run: `export XDG_DATA_HOME="$PWD/tmp-xdg" && tools/run_tests.sh biome_encounter_zones > tmp/t2.log 2>&1; echo "EC=$?"; grep -aE '^  (Tests|Passing|Failing)' tmp/t2.log`

Expected: `Failing 2` — the coordinate rects give one char two zones, and `overworld_plains` is unmapped.

- [ ] **Step 3: Replace the rects with a character lookup**

```gdscript
## Painted terrain char -> encounter zone; the authored biome IS the zone
const BIOME_ZONES := {
	"i": "ice", "F": "forest", "S": "swamp", "s": "desert",
	"l": "volcanic", "d": "volcanic", "c": "coast", "~": "coast",
	"g": "plains", ".": "central", "B": "central", "M": "central",
}

func _get_zone_for_tile(tx: int, ty: int) -> String:
	return BIOME_ZONES.get(biome_char_at(tx, ty), "central")

func _zone_pool_ids() -> Array:
	return _pool_id_map().values()
```

Extend the pool and rate maps, lifting them to a shared helper so the test can read them:

```gdscript
func _pool_id_map() -> Dictionary:
	return {
		"central": "overworld_central", "plains": "overworld_plains",
		"forest": "overworld_forest", "ice": "overworld_ice",
		"swamp": "overworld_swamp", "desert": "overworld_desert",
		"volcanic": "overworld_volcanic", "coast": "overworld_coast",
	}
```

In `_apply_zone_encounters`, replace the inline `pool_id_map` literal with `_pool_id_map()` and add `"plains": 0.05` to `rate_map`.

- [ ] **Step 4: Run and confirm both pass**

Run the Step 2 command. Expected: `Passing 3`, no `Failing` line.

- [ ] **Step 5: Verify the mutation actually discriminates**

Temporarily restore one coordinate rect at the top of `_get_zone_for_tile`:

```gdscript
	if tx < 30 and ty < 15: return "ice"
```

Run the Step 2 command. Expected: `Failing 1` on `test_zone_follows_the_painted_char_not_the_coordinates`. Then revert that line and re-run to confirm green. A ratchet nobody has watched go red is not yet evidence.

- [ ] **Step 6: Commit**

```bash
git add src/exploration/OverworldScene.gd test/unit/test_biome_encounter_zones.gd
git commit -m "fix(overworld): encounter zones read the painted biome, not tile rectangles"
```

---

### Task 3: Full gate on Phase 1

**Files:** none modified.

- [ ] **Step 1: Run the full suite, sandboxed and backgrounded**

```bash
export XDG_DATA_HOME="$PWD/tmp-xdg"; mkdir -p "$XDG_DATA_HOME"
tools/run_tests.sh > tmp/phase1.log 2>&1; echo "GATE_EC=$?" >> tmp/phase1.log
```

- [ ] **Step 2: Read the totals, then decide**

```bash
grep -aE '^  (Scripts|Tests|Passing|Failing|Risky|Asserts)|^GATE_EC' tmp/phase1.log
ls -d "$XDG_DATA_HOME/godot/app_userdata/Cowardly Irregular"   # sandbox artifact
```

Expected: `GATE_EC=0`, `Passing == Tests` (or `Passing + Risky == Tests`), no `Failing` line. If exactly one failure names `test_version_display_regression`, the branch is behind a release tag — rebase, do not hunt it.

- [ ] **Step 3: Push and report**

```bash
git push origin lane/w1-scale-200x140
```

Post the totals, the exit code, and the sandbox artifact to `cowir-irregular`.

---

### Task 4: Confirm zone coverage on the CURRENT map before scaling

**Files:**
- Test: `test/unit/test_biome_encounter_zones.gd`

- [ ] **Step 1: Add a coverage census**

```gdscript
func test_no_zone_covers_the_whole_map_and_none_is_empty() -> void:
	var scene = SceneScript.new()
	add_child_autofree(scene)
	await wait_frames(2)
	var counts := {}
	var total := 0
	for ty in range(scene.MAP_HEIGHT):
		for tx in range(scene.MAP_WIDTH):
			if scene.biome_char_at(tx, ty) == "":
				continue
			var z: String = scene._get_zone_for_tile(tx, ty)
			counts[z] = int(counts.get(z, 0)) + 1
			total += 1
	assert_gt(total, 1000, "only %d tiles sampled -- the census did not run" % total)
	for z in counts.keys():
		var share := float(counts[z]) / float(total)
		assert_lt(share, 0.90, "zone %s covers %d%% of the map -- one biome has swallowed it" % [z, int(share * 100.0)])
```

- [ ] **Step 2: Run it**

Run the Task 2 Step 2 command. Expected: PASS, and the log records the per-zone census for comparison after the re-author.

- [ ] **Step 3: Commit**

```bash
git add test/unit/test_biome_encounter_zones.gd
git commit -m "test(overworld): census guards against one biome swallowing the map"
```

---

### Task 5: Author the 200x140 ASCII map

**Files:**
- Create: `data/maps/overworld_w1.txt` (200 chars x 140 lines)
- Modify: `src/exploration/OverworldScene.gd:22-23` (`MAP_WIDTH 200`, `MAP_HEIGHT 140`), `:257` (default spawn)
- Modify: `test/unit/test_map_image_roundtrip.gd:23-24` (`GOLDEN_W 200`, `GOLDEN_H 140`)

**Interfaces:**
- Consumes: the palette chars in `data/maps/map_palette.json` — 12 terrain, 13 landmarks.
- Produces: `data/maps/overworld_w1.png`, 200x140, one pixel per tile.

**Composition requirements** (from the option struktured picked):
- Grass (`g`) fill as the base.
- Mountain ranges (`M`) and water (`~`) that **force routing** — the current map is ~48% open, so a walker crosses it in a straight line. Ranges must make at least one landmark reachable only by a detour.
- Coast (`c`) along one or more edges; rivers (`~`) with bridges (`B`) at the crossings.
- All 13 landmark characters placed, with room between them.
- Biome regions large enough that each of the 8 zones gets a meaningful share (Task 4's census guards this).

- [ ] **Step 1: Move the three constants and the default spawn**

```gdscript
const MAP_WIDTH: int = 200
const MAP_HEIGHT: int = 140
```

Default spawn — keep it proportionally central and on a walkable tile:

```gdscript
	spawn_points["default"] = Vector2(80 * TILE_SIZE + TILE_SIZE / 2, 50 * TILE_SIZE + TILE_SIZE / 2)
```

And in the test:

```gdscript
const GOLDEN_W := 200
const GOLDEN_H := 140
```

- [ ] **Step 2: Author the ASCII and generate the PNG**

Write `data/maps/overworld_w1.txt`, then:

```bash
python3 tools/map_ascii_to_png.py data/maps/overworld_w1.txt data/maps/overworld_w1.png
python3 -c "from PIL import Image; im=Image.open('data/maps/overworld_w1.png'); print(im.size)"
```

Expected: `(200, 140)`.

- [ ] **Step 3: Run the roundtrip and census tests**

```bash
export XDG_DATA_HOME="$PWD/tmp-xdg"
tools/run_tests.sh map_image_roundtrip > tmp/t5a.log 2>&1; grep -aE '^  (Tests|Passing|Failing)' tmp/t5a.log
tools/run_tests.sh biome_encounter_zones > tmp/t5b.log 2>&1; grep -aE '^  (Tests|Passing|Failing)' tmp/t5b.log
```

Expected: both green, with a `Passing N` line present in each. The census must show no zone above 90%.

- [ ] **Step 4: Verify every landmark spawn resolved**

```bash
tools/run_tests.sh transition_reachability_regression > tmp/t5c.log 2>&1; grep -aE '^  (Tests|Passing|Failing)' tmp/t5c.log
tools/run_tests.sh village_dungeon_spawn_overlap_regression > tmp/t5d.log 2>&1; grep -aE '^  (Tests|Passing|Failing)' tmp/t5d.log
```

Both must pass. `village_dungeon_spawn_overlap` is the ratchet that caught the CrossCode elevation bug — it asserts no spawn shares a cell with a dungeon or cliff collider, and a re-authored map is exactly the change it exists for.

- [ ] **Step 5: Commit and push**

```bash
git add data/maps/overworld_w1.txt data/maps/overworld_w1.png data/maps/overworld_w1.png.import \
        src/exploration/OverworldScene.gd test/unit/test_map_image_roundtrip.gd
git commit -m "feat(overworld): W1 re-authored at 200x140 with routing terrain"
git push origin lane/w1-scale-200x140
```

Ping `cowir-irregular` — struktured asked to be told when the first 200x140 PNG renders.

---

### Task 6: Walk the map in-engine and check the traversal claim

**Files:** none modified (measurement task).

The option he picked promises "~27s to cross." That is a claim about the artifact, and it should be measured rather than asserted.

- [ ] **Step 1: Compute the crossing time from the real constants**

```bash
grep -n 'move_speed' src/exploration/OverworldPlayer.gd | head -3
```

Crossing time = `MAP_WIDTH * TILE_SIZE / move_speed`. At 200 tiles x 32 px / 240 px-s⁻¹ this is ~26.7s, before terrain penalties. Record the measured number.

- [ ] **Step 2: Launch and look**

```bash
setsid godot < /dev/null > tmp/godot.stdout 2>&1 &
```

Confirm the map renders, the routing terrain reads as intended, and landmarks are reachable. Screenshot with F12 if reporting visually.

- [ ] **Step 3: Report the measured crossing time**

Post to `cowir-irregular` with the computed figure and whether the routing terrain actually forces a detour, or whether a straight-line walk still works.

---

### Task 7: Full gate on Phase 2

**Files:** none modified.

- [ ] **Step 1: Rebase onto current main first**

```bash
git fetch origin && git rebase origin/main
```

- [ ] **Step 2: Fresh worktree, cold import, sandboxed gate**

```bash
git worktree add --detach tmp/wt-gate HEAD
cd tmp/wt-gate
export XDG_DATA_HOME="$PWD/tmp-xdg"; mkdir -p "$XDG_DATA_HOME"
godot --headless --audio-driver Dummy --import --quit > ../import.log 2>&1; echo "import EC=$?"
tools/run_tests.sh > ../gate.log 2>&1; echo "GATE_EC=$?" >> ../gate.log
```

A fresh worktree is unimported; without `--import`, `res://` does not resolve and the run is vacuous.

- [ ] **Step 3: Read totals and re-check the artifact AFTER the gate**

```bash
grep -aE '^  (Scripts|Tests|Passing|Failing|Risky)|^GATE_EC' ../gate.log
python3 -c "from PIL import Image; print(Image.open('data/maps/overworld_w1.png').size)"
grep -c 'MAP_WIDTH: int = 200' src/exploration/OverworldScene.gd
```

Merge-clean, gate-green and artifact-present are three separate claims. A green suite on a tree that lost the map during a rebase reads identically to one that kept it.

- [ ] **Step 4: Push and hand off**

```bash
git push --force-with-lease origin lane/w1-scale-200x140
```

Post the SHA, totals, exit code, sandbox artifact and the post-gate artifact check to `cowir-irregular` for cowir-main's fold train.

---

## Phase 3: W2-W6 PNG migration

Not planned in this document. Once Phase 2 lands, write `docs/superpowers/plans/<date>-w2-w6-png-migration.md` covering: one `overworld_w{2..6}.png` per world, each scene adopting `MapImageLoaderScript` in place of its procedural generator, per-world palettes where the biome vocabulary differs (W6 is abstract and may need its own), and Industrial's ragged 59/60 rows fixed as part of the conversion. The five scenes share a shape, so the plan should be five instances of one task rather than five bespoke ones.

## Self-Review

**Spec coverage.** Scale to 200x140 → Task 5. Composition forcing routing → Task 5 requirements + Task 6 verification. Biome-driven encounter zones → Tasks 1-2. W2-W6 to PNG → Phase 3, deliberately deferred to its own plan. The three scope additions cowir-main raised: encounter rects → Task 2; `GOLDEN_W/H` + default spawn → Task 5; W2-W6 → Phase 3. All covered.

**Placeholder scan.** No TBDs. Every code step carries the actual GDScript or shell. Task 5's ASCII authoring is the one step whose content cannot be written in advance — it is creative composition against stated, checkable requirements, and Tasks 4 and 5 Step 3 are the tests that judge it.

**Type consistency.** `map_rows: Array[String]` (Task 1) is read by `biome_char_at` (Task 1) and consumed by `_get_zone_for_tile` (Task 2). `_pool_id_map() -> Dictionary` (Task 2) is used by `_zone_pool_ids() -> Array` (Task 2) and by `_apply_zone_encounters` (existing). `_get_zone_for_tile(int, int) -> String` keeps its original signature, so its existing caller at `:484` is unchanged.

**Known gap, stated rather than hidden.** The frame arm of `test_terrain_speed_frame_and_semantics_regression` is structurally discriminating and carries its own vacuity floor, but has never been observed red. Re-authoring the map changes which tiles that test samples, so Phase 2 is a natural moment to run the frame-only mutation and close it.

---

## Outcome, 2026-08-22

**Fold 1 (scale) and fold 2 (composition) are both landed** on `lane/w1-scale-200x140`.

| | before | after |
|---|---|---|
| tiles | 7,000 (100x70) | 28,000 (200x140) |
| crossing | 13.3s straight | 35.3s, detour ratio 1.332 |
| walkable components | 6 | 1 continent + 4 empty pockets |
| landmarks unreachable on foot | 5 | 0 |

### The defect fold 2 found, which was not in this plan

Component analysis of walkable space found **three sealed enclaves holding five
landmarks** — Glacius + Frosthold behind mountain, Pyrroth + Ironhaven behind lava, a
hidden passage in a 5-cell pocket. Two of the four W1 elemental dragon bosses were
unreachable on foot; only `TeleportMenu` got a player there, which is why it survived
since the ASCII map. Verified pre-existing (the same five landmarks at exactly half the
coordinates on 100x70), so the upscale reproduced it faithfully rather than causing it.

`SPAWN_CLEARANCE` moves an arrival off its landmark pixel, so opening an enclave is
necessary and not sufficient — all 15 arrivals are re-checked with the clearance applied.

---

## Phase 3 scope: W2-W6. NOT started, deliberately.

Measured 2026-08-22, same instruments:

| world | tiles | crossing | detour ratio |
|---|---|---|---|
| W1 medieval | 28,000 | 35.3s | 1.332 |
| W2 suburban | 2,000 | 6.5s | 1.000 |
| W3 steampunk | 3,000 | 7.9s | 1.000 |
| W4 industrial | 2,700 | 7.9s | 1.000 |
| W5 futuristic | 2,475 | — | — (both edges solid border) |
| W6 abstract | 1,400 | 5.2s | 1.000 |

**W1 is now 14x W2's tile count, and every one of W2-W6 is straight-line crossable.**
struktured's note — *"its also a mess in overworld 2+ last I checked"* — is these two rows.

Connectivity is NOT the problem there: every island in W2-W6 is empty terrain
(`tools/audit_overworld_connectivity.py`). W1's enclave defect does not repeat.

**The enabler is the PNG migration.** W2-W6 carry their maps as ASCII literals inside
their `.gd` files, so scaling one means hand-editing thousands of characters in source.
`tools/map_ascii_to_png.py` + `MapImageLoader` already do this for W1; the palette is
per-world (five different vocabularies — W6's blockers `BDES` share not one letter with
W2's `befhmtwy`), so `map_palette.json` needs a per-world section rather than one table.

Order: migrate to PNG → scale → compose. Same three folds W1 took, and the ratchets
(`test_map_image_roundtrip`, `test_overworld_composition`) generalise to each world.
