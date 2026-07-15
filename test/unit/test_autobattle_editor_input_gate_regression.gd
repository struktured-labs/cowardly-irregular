extends GutTest

## 2026-07-14 (cowir-music msg 2539): "hit some button in the auto battle
## menu... it caused something to happen in battle which it should not."
##
## Root: BattleScene._input() runs before any child _input(), and its
## Y-repeat / speed-toggle / formation-hotkey branches had no editor-open
## gate. Pressing Y in the editor fired _repeat_previous_actions on the
## paused battle.
##
## Fix: track the inline editor via _active_inline_editor and early-return
## _input when it's open. Complements the existing TutorialHint gate.


func test_active_inline_editor_var_declared() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_true("var _active_inline_editor: Control" in src,
		"BattleScene must track the open inline editor so _input can gate on it")


func test_open_editor_sets_tracker() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var i := src.find("func _open_autobattle_editor_for")
	assert_gt(i, -1)
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 800)
	assert_true("_active_inline_editor = editor" in body,
		"_open_autobattle_editor_for must set the tracker so _input's gate can consult it")


func test_close_editor_clears_tracker() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var i := src.find("func _on_inline_autobattle_editor_closed")
	assert_gt(i, -1)
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 400)
	assert_true("_active_inline_editor = null" in body,
		"editor-closed handler must clear the tracker so a subsequent Y-press repeats normally")


func test_input_bails_early_when_editor_visible() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var i := src.find("func _input(event: InputEvent) -> void:")
	assert_gt(i, -1)
	# Look only at the first 700 chars of the body — the gate MUST be near top, before any hotkey branches.
	var body := src.substr(i, 700)
	assert_true("_active_inline_editor" in body,
		"_input must gate on _active_inline_editor near the top so no hotkey branch runs while editor owns input")
	assert_true("is_instance_valid(_active_inline_editor)" in body,
		"gate must validate the reference before reading .visible")
	assert_true(".visible" in body,
		"gate must confirm the editor is visible before bailing — hidden trackers shouldn't block input")
