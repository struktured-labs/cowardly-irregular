extends GutTest

## Defensive regression: EquipmentSystem's public equip/unequip/mods API
## must tolerate a null combatant without crashing.
##
## PassiveSystem's sister API already validates `combatant` (see
## equip_passive / get_passive_mods); EquipmentSystem didn't. Trigger
## surfaces are narrow but real:
##   • Auto-equip code that runs during party-add at a frame when the
##     newly-spawned Combatant is being torn down (race).
##   • Save migration / loadout-import paths that re-equip from a saved
##     loadout against a party slot that hasn't materialised.
##   • Test code calling helpers without standing up a full Combatant.
##
## Without the guards, `null.equipped_weapon = id` raises a SCRIPT ERROR
## and the calling flow aborts mid-equip — the equipment state then
## drifts (some pieces equipped, some not).
##
## Tests:
##   • equip_weapon(null, _) returns false, does not crash
##   • equip_armor(null, _) returns false, does not crash
##   • equip_accessory(null, _) returns false, does not crash
##   • unequip_slot(null, _) returns false, does not crash
##   • unequip_slot(combatant, out-of-range slot) returns false, does
##     not crash on EquipSlot.keys()[slot] OOB
##   • get_equipment_mods(null) returns {} (empty), matches
##     PassiveSystem.get_passive_mods's contract for invalid combatants
##   • get_weapon_type(null) returns "" (existing guard, sanity)
##   • Valid combatant flows still succeed (regression against the guard
##     accidentally rejecting healthy callers)

const EQUIPMENT_SYSTEM_PATH := "res://src/jobs/EquipmentSystem.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


func _es() -> Node:
	return get_node_or_null("/root/EquipmentSystem")


# ── Source pins ───────────────────────────────────────────────────────────────

func test_equip_apis_guard_null_combatant() -> void:
	# Pin that all four mutators check the combatant before touching its
	# fields. Without these guards, a null caller would crash on the
	# `.equipped_X = id` write below the existence check on the catalog.
	var text := _read(EQUIPMENT_SYSTEM_PATH)
	for fn in ["func equip_weapon", "func equip_armor",
			"func equip_accessory", "func unequip_slot"]:
		var idx := text.find(fn)
		assert_gt(idx, -1, "%s must exist" % fn)
		var rest := text.substr(idx)
		var next_fn := rest.find("\nfunc ", 1)
		var body := rest.substr(0, next_fn) if next_fn > -1 else rest
		assert_true(body.contains("not is_instance_valid(combatant)") \
				or body.contains("is_instance_valid(combatant)"),
			"%s must check is_instance_valid(combatant) before mutating" % fn)


func test_get_equipment_mods_guards_null_combatant() -> void:
	var text := _read(EQUIPMENT_SYSTEM_PATH)
	var idx := text.find("func get_equipment_mods")
	assert_gt(idx, -1, "get_equipment_mods must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("is_instance_valid(combatant)"),
		"get_equipment_mods must guard the combatant before reading equipped_X")


# ── Behavioural ──────────────────────────────────────────────────────────────

func test_equip_weapon_null_combatant_returns_false() -> void:
	var es := _es()
	if es == null:
		pending("EquipmentSystem autoload unavailable")
		return
	# A real weapon id so the catalog check passes — we want to verify the
	# null-combatant branch is hit, not the catalog-miss branch.
	var existing_weapon: String = es.weapons.keys()[0] if not es.weapons.is_empty() else ""
	if existing_weapon == "":
		pending("EquipmentSystem.weapons empty in test env")
		return
	var result: bool = es.equip_weapon(null, existing_weapon)
	assert_false(result, "equip_weapon(null, …) must return false, not crash")


func test_equip_armor_null_combatant_returns_false() -> void:
	var es := _es()
	if es == null:
		pending("EquipmentSystem autoload unavailable")
		return
	var existing: String = es.armors.keys()[0] if not es.armors.is_empty() else ""
	if existing == "":
		pending("EquipmentSystem.armors empty in test env")
		return
	var result: bool = es.equip_armor(null, existing)
	assert_false(result, "equip_armor(null, …) must return false, not crash")


