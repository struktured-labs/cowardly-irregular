extends GutTest

## DungeonPuzzleLayer regression (struktured 2026-09-06, "counter-intuitive dungeons").
## Portal pairing, wrap, flip-switch walkability, trap encounters, mimic chests and
## switch-state persistence -- the reusable puzzle layer ANY dungeon can opt into.

const ContrarianDepthsScript = preload("res://src/maps/dungeons/ContrarianDepths.gd")
const MimicChestScript = preload("res://src/exploration/MimicChest.gd")

var _saved_constants: Dictionary = {}
var _saved_forced_encounter: bool = false


func before_each() -> void:
	_saved_constants = GameState.game_constants.duplicate(true) if GameState else {}
	_saved_forced_encounter = EncounterSystem.forced_encounter_next_step if EncounterSystem else false


func after_each() -> void:
	if GameState:
		GameState.game_constants = _saved_constants.duplicate(true)
	if EncounterSystem:
		EncounterSystem.forced_encounter_next_step = _saved_forced_encounter


func _isolated_viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	return vp


func _build_cave() -> Node:
	var cave = ContrarianDepthsScript.new()
	var vp := _isolated_viewport()
	vp.add_child(cave)
	return cave


## ---- portal pairing ----

func test_portal_ids_appear_exactly_twice_or_have_a_cross_floor_link() -> void:
	var layouts := {
		1: ["aa", ".."],
		2: ["..", ".."],
	}
	var errors := DungeonPuzzleLayer.validate_portal_pairs(layouts, {})
	assert_eq(errors.size(), 0, "two 'a' occurrences on one floor auto-pair: %s" % str(errors))


func test_a_lone_portal_needs_an_explicit_link_override() -> void:
	var layouts := {1: ["a.", ".."]}
	var broken := DungeonPuzzleLayer.validate_portal_pairs(layouts, {})
	assert_gt(broken.size(), 0, "a single 'a' occurrence with no portal_links override must be flagged")
	var fixed := DungeonPuzzleLayer.validate_portal_pairs(layouts, {"a": {"floor": 2, "cell": [0, 0]}})
	assert_eq(fixed.size(), 0, "the same lone portal is valid once portal_links names its twin")


func test_contrarian_depths_own_portals_pass_validation() -> void:
	var cave := _build_cave()
	var errors := DungeonPuzzleLayer.validate_portal_pairs(cave.floor_layouts, cave.portal_links)
	assert_eq(errors, [], "The Backwards Warren's own portal table must be internally consistent: %s" % str(errors))


func test_portal_destination_resolves_the_cross_floor_twin() -> void:
	var cave := _build_cave()
	# floor3's 'b' is the twin of floor1's 'b' -- "down to go up".
	var dest := DungeonPuzzleLayer.portal_destination(cave.floor_layouts, cave.portal_links, 3, Vector2i(17, 3))
	assert_eq(int(dest.get("floor", -1)), 1, "portal 'b' on floor3 must resolve to floor1")
	assert_eq(dest.get("cell"), Vector2i(15, 2), "portal 'b' must land on floor1's vault cell")


## ---- edge wrap ----

func test_wrap_moves_the_player_to_the_opposite_edge() -> void:
	var cave := _build_cave()
	await get_tree().process_frame
	assert_true(2 in (cave.wrap_floors as Array), "floor 2 must be a wrap floor")
	cave.current_floor = 2
	var w: float = float(cave.MAP_WIDTH * cave.TILE_SIZE)
	cave.player.position = Vector2(w + 5.0, 40.0)
	cave._puzzle_layer._process(0.0)
	assert_almost_eq(cave.player.position.x, 5.0, 0.5, "walking off the east edge must reappear near the west edge")

	cave.player.position = Vector2(-5.0, 40.0)
	cave._puzzle_layer._process(0.0)
	assert_almost_eq(cave.player.position.x, w - 5.0, 0.5, "walking off the west edge must reappear near the east edge")


