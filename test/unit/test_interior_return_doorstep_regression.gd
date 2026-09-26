extends GutTest

## Walking out of a shared inn or shop used to drop you at the village entrance.
##
## InnInterior, ShopInterior and BlacksmithInterior exit through "village_return"
## with spawn names (inn_exit / shop_exit / blacksmith_exit) that no village
## registers. GameLoop rewrote that spawn to "default", and "default" is the
## gate you came in from the overworld. Leave the Sleepy Slime Inn in Harmonia
## and you appeared on the south road, a dozen tiles from the door.
##
## The doorstep is the tile you were actually standing on when you walked in.
## These tests build the real villages, stand on a real walkable cell beside the
## real building, and require the return to put you back there — still facing
## the building, not inside a wall, and not on the auto-exit that leads out of town.


var _gl: Node = null
var _saved_flags: Dictionary = {}
var _saved_world: int = 1
var _saved_mode7: bool = false
var _saved_party: Array = []
var _saved_pool: Dictionary = {}
var _saved_map: String = ""
var _saved_pending: Vector2 = Vector2.INF


func before_each() -> void:
	_gl = load("res://src/GameLoop.gd").new()
	_saved_flags = GameState.story_flags.duplicate() if GameState else {}
	_saved_world = int(GameState.current_world) if GameState else 1
	_saved_mode7 = Mode7Overlay.is_active
	_saved_party = GameState.player_party.duplicate(true) if GameState else []
	_saved_pool = GameState.equipment_pool.duplicate(true) if GameState else {}
	_saved_map = str(MapSystem.current_map_id) if MapSystem else ""
	_saved_pending = SaveSystem.pending_player_position if SaveSystem else Vector2.INF


func after_each() -> void:
	if _gl != null:
		_gl.free()
		_gl = null
	if GameState:
		GameState.story_flags = _saved_flags.duplicate()
		GameState.current_world = _saved_world
		GameState.player_party.clear()
		for entry in _saved_party:
			if entry is Dictionary:
				GameState.player_party.append(entry)
		GameState.equipment_pool = _saved_pool.duplicate(true)
	if MapSystem:
		MapSystem.current_map_id = _saved_map
	if SaveSystem:
		SaveSystem.pending_player_position = _saved_pending
	Mode7Overlay.is_active = _saved_mode7


func _isolated_viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	return vp


func _build(path: String):
	var village = load(path).new()
	_isolated_viewport().add_child(village)
	await get_tree().process_frame
	return village


## A walkable cell beside the building. The building's own origin often sits on a wall tile.
func _doorstep(village, marker: Vector2) -> Vector2:
	var tile: float = float(village.TILE_SIZE)
	var origin := Vector2i(int(floor(marker.x / tile)), int(floor(marker.y / tile)))
	var best := Vector2.INF
	var best_d := INF
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var cell := origin + Vector2i(dx, dy)
			if not village._is_cell_walkable(cell):
				continue
			var centre := Vector2(cell.x * tile + tile * 0.5, cell.y * tile + tile * 0.5)
			var d := centre.distance_squared_to(marker)
			if d < best_d:
				best_d = d
				best = centre
	return best


func _facing_toward(stand: Vector2, marker: Vector2) -> int:
	var delta := marker - stand
	if absf(delta.x) > absf(delta.y):
		return OverworldPlayer.Direction.LEFT if delta.x < 0.0 else OverworldPlayer.Direction.RIGHT
	return OverworldPlayer.Direction.UP if delta.y < 0.0 else OverworldPlayer.Direction.DOWN


func _find_inn(village) -> Node2D:
	for child in village.buildings.get_children():
		if child is VillageInn:
			return child
	return null


func _find_shop(village, shop_type: int) -> Node2D:
	for child in village.buildings.get_children():
		if child is VillageShop and int(child.shop_type) == shop_type:
			return child
	return null


func _round_trip(village, village_id: String, interior_id: String, exit_spawn: String, doorstep: Vector2, facing: int) -> Dictionary:
	village.player.position = doorstep
	village.player.current_direction = facing
	_gl._current_map_id = village_id
	_gl._exploration_scene = village
	_gl._clear_interior_doorstep()
	var entered: Dictionary = _gl._route_area_transition(interior_id, "entrance")
	assert_eq(entered["position"], Vector2.ZERO,
		"walking in must leave the interior on its own entrance spawn, not the village tile")
	assert_true(_gl._has_interior_return, "the doorstep is captured on the way in — %s" % interior_id)
	assert_eq(str(_gl._village_origin_id), village_id)
	# The live body after the fade is the interior's player. Shoving it must not move the return tile.
	village.player.position = Vector2(8000, 8000)
	village.player.current_direction = OverworldPlayer.Direction.LEFT
	_gl._current_map_id = interior_id
	return _gl._route_area_transition("village_return", exit_spawn)


