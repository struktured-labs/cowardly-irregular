extends GutTest
## Demo playthrough 2026-11-03: the battle menu opened on "Auto: this turn", so mashing confirm
## autobattled. Rows marked skip_default (Auto / Trust) are never the opening cursor.

func _menu(items: Array) -> Node:
	var m = load("res://src/ui/Win98Menu.gd").new()
	m.menu_items = items
	autofree(m)
	return m

func test_opening_cursor_skips_auto_and_trust() -> void:
	var m = _menu([
		{"id": "autobattle", "label": "Auto: this turn", "skip_default": true},
		{"id": "trust_toggle", "label": "Trust", "skip_default": true},
		{"id": "attack_x", "label": "Attack"},
	])
	assert_eq(m._opening_index(), 2, "opens on Attack, not Auto")

func test_all_skip_default_still_opens_somewhere() -> void:
	var m = _menu([{"id": "autobattle", "label": "Auto", "skip_default": true}])
	assert_eq(m._opening_index(), 0)

func test_command_menu_marks_auto_and_trust() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleCommandMenu.gd")
	var i := src.find("\"label\": \"Auto: this turn\"")
	assert_gt(i, 0)
	assert_true(src.substr(i, 200).contains("\"skip_default\": true"), "Auto row is skip_default")
	assert_true(src.contains("last_menu_selection in [\"autobattle\", \"trust_toggle\"]"), "memory cannot re-land on Auto")
