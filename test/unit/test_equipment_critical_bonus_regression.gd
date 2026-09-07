extends GutTest

## tick 457: equipment.json special_effects.critical_bonus now
## actually adds to _calculate_crit_chance.
##
## Pre-tick equipment authored:
##   assassin_blade, lucky_charm, etc.: special_effects.critical_bonus
## but no code path read the field. _calculate_crit_chance held a
## stubbed `equip_bonus = 0.0` with a "could add this later"
## comment. Equipping an assassin's dagger gave you the stat boost
## (attack/speed via stat_mods) but NOT the crit chance bonus its
## name implied.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 5, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func test_helper_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("func _sum_equipment_special_effect"),
		"BattleManager must declare _sum_equipment_special_effect helper")
	# Pins for the three slots so future bonuses (evasion, poison
	# chance, etc.) inherit the same plumbing.
	for slot in ["equipped_weapon", "equipped_armor", "equipped_accessory"]:
		assert_true(src.contains("\"" + slot + "\" in combatant"),
			"helper must check the " + slot + " slot")


func test_crit_consults_helper() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _calculate_crit_chance")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_sum_equipment_special_effect(attacker, \"critical_bonus\")"),
		"_calculate_crit_chance must read critical_bonus via the helper")
	# Cap is critical so a chain of crit-bonus items can't fast-track to 1.0.
	assert_true(body.contains("clampf(equip_bonus, 0.0, 0.50)"),
		"the equip_bonus must clamp [0.0, 0.50] so stacked items can't one-shot")


func test_data_still_authors_critical_bonus() -> void:
	# Walk equipment.json and confirm at least one entry still
	# authors critical_bonus so the wire isn't pinned to a future-
	# data-edit hole.
	var raw: String = FileAccess.get_file_as_string("res://data/equipment.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	var found_crit_author: bool = false
	for cat in ["weapons", "armors", "accessories"]:
		if not data.has(cat):
			continue
		for iid in data[cat].keys():
			var entry: Dictionary = data[cat][iid]
			var se: Variant = entry.get("special_effects", {})
			if se is Dictionary and float(se.get("critical_bonus", 0.0)) > 0.0:
				found_crit_author = true
				break
		if found_crit_author:
			break
	assert_true(found_crit_author,
		"equipment.json must still author critical_bonus on at least one piece")


func test_runtime_no_equipment_returns_zero() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var c: Combatant = _make("Bare")
	c.equipped_weapon = ""
	c.equipped_armor = ""
	c.equipped_accessory = ""
	assert_eq(bm._sum_equipment_special_effect(c, "critical_bonus"), 0.0,
		"bare combatant must report 0.0 — fix must not silently grant baseline")


func test_runtime_with_authored_item_grants_bonus() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var es = Engine.get_main_loop().root.get_node_or_null("EquipmentSystem")
	if es == null:
		pending("EquipmentSystem autoload required")
		return
	# Find any weapon that authors critical_bonus.
	var target_id: String = ""
	if es.weapons is Dictionary:
		for k in es.weapons.keys():
			var entry: Dictionary = es.weapons[k]
			var se: Variant = entry.get("special_effects", {})
			if se is Dictionary and float(se.get("critical_bonus", 0.0)) > 0.0:
				target_id = str(k)
				break
	if target_id == "":
		pending("no critical_bonus weapon in EquipmentSystem")
		return
	var c: Combatant = _make("CritWielder")
	c.equipped_weapon = target_id
	var bonus: float = bm._sum_equipment_special_effect(c, "critical_bonus")
	assert_gt(bonus, 0.0,
		"combatant with the critical_bonus weapon must report > 0.0 — wire must read the data")


func test_runtime_helper_is_generic() -> void:
	# Sanity: passing a different (currently unread) key returns
	# the authored value or 0 cleanly — generic shape works for
	# future ticks that wire the companion keys.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var c: Combatant = _make("Whatever")
	c.equipped_weapon = ""
	c.equipped_armor = ""
	c.equipped_accessory = ""
	assert_eq(bm._sum_equipment_special_effect(c, "evasion_bonus"), 0.0,
		"helper must return 0.0 cleanly for an arbitrary key on a bare combatant")
