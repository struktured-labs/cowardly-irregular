extends GutTest

## The console's battle log trims itself at BATTLE_LOG_MAX_LINES by re-inserting get_parsed_text(), which is the text with
## its BBCode stripped. Past 400 lines every warning lost its colour, and any line carrying literal brackets was fed back
## through the BBCode parser. (Unknown tags display literally in Godot 4, so only the colour loss is visible.)

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


func _fill_past_the_cap() -> void:
	for i in _ui.BATTLE_LOG_MAX_LINES + 20:
		_ui._log_message("[color=red]Warning %d[/color]" % i)


func test_a_trimmed_log_keeps_its_colour_markup() -> void:
	_fill_past_the_cap()
	assert_lte(_ui._battle_log.get_line_count(), _ui.BATTLE_LOG_MAX_LINES + 1, "CONTROL: the trim must have run")
	assert_string_contains(_ui._battle_log.get_parsed_text(), "Warning %d" % (_ui.BATTLE_LOG_MAX_LINES + 19),
		"CONTROL: the newest line must be shown")
	assert_string_contains(_ui._battle_log.text, "[color=red]Warning %d[/color]" % (_ui.BATTLE_LOG_MAX_LINES + 19),
		"trimming the log stripped every line's colour")
	assert_false(_ui._battle_log.get_parsed_text().contains("Warning 0\n"), "and the oldest line must be gone")
