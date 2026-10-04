extends GutTest

## Regression (found by cowir-main's 2026-10-03 render smoke on .555): after the field Settings menu closed, GameLoop still held it,
## and _ui_is_showing(ui: Node) rejected the FREED object before its body ran. That SCRIPT ERROR aborted _field_modal_open, which
## returned false, so the Party Chat guard beside it never ran: the overworld menu could open on top of Party Chat again.

const GameLoopScript := preload("res://src/GameLoop.gd")

var _gl: Node = null
var _chat: Control = null


func before_each() -> void:
	_gl = GameLoopScript.new()
	_chat = Control.new()
	add_child_autofree(_chat)
	_chat.visible = true


func after_each() -> void:
	if is_instance_valid(_gl):
		_gl.free()


func test_a_freed_settings_menu_does_not_hide_an_open_party_chat() -> void:
	var settings := Control.new()
	add_child(settings)
	_gl._field_settings_menu = settings
	settings.free()
	_gl._party_chat_menu = _chat
	assert_true(_gl._field_modal_open(),
		"Party Chat is open; a freed Settings menu must read as not showing, not abort the whole check")


func test_ui_is_showing_answers_false_for_a_freed_node() -> void:
	var gone := Control.new()
	add_child(gone)
	gone.free()
	assert_false(GameLoopScript._ui_is_showing(gone), "a freed node is not showing")
	assert_true(GameLoopScript._ui_is_showing(_chat), "CONTROL: a live visible node in the tree is showing")
