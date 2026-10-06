extends GutTest

## Regression (struktured 2026-10-05, Shadow Dragon Cave): "getting attacked in caves, when i finish battle im respawned not where battle
## started". His log: "[CAVE] Restoring to floor 3" then "[POSITION] Dropped return tile ... the cave opened on a different floor", then
## the floor-1 stairs fired and threw him out to the overworld. DragonCave's _ready re-read the saved floor key and, with the boss
## cleared, reset to floor 1, overriding the floor GameLoop had just restored. A rebuild marked restoring_floor now keeps its floor.

const ShadowCave := preload("res://src/maps/dungeons/ShadowDragonCave.gd")

var _saved_constants: Dictionary = {}
var _saved_party: Array[Dictionary] = []


func before_each() -> void:
	_saved_constants = GameState.game_constants.duplicate(true)
	_saved_party = GameState.player_party.duplicate(true)
	var p: Array[Dictionary] = [{"name": "Fighter", "job_id": "fighter", "is_alive": true, "current_hp": 10}]
	GameState.player_party = p


func after_each() -> void:
	GameState.game_constants = _saved_constants
	GameState.player_party = _saved_party


func _cleared_cave_with_stale_key() -> void:
	var flags: Dictionary = GameState.game_constants.get("dungeon_flags", {}).duplicate()
	flags["shadow_dragon_defeated"] = true
	GameState.game_constants["dungeon_flags"] = flags
	GameState.game_constants["shadow_dragon_cave_floor"] = 1


func _build(floor_n: int, restoring: bool) -> Node:
	var cave = ShadowCave.new()
	cave.current_floor = floor_n
	if restoring:
		cave.set_meta("restoring_floor", true)
	add_child_autofree(cave)
	return cave


func test_a_battle_return_keeps_the_floor_the_fight_started_on() -> void:
	_cleared_cave_with_stale_key()
	var cave := _build(3, true)
	await get_tree().process_frame
	assert_eq(int(cave.current_floor), 3, "a restore after battle must open on floor 3, not the boss-cleared floor 1")


func test_a_fresh_entry_into_a_cleared_cave_still_starts_at_the_entrance() -> void:
	_cleared_cave_with_stale_key()
	var cave := _build(3, false)
	await get_tree().process_frame
	assert_eq(int(cave.current_floor), 1, "CONTROL: re-entering a cleared cave still starts at floor 1 (Tick 153's rule)")
