extends GutTest

## A spotlight duel frees the live map inside _start_battle_async and, on victory,
## rebuilds it through _return_to_exploration. Random battles save the player's
## coordinates first, so the rebuild puts them back on the same tile. The duel
## path never did: Whispering Cave floor 3's up-stairs (where the Mage duel
## starts) is tile (11, 11); the rebuild's default marker is tile (12, 14).
## After the win you are standing somewhere else.

const GAME_LOOP := "res://src/GameLoop.gd"


class _StandingMap extends Node2D:
	var player: Node2D
	var current_floor: int = 1


func _loop() -> Node:
	var gl = load(GAME_LOOP).new()
	autofree(gl)
	return gl


func test_capture_records_the_tile_you_are_standing_on() -> void:
	var gl := _loop()
	assert_true(gl.has_method("_capture_duel_return_position"),
		"a duel must remember the live map position before the map is freed")
	if not gl.has_method("_capture_duel_return_position"):
		return
	var map := _StandingMap.new()
	autofree(map)
	var body := Node2D.new()
	autofree(body)
	body.position = Vector2(368, 368)  # floor-3 up-stairs, tile (11, 11) at 32px
	map.player = body
	map.current_floor = 3
	gl._exploration_scene = map
	gl._player_position = Vector2.ZERO
	gl._current_cave_floor = 1
	assert_true(gl._capture_duel_return_position(),
		"a live player on the map must be captured")
	assert_eq(gl._player_position, Vector2(368, 368),
		"the return latch must be the tile you were standing on, not the entrance marker")
	assert_eq(gl._current_cave_floor, 3,
		"the cave floor must travel with the position, or the rebuild opens the wrong floor")


func test_capture_leaves_a_saved_tile_alone_when_the_map_is_already_gone() -> void:
	# Retry: the first attempt already freed the map and stored the tile.
	# A second capture with no scene must not wipe it.
	var gl := _loop()
	if not gl.has_method("_capture_duel_return_position"):
		assert_true(false, "capture helper missing — retry cannot preserve the first attempt's tile")
		return
	gl._exploration_scene = null
	gl._player_position = Vector2(368, 368)
	assert_false(gl._capture_duel_return_position(),
		"no live map means there is nothing new to capture")
	assert_eq(gl._player_position, Vector2(368, 368),
		"a retry must keep the tile the first attempt saved")


func test_solo_battle_captures_before_teardown_and_drops_it_if_entry_is_refused() -> void:
	var src := FileAccess.get_file_as_string(GAME_LOOP)
	var i := src.find("func start_solo_battle")
	assert_gt(i, -1)
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 4000)
	var capture_at: int = body.find("_capture_duel_return_position()")
	var battle_at: int = body.find("_start_battle_async(")
	assert_gt(capture_at, -1, "start_solo_battle must capture the standing position")
	assert_gt(battle_at, -1)
	assert_lt(capture_at, battle_at,
		"the capture has to run BEFORE _start_battle_async frees the map")
	# The early "unavailable" returns (battle already active, no such job) sit above the capture.
	# The one that matters is the refused entry AFTER teardown was attempted.
	var drop: int = body.find("if remember_return:", battle_at)
	var refused: int = body.find("return \"unavailable\"", battle_at)
	assert_gt(drop, battle_at, "a refused entry must drop the latch it just wrote")
	assert_gt(refused, battle_at)
	assert_lt(drop, refused,
		"the drop belongs to the refused-entry branch — a started duel still needs the tile on victory")


func test_the_unlock_flag_is_set_before_the_map_is_rebuilt() -> void:
	var src := FileAccess.get_file_as_string(GAME_LOOP)
	var ended: int = src.find("func _on_battle_ended")
	var flag_at: int = src.find("cutscene_flag_spotlight_unlocked_", ended)
	var emit_at: int = src.find("spotlight_battle_ended.emit", ended)
	assert_gt(flag_at, ended)
	assert_lt(flag_at, emit_at,
		"the duel completion flag has to be set before the victory signal, which is what rebuilds the map")
	var solo: int = src.find("func start_solo_battle")
	var wait_at: int = src.find("await spotlight_battle_ended", solo)
	var rebuild_at: int = src.find("_return_to_exploration", wait_at)
	var cool_at: int = src.find("_cutscene_cooldown = true", wait_at)
	assert_lt(wait_at, cool_at, "the rebuild waits until the flag write has already run")
	assert_lt(cool_at, rebuild_at, "cooldown is on before the rebuild asks which cutscene is pending")
	var explore: int = src.find("func _start_exploration")
	var place_at: int = src.find("scene_player.position = restored_tile", explore)
	var swallow_at: int = src.find("_swallow_return_tile_triggers", place_at)
	var next_fn: int = src.find("\nfunc ", explore + 1)
	assert_gt(place_at, explore)
	assert_lt(swallow_at, next_fn,
		"the restore has to swallow the stair and gate overlap, or standing on the trigger tile fires it")