func test_wrap_does_nothing_on_a_non_wrap_floor() -> void:
	var cave := _build_cave()
	await get_tree().process_frame
	cave.current_floor = 1
	var w: float = float(cave.MAP_WIDTH * cave.TILE_SIZE)
	var out_of_bounds := Vector2(w + 5.0, 40.0)
	cave.player.position = out_of_bounds
	cave._puzzle_layer._process(0.0)
	assert_eq(cave.player.position, out_of_bounds, "floor 1 is not a wrap floor -- position must be untouched")


## ---- flip switches ----

func test_flip_switch_changes_walkability_of_its_cells() -> void:
	var layouts := {1: ["MMM", "M.M", "MMM"]}
	var effects := {"sw0": {"flip": [[1, 0]]}}
	assert_false(DungeonPuzzleLayer.is_walkable(layouts, effects, 1, Vector2i(1, 0), {}),
		"before activation the flip cell is still a wall")
	assert_true(DungeonPuzzleLayer.is_walkable(layouts, effects, 1, Vector2i(1, 0), {"sw0": true}),
		"after activation the flip cell must read as walkable")


func test_contrarian_depths_lever_opens_the_vault_wall() -> void:
	var cave := _build_cave()
	var door_a := Vector2i(14, 3)
	var door_b := Vector2i(14, 4)
	assert_false(DungeonPuzzleLayer.is_walkable(cave.floor_layouts, cave.switch_effects, 3, door_a, {}),
		"the vault door starts sealed")
	assert_true(DungeonPuzzleLayer.is_walkable(cave.floor_layouts, cave.switch_effects, 3, door_a, {"sw2": true}),
		"sw2 (floor3's lever) must flip the vault door open")
	assert_true(DungeonPuzzleLayer.is_walkable(cave.floor_layouts, cave.switch_effects, 3, door_b, {"sw2": true}),
		"both door cells flip together")


func test_flip_switch_activation_repaints_the_live_tilemap() -> void:
	var cave := _build_cave()
	await get_tree().process_frame
	cave.current_floor = 3
	cave._generate_map_for_floor(3)
	var wall_cell := Vector2i(14, 3)
	var before_id: int = cave.tile_map.get_cell_source_id(wall_cell)
	var before_atlas: Vector2i = cave.tile_map.get_cell_atlas_coords(wall_cell)
	cave._puzzle_layer.activate_switch("sw2")
	var after_atlas: Vector2i = cave.tile_map.get_cell_atlas_coords(wall_cell)
	assert_ne(after_atlas, before_atlas,
		"activating sw2 must repaint the vault door tile (was %s, still %s)" % [str(before_atlas), str(after_atlas)])
	assert_eq(after_atlas, cave._get_atlas_coords(TileGeneratorClass.TileType.CAVE_FLOOR),
		"the door tile must become the CAVE_FLOOR atlas coords")
	assert_eq(before_id, cave.tile_map.get_cell_source_id(wall_cell), "sanity: the tile source id itself is unchanged (same atlas source, different coords)")


## ---- trap switches ----

func test_trap_switch_sets_forced_encounter_next_step() -> void:
	var cave := _build_cave()
	await get_tree().process_frame
	EncounterSystem.forced_encounter_next_step = false
	cave.current_floor = 3
	cave._generate_map_for_floor(3)
	cave._puzzle_layer.activate_switch("sw3")  # floor3's decoy plate: flip + trap:encounter
	assert_true(EncounterSystem.forced_encounter_next_step,
		"sw3 is a trap switch (effect includes 'trap': 'encounter') -- it must arm a forced encounter")


func test_trap_warp_switch_moves_the_player_without_touching_the_encounter_flag() -> void:
	var cave := _build_cave()
	await get_tree().process_frame
	EncounterSystem.forced_encounter_next_step = false
	cave.current_floor = 2
	cave._generate_map_for_floor(2)
	var before_pos: Vector2 = cave.player.position
	cave._puzzle_layer.activate_switch("sw1")  # floor2's plate: trap:warp only
	await get_tree().create_timer(0.05).timeout
	assert_false(EncounterSystem.forced_encounter_next_step, "a warp trap is not an encounter trap")
	assert_ne(cave.player.position, before_pos, "trap:warp must relocate the player onto a portal")


