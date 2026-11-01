extends GutTest

## struktured, .758: "after autogrinding I entered a battle with my entire party already KOed". The grind's stop path took a
## wiped party straight back to the field (godot.log: === DEFEAT === → "Controller stopped: Party defeated" → overworld → a chain).
## A grind that ends in a wipe now goes through the manual defeat flow, with the field held still under it.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

const STUB := """
extends "res://src/GameLoop.gd"
var game_overs := 0
var summaries := 0
var locked_during := false
var release := false
func _show_game_over_screen() -> void:
	game_overs += 1
	await get_tree().process_frame
	await get_tree().process_frame
	locked_during = InputLockManager.has_lock(WIPE_FIELD_LOCK)
	while not release:
		await get_tree().process_frame
func _show_autogrind_summary(_stats: Dictionary, _reason: String) -> void:
	summaries += 1
"""

var _ag: Dictionary
var _gl: Node


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	var script := GDScript.new()
	script.source_code = STUB
	script.reload()
	_gl = script.new()
	add_child_autofree(_gl)
	var explore := Node.new()
	add_child_autofree(explore)
	_gl._exploration_scene = explore
	_gl._current_map_id = "overworld"


func after_each() -> void:
	if _gl != null and is_instance_valid(_gl):
		_gl.release = true
	InputLockManager.pop_all()
	Engine.time_scale = 1.0
	AutogrindState.restore(_ag)
	SoundManager.stop_music()


func _party(alive: Array) -> void:
	var members: Array[Combatant] = []
	for a in alive:
		var c := Combatant.new()
		c.max_hp = 50
		c.current_hp = 50 if a else 0
		c.is_alive = a
		autofree(c)
		members.append(c)
	_gl.party = members


func test_a_wiped_grind_reaches_the_game_over_screen_not_the_field() -> void:
	_party([false, false, false])
	var console := Control.new()
	_gl.add_child(console)
	_gl._autogrind_ui = console
	_gl._on_grind_complete("Party defeated")
	await wait_frames(4)
	assert_eq(_gl.game_overs, 1, "a grind that ended in a wipe must hand the party to the defeat flow")
	assert_eq(_gl.summaries, 0, "and must not drop them on the field behind a summary instead")
	assert_true(_gl._autogrind_ui == null, "the console must not sit over the game-over screen")
	assert_true(_gl.locked_during, "the field must be held still while the game-over screen is up")


func test_the_field_is_released_when_the_defeat_flow_returns() -> void:
	_party([false, false])
	_gl._on_grind_complete("Party defeated")
	await wait_frames(4)
	assert_true(InputLockManager.has_lock(_gl.WIPE_FIELD_LOCK), "CONTROL: held while the screen waits")
	_gl.release = true
	await wait_frames(4)
	assert_false(InputLockManager.has_lock(_gl.WIPE_FIELD_LOCK), "a choice made must give the field back")


func test_a_grind_that_stops_with_someone_standing_shows_the_summary() -> void:
	_party([false, true, false])
	_gl._on_grind_complete("Healing items depleted")
	await wait_frames(4)
	assert_eq(_gl.summaries, 1, "CONTROL: an ordinary stop still shows its summary")
	assert_eq(_gl.game_overs, 0, "one member standing is not a wipe")
