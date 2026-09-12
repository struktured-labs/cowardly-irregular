extends GutTest

## "Adjust rules mid-grind" was advertised on the F1 controls reference, bound in the dispatch table
## with its own key, classified by two screens, and emitted by three call sites. It was reachable
## from NONE of them.
##
## `adjust_rules_requested` had exactly one connection in all of src/ — `_monitor.adjust_rules_
## requested` inside AutogrindUI._show_monitor() — and AutogrindMonitor can never be constructed:
## its only `.new()` sits in _show_monitor(), whose only caller is a callback connected inside
## _show_monitor(). No first call. So the live Tier-1 dashboard emitted into nothing.
##
## ⛔ AND THE HANDLER WOULD HAVE OPENED AN INVISIBLE EDITOR IF IT HAD BEEN REACHED. `_toggle_grinding`
## sets AutogrindUI `visible = false` for the whole grind and restores it only at stop, while the
## handler did `add_child(editor)` — parenting the editor inside the hidden node. Two defects in
## series, which is why neither showed up as a bug report: nobody could reach the first one.

var _ui


func before_each() -> void:
	AutogrindSystem._test_disable_persistence = true
	_ui = preload("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(_ui)


func after_each() -> void:
	AutogrindSystem.stop_autogrind()
	AutogrindSystem._test_disable_persistence = false


## Combatant.new() takes no args — initialize() carries the stats.
func _probe_party() -> Array[Combatant]:
	var c := Combatant.new()
	c.initialize({"name": "Probe", "max_hp": 100, "max_mp": 50, "attack": 20, "defense": 15,
		"magic": 10, "speed": 12})
	add_child_autofree(c)
	var party: Array[Combatant] = [c]
	return party


## THE DEFECT: the editor must be visible while the console that owns it is not. This is the arm that
## reds on `add_child(editor)`.
func test_the_editor_is_visible_while_the_console_is_hidden() -> void:
	_ui.setup(_probe_party(), "Probe Region")
	await get_tree().process_frame
	await get_tree().process_frame
	# What a running grind looks like: _toggle_grinding hides the console for the whole session.
	_ui.visible = false
	assert_false(_ui.is_visible_in_tree(), "PRECONDITION: the console must be hidden, as it is mid-grind")

	var editor = _ui.open_rules_editor()
	assert_not_null(editor, "open_rules_editor must return the editor so a caller can restore its own overlay")
	if editor == null:
		return
	await get_tree().process_frame
	assert_ne(editor.get_parent(), _ui,
		("the editor must NOT be a child of the console: the console holds visible = false for the " +
		"whole grind, so a child of it can never be seen"))
	assert_true(editor.is_visible_in_tree(),
		"the mid-grind rules editor must actually be on screen — this is the whole feature")
	editor.queue_free()


## The wiring that was missing. Source-level, because GameLoop is an autoload built by the engine.
func test_the_live_dashboard_signal_is_connected() -> void:
	var gl := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_gt(gl.length(), 1000, "CONTROL: the source read must have produced a file")
	assert_true(gl.contains("_autogrind_dashboard.adjust_rules_requested.connect("),
		("nothing connects the dashboard's adjust_rules_requested, so the button it advertises emits " +
		"into no listener — the state this file was written for"))
	assert_false(gl.contains("adjust_rules_requested_zzq"),
		"CONTROL: the source read can report absence")


## The dashboard must be hidden BEFORE the editor opens, and the reason is not cosmetic: its own
## _input maps ui_cancel to exit_requested, so Cancel-to-close-the-editor would stop the grind.
func test_the_dashboard_is_hidden_before_the_editor_opens() -> void:
	var dash := FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindDashboard.gd")
	assert_true(dash.contains("if not visible:"),
		"PRECONDITION: the dashboard's _input gates on visible, which is what hiding it relies on")
	assert_true(dash.contains("exit_requested.emit()"),
		"PRECONDITION: and it maps an action to exit — the hazard hiding it avoids")

	var gl := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var at := gl.find("func _on_dashboard_adjust_rules")
	assert_gt(at, -1, "GameLoop must have the dashboard's adjust-rules handler")
	if at < 0:
		return
	var body := gl.substr(at, 900)
	var hide_at := body.find("_autogrind_dashboard.visible = false")
	var open_at := body.find("open_rules_editor()")
	assert_gt(hide_at, -1, "the handler must hide the dashboard")
	assert_gt(open_at, -1, "CONTROL: and must actually open the editor, or the order below is vacuous")
	assert_lt(hide_at, open_at,
		("the dashboard must be hidden BEFORE the editor opens: it consumes ui_cancel as exit, so a " +
		"player closing the editor would stop the grind instead"))


## Why no pause is needed: the editor writes through the checked setter, so a grind already running
## picks up the edit. If that ever stops being true, editing mid-grind becomes a silent divergence.
func test_a_saved_edit_reaches_the_running_system() -> void:
	var ed := FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindGridEditor.gd")
	assert_true(ed.contains("if not AutogrindSystem.set_autogrind_rules(rules):"),
		("the editor must write through the checked setter — that is what lets the grind keep running " +
		"while the player edits, instead of needing a pause"))
	var at := ed.find("if not AutogrindSystem.set_autogrind_rules(rules):")
	assert_gt(ed.find("rules_saved.emit(", at), at,
		"and it must emit only AFTER that call, so a refused ruleset is not announced as saved")


## CONTROL for the whole file: the signal really is emitted, from more than one screen. If these ever
## drop to zero the arms above are guarding a signal nobody sends.
func test_the_signal_really_is_emitted() -> void:
	var emitters := 0
	for path in ["res://src/ui/autogrind/AutogrindDashboard.gd", "res://src/ui/autogrind/AutogrindMonitor.gd"]:
		emitters += FileAccess.get_file_as_string(path).count("adjust_rules_requested.emit()")
	assert_gt(emitters, 1,
		"CONTROL: only %d emit sites found — the feature's input side must exist" % emitters)
	assert_eq(str(AutogrindInputHelper.ACTION_KEYS.get("adjust_rules", "")), "R",
		"and the dispatch table must still offer a key for it")