## ---- mimic chests ----

func test_mimic_chest_opens_into_a_battle_not_loot() -> void:
	var chest := MimicChestScript.new()
	chest.chest_id = "zz_test_mimic_%d" % Time.get_ticks_usec()
	chest.mimic_monster_id = "treasure_mimic"
	# A real DragonCave-family instance (never added to the tree) so
	# cave_ref.battle_triggered.emit(...) hits a script-declared signal --
	# add_user_signal() on a bare Node has no property-style accessor.
	var fake_cave := ContrarianDepthsScript.new()
	autofree(fake_cave)
	chest.cave_ref = fake_cave
	add_child_autofree(chest)

	var loot_fired := [false]
	chest.chest_opened.connect(func(_c): loot_fired[0] = true)
	var battle_enemies := []
	var battle_fired := [false]
	fake_cave.battle_triggered.connect(func(enemies):
		battle_fired[0] = true
		battle_enemies.append_array(enemies)
	)

	chest._open_chest(null)
	await get_tree().create_timer(0.7).timeout

	assert_true(GameState.get_story_flag("chest_" + chest.chest_id), "the mimic chest must mark itself opened so it cannot re-ambush")
	assert_false(loot_fired[0], "a mimic chest must never emit chest_opened (that would grant loot)")
	assert_true(battle_fired[0], "a mimic chest must trigger a battle")
	assert_eq(battle_enemies, ["treasure_mimic"], "the battle must be fought against the mimic monster id")


## ---- switch persistence ----

func test_switch_state_persists_and_reloads() -> void:
	var cave := _build_cave()
	await get_tree().process_frame
	cave.current_floor = 3
	cave._generate_map_for_floor(3)
	cave._puzzle_layer.activate_switch("sw2")

	var saved: Dictionary = GameState.game_constants.get(str(cave.cave_id) + "_switches", {})
	assert_true(bool(saved.get("sw2", false)), "activation must persist into game_constants[cave_id + \"_switches\"]")

	# A brand new puzzle layer on a fresh cave instance reloads the SAME state.
	var cave2 := _build_cave()
	await get_tree().process_frame
	assert_true(bool(cave2._puzzle_layer._active.get("sw2", false)),
		"a freshly-attached puzzle layer must reload persisted switch state")


func test_reveal_effect_gates_a_portal_until_its_switch_fires() -> void:
	var cave := _build_cave()
	await get_tree().process_frame
	cave.current_floor = 1
	cave._generate_map_for_floor(1)
	assert_false(DungeonPuzzleLayer.portal_usable(cave.switch_effects, cave.floor_layouts, 1, Vector2i(18, 4), {}),
		"portal 'c' is gated by sw0's reveal until thrown")
	cave._puzzle_layer.activate_switch("sw0")
	assert_true(DungeonPuzzleLayer.portal_usable(cave.switch_effects, cave.floor_layouts, 1, Vector2i(18, 4), cave._puzzle_layer._active),
		"portal 'c' must become usable once sw0 (its reveal switch) fires")


## ---- Skiptrotter bypass ----

func test_bypass_puzzle_resolves_every_non_trap_switch_dungeon_wide() -> void:
	GameState.game_constants["meta_auto_solve_puzzle_pending"] = true
	var cave := _build_cave()
	await get_tree().process_frame
	assert_false(bool(GameState.game_constants.get("meta_auto_solve_puzzle_pending", false)),
		"the pending flag must be consumed on the first floor build")
	assert_true(bool(cave._puzzle_layer._active.get("sw0", false)), "sw0 (a reveal switch) must be auto-solved")
	assert_true(bool(cave._puzzle_layer._active.get("sw2", false)), "sw2 (a flip switch, on a floor never visited yet) must be auto-solved dungeon-wide")
	assert_false(bool(cave._puzzle_layer._active.get("sw3", false)), "sw3 carries a trap -- bypass must NOT auto-solve it")


const TileGeneratorClass = preload("res://src/exploration/TileGenerator.gd")
