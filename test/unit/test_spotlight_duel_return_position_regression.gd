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
