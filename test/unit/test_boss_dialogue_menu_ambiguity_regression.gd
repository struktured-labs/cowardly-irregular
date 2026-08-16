extends GutTest

## struktured 2026-08-15 (mage spotlight duel vs Prismatic Construct): the boss
## spoke mid-selection while the command menu was open — BattleDialogue and
## Win98Menu both listen for ui_accept in _input, so one A press was ambiguous
## (ack the dialogue? pick the action?). Ownership rule: while boss dialogue is
## visible it OWNS the screen — the command menu hides (or spawns hidden) and
## comes back when the dialogue finishes, only if selection is still running.

const BS := "res://src/battle/BattleScene.gd"


func test_hidden_win98_menu_never_consumes_input() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")
	var fn_idx := src.find("func _input")
	var next_fn := src.find("\nfunc ", fn_idx + 1)
	var body := src.substr(fn_idx, (next_fn - fn_idx) if next_fn > -1 else -1)
	var vis_guard := body.find("if not visible:")
	var first_action := body.find("is_action_pressed")
	assert_gt(vis_guard, -1, "_input must bail when the menu is hidden")
	assert_lt(vis_guard, first_action, "the visibility bail must precede ALL action handling")


func test_mid_battle_boss_lines_route_through_the_hiding_helper() -> void:
	var src := FileAccess.get_file_as_string(BS)
	var helper_idx := src.find("func _show_boss_dialogue")
	assert_gt(helper_idx, -1, "hiding helper exists")
	var helper := src.substr(helper_idx, src.find("\nfunc ", helper_idx + 1) - helper_idx)
	var hide := helper.find("set_command_menu_visible(false)")
	var show := helper.find("show_boss_intro")
	assert_gt(hide, -1, "helper hides the command menu")
	assert_lt(hide, show, "menu hides BEFORE the dialogue appears — no ambiguous frame")
	# Direct show_boss_intro calls: 1 in the helper + 1 in the pre-menu intro path. Any more = an unrouted mid-battle site.
	assert_eq(src.count("_battle_dialogue.show_boss_intro("), 2,
		"defeat + low_hp boss lines must route through _show_boss_dialogue, not call the dialogue directly")


func test_dialogue_finish_restores_the_menu_only_mid_selection() -> void:
	var src := FileAccess.get_file_as_string(BS)
	var fn_idx := src.find("func _on_dialogue_finished")
	var body := src.substr(fn_idx, src.find("\nfunc ", fn_idx + 1) - fn_idx)
	var guard := body.find("BattleManager.is_selecting()")
	var restore := body.find("set_command_menu_visible(true)")
	assert_gt(guard, -1, "restore is guarded on selection phase")
	assert_gt(restore, guard, "never resurrect the menu over a victory screen or mid-execution")


func test_menu_spawning_under_active_dialogue_starts_hidden() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleCommandMenu.gd")
	assert_true("_dialogue_owns_screen" in src, "spawn-time dialogue check exists")
	assert_true("visible = not _dialogue_owns_screen" in src,
		"a menu created while the boss is speaking must start hidden — else the ambiguity returns through the spawn path")