func test_equip_accessory_null_combatant_returns_false() -> void:
	var es := _es()
	if es == null:
		pending("EquipmentSystem autoload unavailable")
		return
	var existing: String = es.accessories.keys()[0] if not es.accessories.is_empty() else ""
	if existing == "":
		pending("EquipmentSystem.accessories empty in test env")
		return
	var result: bool = es.equip_accessory(null, existing)
	assert_false(result, "equip_accessory(null, …) must return false, not crash")


func test_unequip_slot_null_combatant_returns_false() -> void:
	var es := _es()
	if es == null:
		pending("EquipmentSystem autoload unavailable")
		return
	var result: bool = es.unequip_slot(null, es.EquipSlot.WEAPON)
	assert_false(result, "unequip_slot(null, …) must return false, not crash")


func test_unequip_slot_out_of_range_returns_false() -> void:
	# An out-of-band slot value (e.g. -1 from a UI bug, or a future enum
	# entry not yet handled) must NOT crash EquipSlot.keys()[slot]. The
	# function should return false.
	var es := _es()
	if es == null:
		pending("EquipmentSystem autoload unavailable")
		return
	var c: Combatant = Combatant.new()
	c.combatant_name = "TestC"
	add_child_autofree(c)
	# Use a sentinel-low int that's clearly invalid. (-1 is the canonical
	# "no slot" — guards against UI bugs that pass it through.)
	var result_low: bool = es.unequip_slot(c, -1)
	assert_false(result_low, "unequip_slot(combatant, -1) must return false, not crash")
	# Beyond enum size: EquipSlot has 3 entries (WEAPON, ARMOR, ACCESSORY).
	var result_high: bool = es.unequip_slot(c, 99)
	assert_false(result_high, "unequip_slot(combatant, 99) must return false, not crash")


func test_get_equipment_mods_null_returns_empty_dict() -> void:
	var es := _es()
	if es == null:
		pending("EquipmentSystem autoload unavailable")
		return
	var mods: Dictionary = es.get_equipment_mods(null)
	assert_true(mods.is_empty(),
		"get_equipment_mods(null) must return an empty dict (matches PassiveSystem's contract)")


func test_get_weapon_type_null_returns_empty_string() -> void:
	# Pre-existing guard — keep it covered so a future refactor doesn't drop it.
	var es := _es()
	if es == null:
		pending("EquipmentSystem autoload unavailable")
		return
	var t: String = es.get_weapon_type(null)
	assert_eq(t, "", "get_weapon_type(null) must return \"\"")


# ── Regression against guard overreach ───────────────────────────────────────

func test_valid_combatant_still_succeeds() -> void:
	# Sanity: the null-guards must NOT reject a valid combatant. Drive a
	# real equip cycle and assert success.
	var es := _es()
	if es == null:
		pending("EquipmentSystem autoload unavailable")
		return
	var existing_weapon: String = es.weapons.keys()[0] if not es.weapons.is_empty() else ""
	if existing_weapon == "":
		pending("EquipmentSystem.weapons empty in test env")
		return
	var c: Combatant = Combatant.new()
	c.combatant_name = "Equipper"
	c.max_hp = 100
	c.max_mp = 50
	add_child_autofree(c)
	# Combatant._ready resets HP/MP after add_child; set after.
	c.current_hp = 100
	c.current_mp = 50
	var result: bool = es.equip_weapon(c, existing_weapon)
	assert_true(result, "equip_weapon must still succeed on a valid combatant")
	assert_eq(c.equipped_weapon, existing_weapon,
		"valid combatant must end up with the equipped weapon id")
	# Now exercise get_equipment_mods on the valid combatant.
	var mods: Dictionary = es.get_equipment_mods(c)
	assert_false(mods.is_empty(),
		"get_equipment_mods must return a populated dict for a valid combatant")
	for stat in ["attack", "defense", "magic", "speed", "max_hp", "max_mp"]:
		assert_true(mods.has(stat),
			"populated dict must contain default stat key '%s'" % stat)
