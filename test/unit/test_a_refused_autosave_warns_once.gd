extends GutTest

## Regression (struktured's .563 play log, 2026-10-04): a game-over screen left idle from 08:59 to 11:25 logged
## "[SAVE] save_game refused: Cannot save with the whole party down" 292 times, once per 30 s autosave retry. Refusing is
## correct (the gate passes on the healthy snapshot; the post-sync check catches the flushed wipe), but the code comment says
## the refusal is meant to be quiet. It now warns once per streak and re-arms when a save gets past the party check.

const SLOT := 91

var _saved_party: Array[Dictionary] = []
var _saved_battle_state: int = 0
var _saved_slot: int = 0


func before_each() -> void:
	_saved_party = GameState.player_party.duplicate(true)
	_saved_battle_state = BattleManager.current_state
	BattleManager.current_state = BattleManager.BattleState.INACTIVE
	_saved_slot = SaveSystem.current_save_slot
	SaveSystem._last_party_refusal = ""


func after_each() -> void:
	if SaveSystem.pre_save_sync.is_connected(_flush_wipe):
		SaveSystem.pre_save_sync.disconnect(_flush_wipe)
	if SaveSystem.save_exists(SLOT):
		SaveSystem.delete_save(SLOT)
	SaveSystem.current_save_slot = _saved_slot
	GameState.player_party = _saved_party
	BattleManager.current_state = _saved_battle_state
	SaveSystem._last_party_refusal = ""


func _set_party(dead: bool) -> void:
	var typed: Array[Dictionary] = []
	for n in ["Fighter", "Cleric"]:
		typed.append({"name": n, "job_id": n.to_lower(), "is_alive": not dead, "current_hp": 0 if dead else 50})
	GameState.player_party = typed


func _flush_wipe() -> void:
	_set_party(true)


func test_a_streak_of_refusals_remembers_it_already_warned() -> void:
	_set_party(false)
	SaveSystem.pre_save_sync.connect(_flush_wipe)
	assert_false(SaveSystem.save_game(SLOT), "SCOPE: the flushed wipe is refused")
	assert_eq(SaveSystem._last_party_refusal, "Cannot save with the whole party down", "the first refusal records what it warned")
	_set_party(false)
	assert_false(SaveSystem.save_game(SLOT), "SCOPE: the retry is refused too")
	assert_eq(SaveSystem._last_party_refusal, "Cannot save with the whole party down", "the streak stays marked, so the retry is quiet")


func test_a_save_that_passes_the_party_check_re_arms_the_warning() -> void:
	SaveSystem._last_party_refusal = "Cannot save with the whole party down"
	_set_party(false)
	SaveSystem.save_game(SLOT)
	assert_eq(SaveSystem._last_party_refusal, "", "a living party clears the streak, so the next wipe warns again")


func test_the_warning_is_guarded_by_the_streak() -> void:
	var src := FileAccess.get_file_as_string("res://src/save/SaveSystem.gd")
	var i := src.find("if party_reason != _last_party_refusal:")
	assert_gt(i, -1, "the warning must be guarded by the streak marker")
	assert_true(src.substr(i, 120).contains("push_warning"), "the guarded line is the refusal warning")
