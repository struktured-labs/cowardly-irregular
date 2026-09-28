extends GutTest

## The console's BATTLE LOG was a RichTextLabel that _build_ui() recreated empty. The grind's end (set_grinding(false)),
## an interrupt and a manual stop all rebuild, so the stop reason and the session's log were gone exactly when the
## console came back on screen for the player to read them.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

var _ag_state: Dictionary
var _ui: Control


func before_each() -> void:
	_ag_state = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	_ui = load("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(_ui)
	var c := Combatant.new()
	c.initialize({"name": "Solo", "max_hp": 100, "max_mp": 10, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	var party: Array[Combatant] = [c]
	_ui.setup(party, "Test Plains")
	await wait_frames(2)


func after_each() -> void:
	_ui._disconnect_autogrind_signals()
	AutogrindState.restore(_ag_state)


func _log() -> String:
	return _ui._battle_log.get_parsed_text() if _ui._battle_log and is_instance_valid(_ui._battle_log) else ""


func test_a_message_survives_a_rebuild() -> void:
	_ui._log_message("Won battle 7 against 2 Slimes")
	assert_string_contains(_log(), "Won battle 7", "CONTROL: the message must land before the rebuild")
	_ui._build_ui()
	assert_string_contains(_log(), "Won battle 7", "a console rebuild wiped the battle log")


func test_the_grind_end_keeps_the_log() -> void:
	_ui._log_message("Won battle 12 against a Goblin")
	_ui.set_grinding(false)
	assert_string_contains(_log(), "Won battle 12", "the grind's end rebuilt the console and wiped the session's log")


func test_an_interrupt_reason_is_still_there_when_the_console_returns() -> void:
	_ui._on_interrupt_triggered("HP threshold reached (20%)")
	assert_string_contains(_log(), "HP threshold reached", "the interrupt logged its reason and then rebuilt it away")


func test_the_kept_log_is_still_bounded() -> void:
	for i in _ui.BATTLE_LOG_MAX_LINES + 50:
		_ui._log_message("line %d" % i)
	_ui._build_ui()
	assert_lte(_ui._battle_log.get_line_count(), _ui.BATTLE_LOG_MAX_LINES + 1, "the replayed log must keep the existing memory bound")
	assert_string_contains(_log(), "line %d" % (_ui.BATTLE_LOG_MAX_LINES + 49), "and keep the NEWEST lines")
	assert_false(_log().contains("line 0\n"), "and drop the oldest")
