extends GutTest

## Walking out of a dungeon erases that cave's saved floor, so the next entry
## starts on floor 1. GameLoop also keeps `_current_cave_floor` so a battle
## can return you to the floor you fought on. That latch survived the exit.
## The next dungeon — including one in another world — was stamped with it
## before `_ready`, and `_ready` only restores a floor when the saved key
## still exists. A descent in Whispering Cave, the walk back out, the portal
## to World 2, then Suburban Underground opened several floors down.
##
## Battle return does not go through `_on_area_transition`. A transition
## suppressed because a battle is already starting must leave the latch alone.

const GameLoopScript := preload("res://src/GameLoop.gd")
const SuburbanUndergroundScript := preload("res://src/maps/dungeons/SuburbanUnderground.gd")

## _ready would boot the title. _start_exploration awaits a signal nothing emits,
## so the handler suspends before the auto-save that follows a real scene swap.
class QuietTravel extends GameLoopScript:
	signal _hold
	func _ready() -> void:
		pass
	func _start_exploration(_force_battle_teardown: bool = false) -> void:
		await _hold


var _gl: QuietTravel = null
var _saved_world: int = 1
var _saved_map_id: String = ""
var _had_suburban_floor: bool = false
var _suburban_floor: int = 1
var _had_whisper_floor: bool = false
var _whisper_floor: int = 1


func before_each() -> void:
	_gl = QuietTravel.new()
	add_child(_gl)
	_saved_world = int(GameState.current_world) if GameState else 1
	_saved_map_id = str(MapSystem.current_map_id) if MapSystem and "current_map_id" in MapSystem else ""
	_had_suburban_floor = GameState.game_constants.has("suburban_underground_floor")
	if _had_suburban_floor:
		_suburban_floor = int(GameState.game_constants["suburban_underground_floor"])
	_had_whisper_floor = GameState.game_constants.has("whispering_cave_floor")
	if _had_whisper_floor:
		_whisper_floor = int(GameState.game_constants["whispering_cave_floor"])


func after_each() -> void:
	if _gl != null and is_instance_valid(_gl):
		_gl.free()
		_gl = null
	if GameState:
		GameState.current_world = _saved_world
		if _had_suburban_floor:
			GameState.game_constants["suburban_underground_floor"] = _suburban_floor
		else:
			GameState.game_constants.erase("suburban_underground_floor")
		if _had_whisper_floor:
			GameState.game_constants["whispering_cave_floor"] = _whisper_floor
		else:
			GameState.game_constants.erase("whispering_cave_floor")
	if MapSystem and "current_map_id" in MapSystem:
		MapSystem.current_map_id = _saved_map_id


## The stamp still exists. Battle return and an in-dungeon save both need a
## deep floor to reopen on that floor. Clearing it inside the creator would
## "fix" the travel bug by breaking the return.
func test_the_latch_still_opens_a_dungeon_on_that_floor() -> void:
	_gl._current_cave_floor = 4
	var cave: Node = _gl._create_dragon_cave_from_script(SuburbanUndergroundScript)
	assert_eq(int(cave.current_floor), 4,
		"a dungeon built while the latch is 4 must open on floor 4 — that is how a fight returns you")
	cave.free()


## A battle that starts on the same frame as a door must not drop the floor.
## The handler returns before it changes anything; battle return reads the latch.
func test_a_suppressed_transition_keeps_the_floor() -> void:
	_gl._battle_transition_starting = true
	_gl._current_cave_floor = 4
	_gl._set_current_map_id("whispering_cave")
	_gl._on_area_transition("suburban_overworld", "default")
	assert_eq(_gl._current_cave_floor, 4,
		"the door lost the race to an encounter — the floor the battle will return to is still 4")
	assert_eq(str(_gl._current_map_id), "whispering_cave",
		"a suppressed transition must not change maps either")


## The bug. Keys are already gone (the exit erased them). The latch is not.
## Crossing into World 2 must not carry Whispering Cave's floor into the
## Suburban Underground.
func test_leaving_a_dungeon_for_another_world_does_not_carry_the_floor() -> void:
	GameState.game_constants.erase("whispering_cave_floor")
	GameState.game_constants.erase("suburban_underground_floor")
	_gl._set_current_map_id("whispering_cave")
	_gl._current_cave_floor = 4
	assert_eq(int(GameState.current_world), 1, "the cave is World 1 before the portal")
	_gl._on_area_transition("suburban_overworld", "default")
	assert_eq(int(GameState.current_world), 2,
		"the portal landed in World 2 — otherwise this never left the cave")
	assert_false(GameState.game_constants.has("suburban_underground_floor"),
		"the underground has no saved floor; _ready will not correct a stamped one")
	assert_eq(_gl._current_cave_floor, 1,
		"leaving the map must drop the in-memory floor — it still said 4 after the portal")
	var cave: Node = _gl._create_dragon_cave_from_script(SuburbanUndergroundScript)
	assert_eq(int(cave.current_floor), 1,
		"Suburban Underground opened on floor %d, the floor you walked out of in Whispering Cave" % int(cave.current_floor))
	cave.free()
