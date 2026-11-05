extends GutTest

## cowir-controller 22016 / cowir-main 22029: JSON hands every number back as a FLOAT, and in Godot 4
## `0.0 in [0, 1, 2, 3]` is false and `match` is type-strict, so the autobattle item picker offered no items in the
## real game. ItemSystem now coerces its ENUM fields (ItemSystem.INT_FIELDS) to int where the JSON enters.


func test_a_raw_json_parse_really_gives_floats() -> void:
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	var table: Dictionary = raw.get("items", raw) if raw is Dictionary else {}
	assert_true(table.has("potion"), "CONTROL: items.json parsed")
	assert_true(table["potion"].get("category") is float, "CONTROL: JSON gives the category as a float, the trap this guards")
	assert_false(table["potion"].get("category") in [0, 1, 2, 3], "CONTROL: and a float is NOT in an int list in Godot 4")


func test_every_enum_field_is_an_int_after_load() -> void:
	var checked := 0
	var floats: Array = []
	for id in ItemSystem.items:
		var entry = ItemSystem.items[id]
		if not (entry is Dictionary):
			continue
		for key in ItemSystem.INT_FIELDS:
			if (entry as Dictionary).has(key):
				checked += 1
				if not (entry[key] is int):
					floats.append("%s.%s = %s (%s)" % [id, key, str(entry[key]), type_string(typeof(entry[key]))])
	assert_gt(checked, 100, "CONTROL: the enum fields were found (%d)" % checked)
	assert_eq(floats, [], "an enum field reached a consumer as a non-int")


func test_a_loaded_category_passes_an_int_membership_test() -> void:
	var potion: Dictionary = ItemSystem.get_item("potion")
	assert_false(potion.is_empty(), "CONTROL: potion is loaded")
	assert_true(potion.get("category") in [0, 1, 2, 3], "the consumer's own shape (`in [ints]`) now matches")


func test_quantities_keep_their_loaded_type() -> void:
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	var table: Dictionary = raw.get("items", raw) if raw is Dictionary else {}
	var t := {"x": {"category": 1.0, "cost": 50.0, "effects": {"heal_hp_percent": 25.0}}}
	ItemSystem.coerce_int_fields(t)
	assert_true(t["x"]["category"] is int, "an enum field is coerced")
	assert_true(t["x"]["cost"] is float, "a quantity is NOT: integer division would follow it into arithmetic")
	assert_true(t["x"]["effects"]["heal_hp_percent"] is float, "nor an effect value (25 / 100 must not become 0)")
	assert_true(table.size() > 0, "CONTROL: the real table was read")
