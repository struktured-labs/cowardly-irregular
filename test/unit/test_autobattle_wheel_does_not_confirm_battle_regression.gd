extends GutTest

## Playtest 2026-09-20: "while in the ability wheel on autobattle mind I
## somehow selected options in the live battle."
##
## Win98Menu submenus are SIBLINGS (`get_parent().add_child(submenu)`), so
## set_command_menu_visible(false) hiding only active_win98_menu leaves a
## live-battle ability list receiving _input. Confirm on the autobattle
## RadialPicker also confirms that list. Hold-A already refused to open
## the editor under a submenu; F5 / Start did not close it.

const BS := "res://src/battle/BattleScene.gd"
const WIN := "res://src/ui/Win98Menu.gd"
const ED := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const RING := "res://src/ui/RadialPicker.gd"


func _fn(src: String, name: String) -> String:
	var i: int = src.find("func %s" % name)
	assert_gt(i, -1, "floor: %s exists" % name)
	var nxt: int = src.find("\nfunc ", i + 1)
	return src.substr(i, (nxt - i) if nxt > -1 else 900)


func test_hiding_the_command_menu_closes_sibling_submenus() -> void:
	var body: String = _fn(FileAccess.get_file_as_string(BS), "set_command_menu_visible")
	assert_true("submenu" in body,
		"hiding the root must close the sibling submenu — visible=false on the root does not hide it")
	assert_true("force_close" in body,
		"use force_close so nested target-pickers die with the ability list, not hide-and-linger")


func test_win98_menu_refuses_input_while_the_autobattle_editor_is_open() -> void:
	var body: String = _fn(FileAccess.get_file_as_string(WIN), "_nav_is_blocked")
	assert_true("autobattle_grid_editor" in body,
		"_nav_is_blocked must consult the editor group — hiding the root is not enough if a sibling submenu survived")


func test_editor_registers_the_group_win98_consults() -> void:
	var src: String = FileAccess.get_file_as_string(ED)
	assert_true('add_to_group("autobattle_grid_editor")' in src,
		"the editor must join the group Win98Menu's block reads, or the block is dead")


func test_a_visible_editor_blocks_win98_nav() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var menu: Node = load(WIN).new()
	host.add_child(menu)
	autofree(menu)
	menu.visible = true
	menu._can_accept_input = true
	assert_false(menu._nav_is_blocked(), "CONTROL: a lone visible menu is not blocked")
	var ed := Control.new()
	ed.add_to_group("autobattle_grid_editor")
	ed.visible = true
	host.add_child(ed)
	autofree(ed)
	assert_true(menu._nav_is_blocked(),
		"a visible autobattle editor must freeze the battle menu — that is the leak")


func test_option_picker_input_does_not_assume_list_meta_on_the_ring() -> void:
	var body: String = _fn(FileAccess.get_file_as_string(ED), "_handle_option_picker_input")
	assert_true("RadialPicker" in body,
		"_handle_option_picker_input must no-op for RadialPicker — get_meta(\"spec\") is the list picker's storage and aborts on the ring")
