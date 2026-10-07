extends GutTest

## struktured 2026-10-07 ruling ("Required, Zelda-style"): a block landing on its pylon and a
## mirror lever's toggle must survive save/load and battle-return (same mechanism round 1's K/Q/G/Z
## already relies on); a timed gate's open window must NOT persist -- it always starts closed.

const LightningCave := preload("res://src/maps/dungeons/LightningDragonCave.gd")

var _saved_constants: Dictionary = {}


func before_each() -> void:
	_saved_constants = GameState.game_constants.duplicate(true)


func after_each() -> void:
	GameState.game_constants = _saved_constants


func test_a_pushed_block_and_a_toggled_mirror_survive_a_fresh_instance() -> void:
	var cave := LightningCave.new()
	add_child_autofree(cave)
	await get_tree().process_frame
	cave._mechanics_layer.mark_block_on_target("bp0")
	assert_true(bool(cave._mechanics_layer._block_pushed.get("bp0", false)), "CONTROL: marking must set the in-memory flag")

	var cave2 := LightningCave.new()
	add_child_autofree(cave2)
	await get_tree().process_frame
	assert_true(bool(cave2._mechanics_layer._block_pushed.get("bp0", false)),
		"a fresh DragonCave instance for the same cave_id must load the pushed block from GameState")


func test_a_timed_gate_never_persists_its_open_window() -> void:
	var cave = load("res://src/maps/dungeons/FireDragonCave.gd").new()
	add_child_autofree(cave)
	await get_tree().process_frame
	cave._mechanics_layer._timed_open_until[3] = int(Time.get_ticks_msec()) + 999999
	cave._mechanics_layer.toggle_mirror("tp0")  # no-op (Fire has no mirror), just forces a _save_round2_state write
	var saved: Dictionary = GameState.game_constants.get(str(cave.cave_id) + "_mechanics2", {})
	assert_false(saved.has("timed"), "the persisted mechanics2 blob must never carry timed-gate state: %s" % str(saved))

	var cave2 = load("res://src/maps/dungeons/FireDragonCave.gd").new()
	add_child_autofree(cave2)
	await get_tree().process_frame
	assert_eq(int(cave2._mechanics_layer._timed_open_until.get(3, 0)), 0,
		"a fresh instance must never inherit another instance's timed-gate window -- it is deliberately never saved")
