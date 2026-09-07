extends GutTest

## tick 395: Combatant.from_dict guards the inventory field against
## non-Dictionary values so a corrupted save doesn't crash the load
## path.
##
## Pre-fix:
##   var raw_inv: Dictionary = data["inventory"]
##   # ↑ raises "Trying to assign value of type 'X' to a variable of
##   #   type 'Dictionary'" if inventory is null / int / string.
##
## Same fragility class as ticks 363-364's GameState save-load guards.

const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _make_via_from_dict(data: Dictionary) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	add_child_autofree(c)
	# Initialize so the combatant has sane defaults.
	c.initialize({"name": "Test", "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	c.from_dict(data)
	return c


func test_null_inventory_does_not_crash() -> void:
	# Pre-fix this would crash on the typed-Dict assignment.
	var c: Combatant = _make_via_from_dict({"inventory": null})
	assert_eq(typeof(c.inventory), TYPE_DICTIONARY,
		"inventory must stay a Dictionary after malformed load — no crash")


func test_int_inventory_does_not_crash() -> void:
	var c: Combatant = _make_via_from_dict({"inventory": 42})
	assert_eq(typeof(c.inventory), TYPE_DICTIONARY,
		"inventory must stay a Dictionary after int-corrupted load")


func test_string_inventory_does_not_crash() -> void:
	var c: Combatant = _make_via_from_dict({"inventory": "bad"})
	assert_eq(typeof(c.inventory), TYPE_DICTIONARY,
		"inventory must stay a Dictionary after string-corrupted load")


func test_well_formed_inventory_still_loads() -> void:
	# Regression guard: don't break the happy path.
	var c: Combatant = _make_via_from_dict({"inventory": {"potion": 3, "ether": 1}})
	assert_eq(c.get_item_count("potion"), 3)
	assert_eq(c.get_item_count("ether"), 1)


func test_source_pin_uses_type_guard() -> void:
	var src: String = FileAccess.get_file_as_string(COMBATANT_PATH)
	assert_true(src.contains("if raw_inv_v is Dictionary"),
		"from_dict inventory load must type-guard before the typed-Dict assignment")
	assert_true(src.contains("inventory malformed"),
		"the malformed path must push_warning so the corruption surfaces")
