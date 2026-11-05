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
var retry_against_seen := ""
func _show_game_over_screen() -> void:
	game_overs += 1
	retry_against_seen = _game_over_retry_against
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
	## A stand-in console with the one call _on_grind_complete makes on it; a bare Control aborted the handler there.
	var console_script := GDScript.new()
	console_script.source_code = "extends Control\nfunc set_grinding(_active: bool) -> void:\n\tpass\n"
	console_script.reload()
	var console: Control = console_script.new()
	_gl.add_child(console)
	_gl._autogrind_ui = console
	_gl._on_grind_complete("Party defeated")
	await wait_frames(4)
	assert_eq(_gl.game_overs, 1, "a grind that ended in a wipe must hand the party to the defeat flow")
	assert_eq(_gl.summaries, 0, "and must not drop them on the field behind a summary instead")
	assert_true(_gl._autogrind_ui == null, "the console must not sit over the game-over screen")
	## Read here, not by the stub: the stub's process frames and this wait's physics frames do not advance together.
	assert_true(InputLockManager.has_lock(_gl.WIPE_FIELD_LOCK), "the field must be held still while the game-over screen is up")


func test_the_field_is_released_when_the_defeat_flow_returns() -> void:
	_party([false, false])
	_gl._on_grind_complete("Party defeated")
	await wait_frames(4)
	assert_true(InputLockManager.has_lock(_gl.WIPE_FIELD_LOCK), "CONTROL: held while the screen waits")
	_gl.release = true
	## Waits on PROCESS frames for the condition, bounded: GUT's frame count and the hold loop's do not advance together (red in a sweep).
	for i in 120:
		if not InputLockManager.has_lock(_gl.WIPE_FIELD_LOCK):
			break
		await get_tree().process_frame
	assert_false(InputLockManager.has_lock(_gl.WIPE_FIELD_LOCK), "a choice made must give the field back")


func test_a_grind_that_stops_with_someone_standing_shows_the_summary() -> void:
	_party([false, true, false])
	_gl._on_grind_complete("Healing items depleted")
	await wait_seconds(1.0)  # the summary waits out the stop banner
	assert_eq(_gl.summaries, 1, "CONTROL: an ordinary stop still shows its summary")
	assert_eq(_gl.game_overs, 0, "one member standing is not a wipe")


## struktured, preview 2026-11-01: "when retrying from autogrind it put me in some other battle" — Retry fought his last
## MANUAL battle (a Bat) instead of the Ice Wolf that wiped the grind, because grind battles never set _last_battle_enemies.
func test_retry_after_a_grind_wipe_refights_the_grind_battle_and_names_it() -> void:
	_party([false, false])
	_gl._last_battle_enemies = ["bat"]
	_gl._last_grind_enemies = _gl._grind_enemy_ids([{"id": "ice_wolf", "stats": {}}])
	assert_eq(_gl._last_grind_enemies, ["ice_wolf"], "CONTROL: a grind row yields its monster id")
	_gl._on_grind_complete("Party defeated")
	await wait_frames(4)
	assert_eq(_gl._last_battle_enemies, ["ice_wolf"], "Retry must re-fight the grind battle that wiped, not the last one played by hand")
	assert_true(_gl._last_battle_is_encounter, "and as the encounter it was")
	var name: String = str((EncounterSystem.monster_database.get("ice_wolf", {}) as Dictionary).get("name", ""))
	assert_ne(name, "", "CONTROL: the ice wolf has a display name")
	assert_eq(_gl.retry_against_seen, name, "the defeat screen must be told what Retry fights")


func test_the_retry_row_says_what_it_fights() -> void:
	var screen := GameOverScreen.new()
	add_child_autofree(screen)
	screen.retry_against = "Goblin ×3"
	screen._update_selection()
	assert_string_contains(screen._retry_label.text, "Retry: vs Goblin ×3", "the Retry row must name its fight")
	screen.retry_against = ""
	screen._update_selection()
	assert_eq(screen._retry_label.text, "> Retry", "CONTROL: a manual defeat keeps the plain row")


func test_an_encounter_is_named_by_species_and_count() -> void:
	var db: Dictionary = EncounterSystem.monster_database
	var goblin: String = str((db.get("goblin", {}) as Dictionary).get("name", "Goblin"))
	var bat: String = str((db.get("bat", {}) as Dictionary).get("name", "Bat"))
	assert_eq(_gl._encounter_label(["goblin", "goblin", "bat"]), "%s ×2, %s" % [goblin, bat])
	assert_eq(_gl._encounter_label(["bat"]), bat, "one of a kind carries no count")
