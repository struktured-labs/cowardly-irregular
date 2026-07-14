extends GutTest

## tick 460: equipment.json special_effects.<element>_resistance
## now actually halves matching-element damage.
##
## Pre-tick equipment authored:
##   bone_armor: dark_resistance = true
##   dragon_mail: fire_resistance = true
## but no code path read either flag. The dragon's namesake fire
## protection was decoration — dragon_mail gave the stat boost
## (stat_mods.defense etc.) but NOT the fire reduction.

const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String, max_hp: int = 100) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": max_hp, "max_mp": 50,
		"attack": 10, "defense": 0, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func test_helper_exists() -> void:
	var src := _read(COMBATANT_PATH)
	assert_true(src.contains("func _has_equipment_resistance"),
		"Combatant must declare _has_equipment_resistance helper")
	# Pin the three-slot scan with the dynamic key construction.
	assert_true(src.contains("element + \"_resistance\""),
		"helper must construct the lookup key dynamically by element")
	for slot in ["equipped_weapon", "equipped_armor", "equipped_accessory"]:
		assert_true(src.contains(slot + " != \"\""),
			"helper must check the " + slot + " slot")


func test_take_elemental_damage_consults_helper() -> void:
	var src := _read(COMBATANT_PATH)
	var fn_idx: int = src.find("func take_elemental_damage")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_has_equipment_resistance(element)"),
		"take_elemental_damage must consult _has_equipment_resistance")
	# Halve when present.
	assert_true(body.contains("elemental_mod *= 0.5"),
		"matched resistance must halve elemental_mod multiplicatively")


func test_ordering_after_absorb_before_mod() -> void:
	# Pin ordering: resistance halving happens AFTER absorb (so
	# absorption still wins for converters like undead_affinity)
	# and AFTER calculate_elemental_modifier (so it stacks with
	# the combatant's elemental_resistances list).
	var src := _read(COMBATANT_PATH)
	var fn_idx: int = src.find("func take_elemental_damage")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	var absorb_idx: int = body.find("_absorbs_element")
	var mod_idx: int = body.find("calculate_elemental_modifier(element)")
	var resist_idx: int = body.find("_has_equipment_resistance(element)")
	assert_gt(absorb_idx, -1)
	assert_gt(mod_idx, -1)
	assert_gt(resist_idx, -1)
	assert_lt(absorb_idx, resist_idx,
		"resistance must come AFTER absorb (absorption still wins)")
	assert_lt(mod_idx, resist_idx,
		"resistance must come AFTER calculate_elemental_modifier so it stacks with elemental_resistances list")


func test_data_still_authors_resistance() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/equipment.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	var found: bool = false
	for cat in ["weapons", "armors", "accessories"]:
		if not data.has(cat):
			continue
		for iid in data[cat].keys():
			var entry: Dictionary = data[cat][iid]
			var se: Variant = entry.get("special_effects", {})
			if not (se is Dictionary):
				continue
			for k in se.keys():
				if str(k).ends_with("_resistance") and str(k) != "status_resistance":
					found = true
					break
			if found:
				break
		if found:
			break
	assert_true(found,
		"equipment.json must still author at least one <element>_resistance entry")


func test_runtime_no_equip_returns_false() -> void:
	var c: Combatant = _make("Bare", 100)
	c.equipped_weapon = ""
	c.equipped_armor = ""
	c.equipped_accessory = ""
	assert_false(c._has_equipment_resistance("fire"),
		"bare combatant must report no resistance — fix must not silently grant baseline")


func test_runtime_equipped_armor_resists() -> void:
	var es = Engine.get_main_loop().root.get_node_or_null("EquipmentSystem")
	if es == null:
		pending("EquipmentSystem autoload required")
		return
	# Find any armor authoring fire_resistance (or any <elem>_resistance).
	var armor_id: String = ""
	var elem: String = ""
	if es.armors is Dictionary:
		for k in es.armors.keys():
			var entry: Dictionary = es.armors[k]
			var se: Variant = entry.get("special_effects", {})
			if not (se is Dictionary):
				continue
			for k2 in se.keys():
				if str(k2).ends_with("_resistance") and str(k2) != "status_resistance":
					if float(se.get(k2, 0.0)) > 0.0:
						armor_id = str(k)
						elem = str(k2).replace("_resistance", "")
						break
			if armor_id != "":
				break
	if armor_id == "":
		pending("no <element>_resistance armor found")
		return
	var c: Combatant = _make("Resister", 100)
	c.equipped_armor = armor_id
	assert_true(c._has_equipment_resistance(elem),
		"combatant wearing the matching-element armor must report resistance")
	# Different element should NOT resist.
	var different: String = "lightning" if elem != "lightning" else "ice"
	assert_false(c._has_equipment_resistance(different),
		"resistance must not bleed across elements — wire is per-element")


func test_runtime_empty_element_returns_false() -> void:
	# Edge case: empty element string must return false (don't
	# pretend bare-magic damage gets resisted).
	var c: Combatant = _make("Anon", 100)
	c.equipped_armor = "bone_armor"  # may or may not exist; ignored
	assert_false(c._has_equipment_resistance(""),
		"empty element must short-circuit to false")
