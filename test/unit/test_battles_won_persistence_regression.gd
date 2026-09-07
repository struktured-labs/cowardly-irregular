extends GutTest

## tick 418: GameState owns battles_won as the canonical persistent
## counter. Pre-fix this lived only on GameLoop as a session-local
## int that never made it to save data. SaveSystem and
## CutsceneDirector both tried to read a non-existent
## BattleManager.total_battles_won field and silently got 0;
## CutsceneDirector's "playstyle has been more automated" gating
## (requires >= 20 battles) never fired regardless of how much the
## player actually played.
##
## Migration: GameState.battles_won is the truth, GameLoop's
## session-local mirror syncs to it on every victory, SaveSystem +
## CutsceneDirector read from GameState.

const GAME_STATE_PATH := "res://src/meta/GameState.gd"
const GAME_LOOP_PATH := "res://src/GameLoop.gd"
const SAVE_SYSTEM_PATH := "res://src/save/SaveSystem.gd"
const CUTSCENE_DIRECTOR_PATH := "res://src/cutscene/CutsceneDirector.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_game_state_declares_battles_won() -> void:
	var src := _read(GAME_STATE_PATH)
	assert_true(src.contains("var battles_won: int = 0"),
		"GameState must declare battles_won as the canonical persistent counter")


func test_game_state_persists_battles_won_in_to_dict() -> void:
	var src := _read(GAME_STATE_PATH)
	var fn_idx: int = src.find("func _create_save_data")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("\"battles_won\": battles_won"),
		"_create_save_data must include battles_won")


func test_game_state_restores_battles_won_in_from_dict() -> void:
	var src := _read(GAME_STATE_PATH)
	var fn_idx: int = src.find("func _apply_save_data")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("save_data.has(\"battles_won\")"),
		"_apply_save_data must restore battles_won")
	# Defense against corrupted negatives.
	assert_true(body.contains("max(0, int(save_data[\"battles_won\"]))"),
		"_apply_save_data must clamp battles_won to >= 0 on load")


func test_game_loop_syncs_to_game_state() -> void:
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func _on_battle_ended")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("GameState.battles_won += 1"),
		"_on_battle_ended victory path must sync to GameState.battles_won")


func test_save_system_reads_game_state_not_battle_manager() -> void:
	var src := _read(SAVE_SYSTEM_PATH)
	# Negative pin: the dead BattleManager.total_battles_won read must be gone.
	assert_false(src.contains("BattleManager.total_battles_won"),
		"SaveSystem must NOT read the non-existent BattleManager.total_battles_won — read GameState.battles_won instead")
	assert_true(src.contains("GameState.battles_won"),
		"SaveSystem must read GameState.battles_won as the canonical source")


func test_cutscene_director_reads_game_state_not_battle_manager() -> void:
	var src := _read(CUTSCENE_DIRECTOR_PATH)
	# Negative pin: the dead BattleManager.total_battles_won read must be gone.
	assert_false(src.contains("BattleManager.total_battles_won"),
		"CutsceneDirector must NOT read the non-existent BattleManager.total_battles_won")
	assert_true(src.contains("GameState.battles_won"),
		"CutsceneDirector must read GameState.battles_won for automation-ratio gating")


func test_round_trip_preserves_battles_won() -> void:
	if not GameState:
		pending("GameState autoload required")
		return
	var prior_count: int = GameState.battles_won
	GameState.battles_won = 42
	var save_data: Dictionary = GameState._create_save_data()
	GameState.battles_won = 0
	GameState._apply_save_data(save_data)
	assert_eq(GameState.battles_won, 42,
		"battles_won must survive a save+load round-trip")
	GameState.battles_won = prior_count
