extends GutTest

## Milo's thesis quest (world1_chapter_three) shipped data-first: its
## three "custom" objectives sat inert until battle-telemetry emitters
## existed. BattleManager._emit_c3_battle_telemetry now fires them per
## the quest's _wiring_notes spec. Behavioral tests against the real
## autoloads with full state snapshot/restore (hermetic).

const QID := "world1_chapter_three"
const F_AUTO := "quest_world1_chapter_three_autobattle_run"
const F_BASIC := "quest_world1_chapter_three_basics_only"
const F_IMPOSSIBLE := "quest_world1_chapter_three_impossible"
const STREAK_KEY := "quest_c3_auto_streak"

var _saved_quests: Dictionary
var _saved_flags: Dictionary
var _saved_streak: Variant
var _bm_full_auto: bool
var _bm_auto_turns: int
var _bm_manual_turns: int
var _bm_nonbasic: bool


func before_each() -> void:
	_saved_quests = GameState.quests.duplicate(true)
	_saved_flags = {}
	for f in [F_AUTO, F_BASIC, F_IMPOSSIBLE]:
		_saved_flags[f] = GameState.story_flags.get(f, null)
	_saved_streak = GameState.game_constants.get(STREAK_KEY, null)
	_bm_full_auto = BattleManager._full_autobattle
	_bm_auto_turns = BattleManager._autobattle_player_turns
	_bm_manual_turns = BattleManager._manual_player_turns
	_bm_nonbasic = BattleManager._c3_nonbasic_used


func after_each() -> void:
	GameState.quests = _saved_quests
	for f in _saved_flags:
		if _saved_flags[f] == null:
			GameState.story_flags.erase(f)
		else:
			GameState.story_flags[f] = _saved_flags[f]
	if _saved_streak == null:
		GameState.game_constants.erase(STREAK_KEY)
	else:
		GameState.game_constants[STREAK_KEY] = _saved_streak
	BattleManager._full_autobattle = _bm_full_auto
	BattleManager._autobattle_player_turns = _bm_auto_turns
	BattleManager._manual_player_turns = _bm_manual_turns
	BattleManager._c3_nonbasic_used = _bm_nonbasic


func _activate_quest(objective_index: int) -> void:
	GameState.quests[QID] = {"state": "active", "objective_index": objective_index}
	GameState.game_constants.erase(STREAK_KEY)
	for f in [F_AUTO, F_BASIC, F_IMPOSSIBLE]:
		GameState.story_flags.erase(f)


func _set_battle(full_auto: bool, auto_turns: int, manual_turns: int, nonbasic: bool) -> void:
	BattleManager._full_autobattle = full_auto
	BattleManager._autobattle_player_turns = auto_turns
	BattleManager._manual_player_turns = manual_turns
	BattleManager._c3_nonbasic_used = nonbasic


func test_two_consecutive_full_auto_wins_complete_exercise_one() -> void:
	_activate_quest(1)  # step 2 = objective index 1 (autobattle_run)
	_set_battle(true, 5, 0, false)
	BattleManager._emit_c3_battle_telemetry(true, false)
	assert_false(GameState.story_flags.get(F_AUTO, false),
		"one win is not enough — the exercise wants a streak of two")
	assert_eq(int(GameState.game_constants.get(STREAK_KEY, 0)), 1)
	BattleManager._emit_c3_battle_telemetry(true, false)
	assert_true(GameState.story_flags.get(F_AUTO, false), "second consecutive auto win sets the flag")
	assert_eq(QuestSystem.get_objective_index(QID), 2, "custom objective must advance via notify_flag")


func test_manual_win_or_defeat_breaks_streak() -> void:
	_activate_quest(1)
	_set_battle(true, 5, 0, false)
	BattleManager._emit_c3_battle_telemetry(true, false)
	assert_eq(int(GameState.game_constants.get(STREAK_KEY, 0)), 1)
	_set_battle(false, 2, 3, false)  # manual intervention this battle
	BattleManager._emit_c3_battle_telemetry(true, false)
	assert_eq(int(GameState.game_constants.get(STREAK_KEY, 0)), 0, "manual win resets the streak")
	_set_battle(true, 5, 0, false)
	BattleManager._emit_c3_battle_telemetry(false, false)
	assert_eq(int(GameState.game_constants.get(STREAK_KEY, 0)), 0, "defeat/escape resets the streak")


func test_basics_only_manual_win_completes_exercise_two() -> void:
	_activate_quest(3)  # step 4 = objective index 3 (basics_only)
	_set_battle(false, 0, 4, false)
	BattleManager._emit_c3_battle_telemetry(true, false)
	assert_true(GameState.story_flags.get(F_BASIC, false))
	assert_eq(QuestSystem.get_objective_index(QID), 4)


func test_ability_use_disqualifies_basics_only() -> void:
	_activate_quest(3)
	_set_battle(false, 0, 4, true)  # an ability/item was executed
	BattleManager._emit_c3_battle_telemetry(true, false)
	assert_false(GameState.story_flags.get(F_BASIC, false),
		"any player ability/item use must disqualify the basics-only win")


func test_autobattle_disqualifies_basics_only() -> void:
	_activate_quest(3)
	_set_battle(false, 2, 4, false)  # mixed auto+manual battle
	BattleManager._emit_c3_battle_telemetry(true, false)
	assert_false(GameState.story_flags.get(F_BASIC, false),
		"holding on means a manual battle — autobattle turns disqualify")


func test_one_hp_victory_completes_exercise_three() -> void:
	_activate_quest(5)  # step 6 = objective index 5 (impossible)
	_set_battle(false, 0, 3, true)
	BattleManager._emit_c3_battle_telemetry(true, true)
	assert_true(GameState.story_flags.get(F_IMPOSSIBLE, false))
	assert_eq(QuestSystem.get_objective_index(QID), 6)


func test_inactive_quest_emits_nothing() -> void:
	GameState.quests.erase(QID)
	for f in [F_AUTO, F_BASIC, F_IMPOSSIBLE]:
		GameState.story_flags.erase(f)
	GameState.game_constants.erase(STREAK_KEY)
	_set_battle(true, 5, 0, false)
	BattleManager._emit_c3_battle_telemetry(true, true)
	assert_false(GameState.game_constants.has(STREAK_KEY),
		"pre-quest battles must not track — Milo has to assign the exercises first")
	for f in [F_AUTO, F_BASIC, F_IMPOSSIBLE]:
		assert_false(GameState.story_flags.get(f, false))


func test_execution_hooks_mark_nonbasic_use() -> void:
	# Source pins: the disqualifier must be set at EXECUTION level so
	# advance-embedded ability/item use counts.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	for fn in ["_execute_ability", "_execute_item"]:
		var idx: int = src.find("func %s(" % fn)
		assert_gt(idx, -1)
		var body: String = src.substr(idx, 400)
		assert_true(body.contains("_c3_nonbasic_used = true"),
			"%s must mark non-basic use for the thesis-quest telemetry" % fn)
