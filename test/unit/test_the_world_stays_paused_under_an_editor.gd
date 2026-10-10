extends GutTest

## Opening Auto Rules or Autogrind from the field menu left the world RUNNING under the editor: OverworldMenu emits its
## action and THEN `closed`, and the close handler resumed exploration after the editor had paused it. The arrow keys that
## edit the grid walked the player and roaming monsters stayed live. The minimap, quest tracker and objective arrow (on
## layers above the editor's 50) also drew over it. Drives the real handlers on a GameLoop with a stub field scene; the
## two older guards here pin source text, which is how the 2026-07-13 fix stayed green while the bug was still live.

const GL := preload("res://src/GameLoop.gd")


class StubField extends Node:
	var paused := false
	var resumes := 0
	var _minimap: CanvasLayer
	var _quest_tracker: CanvasLayer

	func pause() -> void:
		paused = true

	func resume() -> void:
		paused = false
		resumes += 1


var _gl: Node
var _field: StubField


func before_each() -> void:
	_gl = GL.new()
	autofree(_gl)
	_field = StubField.new()
	_field._minimap = CanvasLayer.new()
	_field._quest_tracker = CanvasLayer.new()
	_field.add_child(_field._minimap)
	_field.add_child(_field._quest_tracker)
	add_child_autofree(_field)
	_gl._exploration_scene = _field


func _open_editor_stub() -> void:
	_gl._autobattle_editor = Control.new()
	autofree(_gl._autobattle_editor)


func test_closing_the_menu_with_no_editor_resumes_the_world() -> void:
	# CONTROL: the plain back-to-field close must still resume and bring the HUD back.
	_field.pause()
	_gl._set_field_hud_hidden(true)
	_gl._on_overworld_menu_closed()
	assert_false(_field.paused, "backing out of the menu resumes exploration")
	assert_true(_field._minimap.visible, "and brings the minimap back")


func test_the_menu_closing_behind_an_editor_does_not_resume_the_world() -> void:
	_field.pause()
	_gl._set_field_hud_hidden(true)
	_open_editor_stub()
	_gl._on_overworld_menu_closed()
	assert_true(_field.paused, "the world stays paused under the editor the menu just opened")
	assert_eq(_field.resumes, 0, "exploration was never resumed")
	assert_false(_field._minimap.visible, "the minimap stays hidden under the editor")
	assert_false(_field._quest_tracker.visible, "the quest tracker stays hidden under the editor")


func test_a_second_hide_does_not_forget_what_the_first_hid() -> void:
	_gl._set_field_hud_hidden(true)
	_gl._set_field_hud_hidden(true)
	assert_false(_field._minimap.visible, "CONTROL: hidden")
	_gl._set_field_hud_hidden(false)
	assert_true(_field._minimap.visible, "the menu's hide then the editor's hide still restore the minimap")
	assert_true(_field._quest_tracker.visible, "and the quest tracker")


func test_closing_the_editor_brings_the_world_and_hud_back() -> void:
	_field.pause()
	_gl._set_field_hud_hidden(true)
	_open_editor_stub()
	_gl._on_overworld_menu_closed()
	_gl.current_state = _gl.LoopState.EXPLORATION
	_gl._on_autobattle_editor_closed()
	assert_false(_field.paused, "closing the editor resumes exploration")
	assert_true(_field._minimap.visible, "and restores the minimap")


func test_the_editors_hide_the_hud_when_they_open() -> void:
	# The openers build real UI and need a live tree, so this half is pinned at the source: hide precedes the layer.
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	for fn in ["func _open_autobattle_for_character", "func _open_autogrind_ui"]:
		var i := src.find(fn)
		var body := src.substr(i, src.find("\nfunc ", i + 1) - i)
		assert_true("_set_field_hud_hidden(true)" in body, "%s hides the field HUD" % fn)
