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


func test_win98_menu_input_gates_on_hint_and_dying_menu() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")
	var i := src.find("func _input(")
	assert_gt(i, -1, "Win98Menu._input must exist")
	var head := src.substr(i, 700)
	assert_true("is_queued_for_deletion()" in head and "_is_closing" in head,
		"Win98Menu._input must bail for a dying/closing menu so one press can't double-Advance")
	assert_true("TutorialHint.is_any_active()" in head,
		"Win98Menu._input must bail while a tutorial hint captures input")


func test_battle_scene_input_gates_on_hint() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var i := src.find("func _input(")
	assert_gt(i, -1, "BattleScene._input must exist")
	var head := src.substr(i, 300)
	assert_true("TutorialHint.is_any_active()" in head,
		"BattleScene._input must bail while a tutorial hint captures input (Select/speed/formation must not fire on the dismiss press)")
