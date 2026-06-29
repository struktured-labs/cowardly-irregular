extends GutTest

## tick 162 regression: Combatant.from_dict must sanitize the
## inventory dict on load:
##
##   1. int() coerce quantity values. JSON.parse returns numerics
##      as float; downstream add_item/consume_item treat them as
##      int. Without explicit coerce a save with `potion: 3.7`
##      surfaces as 3.7 in UI until first mutation auto-truncates.
##
##   2. Filter non-positive quantities. consume_item erases entries
##      that drop to ≤ 0 (line 1108). A save with `potion: -5`
##      from corruption would sit as a ghost negative until the
##      next consume call, surfacing as "-5 potions" in the menu
##      and breaking has_item / get_item_count semantics.
##
##   3. Filter empty-string keys. `{"": 3}` is a phantom row that
##      iteration sites (Use Item menu, sell screens) can't render
##      meaningfully but still count toward inventory.size().

const COMBATANT := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Source pins ──────────────────────────────────────────────────────────

func test_inventory_load_builds_typed_dict() -> void:
	var src := _read(COMBATANT)
	var idx: int = src.find("if data.has(\"inventory\"):")
	assert_gt(idx, -1, "inventory load branch must exist")
	# Tick 395 added a type guard + comment block above the sanitize
	# code, which pushed the asserted strings further from the
	# `if data.has("inventory"):` anchor. 1800 chars covers the
	# expanded block plus a margin.
	var window: String = src.substr(idx, 1800)
	assert_true(window.contains("var typed_inv: Dictionary = {}"),
		"inventory load must build a typed_inv dict for sanitization")
	assert_true(window.contains("inventory = typed_inv"),
		"inventory load must assign the sanitized dict back")
	# Negative pin: old direct duplicate path must be gone.
	assert_false(window.contains("inventory = data[\"inventory\"].duplicate()"),
		"old `inventory = data[\"inventory\"].duplicate()` direct path must be gone")


func test_inventory_load_int_coerces_quantity() -> void:
	var src := _read(COMBATANT)
	var idx: int = src.find("if data.has(\"inventory\"):")
	# Tick 395 added a type guard + comment block above the sanitize
	# code, which pushed the asserted strings further from the
	# `if data.has("inventory"):` anchor. 1800 chars covers the
	# expanded block plus a margin.
	var window: String = src.substr(idx, 1800)
	assert_true(window.contains("var qty: int = int(raw_inv[item_id])"),
		"inventory load must int() coerce quantity — JSON returns float")


func test_inventory_load_filters_non_positive() -> void:
	var src := _read(COMBATANT)
	var idx: int = src.find("if data.has(\"inventory\"):")
	# Tick 395 added a type guard + comment block above the sanitize
	# code, which pushed the asserted strings further from the
	# `if data.has("inventory"):` anchor. 1800 chars covers the
	# expanded block plus a margin.
	var window: String = src.substr(idx, 1800)
	assert_true(window.contains("if qty <= 0:"),
		"inventory load must filter non-positive quantities (mirrors consume_item's erase semantics)")
	assert_true(window.contains("continue"),
		"non-positive filter must continue, not break — keep checking later entries")


func test_inventory_load_filters_empty_key() -> void:
	var src := _read(COMBATANT)
	var idx: int = src.find("if data.has(\"inventory\"):")
	# Tick 395 added a type guard + comment block above the sanitize
	# code, which pushed the asserted strings further from the
	# `if data.has("inventory"):` anchor. 1800 chars covers the
	# expanded block plus a margin.
	var window: String = src.substr(idx, 1800)
	assert_true(window.contains("if key == \"\":"),
		"inventory load must filter empty-string keys (phantom rows)")


# ── Runtime behavior ────────────────────────────────────────────────────

func test_runtime_negative_quantity_filtered() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({"inventory": {"potion": -5, "ether": 3}})
	assert_false(c.inventory.has("potion"),
		"negative quantity must be dropped on load — would otherwise surface as '-5 potions' in UI")
	assert_eq(int(c.inventory.get("ether", 0)), 3,
		"valid sibling entry must still load")


func test_runtime_zero_quantity_filtered() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({"inventory": {"potion": 0, "ether": 3}})
	assert_false(c.inventory.has("potion"),
		"zero quantity must be dropped on load — consume_item erases zero entries; load must match")


func test_runtime_empty_key_filtered() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({"inventory": {"": 5, "potion": 3}})
	assert_false(c.inventory.has(""),
		"empty-string key must be filtered — phantom row")
	assert_eq(int(c.inventory.get("potion", 0)), 3,
		"valid sibling entry must still load")


func test_runtime_float_quantity_coerces_to_int() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({"inventory": {"potion": 3.7}})
	# int(3.7) = 3 in GDScript (truncate toward zero).
	var qty = c.inventory.get("potion", 0)
	assert_eq(typeof(qty), TYPE_INT,
		"quantity must be int after load, not float")
	assert_eq(qty, 3,
		"float 3.7 must truncate to int 3 via int() coerce")


func test_runtime_normal_inventory_passes_through() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({"inventory": {"potion": 5, "ether": 3, "phoenix_down": 1}})
	assert_eq(c.inventory.size(), 3,
		"all valid entries pass through")
	assert_eq(int(c.inventory["potion"]), 5)
	assert_eq(int(c.inventory["ether"]), 3)
	assert_eq(int(c.inventory["phoenix_down"]), 1)


# ── Cross-pin: consume_item still works on sanitized state ──────────────

func test_runtime_loaded_inventory_consume_still_works() -> void:
	# Sanity: after load + sanitization, the normal consume path
	# still behaves correctly.
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({"inventory": {"potion": 5}})
	var ok: bool = c.remove_item("potion", 2)
	assert_true(ok, "remove succeeds on positive quantity")
	assert_eq(int(c.inventory.get("potion", 0)), 3,
		"quantity correctly decremented to 3")
