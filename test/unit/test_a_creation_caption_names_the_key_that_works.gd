extends GutTest

## The character creation instruction bar derived its PAD token and hardcoded its KEYBOARD one.
## `_route("ui_accept", "Z")` returned "Z" outright whenever no pad was attached -- true before
## struktured's 2026-09-29 emulator ruling (X=Confirm, Z=Back) and exactly inverted after it.
## The first screen a new player sees told them "[Z] Next Char  [X] Back" while X confirms.
## Caught by rendering the screen, not by reading it.
##
## These arms pin the DERIVATION, never the letters: a caption that happens to read "X" today
## because someone retyped it must still fail, so each arm REBINDS the action and requires the
## caption to follow.

const SCREEN := "res://src/ui/CharacterCreationScreen.gd"

var _saved: Array[InputEvent] = []


func before_each() -> void:
	_saved.clear()
	for ev in InputMap.action_get_events("ui_accept"):
		_saved.append(ev)


func after_each() -> void:
	InputMap.action_erase_events("ui_accept")
	for ev in _saved:
		InputMap.action_add_event("ui_accept", ev)


func _caption_token(scr: Object, action: String, fallback: String) -> String:
	return str(scr.call("_route", action, fallback))


func test_the_keyboard_token_follows_the_real_binding() -> void:
	var scr = load(SCREEN).new()
	assert_true(scr.has_method("_route"), "FLOOR: _route is the caption's key router")
	autofree(scr)

	## CONTROL: with the shipped binding the token is the shipped key, not the fallback literal.
	var live: String = _caption_token(scr, "ui_accept", "ZZZ")
	assert_ne(live, "ZZZ",
		"the caption returned its FALLBACK with ui_accept bound -- the keyboard half is not derived")

	## Now rebind and require the caption to move with it. A hardcoded literal cannot.
	InputMap.action_erase_events("ui_accept")
	var ev := InputEventKey.new()
	ev.keycode = KEY_J
	InputMap.action_add_event("ui_accept", ev)
	var after: String = _caption_token(scr, "ui_accept", "ZZZ")
	assert_eq(after, "J",
		"rebinding ui_accept to J must change the caption; got '%s'. A frozen literal reds here." % after)
	assert_ne(after, live, "CONTROL: the token must actually have CHANGED, or this arm proves nothing")


func test_accept_and_cancel_are_not_swapped() -> void:
	var scr = load(SCREEN).new()
	autofree(scr)
	var acc: String = _caption_token(scr, "ui_accept", "?")
	var can: String = _caption_token(scr, "ui_cancel", "?")
	assert_ne(acc, can, "FLOOR: Confirm and Back must not name the same key")
	## Derived from the InputMap, so this states the RELATIONSHIP rather than pinning X/Z.
	assert_eq(acc, InputProfileManager.first_key_label("ui_accept", "?"),
		"the Next Char token must be ui_accept's own key")
	assert_eq(can, InputProfileManager.first_key_label("ui_cancel", "?"),
		"the Back token must be ui_cancel's own key")


func test_the_router_does_not_return_its_fallback_when_a_binding_exists() -> void:
	## Source arm: the defect's shape was `return key` before consulting the InputMap.
	var src: String = GdSource.code_of(SCREEN)
	var i: int = src.find("func _route(")
	assert_gt(i, -1, "FLOOR: _route must exist to be judged")
	var body: String = src.substr(i, 420)
	assert_true(body.contains("first_key_label"),
		"_route must derive the keyboard label from the InputMap, not take it from its argument")