const CAVE := "res://src/maps/dungeons/WhisperingCave.gd"

var _saved_constants: Dictionary = {}


func before_each() -> void:
	_saved_constants = GameState.game_constants.duplicate(true) if GameState else {}
	if GameState:
		GameState.game_constants.erase("whispering_cave_floor")


func after_each() -> void:
	if GameState:
		GameState.game_constants = _saved_constants.duplicate(true)


func _cave(floor_num: int) -> Node:
	if GameState:
		GameState.game_constants.erase("whispering_cave_floor")
		var flags: Variant = GameState.game_constants.get("dungeon_flags", {})
		if flags is Dictionary:
			(flags as Dictionary).erase("cave_rat_king_defeated")
	var cave = load(CAVE).new()
	cave.current_floor = floor_num
	add_child_autofree(cave)
	await get_tree().process_frame
	if cave.get("controller") != null:
		cave.controller.encounter_enabled = false
	return cave


func _settle_floor_change() -> void:
	# _transition_to_floor keeps timers after it has already changed the floor.
	await get_tree().create_timer(1.0).timeout


func test_restoring_onto_the_up_stairs_does_not_climb_and_a_later_step_does() -> void:
	var bare = await _cave(3)
	var stairs: Vector2 = bare.spawn_points["stairs_up"]
	assert_eq(bare.current_floor, 3)
	bare.player.position = stairs
	for _i in 4:
		await get_tree().physics_frame
	assert_eq(bare.current_floor, 4,
		"control: placing the player on the floor-3 up-stairs must climb, or a green swallow proved nothing")
	await _settle_floor_change()
	var cave = await _cave(3)
	var back: Vector2 = cave.spawn_points["stairs_up"]
	cave.player.position = back
	await _loop()._swallow_return_tile_triggers(cave, cave.player)
	for _i in 4:
		await get_tree().physics_frame
	assert_eq(cave.current_floor, 3,
		"the victory rebuild stands on the stair the duel started on and must not take the next floor")
	cave.player.position = cave.spawn_points["default"]
	for _i in 3:
		await get_tree().physics_frame
	cave.player.position = back
	for _i in 4:
		await get_tree().physics_frame
	assert_eq(cave.current_floor, 4,
		"walking off the stair and back on must still climb — the swallow is only the overlap you spawned inside")
	await _settle_floor_change()


func test_restoring_onto_the_floor1_exit_does_not_leave_and_a_later_step_does() -> void:
	var bare = await _cave(1)
	var exits: Array = []
	bare.area_transition.connect(func(map_id, _spawn): exits.append(str(map_id)))
	var gate: Vector2 = bare.spawn_points["stairs_down"]
	bare.player.position = gate
	for _i in 4:
		await get_tree().physics_frame
	assert_false(exits.is_empty(),
		"control: the floor-1 exit must fire when you are placed on it")
	exits.clear()
	var cave = await _cave(1)
	var left: Array = []
	cave.area_transition.connect(func(map_id, _spawn): left.append(str(map_id)))
	var door: Vector2 = cave.spawn_points["stairs_down"]
	cave.player.position = door
	await _loop()._swallow_return_tile_triggers(cave, cave.player)
	for _i in 4:
		await get_tree().physics_frame
	assert_eq(left.size(), 0,
		"returning onto the cave exit must not walk the party out of the cave")
	cave.player.position = cave.spawn_points["default"]
	for _i in 3:
		await get_tree().physics_frame
	cave.player.position = door
	for _i in 4:
		await get_tree().physics_frame
	assert_eq(left.size(), 1,
		"leaving the exit and stepping back on must still leave the cave")
