extends GutTest

## tick 371: Combatant.add_item / remove_item reject negative quantity.
##
## Pre-fix:
##   func add_item(item_id, quantity=1):
##       if inventory.has(item_id):
##           inventory[item_id] += quantity     # += -5 drains 5
##       else:
##           inventory[item_id] = quantity      # creates negative-count slot
##
##   func remove_item(item_id, quantity=1) -> bool:
##       if not inventory.has(item_id) or inventory[item_id] < quantity:
##           return false                        # both gates pass for negative
##       inventory[item_id] -= quantity          # -= -5 GRANTS 5
##       return true                             # caller thinks consume happened
##
## Symmetric with ticks 368-370's negative-amount footgun guards
## (heal/restore_mp/spend_ap/gain_ap/spend_mp). A typo'd reward
## table, Scriptweaver mod, or sign bug in computed drop count
## could silently empty or stuff inventories.

const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _make_combatant(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({
		"name": name_str, "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10,
	})
	add_child_autofree(c)
	return c


# ── Source pin: add_item refuses negative quantity ──────────────────

func test_add_item_source_pin() -> void:
	var src: String = FileAccess.get_file_as_string(COMBATANT_PATH)
	var fn_idx: int = src.find("func add_item(item_id: String, quantity: int")
	assert_gt(fn_idx, -1, "add_item must exist")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("if quantity < 0"),
		"add_item must guard against negative quantity")
	assert_true(body.contains("use remove_item"),
		"add_item warning must point caller at remove_item as the legitimate drain path")


# ── Source pin: remove_item refuses negative quantity ───────────────

func test_remove_item_source_pin() -> void:
	var src: String = FileAccess.get_file_as_string(COMBATANT_PATH)
	var fn_idx: int = src.find("func remove_item(item_id: String, quantity: int")
	assert_gt(fn_idx, -1, "remove_item must exist")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("if quantity < 0"),
		"remove_item must guard against negative quantity")
	assert_true(body.contains("use add_item"),
		"remove_item warning must point caller at add_item as the legitimate gain path")


# ── Behavioral: add_item(-5) does NOT drain inventory ───────────────

func test_add_item_negative_does_not_drain() -> void:
	var c: Combatant = _make_combatant("Hero")
	c.add_item("potion", 10)
	c.add_item("potion", -5)
	assert_eq(c.get_item_count("potion"), 10,
		"add_item('potion', -5) must NOT drain potions — pre-fix dropped to 5")


# ── Behavioral: remove_item(-5) does NOT grant inventory ────────────

func test_remove_item_negative_does_not_grant() -> void:
	var c: Combatant = _make_combatant("Hero")
	c.add_item("potion", 10)
	var ret: bool = c.remove_item("potion", -5)
	assert_false(ret,
		"remove_item('potion', -5) must return false (refused, not true)")
	assert_eq(c.get_item_count("potion"), 10,
		"remove_item('potion', -5) must NOT grant 5 potions — pre-fix bumped count to 15")


# ── Behavioral: add_item('') refused ────────────────────────────────

func test_add_item_empty_id_refused() -> void:
	# Pre-fix add_item("", 3) created an empty-key inventory slot
	# that no caller could reference cleanly.
	var c: Combatant = _make_combatant("Hero")
	c.add_item("", 3)
	assert_false("" in c.inventory,
		"add_item('', 3) must NOT create an empty-key inventory entry")


# ── Behavioral: positive add_item still works (regression guard) ────

func test_positive_add_item_still_works() -> void:
	var c: Combatant = _make_combatant("Hero")
	c.add_item("potion", 5)
	assert_eq(c.get_item_count("potion"), 5)
	c.add_item("potion", 3)
	assert_eq(c.get_item_count("potion"), 8,
		"positive add_item must still increment existing inventory slot")


# ── Behavioral: positive remove_item still works ────────────────────

func test_positive_remove_item_still_works() -> void:
	var c: Combatant = _make_combatant("Hero")
	c.add_item("potion", 10)
	var ret: bool = c.remove_item("potion", 3)
	assert_true(ret, "positive remove_item must still return true on success")
	assert_eq(c.get_item_count("potion"), 7,
		"positive remove_item must still decrement inventory")


# ── Behavioral: insufficient remove_item still returns false ────────

func test_remove_item_insufficient_still_returns_false() -> void:
	# Regression guard — don't break the existing positive-too-high branch.
	var c: Combatant = _make_combatant("Hero")
	c.add_item("potion", 2)
	var ret: bool = c.remove_item("potion", 5)
	assert_false(ret, "remove_item with quantity > stock must still return false")
	assert_eq(c.get_item_count("potion"), 2,
		"failed remove_item must NOT change inventory")
