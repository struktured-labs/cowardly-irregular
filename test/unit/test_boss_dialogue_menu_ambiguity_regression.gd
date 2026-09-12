extends GutTest

## struktured 2026-08-15 (mage spotlight duel vs Prismatic Construct): the boss
## spoke mid-selection while the command menu was open — BattleDialogue and
## Win98Menu both listen for ui_accept in _input, so one A press was ambiguous
## (ack the dialogue? pick the action?). Ownership rule: while boss dialogue is
## visible it OWNS the screen — the command menu hides (or spawns hidden) and
## comes back when the dialogue finishes, only if selection is still running.

const BS := "res://src/battle/BattleScene.gd"


## BEHAVIOURAL since 2026-09-12. This asserted that the literal text `if not visible:` sat
## inside _input's body ABOVE the first is_action_pressed — a claim about WHERE the guard
## lives. The guards moved into the shared _nav_is_blocked() predicate (so the hold-to-repeat
## path honours them too, which it did not), and this went red on a strictly better tree.
## Driving the menu answers the question the test name asks, and cannot be broken by a move.
func test_hidden_win98_menu_never_consumes_input() -> void:
	var menu = load("res://src/ui/Win98Menu.gd").new()
	add_child_autofree(menu)
	menu.setup("Command", [
		{"id": "attack", "label": "Attack"},
		{"id": "item", "label": "Item"},
	], Vector2(10, 10), "fighter")
	menu._can_accept_input = true
	menu.selected_index = 0
	menu.visible = false

	var picked := {"v": false}
	if menu.has_signal("item_selected"):
		menu.item_selected.connect(func(_a = null, _b = null): picked["v"] = true)

	for action in ["ui_down", "ui_accept"]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = true
		menu._input(ev)

	assert_eq(menu.selected_index, 0,
		"a HIDDEN menu must not act on navigation — boss dialogue hides the command menu and " +
		"owns the press (struktured 2026-08-15 spotlight-duel ambiguity)")
	assert_false(picked["v"], "…and must not confirm a selection either")

	# CONTROL: the same harness on a VISIBLE menu must move, or the arm above is vacuous.
	menu.visible = true
	var ev2 := InputEventAction.new()
	ev2.action = "ui_down"
	ev2.pressed = true
	menu._input(ev2)
	assert_eq(menu.selected_index, 1,
		"CONTROL: visible, the identical press MUST step — otherwise 'hidden did nothing' is " +
		"just a harness that does nothing")


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
