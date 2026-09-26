extends GutTest

## A cleared cave's _ready forces floor 1 (tick 153) after the battle-return
## tile was saved on the floor the fight started on. spawn_player_at already
## put the party at the entrance; applying that tile drops them on floor 1
## at the deep floor's coordinates. The tile is kept when the rebuild opens
## the same floor, and a load (floor tag 0) is never treated as a deep tile.

const GAME_LOOP := "res://src/GameLoop.gd"


class _FloorMap extends Node2D:
	var player: Node2D
	var current_floor: int = 1


class _OpenMap extends Node2D:
	var player: Node2D


func _loop() -> Node:
	var gl = load(GAME_LOOP).new()
	autofree(gl)
	return gl


func _map_on_floor(floor_num: int, standing: Vector2) -> _FloorMap:
	var map := _FloorMap.new()
	add_child_autofree(map)
	var body := Node2D.new()
	map.add_child(body)
	map.player = body
	map.current_floor = floor_num
	body.position = standing
	return map


func _place_consumed_tile(gl: Node, scene: Node) -> void:
	var tile: Vector2 = gl._consume_return_tile(scene)
	var body: Node2D = scene.get("player")
	if body and tile != Vector2.ZERO:
		body.position = tile


func test_a_deep_floor_tile_is_not_stamped_onto_floor_1() -> void:
	var gl := _loop()
	var map := _map_on_floor(1, Vector2(48, 64))
	gl._player_position = Vector2(320, 224)
	gl._position_floor = 6
	_place_consumed_tile(gl, map)
	assert_eq(map.player.position, Vector2(48, 64),
		"floor 1 already spawned the entrance — a floor-6 tile must not move the party there")
	assert_eq(gl._player_position, Vector2.ZERO,
		"the dropped tile is spent, or the second restore site stamps it anyway")
	assert_eq(gl._position_floor, 0,
		"the floor tag is spent with the tile")


func test_the_same_floor_still_gets_its_tile() -> void:
	var gl := _loop()
	var map := _map_on_floor(6, Vector2(48, 64))
	gl._player_position = Vector2(320, 224)
	gl._position_floor = 6
	_place_consumed_tile(gl, map)
	assert_eq(map.player.position, Vector2(320, 224),
		"a fight on floor 6 that reopens on floor 6 still returns to that tile")
	assert_eq(gl._player_position, Vector2.ZERO)
	assert_eq(gl._position_floor, 0)


func test_floor_1_and_an_untagged_load_still_apply() -> void:
	var gl := _loop()
	var on_one := _map_on_floor(1, Vector2(48, 64))
	gl._player_position = Vector2(160, 96)
	gl._position_floor = 1
	_place_consumed_tile(gl, on_one)
	assert_eq(on_one.player.position, Vector2(160, 96),
		"a fight that started on floor 1 returns to that tile")
	var loaded := _map_on_floor(1, Vector2(48, 64))
	gl._player_position = Vector2(1500, 800)
	gl._position_floor = 0
	_place_consumed_tile(gl, loaded)
	assert_eq(loaded.player.position, Vector2(1500, 800),
		"Continue has no floor tag and must still land on the saved coordinates")


func test_a_map_without_a_floor_keeps_the_tile() -> void:
	var gl := _loop()
	var map := _OpenMap.new()
	add_child_autofree(map)
	var body := Node2D.new()
	map.add_child(body)
	map.player = body
	body.position = Vector2(10, 10)
	gl._player_position = Vector2(400, 200)
	gl._position_floor = 4
	_place_consumed_tile(gl, map)
	assert_eq(body.position, Vector2(400, 200),
		"the overworld has no current_floor — the return tile still applies")


func test_capture_tags_the_floor_the_fight_started_on() -> void:
	var gl := _loop()
	var map := _map_on_floor(6, Vector2(320, 224))
	gl._exploration_scene = map
	gl._position_floor = 0
	assert_true(gl._capture_duel_return_position())
	assert_eq(gl._position_floor, 6,
		"the return tile has to remember floor 6, or the floor-1 rebuild cannot tell it apart")
	var opened := _map_on_floor(1, Vector2(48, 64))
	_place_consumed_tile(gl, opened)
	assert_eq(opened.player.position, Vector2(48, 64),
		"a capture from floor 6 applied onto a floor-1 rebuild must leave the entrance")


func test_both_restore_sites_consume_the_tile_and_both_captures_stamp_the_floor() -> void:
	var src := FileAccess.get_file_as_string(GAME_LOOP)
	for sig in ["func _start_exploration", "func _return_to_exploration"]:
		var body := _fn_body(src, sig)
		var consume_at: int = body.find("_consume_return_tile(")
		var assign_at: int = body.find("position = restored_tile")
		assert_gt(consume_at, -1, "%s must consume the return tile" % sig)
		assert_gt(assign_at, consume_at, "%s must decide the tile before moving the player" % sig)
		assert_true(body.contains("restored_tile != Vector2.ZERO"),
			"%s must not move the player when the tile was dropped" % sig)
	for sig in ["func _capture_duel_return_position", "func _on_exploration_battle_triggered", "func _on_grind_battle_requested"]:
		assert_true(_fn_body(src, sig).contains("_stamp_return_floor("),
			"%s must tag the saved tile with the floor it came from" % sig)
	assert_true(_fn_body(src, "func _restore_party_from_save_data").contains("_position_floor = 0"),
		"a loaded position is not a deep-floor tile")


func _fn_body(src: String, signature: String) -> String:
	var start: int = src.find(signature)
	if start < 0:
		return ""
	var next: int = src.find("\nfunc ", start + signature.length())
	if next < 0:
		return src.substr(start)
	return src.substr(start, next - start)
