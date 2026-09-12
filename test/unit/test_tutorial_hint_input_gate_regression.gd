extends GutTest

## Playtest 2026-07-12: pressing a button to dismiss a tutorial hint at the top
## of the battle screen ALSO triggered a menu action (confirm/advance). Root
## cause: TutorialHint._input calls get_viewport().set_input_as_handled(), but
## that does NOT stop sibling _input() handlers — Win98Menu._input and
## BattleScene._input both read the same press. Fix: TutorialHint exposes a
## static is_any_active() gate and those _input handlers bail while it's true.
## Also pins the dying-menu guard (one press must not double-Advance).


func test_is_any_active_tracks_hint_lifecycle() -> void:
	var hint = TutorialHint.new()
	add_child_autofree(hint)  # triggers _ready -> _build_ui so _panel exists
	# Fresh id so show_hint's once-per-save dedup doesn't short-circuit.
	TutorialHint._shown_hints.erase("__gate_test__")
	if GameState:
		GameState.game_constants.erase("tutorial___gate_test__")
	var before: int = TutorialHint._active_count
	assert_false(TutorialHint.is_any_active() and before == 0,
		"sanity: count matches is_any_active before show")
	hint.show_hint("__gate_test__", "Title", "Body")
	assert_true(TutorialHint.is_any_active(), "a shown hint must gate input")
	assert_eq(TutorialHint._active_count, before + 1, "activation increments the gate count")
	hint._dismiss()
	assert_eq(TutorialHint._active_count, before, "dismiss restores the gate count (no leak)")
	# Cleanup shared static + save state.
	TutorialHint._shown_hints.erase("__gate_test__")
	if GameState:
		GameState.game_constants.erase("tutorial___gate_test__")


func test_exit_tree_releases_gate_if_freed_while_active() -> void:
	# If the battle scene is freed mid-hint the count must not stick > 0
	# forever (that would permanently block battle input next battle).
	var hint = TutorialHint.new()
	add_child(hint)
	TutorialHint._shown_hints.erase("__gate_test2__")
	if GameState:
		GameState.game_constants.erase("tutorial___gate_test2__")
	var before: int = TutorialHint._active_count
	hint.show_hint("__gate_test2__", "T", "B")
	assert_eq(TutorialHint._active_count, before + 1)
	hint.free()  # freed while still active — _exit_tree must release the gate
	assert_eq(TutorialHint._active_count, before, "freeing an active hint must release the gate")
	TutorialHint._shown_hints.erase("__gate_test2__")
	if GameState:
		GameState.game_constants.erase("tutorial___gate_test2__")


## FOLLOWS THE CALL since 2026-09-12. This read 700 chars after `func _input(` and required the
## guard text to be there. The guards moved into _nav_is_blocked(), which _input calls on its
## first line and the hold-to-repeat path now calls too — so the claim is unchanged and its
## ANCHOR was wrong. The closing-menu half is driven; the hint half stays source-read because
## no test here can make TutorialHint.is_any_active() true, and a weaker arm is worse than an
## honest one.
func test_win98_menu_input_gates_on_hint_and_dying_menu() -> void:
	var menu = load("res://src/ui/Win98Menu.gd").new()
	add_child_autofree(menu)
	menu.setup("Command", [
		{"id": "attack", "label": "Attack"},
		{"id": "item", "label": "Item"},
	], Vector2(10, 10), "fighter")
	menu._can_accept_input = true
	menu.selected_index = 0
	menu._is_closing = true
	var ev := InputEventAction.new()
	ev.action = "ui_down"
	ev.pressed = true
	menu._input(ev)
	assert_eq(menu.selected_index, 0,
		"a dying/closing menu must bail so one press can't double-Advance")
	menu._is_closing = false
	menu._input(ev)
	assert_eq(menu.selected_index, 1,
		"CONTROL: not closing, the identical press steps — the arm above is not a dead harness")

	var src := FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")
	var i := src.find("func _nav_is_blocked(")
	assert_gt(i, -1, "the shared refusal predicate must exist")
	var body := src.substr(i, src.find("\nfunc ", i + 1) - i)
	assert_true("TutorialHint.is_any_active()" in body,
		"the predicate must bail while a tutorial hint captures input")
	assert_true("is_queued_for_deletion()" in body and "_is_closing" in body,
		"…and for a dying/closing menu")
	var ii := src.find("func _input(")
	var ihead := src.substr(ii, 200)
	assert_true("_nav_is_blocked()" in ihead,
		"_input must consult the predicate FIRST — a guard nothing calls is decoration")


func test_battle_scene_input_gates_on_hint() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var i := src.find("func _input(")
	assert_gt(i, -1, "BattleScene._input must exist")
	var head := src.substr(i, 300)
	assert_true("TutorialHint.is_any_active()" in head,
		"BattleScene._input must bail while a tutorial hint captures input (Select/speed/formation must not fire on the dismiss press)")
