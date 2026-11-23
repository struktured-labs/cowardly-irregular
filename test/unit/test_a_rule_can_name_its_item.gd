extends GutTest

## "Has Item" is the one named payload the value dial cannot choose: its dial is the COUNT. So a rule written in the
## grid could only ever count potions (the seed), whatever the player carries. Choosing "Has Item" in the condition
## picker now asks WHICH item straight away, through the same picker the item action uses. .795, beside
## test_a_rule_can_name_its_element (the dial's half).

const EDITOR := "res://src/ui/autobattle/AutobattleGridEditor.gd"

var _abs
var _persist_before = false


func before_each() -> void:
	_abs = get_tree().root.get_node_or_null("AutobattleSystem")
	assert_not_null(_abs, "CONTROL: AutobattleSystem autoload must exist")
	_persist_before = _abs._test_disable_persistence
	_abs._test_disable_persistence = true


func after_each() -> void:
	_abs._test_disable_persistence = _persist_before


func _editor() -> Node:
	var e: Node = load(EDITOR).new()
	add_child_autofree(e)
	await get_tree().process_frame
	var rules: Array = e.get("rules") as Array
	rules.clear()
	rules.append({"conditions": [{"type": "hp_percent", "op": "<", "value": 50}], "actions": [{"type": "attack"}], "enabled": true})
	e.set("cursor_row", 0)
	e.set("cursor_col", 0)
	return e


func _cond(e: Node) -> Dictionary:
	return ((e.get("rules") as Array)[0] as Dictionary)["conditions"][0] as Dictionary


func _spec(e: Node) -> Dictionary:
	var p = e.get("_option_picker")
	return p.get_meta("spec") if p != null and is_instance_valid(p) and p.has_meta("spec") else {}


func test_the_floor_names_every_member_this_file_drives() -> void:
	var e: Node = await _editor()
	for f in ["_commit_option_choice", "_open_condition_item_picker", "_apply_condition_item", "_get_character_consumables", "_format_condition", "_close_option_picker"]:
		assert_true(e.has_method(f), "AutobattleGridEditor.%s must exist" % f)
	assert_true("_option_picker" in e, "AutobattleGridEditor._option_picker must exist")
	assert_gt(e._get_character_consumables().size(), 1, "PRECONDITION: the game has more than one consumable to count")


func test_choosing_has_item_asks_which_item() -> void:
	var e: Node = await _editor()
	e._commit_option_choice("condition_type", "item_count", {})
	assert_eq(str(_cond(e)["type"]), "item_count", "CONTROL: the type was applied")
	var spec := _spec(e)
	assert_eq(str(spec.get("kind", "")), "condition_item_id", "an item picker opens behind the type choice")
	var options: Array = spec.get("options", [])
	assert_gt(options.size(), 1, "and offers more than the seed")
	var seed: String = str(_cond(e)["item_id"])
	assert_eq(str(options[int(spec.get("selected", -1))]["id"]), seed, "with the current item ('%s') under the cursor" % seed)
	var other: Dictionary = options[0] if str(options[0]["id"]) != seed else options[1]
	var before_text: String = e._format_condition(_cond(e))
	e._close_option_picker()
	e._commit_option_choice("condition_item_id", str(other["id"]), {})
	assert_eq(str(_cond(e)["item_id"]), str(other["id"]), "the chosen item is the one the rule counts")
	assert_ne(e._format_condition(_cond(e)), before_text, "and the cell names it")
	assert_true(_cond(e).has("op") and _cond(e).has("value"), "the count's operator and number are kept")
	assert_eq(_abs.validate_rule((e.get("rules") as Array)[0]), [] as Array[String], "and the rule validates")


## Backing out of the item picker keeps the seed: the rule is whole either way.
func test_cancelling_the_item_picker_keeps_a_whole_rule() -> void:
	var e: Node = await _editor()
	e._commit_option_choice("condition_type", "item_count", {})
	e._close_option_picker()
	assert_ne(str(_cond(e).get("item_id", "")), "", "the condition still names an item")
	assert_eq(_abs.validate_rule((e.get("rules") as Array)[0]), [] as Array[String], "and validates")


## CONTROLS: no other type opens a second picker, and the item choice lands only on a Has Item cell.
func test_only_has_item_asks() -> void:
	var e: Node = await _editor()
	for t in ["hp_percent", "enemy_weak_to", "has_status", "always"]:
		e._commit_option_choice("condition_type", t, {})
		assert_eq(_spec(e), {}, "%s opens no second picker" % t)
	e._commit_option_choice("condition_item_id", "ether", {})
	assert_false(_cond(e).has("item_id"), "an item choice does not land on a cell that is not Has Item")
