extends GutTest

## A party move opened with two spellings (battle 22809, PR #402): Confirm logged "★ All-Out Attack initiated! ★" in its
## own colour, while the Advance-commit branch logged "All Out Attack" in cyan for every move. Both paths ask one helper now.

const MENU_PATH := "res://src/battle/BattleCommandMenu.gd"


func test_each_party_move_has_its_name_and_colour() -> void:
	assert_eq(BattleCommandMenu.group_attack_banner("all_out_attack"), "[color=orange]★ All-Out Attack initiated! ★[/color]")
	assert_eq(BattleCommandMenu.group_attack_banner("limit_break"), "[color=orange]★ Limit Break initiated! ★[/color]")
	assert_eq(BattleCommandMenu.group_attack_banner("combo_magic"), "[color=magenta]★ Combo Magic initiated! ★[/color]")
	assert_eq(BattleCommandMenu.group_attack_banner("formation", "iron_wall"), "[color=cyan]★ Iron Wall initiated! ★[/color]")


func test_every_launch_path_asks_the_one_helper() -> void:
	var src := FileAccess.get_file_as_string(MENU_PATH)
	assert_gt(src.length(), 0, "read %s" % MENU_PATH)
	var callers := 0
	var hand_built: Array = []
	for line in src.split("\n"):
		if "group_attack_banner(" in line and not line.strip_edges().begins_with("static func"):
			callers += 1
		if "initiated! ★" in line and not line.strip_edges().begins_with("return"):
			hand_built.append(line.strip_edges())
	assert_eq(callers, 2, "Confirm and the Advance commit each announce through the helper")
	assert_eq(hand_built, [], "a launch path spells its own banner")
