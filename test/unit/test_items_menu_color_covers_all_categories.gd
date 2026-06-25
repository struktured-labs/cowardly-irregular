extends GutTest

## tick 138 regression: ItemsMenu._get_item_color must return the
## semantically correct color for every ItemCategory enum value in
## ItemSystem.ItemCategory. Pre-fix only CONSUMABLE / CURATIVE /
## BUFF had explicit branches; OFFENSIVE (3) and META (4) — both
## present in data/items.json — silently fell through to
## TEXT_COLOR (white). So bomb_fragment looked the same as a
## neutral item, and Scriptweaver / save-edit items couldn't be
## visually distinguished from healing items at a glance.
##
## Same fix shape as tick 137's AbilitiesMenu coverage fix.

const ITEMS_MENU := "res://src/ui/ItemsMenu.gd"


func _color(category: int) -> Color:
	var script_class = load(ITEMS_MENU)
	var inst: Node = script_class.new()
	add_child_autofree(inst)
	return inst._get_item_color({"category": category})


func test_consumable_returns_heal_color() -> void:
	var script_class = load(ITEMS_MENU)
	var expected: Color = script_class.HEAL_COLOR
	assert_eq(_color(ItemSystem.ItemCategory.CONSUMABLE), expected,
		"CONSUMABLE must return HEAL_COLOR")


func test_curative_returns_mp_color() -> void:
	var script_class = load(ITEMS_MENU)
	var expected: Color = script_class.MP_COLOR
	assert_eq(_color(ItemSystem.ItemCategory.CURATIVE), expected,
		"CURATIVE must return MP_COLOR")


func test_buff_returns_buff_color() -> void:
	var script_class = load(ITEMS_MENU)
	var expected: Color = script_class.BUFF_COLOR
	assert_eq(_color(ItemSystem.ItemCategory.BUFF), expected,
		"BUFF must return BUFF_COLOR")


func test_offensive_returns_offensive_color() -> void:
	# Pre-tick-138 this fell through to TEXT_COLOR (white).
	var script_class = load(ITEMS_MENU)
	var expected: Color = script_class.OFFENSIVE_COLOR
	assert_eq(_color(ItemSystem.ItemCategory.OFFENSIVE), expected,
		"OFFENSIVE must return OFFENSIVE_COLOR — used to silently render as white")


func test_meta_returns_meta_color() -> void:
	# Pre-tick-138 this fell through to TEXT_COLOR (white).
	var script_class = load(ITEMS_MENU)
	var expected: Color = script_class.META_COLOR
	assert_eq(_color(ItemSystem.ItemCategory.META), expected,
		"META must return META_COLOR — used to silently render as white")


func test_offensive_and_meta_are_distinct_from_each_other_and_text() -> void:
	# Pin: the two new colors must differ from each other AND from
	# the fallback white. Otherwise adding the branches accomplishes
	# nothing visually.
	var script_class = load(ITEMS_MENU)
	var offensive: Color = script_class.OFFENSIVE_COLOR
	var meta: Color = script_class.META_COLOR
	var text: Color = script_class.TEXT_COLOR
	assert_ne(offensive, meta,
		"OFFENSIVE_COLOR and META_COLOR must be visually distinct")
	assert_ne(offensive, text,
		"OFFENSIVE_COLOR must differ from TEXT_COLOR — otherwise the fix is a no-op")
	assert_ne(meta, text,
		"META_COLOR must differ from TEXT_COLOR — otherwise the fix is a no-op")


func test_default_falls_back_to_text_color() -> void:
	# Defensive: an int outside the enum range still returns SOME
	# valid color. Pin to TEXT as the safe default.
	var script_class = load(ITEMS_MENU)
	var expected: Color = script_class.TEXT_COLOR
	# 99 is outside ItemCategory (0-4).
	assert_eq(_color(99), expected,
		"unknown category must safely fall back to TEXT_COLOR")


func test_every_item_category_enum_value_has_an_explicit_branch() -> void:
	# Source-level pin: every value in ItemSystem.ItemCategory must
	# appear as an explicit case in _get_item_color. If a new enum
	# value is added to ItemSystem, the test fails until the menu
	# is updated.
	var src: String = FileAccess.get_file_as_string(ITEMS_MENU)
	var idx: int = src.find("func _get_item_color")
	assert_gt(idx, -1, "_get_item_color must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	for cat in ["CONSUMABLE", "CURATIVE", "BUFF", "OFFENSIVE", "META"]:
		var qualified: String = "ItemSystem.ItemCategory." + cat
		assert_true(body.contains(qualified),
			"_get_item_color must mention '%s' — every ItemCategory enum value needs an explicit branch (no silent default-through)" % qualified)


func test_actual_offensive_item_renders_with_offensive_color() -> void:
	# Runtime cross-check via a real items.json entry. bomb_fragment
	# is in the file with category=3 (OFFENSIVE). The menu must
	# render it with OFFENSIVE_COLOR.
	var item_sys = get_node_or_null("/root/ItemSystem")
	if item_sys == null or not item_sys.has_method("get_item"):
		pending("ItemSystem not available in this test context")
		return
	var data: Dictionary = item_sys.get_item("bomb_fragment")
	if data.is_empty():
		pending("bomb_fragment not in items.json — cannot cross-check")
		return
	var script_class = load(ITEMS_MENU)
	var inst: Node = script_class.new()
	add_child_autofree(inst)
	var color: Color = inst._get_item_color(data)
	assert_eq(color, script_class.OFFENSIVE_COLOR,
		"bomb_fragment (OFFENSIVE category) must render with OFFENSIVE_COLOR")