func _assert_back_at_the_door(village, back: Dictionary, doorstep: Vector2, facing: int) -> void:
	var gate: Vector2 = village.spawn_points["default"]
	assert_eq(str(back["map"]), str(village._get_area_id()))
	assert_eq(str(back["spawn"]), "default",
		"the unregistered inn_exit/shop_exit name is still replaced — villages do not have that key")
	assert_eq(back["position"], doorstep,
		"return tile %s is the village gate %s — walked out of the building and appeared at the entrance" % [str(back["position"]), str(gate)])
	assert_eq(int(back["facing"]), facing, "you come back facing the building you just left")
	assert_false(_gl._has_interior_return, "the doorstep is consumed by the exit so the next trip can capture a different door")
	assert_gt(doorstep.distance_to(gate), float(village.TILE_SIZE) * 4.0,
		"this building's door and the village gate are the same spot — the test would pass by standing on the bug")

	village.spawn_player_at("default")
	var arrived_at_gate: Vector2 = village.player.position
	assert_lt(arrived_at_gate.distance_to(gate), 1.0, "spawn \"default\" really is the gate this village uses")
	village.player.position = back["position"]
	_gl._pending_facing = int(back["facing"])
	_gl._apply_pending_facing(village.player)
	assert_eq(village.player.position, doorstep)
	assert_eq(int(village.player.current_direction), facing)
	var tile: float = float(village.TILE_SIZE)
	var cell := Vector2i(int(floor(village.player.position.x / tile)), int(floor(village.player.position.y / tile)))
	assert_true(village._is_cell_walkable(cell),
		"returned on a blocked cell %s — stuck in a wall beside the door" % str(cell))
	var areas: Array[Area2D] = []
	_gl._collect_areas(village, areas)
	for area in areas:
		if area is AreaTransition and not (area as AreaTransition).require_interaction:
			assert_false(_gl._return_point_in_area(area, village.player.global_position),
				"returned inside auto-exit '%s' — the town gate fires the moment you leave the building" % area.name)


func test_leaving_harmonia_inn_and_smith_puts_you_back_at_each_door() -> void:
	var village = await _build("res://src/maps/villages/HarmoniaVillage.gd")
	var inn := _find_inn(village)
	var smith := _find_shop(village, VillageShop.ShopType.BLACKSMITH)
	assert_not_null(inn, "Harmonia builds its inn")
	assert_not_null(smith, "Harmonia builds its blacksmith")
	var inn_step := _doorstep(village, inn.position)
	var smith_step := _doorstep(village, smith.position)
	assert_ne(inn_step, Vector2.INF, "a walkable cell exists beside the inn")
	assert_ne(smith_step, Vector2.INF, "a walkable cell exists beside the smith")
	assert_gt(inn_step.distance_to(smith_step), float(village.TILE_SIZE) * 4.0,
		"the two doors are far enough apart that one shared return tile cannot be both")

	var inn_face := _facing_toward(inn_step, inn.position)
	var inn_back := _round_trip(village, "harmonia_village", "inn_interior", "inn_exit", inn_step, inn_face)
	_assert_back_at_the_door(village, inn_back, inn_step, inn_face)

	var smith_face := _facing_toward(smith_step, smith.position)
	var smith_back := _round_trip(village, "harmonia_village", "shop_interior_blacksmith", "shop_exit", smith_step, smith_face)
	_assert_back_at_the_door(village, smith_back, smith_step, smith_face)
	assert_gt((inn_back["position"] as Vector2).distance_to(smith_back["position"]), float(village.TILE_SIZE) * 4.0,
		"leaving the smith put you back at the inn")


func test_leaving_maple_heights_inn_puts_you_back_at_that_door() -> void:
	var village = await _build("res://src/maps/villages/MapleHeightsVillage.gd")
	var inn := _find_inn(village)
	assert_not_null(inn, "Maple Heights builds its inn")
	var step := _doorstep(village, inn.position)
	assert_ne(step, Vector2.INF, "a walkable cell exists beside Mom's Guest Room")
	var facing := _facing_toward(step, inn.position)
	var back := _round_trip(village, "maple_heights_village", "inn_interior", "inn_exit", step, facing)
	_assert_back_at_the_door(village, back, step, facing)


