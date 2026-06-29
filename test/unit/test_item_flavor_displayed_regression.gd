extends GutTest

## tick 430: ItemsMenu surfaces authored `flavor` text from
## items.json. Pre-fix 146 items authored a flavor string (e.g.
## potion's "A dusty bottle that smells faintly of mint") but no
## UI ever displayed it — pure data bloat.

const ITEMS_MENU_PATH := "res://src/ui/ItemsMenu.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_flavor_read_in_items_menu() -> void:
	var src := _read(ITEMS_MENU_PATH)
	# Pin the flavor read.
	assert_true(src.contains("str(item_data.get(\"flavor\", \"\"))"),
		"ItemsMenu must read the flavor field from item_data")


func test_flavor_only_renders_when_authored() -> void:
	# Empty flavor must not produce blank padding — only items with
	# authored flavor render the label.
	var src := _read(ITEMS_MENU_PATH)
	assert_true(src.contains("if flavor_text != \"\":"),
		"ItemsMenu must gate the flavor label on non-empty flavor")


func test_data_still_authors_item_flavor() -> void:
	# Sanity: at least the basic potions still author flavor.
	var raw: String = FileAccess.get_file_as_string("res://data/items.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	for item_id in ["potion", "hi_potion", "mega_potion"]:
		assert_true(data.has(item_id))
		var flavor: String = str(data[item_id].get("flavor", ""))
		assert_ne(flavor, "",
			"%s must still author non-empty flavor (fix relies on this)" % item_id)


func test_effects_breakdown_pushed_down_when_flavor_present() -> void:
	# Pin that the effects_y offset is applied so the effects
	# breakdown doesn't overlap the flavor label.
	var src := _read(ITEMS_MENU_PATH)
	assert_true(src.contains("effects_y_offset = 60"),
		"effects_y must be pushed down when flavor is rendered (prevents label overlap)")
	assert_true(src.contains("var effects_y = 100 + effects_y_offset"),
		"effects_y must include the offset in its initial value")
