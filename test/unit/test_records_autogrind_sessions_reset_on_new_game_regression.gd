extends GutTest

## Regression (#193): the Records page showed "Autogrind Sessions 4" on a 22-second New Game, because the row read
## AutogrindSystem.session_history — a machine-global file (capped at 10) that New Game never clears. The row now reads
## GameState.autogrind_sessions, a per-run counter saved with the run and reset on New Game. The history file itself is
## left alone: AutogrindHistoryScreen browses it across saves.

const RecordsMenuScript := preload("res://src/ui/RecordsMenu.gd")
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

var _saved_count: int = 0
var _saved_history: Array = []
var _ag: Dictionary


func before_each() -> void:
	_saved_count = GameState.autogrind_sessions
	_saved_history = AutogrindSystem.session_history.duplicate(true)
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true


func after_each() -> void:
	GameState.autogrind_sessions = _saved_count
	AutogrindSystem.session_history = _saved_history
	AutogrindState.restore(_ag)


func _sessions_row() -> Array:
	var m = RecordsMenuScript.new()
	autofree(m)
	for r in m._collect_records():
		if str(r[0]) == "Autogrind Sessions":
			return r
	return []


func test_new_game_shows_zero_sessions_even_with_old_history() -> void:
	AutogrindSystem.session_history = [{"battles": 3}, {"battles": 1}, {"battles": 9}, {"battles": 2}]
	GameState.autogrind_sessions = 4
	GameState.reset_game_state()
	var row := _sessions_row()
	assert_eq(row.size(), 3, "SCOPE: the Records page has an Autogrind Sessions row")
	assert_eq(str(row[1]) if row.size() > 1 else "", "0", "a New Game has run no autogrind sessions, whatever the machine history holds")
	assert_eq(AutogrindSystem.session_history.size(), 4, "CONTROL: New Game does not delete the cross-save history the history browser shows")


func test_a_finished_session_counts_for_this_run() -> void:
	GameState.autogrind_sessions = 0
	AutogrindSystem._record_session({"battles_completed": 2, "stop_reason": "test"}, {"elapsed_seconds": 1.0})
	assert_eq(GameState.autogrind_sessions, 1, "recording a session increments the run's count")
	assert_eq(str(_sessions_row()[1]), "1", "and the Records page shows it")


func test_the_count_survives_save_and_load_and_old_saves_read_zero() -> void:
	GameState.autogrind_sessions = 6
	var data: Dictionary = GameState.to_dict()
	assert_true(data.has("autogrind_sessions"), "the count is written to the save")
	GameState.autogrind_sessions = 0
	GameState.from_dict(data)
	assert_eq(GameState.autogrind_sessions, 6, "and restored on load")
	data.erase("autogrind_sessions")
	GameState.from_dict(data)
	assert_eq(GameState.autogrind_sessions, 0, "a save from before #193 loads as zero, not the global history")
