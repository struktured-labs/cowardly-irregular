extends GutTest

## Superseded (struktured ruling 2026-10-03): "auto -> run auto kind of sucks... auto should
## immediately do Run auto again without a submenu... Auto Rules is definitely a button and
## not a menu item." The hold-A-to-open-editor shortcut this file used to pin went dead the
## same day: confirm on the Auto row now runs auto and closes the menu on the SAME press, so a
## hold can never be observed. This file now pins the NEW menu shape instead of the hold.

const MenuBuilder := preload("res://src/battle/BattleCommandMenu.gd")

func _combatant() -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": "Fighter", "max_hp": 100, "max_mp": 20,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10
	})
	add_child_autofree(c)
	return c

## The builder reads `_scene.get_viewport()` and `_scene.test_enemies`. A null scene makes the
## first line ERROR, which ABORTS the function and returns the typed default `[]` — the menu reads
## as empty rather than as broken. My first harness did exactly that and the populated-menu control
## is what caught it, not the assertions under test.
class _StubScene extends Node2D:
	const FORMATION_NAMES := ["V-Formation", "Front Line", "Back Row", "Diamond", "Spread"]
	var current_formation: int = 0
	var test_enemies: Array = []
	var party_members: Array = []
	var party_sprite_nodes: Array = []
	var enemy_sprite_nodes: Array = []

func _items() -> Array:
	var stub := _StubScene.new()
	add_child_autofree(stub)
	var builder = MenuBuilder.new(stub)
	var items: Array = builder.build_command_menu_items_with_targets(_combatant())
	assert_gt(items.size(), 2, "CONTROL: the builder returned a populated menu (%d rows)" % items.size())
	return items

func _row(items: Array, id: String) -> Dictionary:
	for it in items:
		if str((it as Dictionary).get("id", "")) == id:
			return it
	return {}

func test_the_auto_row_has_no_submenu() -> void:
	var row := _row(_items(), "autobattle")
	assert_false(row.is_empty(), "CONTROL: the Auto row exists at the menu root")
	assert_false(row.has("submenu"), "Auto must not open a submenu — one press runs auto")

func test_the_auto_row_still_carries_the_combatant() -> void:
	## The row's data still needs the combatant: on_menu_item_selected's "autobattle" handler
	## reads item_data.get("combatant") to run that character's turn.
	var row := _row(_items(), "autobattle")
	var data = row.get("data", null)
	assert_true(data is Dictionary, "the Auto row needs a data dict to resolve a combatant")
	assert_true((data as Dictionary).get("combatant", null) is Combatant,
		"the Auto row's data must carry the combatant autobattle runs for")

func test_trust_is_a_sibling_row_not_nested_under_auto() -> void:
	## Trust lived inside Auto's submenu; that submenu is gone, so Trust must still be reachable
	## as its OWN top-level row (struktured: "if it lived in the Auto submenu, keep it reachable").
	var row := _row(_items(), "trust_toggle")
	assert_false(row.is_empty(), "Trust must survive as a top-level row: %s" % str(row))
	assert_false(row.has("submenu"), "CONTROL: Trust was never a submenu host")

func test_auto_rules_has_no_menu_row() -> void:
	## "Auto Rules is definitely a button and not a menu item" (struktured 2026-10-03).
	var items := _items()
	for it in items:
		assert_ne(str((it as Dictionary).get("id", "")), "autobattle_edit",
			"Auto Rules must not appear as a menu row — it is the Start/F5 button")
		var sub: Array = (it as Dictionary).get("submenu", []) as Array
		for s in sub:
			assert_ne(str((s as Dictionary).get("id", "")), "autobattle_edit",
				"Auto Rules must not appear nested in any submenu either")

func test_the_dead_hold_shortcut_is_gone() -> void:
	## The hold-to-open mechanism this file used to pin is unreachable now (confirm executes and
	## closes the menu on the same press) and was removed rather than left as dead code.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_gt(src.length(), 1000, "CONTROL: BattleScene reads")
	assert_eq(src.find("func _process_hold_a"), -1,
		"_process_hold_a should have been removed with the submenu it depended on")
