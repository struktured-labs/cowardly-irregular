extends GutTest

## Log-hygiene tick 2026-07-03. Two chronic console polluters:
## 1. The spotlight-locked CMD-MENU silent-return push_warned EVERY
##    selection phase (4 PCs × every round in early-game battles),
##    drowning real warnings in the logs these mining ticks read.
##    Now a once-per-PC-per-session print via a static dedupe dict.
## 2. "X reached job level N!" printed inside gain_job_exp, BEFORE the
##    caller's "gained N job EXP" line — consequence before cause
##    (same class as the deferred defeat announcement).

const MenuScript = preload("res://src/battle/BattleCommandMenu.gd")


class SceneStub extends Node:
	var active_win98_menu = null


func before_each() -> void:
	MenuScript._spotlight_logged.clear()


func _locked_pc(pc_name: String) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = pc_name
	c.autobattle_locked = true
	autofree(c)
	return c


func test_spotlight_silent_return_logs_once_per_pc() -> void:
	var stub := SceneStub.new()
	add_child_autofree(stub)
	var menu = MenuScript.new(stub)
	var rogue := _locked_pc("Rogue")
	menu.show_win98_command_menu(rogue)
	menu.show_win98_command_menu(rogue)
	menu.show_win98_command_menu(rogue)
	assert_eq(MenuScript._spotlight_logged.size(), 1,
		"three locked opens must dedupe to one log entry")
	menu.show_win98_command_menu(_locked_pc("Bard"))
	assert_eq(MenuScript._spotlight_logged.size(), 2,
		"a different PC still gets its own (single) line")


func test_spotlight_silent_return_no_longer_push_warns() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleCommandMenu.gd")
	assert_false(src.contains("push_warning(\"[CMD-MENU] silent-return: spotlight-locked"),
		"spotlight lock is by-design — per-phase push_warning was log spam")


func test_level_up_print_is_deferred() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/Combatant.gd")
	assert_true(src.contains("call_deferred(\"_print_level_up_line\""),
		"level-up line must defer or it prints before the EXP gain that caused it")
	assert_true(src.contains("func _print_level_up_line"),
		"deferred target must exist")
