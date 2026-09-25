extends GutTest

## Quit to Title leaves the last door's spawn name in GameLoop._spawn_point
## and a battle/grind return coordinate in _player_position. New Game forces
## the overworld, then _start_exploration places the player with both latches.
## Walking out of Harmonia and starting over dropped the new party on
## village_entrance; a grind's last tile did the same via _player_position.
## Area transitions still need the latches, so the clear belongs on New Game
## and not on every scene entry.

const GameLoopScript := preload("res://src/GameLoop.gd")
const BattleSceneScript := preload("res://src/battle/BattleScene.gd")

## In the tree only so the handler can await a frame. _ready would boot the title.
class QuietNewGame extends GameLoopScript:
	var seen_spawn: String = ""
	var seen_position: Vector2 = Vector2.INF
	func _ready() -> void:
		pass
	func _create_party() -> void:
		pass
	func _start_exploration(_force_battle_teardown: bool = false) -> void:
		seen_spawn = _spawn_point
		seen_position = _player_position


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
	if SaveSystem and SaveSystem.has_method("save_settings"):
		SaveSystem.save_settings()


func test_new_game_places_the_party_at_the_start_not_the_last_door() -> void:
	var gl: QuietNewGame = autofree(QuietNewGame.new())
	add_child(gl)
	gl._spawn_point = "village_entrance"
	gl._player_position = Vector2(4000, 900)
	await gl._on_title_new_game()
	assert_eq(gl.seen_spawn, "default",
		"New Game handed _start_exploration the last door (%s) — the overworld teleports there when that name exists" % gl.seen_spawn)
	assert_eq(gl.seen_position, Vector2.ZERO,
		"New Game handed _start_exploration last run's coordinates %s — that override wins over the start marker" % str(gl.seen_position))


func test_scene_entry_still_honors_a_door_spawn() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var explore: String = _fn_body(src, "func _start_exploration")
	assert_false(explore.contains("_spawn_point = \"default\""),
		"_start_exploration must keep the door's spawn — resetting it here would dump every transition on the default marker")
	assert_true(explore.contains("spawn_player_at(_spawn_point)"),
		"doors still place the player through the live spawn latch")
	var fresh: String = _fn_body(src, "func _on_title_new_game")
	assert_true(fresh.contains("_spawn_point = \"default\""),
		"New Game is the path that must drop the last door")
	assert_true(fresh.contains("_player_position = Vector2.ZERO"),
		"New Game is the path that must drop the last coordinates")
	var spawn_clear: int = fresh.find("_spawn_point = \"default\"")
	var pos_clear: int = fresh.find("_player_position = Vector2.ZERO")
	var start_call: int = fresh.find("_start_exploration()")
	assert_lt(spawn_clear, start_call, "the door latch has to be cleared before exploration reads it")
	assert_lt(pos_clear, start_call, "the coordinate latch has to be cleared before exploration reads it")


func _fn_body(src: String, signature: String) -> String:
	var start: int = src.find(signature)
	if start < 0:
		return ""
	var next: int = src.find("\nfunc ", start + signature.length())
	if next < 0:
		return src.substr(start)
	return src.substr(start, next - start)