## Chapel / library doors name their own spawn. Remembering a doorstep must not steal that landing.
func test_a_named_building_exit_keeps_its_own_spawn() -> void:
	var village = await _build("res://src/maps/villages/HarmoniaVillage.gd")
	var inn := _find_inn(village)
	assert_not_null(inn, "Harmonia builds its inn")
	var step := _doorstep(village, inn.position)
	var facing := _facing_toward(step, inn.position)
	_round_trip(village, "harmonia_village", "inn_interior", "inn_exit", step, facing)

	var chapel_step := _doorstep(village, Vector2(7 * village.TILE_SIZE, 17.5 * village.TILE_SIZE))
	assert_ne(chapel_step, Vector2.INF, "a walkable cell exists by the chapel door")
	var chapel_face := _facing_toward(chapel_step, Vector2(7 * village.TILE_SIZE, 17.5 * village.TILE_SIZE))
	village.player.position = chapel_step
	village.player.current_direction = chapel_face
	_gl._current_map_id = "harmonia_village"
	_gl._exploration_scene = village
	var entered: Dictionary = _gl._route_area_transition("harmonia_chapel", "entrance")
	assert_eq(entered["position"], Vector2.ZERO)
	assert_true(_gl._has_interior_return)
	village.player.position = Vector2(8000, 8000)
	_gl._current_map_id = "harmonia_chapel"
	var back: Dictionary = _gl._route_area_transition("harmonia_village", "chapel_exit")
	assert_eq(str(back["map"]), "harmonia_village")
	assert_eq(str(back["spawn"]), "chapel_exit",
		"the chapel's own exit spawn was replaced — you would miss the door the scene authored")
	assert_eq(back["position"], Vector2.ZERO,
		"a named exit also applied the captured doorstep, so the authored chapel_exit never runs")
	assert_false(_gl._has_interior_return)
	assert_true(village.spawn_points.has("chapel_exit"))
	assert_gt((village.spawn_points["chapel_exit"] as Vector2).distance_to(village.spawn_points["default"]), float(village.TILE_SIZE),
		"chapel_exit and the village gate are the same point — this control no longer distinguishes them")


## Dev teleport into an interior never watched a door. The gate remains the fallback.
func test_a_return_with_no_captured_doorstep_still_uses_the_village_gate() -> void:
	_gl._village_origin_id = "harmonia_village"
	_gl._current_map_id = "inn_interior"
	_gl._clear_interior_doorstep()
	var back: Dictionary = _gl._route_area_transition("village_return", "inn_exit")
	assert_eq(str(back["map"]), "harmonia_village")
	assert_eq(str(back["spawn"]), "default")
	assert_eq(back["position"], Vector2.ZERO,
		"no captured doorstep must not invent a tile — spawn \"default\" is the landing")
	assert_eq(int(back["facing"]), -1)


## The doorstep is not in the save. Loading another interior must not keep the door you walked in from.
##
## Repro, cross-interior: enter the Harmonia inn (latch set), load a save taken inside a different
## shared interior, walk out. The exit used the Harmonia inn door.
## Repro, same village: enter the blacksmith, load a save from inside the inn, leave the inn.
## You landed at the blacksmith door. A loaded room falls back to the village gate.
func test_loading_another_interior_does_not_keep_the_door_you_entered_from() -> void:
	var village = await _build("res://src/maps/villages/HarmoniaVillage.gd")
	var inn := _find_inn(village)
	var smith := _find_shop(village, VillageShop.ShopType.BLACKSMITH)
	assert_not_null(inn, "Harmonia builds its inn")
	assert_not_null(smith, "Harmonia builds its blacksmith")
	var inn_step := _doorstep(village, inn.position)
	var smith_step := _doorstep(village, smith.position)
	assert_ne(inn_step, Vector2.INF, "a walkable cell exists beside the inn")
	assert_ne(smith_step, Vector2.INF, "a walkable cell exists beside the smith")
	assert_gt(inn_step.distance_to(smith_step), float(village.TILE_SIZE) * 4.0,
		"the two doors are far enough apart that one shared return tile cannot be both")

	var inn_face := _facing_toward(inn_step, inn.position)
	_stand_and_enter(village, "harmonia_village", "inn_interior", inn_step, inn_face)
	var harmonia_door: Vector2 = _gl._interior_return_position
	assert_eq(harmonia_door, inn_step)
	_load_save_from_interior("shop_interior_item")
	var other_room: Dictionary = _gl._route_area_transition("village_return", "shop_exit")
	_assert_gate_not_the_old_door(other_room, harmonia_door,
		"walked out of the loaded interior and appeared at the Harmonia inn door")

	var smith_face := _facing_toward(smith_step, smith.position)
	_stand_and_enter(village, "harmonia_village", "shop_interior_blacksmith", smith_step, smith_face)
	var smith_door: Vector2 = _gl._interior_return_position
	assert_eq(smith_door, smith_step)
	_load_save_from_interior("inn_interior")
	var inn_after_smith: Dictionary = _gl._route_area_transition("village_return", "inn_exit")
	_assert_gate_not_the_old_door(inn_after_smith, smith_door,
		"left the loaded inn and landed at the blacksmith door")


