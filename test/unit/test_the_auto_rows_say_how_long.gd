extends GutTest

## struktured 2026-09-24: "confused about Trust: ON/OFF vs Run Auto". Auto runs the script for THIS turn;
## Trust hands every turn to it until switched off. Side by side, the labels never said which lasted how
## long. 2026-10-06: relabel. The labels now carry the duration.

func test_each_row_names_how_long_it_lasts() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleCommandMenu.gd")
	assert_string_contains(src, '"label": "Auto: this turn"', "Auto lasts one turn and must say so")
	assert_string_contains(src, '"Trust (every turn): ON" if combatant.player_trust else "Trust (every turn): OFF"',
		"Trust lasts every turn until switched off and must say so, in both states")
