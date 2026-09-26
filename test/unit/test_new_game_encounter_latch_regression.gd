extends GutTest

## Quit to Title leaves EncounterSystem's run latches on the autoload. New Game
## resets gold, quests, and story flags, then starts the overworld without
## touching them. A Repel used last run still suppresses random fights, a long
## dry spell spends the new game's opening grace, and an ambush plate that
## already sprung forces a battle on the first step — before the player has
## had a quiet moment of control.
##
## Continue is the other door off the title. It must still put a saved Repel
## back; the clear belongs on New Game, ahead of _start_exploration, because
## that call is not awaited and the first walk can roll immediately.

const GameLoopScript := preload("res://src/GameLoop.gd")
const BattleSceneScript := preload("res://src/battle/BattleScene.gd")

## In the tree only so the handler can await a frame. _ready would boot the title.
class QuietNewGame extends GameLoopScript:
	func _ready() -> void:
		pass
	func _create_party() -> void:
		pass
	func _start_exploration(_force_battle_teardown: bool = false) -> void:
		pass


var _saved_state: Dictionary = {}
var _saved_speed: float = 0.25
var _saved_encounter: float = 1.0
var _saved_speed_index: int = 0
var _saved_auto: Dictionary = {}
var _saved_cancel_all: bool = false
var _saved_legacy_auto: bool = false
var _saved_grind: float = 0.0
var _saved_intensity: float = 0.0
var _saved_target: float = 0.0
var _saved_map_id: String = ""
var _saved_repel: int = 0
var _saved_steps: int = 0
var _saved_forced: bool = false
var _saved_pending_pos: Vector2 = Vector2.INF


func before_each() -> void:
	_saved_state = GameState.to_dict()
	_saved_speed = GameState.default_battle_speed
	_saved_encounter = GameState.encounter_rate_multiplier
	_saved_speed_index = BattleSceneScript._battle_speed_index
	_saved_auto = AutobattleSystem.autobattle_enabled.duplicate()
	_saved_cancel_all = AutobattleSystem.cancel_all_next_turn
	_saved_legacy_auto = BattleManager.is_autobattle_enabled
	_saved_grind = SoundManager._grind_corruption
	_saved_intensity = SoundManager._corruption_intensity
	_saved_target = SoundManager._corruption_target
	if MapSystem and "current_map_id" in MapSystem:
		_saved_map_id = str(MapSystem.current_map_id)
	_saved_repel = int(EncounterSystem.repel_steps_remaining)
	_saved_steps = int(EncounterSystem.steps_since_last_encounter)
	_saved_forced = bool(EncounterSystem.forced_encounter_next_step)
	if SaveSystem and "pending_player_position" in SaveSystem:
		_saved_pending_pos = SaveSystem.pending_player_position


func after_each() -> void:
	GameState._apply_save_data(_saved_state)
	GameState.default_battle_speed = _saved_speed
	GameState.encounter_rate_multiplier = _saved_encounter
	BattleSceneScript._battle_speed_index = _saved_speed_index
	AutobattleSystem.autobattle_enabled = _saved_auto.duplicate()
	AutobattleSystem.cancel_all_next_turn = _saved_cancel_all
	BattleManager.is_autobattle_enabled = _saved_legacy_auto
	SoundManager._grind_corruption = _saved_grind
	SoundManager._corruption_intensity = _saved_intensity
	SoundManager._corruption_target = _saved_target
	if MapSystem and "current_map_id" in MapSystem:
		MapSystem.current_map_id = _saved_map_id
	EncounterSystem.repel_steps_remaining = _saved_repel
	EncounterSystem.steps_since_last_encounter = _saved_steps
	EncounterSystem.forced_encounter_next_step = _saved_forced
	if SaveSystem and "pending_player_position" in SaveSystem:
		SaveSystem.pending_player_position = _saved_pending_pos
	if SaveSystem and SaveSystem.has_method("save_settings"):
		SaveSystem.save_settings()


func test_floor_the_encounter_latches_still_exist() -> void:
	for name in ["reset_for_new_game", "check_for_encounter", "reset_encounter_counter"]:
		assert_true(EncounterSystem.has_method(name), "EncounterSystem must still expose %s()" % name)
	for field in ["repel_steps_remaining", "steps_since_last_encounter", "forced_encounter_next_step"]:
		assert_true(field in EncounterSystem, "EncounterSystem must still carry %s" % field)


func test_new_game_drops_the_last_runs_repel_and_ambush() -> void:
	EncounterSystem.repel_steps_remaining = 47
	EncounterSystem.steps_since_last_encounter = 12
	EncounterSystem.forced_encounter_next_step = true
	assert_false(EncounterSystem.check_for_encounter(),
		"CONTROL: a live Repel must suppress the step, or this file is not holding the latch")
	assert_eq(int(EncounterSystem.repel_steps_remaining), 46,
		"CONTROL: the suppression has to spend a charge (still %d)" % int(EncounterSystem.repel_steps_remaining))
	var gl: QuietNewGame = autofree(QuietNewGame.new())
	add_child(gl)
	await gl._on_title_new_game()
	assert_eq(int(EncounterSystem.repel_steps_remaining), 0,
		"New Game still had %d Repel steps — the world map stays empty until last run's charm wears off" % int(EncounterSystem.repel_steps_remaining))
	assert_eq(int(EncounterSystem.steps_since_last_encounter), 0,
		"New Game kept a %d-step dry spell — the opening grace is already spent, so the first step can be a fight" % int(EncounterSystem.steps_since_last_encounter))
	assert_false(bool(EncounterSystem.forced_encounter_next_step),
		"New Game kept a sprung ambush plate — the first step is a forced battle")


func test_the_clear_happens_before_exploration_and_continue_still_restores() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var fresh := _fn_body(src, "func _on_title_new_game")
	var reset_at := fresh.find("reset_for_new_game")
	var start_at := fresh.find("_start_exploration()")
	assert_gt(reset_at, 0, "New Game never clears the encounter latches")
	assert_lt(reset_at, start_at,
		"the clear sits after _start_exploration — that call is not awaited, so the first walk can roll the old latch")
	EncounterSystem.repel_steps_remaining = 47
	EncounterSystem.steps_since_last_encounter = 3
	var saved := SaveSystem._create_save_data()
	EncounterSystem.repel_steps_remaining = 0
	EncounterSystem.steps_since_last_encounter = 0
	SaveSystem._apply_save_data(saved)
	assert_eq(int(EncounterSystem.repel_steps_remaining), 47,
		"Continue must still restore a saved Repel — New Game is the path that drops it")
	assert_eq(int(EncounterSystem.steps_since_last_encounter), 3,
		"Continue must still restore the saved step gap")


func _fn_body(src: String, signature: String) -> String:
	var start: int = src.find(signature)
	if start < 0:
		return ""
	var next: int = src.find("\nfunc ", start + signature.length())
	if next < 0:
		return src.substr(start)
	return src.substr(start, next - start)
