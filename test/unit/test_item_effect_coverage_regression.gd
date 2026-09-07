extends GutTest

## Data-integrity guard (2026-07-05): every `effects` key authored in items.json
## must be referenced in ItemSystem.gd — otherwise a newly-authored item effect
## silently no-ops on use (the turn/AP is spent and the item consumed, but
## nothing happens). This is the item-side sibling of
## test_support_ability_effect_coverage_regression, closing the project's
## canonical silent-failure class for consumables.

const ITEMS_PATH := "res://data/items.json"
const ITEM_SYSTEM_PATH := "res://src/items/ItemSystem.gd"


func test_every_item_effect_key_is_referenced_in_itemsystem() -> void:
	var items = JSON.parse_string(FileAccess.get_file_as_string(ITEMS_PATH))
	assert_eq(typeof(items), TYPE_DICTIONARY, "items.json must parse to a Dictionary (id -> item)")
	var src := FileAccess.get_file_as_string(ITEM_SYSTEM_PATH)
	assert_true(src != "", "ItemSystem.gd must be readable")

	var effect_keys := {}
	for item_id in items:
		var item = items[item_id]
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var effects = item.get("effects", {})
		if typeof(effects) == TYPE_DICTIONARY:
			for k in effects.keys():
				effect_keys[str(k)] = true

	assert_gt(effect_keys.size(), 0, "sanity: items.json authors at least one effect key")

	var unhandled: Array[String] = []
	for key in effect_keys.keys():
		if not src.contains("\"" + key + "\""):
			unhandled.append(key)
	assert_eq(unhandled.size(), 0,
		"item effect keys authored in items.json but never referenced in ItemSystem.gd would " +
		"silently no-op on use — implement them (or confirm they're read): %s" % str(unhandled))
