extends GutTest

## The autobattle grid printed an item cell as its ID in words: "Use Phoenix Down", "Hi Potion < 1". His menu
## says "Resurgo Plume" and "Potio Maior", and the editor's own item picker already listed those names, so a rule
## read one name in the picker and another in its cell. Both cells now ask ItemNameResolver, as the battle log
## (@cowir-battle) and the LLM villagers (@cowir-ai) do since 2026-11-05.
##
## ⚠️ The sweeps that found the others searched for `replace("_"," ").capitalize()`. These two called bare
## `.capitalize()`, which turns underscores into spaces by itself, so that pattern could not see them.

const ED := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")

var _ed: Node = null
var _saved_persist := false
var _ab_profiles_entry: Dictionary = {}


func before_all() -> void:
	_ab_profiles_entry = ABProfiles.snapshot(get_tree().root.get_node_or_null("AutobattleSystem"))


func after_all() -> void:
	ABProfiles.restore(get_tree().root.get_node_or_null("AutobattleSystem"), _ab_profiles_entry)


func before_each() -> void:
	_saved_persist = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true
	_ed = load(ED).new()
	add_child_autofree(_ed)
	_ed.setup("hero", "Hero")
	await get_tree().process_frame


func after_each() -> void:
	AutobattleSystem._test_disable_persistence = _saved_persist


## Items the menu names differently from their id in words, read from the data, not listed by hand.
func _renamed() -> Array:
	var out: Array = []
	for row in _ed._get_character_consumables():
		var id := str(row["id"])
		var shown := str(ItemSystem.get_item(id).get("name", ""))
		if shown != "" and shown.to_lower() != id.capitalize().to_lower() and not shown.to_lower().contains(id.capitalize().to_lower()):
			out.append([id, shown])
	assert_gt(out.size(), 5, "PRECONDITION: the offered consumables must include renamed items, got %d" % out.size())
	return out


## The picker read each JSON category as a float, and `0.0 in [0, 1, 2, 3]` is false: it offered no items at all.
func test_the_item_picker_offers_the_consumables() -> void:
	var offered: Array = _ed._get_character_consumables()
	assert_gt(offered.size(), 10, "the editor's item picker must offer the consumables, got %d" % offered.size())
	var ids: Array = []
	for row in offered:
		ids.append(str(row["id"]))
	assert_true("potion" in ids, "CONTROL: a plain Potion is offered")
	var meta_item := ""
	for id in ItemSystem.items:
		if int(ItemSystem.items[id].get("category", 0)) == int(ItemSystem.ItemCategory.META):
			meta_item = str(id)
			break
	assert_ne(meta_item, "", "CONTROL: the data holds META items (the category the picker leaves out)")
	assert_false(meta_item in ids, "and a META item is not offered (%s)" % meta_item)


func test_the_floor_names_every_member_this_file_drives() -> void:
	for m in ["_format_action", "_format_condition", "_item_label", "_get_character_consumables"]:
		assert_true(_ed.has_method(m), "AutobattleGridEditor.%s must exist" % m)


func test_an_item_action_cell_reads_as_the_menu_does() -> void:
	var ids: Array = []
	for pair in _renamed():
		ids.append(pair[0])
		var cell: String = _ed._format_action({"type": "item", "id": pair[0], "target": "self"})
		assert_eq(cell, "Use %s" % pair[1], "%s's cell must use its menu name" % pair[0])
		assert_false(cell.contains(str(pair[0]).capitalize()), "and never the id-built '%s'" % str(pair[0]).capitalize())
	assert_true("phoenix_down" in ids and "hi_potion" in ids, "CONTROL: the two FF ids the renames retired are in the derived set")


func test_an_item_condition_cell_reads_as_the_menu_does() -> void:
	for pair in _renamed():
		var cell: String = _ed._format_condition({"type": "item_count", "item_id": pair[0], "op": "<", "value": 1})
		assert_true(cell.begins_with(str(pair[1])), "%s's condition must open with its menu name, got '%s'" % [pair[0], cell])


func test_an_unknown_or_missing_item_still_reads() -> void:
	assert_eq(_ed._format_action({"type": "item", "id": "zz_made_up_thing", "target": "self"}), "Use Zz Made Up Thing",
		"an id nothing knows keeps its words")
	assert_true(_ed._format_condition({"type": "item_count", "op": "<", "value": 1}).begins_with("Item"),
		"a condition with no item id still reads 'Item'")