## In-game Load restarts exploration even when the save has no party. That call must still drop the latch.
func test_a_party_less_restore_still_drops_the_doorstep() -> void:
	_gl._has_interior_return = true
	_gl._interior_return_position = Vector2(320, 480)
	_gl._interior_return_facing = OverworldPlayer.Direction.UP
	GameState.player_party.clear()
	assert_false(_gl._restore_party_from_save_data(), "an empty party still refuses to rebuild")
	_assert_latch_cleared("a restore that rebuilds nobody must still forget the door you entered before the load")


## Quit to Title never loads a save. The latch has to die here too, or Continue inherits it.
func test_quit_to_title_drops_the_captured_doorstep() -> void:
	_gl._has_interior_return = true
	_gl._interior_return_position = Vector2(160, 240)
	_gl._interior_return_facing = OverworldPlayer.Direction.LEFT
	_gl._village_origin_id = "harmonia_village"
	_gl._on_quit_to_title()
	_assert_latch_cleared("Quit to Title left the doorstep latched for whoever loads next")
	assert_eq(_gl.current_state, _gl.LoopState.TITLE, "Quit to Title still reaches the title screen")
	assert_eq(str(_gl._village_origin_id), "harmonia_village",
		"Quit to Title only drops the doorstep latch — the village you came from is a separate field")


func _stand_and_enter(village, village_id: String, interior_id: String, doorstep: Vector2, facing: int) -> void:
	village.player.position = doorstep
	village.player.current_direction = facing
	_gl._current_map_id = village_id
	_gl._exploration_scene = village
	_gl._clear_interior_doorstep()
	var entered: Dictionary = _gl._route_area_transition(interior_id, "entrance")
	assert_eq(entered["position"], Vector2.ZERO)
	assert_true(_gl._has_interior_return, "the doorstep is captured on the way in — %s" % interior_id)
	_gl._current_map_id = interior_id


func _load_save_from_interior(map_id: String) -> void:
	GameState.player_party.clear()
	GameState.player_party.append({
		"name": "Fighter",
		"job_id": "fighter",
		"equipped_weapon": "",
		"equipped_armor": "",
		"equipped_accessory": "",
		"purchased_abilities": [],
		"current_hp": 100,
		"max_hp": 100,
		"current_mp": 10,
		"max_mp": 10,
		"is_alive": true,
	})
	MapSystem.current_map_id = map_id
	SaveSystem.pending_player_position = Vector2.INF
	assert_true(_gl._restore_party_from_save_data(), "the save taken inside %s must restore" % map_id)
	_assert_latch_cleared("load kept the doorstep from before the save — it is not in the save file")
	assert_eq(str(_gl._current_map_id), map_id, "restore must land in the interior the save was taken in")


func _assert_latch_cleared(why: String) -> void:
	assert_false(_gl._has_interior_return, why)
	assert_eq(_gl._interior_return_position, Vector2.ZERO, why)
	assert_eq(int(_gl._interior_return_facing), -1, why)


func _assert_gate_not_the_old_door(back: Dictionary, old_door: Vector2, why: String) -> void:
	assert_eq(str(back["map"]), "harmonia_village", why)
	assert_eq(str(back["spawn"]), "default", why)
	assert_eq(back["position"], Vector2.ZERO,
		"%s %s — a loaded interior has no remembered tile, so the village gate is the landing" % [why, str(old_door)])
	assert_eq(int(back["facing"]), -1, why)
	assert_gt(old_door.distance_to(Vector2.ZERO), 1.0,
		"the captured door was already the origin, so this check cannot see the leak")


func test_the_area_transition_applies_the_routed_tile_and_facing() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var call := src.find("var routed := _route_area_transition(")
	assert_gt(call, 0, "_on_area_transition no longer asks _route_area_transition where to put the player")
	var window := src.substr(call, 400)
	assert_true("_player_position = routed[\"position\"]" in window,
		"the routed doorstep is computed and then discarded — _player_position is what _start_exploration actually applies")
	assert_true("_pending_facing = int(routed[\"facing\"])" in window,
		"facing is computed and then discarded")
	assert_true(src.find("_apply_pending_facing(scene_player)") > 0,
		"_start_exploration never applies the facing it was given")
