extends GutTest

## The console's "Restore Shipped Profiles" row (.837) opened the rules editor without saving the console's grid. The
## editor reads the SAVED profile, and on close the console adopts whatever is saved, so answering the restore prompt
## with Back silently erased every unsaved edit made in the console. The row now saves the grid first; a grid the
## validator refuses keeps the editor shut and stays on screen.
## An EMPTY saved profile opens the editor's composer on setup, whose input gate sat above the prompt's, so the prompt ignored Confirm
## and Back (.839: clear every rule, Switch away and back, Restore). The prompt now dismisses that splash. An unloaded console saves nothing.
## Arms: Back keeps the unsaved grid · Confirm still restores · a refused grid opens nothing · an emptied grid's prompt answers Confirm and
## Back · the shipped clear/switch/restore path · an unloaded console never overwrites a saved profile through Restore or Switch.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const UI := "res://src/ui/autogrind/AutogrindUI.gd"
const PLANTED_RULE := {"enabled": true, "conditions": [{"type": "battles_done", "op": ">=", "value": 7}], "actions": [{"type": "stop_grinding"}]}

var _ag: Dictionary
var _vp: SubViewport
var _ui: Control


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	add_child_autofree(_vp)
	_ui = load(UI).new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vp.add_child(_ui)
	await get_tree().process_frame
	_ui._is_grinding = false
	_ui._load_rules()  # as setup() does in play


func after_each() -> void:
	var ed = _ui._rules_editor_open if _ui and is_instance_valid(_ui) else null
	if ed and is_instance_valid(ed):
		ed.queue_free()
	if _ui and is_instance_valid(_ui):
		_ui.queue_free()
	AutogrindState.restore(_ag)


func _pad(button: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = true
	return e


## Plants an unsaved grid, chooses the row, and returns the editor it opened (null if none).
func _choose_row_over(grid: Array) -> Control:
	_ui.rules = grid.duplicate(true)
	assert_ne(AutogrindSystem.get_autogrind_rules(), _ui.rules, "CONTROL: the console's grid is not yet saved")
	_ui._commit_autogrind_option("restore_defaults")
	return _ui._rules_editor_open


func test_back_keeps_the_unsaved_grid() -> void:
	var ed := _choose_row_over([PLANTED_RULE])
	assert_not_null(ed, "PRECONDITION: the row opened the rules editor")
	if ed == null:
		return
	ed._input(_pad(JOY_BUTTON_A))
	assert_null(ed._reset_confirm, "PRECONDITION: Back closed the prompt")
	ed.closed.emit()
	assert_eq(_ui.rules, [PLANTED_RULE], "answering the restore prompt with Back erased the console's unsaved grid")
	assert_eq(AutogrindSystem.get_autogrind_rules(), [PLANTED_RULE], "and the grid is in its profile, not only on screen")


func test_confirm_still_restores() -> void:
	var ed := _choose_row_over([PLANTED_RULE])
	assert_not_null(ed, "PRECONDITION: the row opened the rules editor")
	if ed == null:
		return
	ed._input(_pad(JOY_BUTTON_B))
	ed.closed.emit()
	assert_ne(_ui.rules, [PLANTED_RULE], "Confirm must still replace the grid with the shipped rules")
	assert_eq(_ui.rules, AutogrindSystem.get_autogrind_rules(), "and the console shows what was restored")


func test_a_refused_grid_opens_nothing_and_stays() -> void:
	var junk: Array = ["not a rule"]
	var ed := _choose_row_over(junk)
	assert_null(ed, "a grid the validator refuses must not open an editor that would replace it on close")
	assert_eq(_ui.rules, junk, "and the refused grid stays on screen")


func _profile_count() -> int:
	return AutogrindSystem.get_autogrind_profiles().size()


func test_an_emptied_grid_answers_confirm() -> void:
	var ed := _choose_row_over([])
	assert_not_null(ed, "PRECONDITION: the row opened the rules editor")
	if ed == null:
		return
	assert_not_null(ed._reset_confirm, "PRECONDITION: the prompt is up")
	ed._input(_pad(JOY_BUTTON_B))
	assert_null(ed._reset_confirm, "on an emptied grid the restore prompt ignored Confirm")
	ed.closed.emit()
	assert_false(_ui.rules.is_empty(), "and Confirm restored the shipped rules")


func test_an_emptied_grid_answers_back_and_stays_empty() -> void:
	var ed := _choose_row_over([])
	if ed == null:
		assert_not_null(ed, "PRECONDITION: the row opened the rules editor")
		return
	ed._input(_pad(JOY_BUTTON_A))
	assert_null(ed._reset_confirm, "on an emptied grid the restore prompt ignored Back")
	assert_eq(_drawn_rows(ed), ed.rules.size(), "the editor's drawn grid disagrees with its rules after the splash was dismissed")
	ed.closed.emit()
	assert_eq(AutogrindSystem.get_autogrind_rules(), [], "Back keeps the SAVED profile the player emptied")


func _drawn_rows(ed: Control) -> int:
	var n := 0
	for c in ed._grid_container.get_children():
		if not c.is_queued_for_deletion() and str(c.get_meta("cell_type", "")) == "toggle":
			n += 1
	return n


func test_the_shipped_path_clear_switch_back_restore() -> void:
	var n := _profile_count()
	assert_gt(n, 1, "PRECONDITION: a second profile to switch through")
	_ui.rules = []
	for i in range(n):
		_ui._commit_autogrind_option("next_profile")
	assert_eq(_ui.rules, [], "CONTROL: back on the emptied profile, as a player gets there on .839")
	_ui._commit_autogrind_option("restore_defaults")
	var ed: Control = _ui._rules_editor_open
	assert_not_null(ed, "PRECONDITION: the row opened the rules editor")
	if ed == null:
		return
	ed._input(_pad(JOY_BUTTON_B))
	assert_null(ed._reset_confirm, "the restore prompt over an empty profile ignored Confirm")


func test_an_unloaded_console_never_overwrites_a_saved_profile() -> void:
	var fresh: Control = load(UI).new()
	fresh.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vp.add_child(fresh)
	await get_tree().process_frame
	fresh._is_grinding = false
	var saved: Array = AutogrindSystem.get_autogrind_rules().duplicate(true)
	assert_false(saved.is_empty(), "CONTROL: the active profile has rules to lose")
	assert_true(fresh.rules.is_empty(), "CONTROL: the console never loaded its grid")
	fresh._commit_autogrind_option("restore_defaults")
	var ed = fresh._rules_editor_open
	if ed and is_instance_valid(ed):
		ed.queue_free()
	assert_eq(AutogrindSystem.get_autogrind_rules(), saved, "an unloaded console's Restore wrote its empty grid over the saved profile")
	var active := AutogrindSystem.get_active_autogrind_profile_index()
	fresh._commit_autogrind_option("next_profile")
	assert_eq((AutogrindSystem.get_autogrind_profiles()[active] as Dictionary).get("rules", []), saved, "and its Switch wrote it over the profile it left")
	fresh.queue_free()
