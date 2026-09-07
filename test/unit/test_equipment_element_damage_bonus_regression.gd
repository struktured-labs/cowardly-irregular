extends GutTest

## tick 458: equipment.json special_effects.<element>_damage_bonus
## family now actually multiplies magic damage on matching-element
## spells.
##
## Pre-tick equipment authored:
##   flame_sword: special_effects.fire_damage_bonus = 1.5
##   ice_blade: special_effects.ice_damage_bonus
##   thunder_rod: special_effects.lightning_damage_bonus
##   shadow_rod: special_effects.dark_damage_bonus
##   holy_staff: special_effects.holy_damage_bonus
## but no code path read any of them. Themed gear gave the stat
## boost (stat_mods.magic etc.) but NOT the headline elemental
## damage promise.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_magic_consults_helper_with_dynamic_key() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_magic_ability")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# Dynamic key construction so all five (fire/ice/light/dark/holy)
	# inherit the same wire with no per-element conditionals.
	assert_true(body.contains("_sum_equipment_special_effect(caster, element + \"_damage_bonus\")"),
		"_execute_magic_ability must consult <element>_damage_bonus dynamically by element string")
	# Bake into multiplier so all targets in the loop pick it up.
	assert_true(body.contains("multiplier *= elem_bonus"),
		"the elem_bonus must multiply the cast's damage_multiplier (so all per-target hits scale)")


func test_skip_for_element_less_abilities() -> void:
	# Pin the element=="" gate so a generic magic cast (no element)
	# doesn't accidentally pick up a stale lookup.
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_magic_ability")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("if element != \"\":"),
		"element-less abilities must be skipped (no fire bonus on a no-element spell)")


func test_data_still_authors_fire_bonus_somewhere() -> void:
	# Walk equipment.json and confirm at least one piece still
	# authors fire_damage_bonus (canonical regression — flame_sword
	# was the first authored entry).
	var raw: String = FileAccess.get_file_as_string("res://data/equipment.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	var found_fire: bool = false
	for cat in ["weapons", "armors", "accessories"]:
		if not data.has(cat):
			continue
		for iid in data[cat].keys():
			var entry: Dictionary = data[cat][iid]
			var se: Variant = entry.get("special_effects", {})
			if se is Dictionary and float(se.get("fire_damage_bonus", 0.0)) > 0.0:
				found_fire = true
				break
		if found_fire:
			break
	assert_true(found_fire,
		"equipment.json must still author fire_damage_bonus on at least one piece")


func test_helper_handles_missing_autoload_cleanly() -> void:
	# Indirect via the helper from tick 457: an arbitrary unread key
	# returns 0.0 cleanly so the bake-in becomes a no-op rather than
	# multiplying by NaN.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var c_script: GDScript = load("res://src/battle/Combatant.gd")
	var c: Combatant = c_script.new()
	c.initialize({"name": "Test", "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 5, "magic": 10, "speed": 10})
	add_child_autofree(c)
	c.equipped_weapon = ""
	c.equipped_armor = ""
	c.equipped_accessory = ""
	assert_eq(bm._sum_equipment_special_effect(c, "fire_damage_bonus"), 0.0,
		"bare combatant must report 0.0 fire_damage_bonus (no silent baseline)")


func test_runtime_authored_element_returns_bonus() -> void:
	# Find any weapon that authors fire_damage_bonus, equip it,
	# verify helper returns >0.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var es = Engine.get_main_loop().root.get_node_or_null("EquipmentSystem")
	if es == null:
		pending("EquipmentSystem autoload required")
		return
	var fire_weapon: String = ""
	if es.weapons is Dictionary:
		for k in es.weapons.keys():
			var entry: Dictionary = es.weapons[k]
			var se: Variant = entry.get("special_effects", {})
			if se is Dictionary and float(se.get("fire_damage_bonus", 0.0)) > 0.0:
				fire_weapon = str(k)
				break
	if fire_weapon == "":
		pending("no fire_damage_bonus weapon in EquipmentSystem")
		return
	var c_script: GDScript = load("res://src/battle/Combatant.gd")
	var c: Combatant = c_script.new()
	c.initialize({"name": "FireMage", "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 5, "magic": 30, "speed": 10})
	add_child_autofree(c)
	c.equipped_weapon = fire_weapon
	var bonus: float = bm._sum_equipment_special_effect(c, "fire_damage_bonus")
	assert_gt(bonus, 0.0,
		"caster with the fire weapon must report a positive fire_damage_bonus")
	# Sanity: a different element doesn't accidentally pick up the
	# fire weapon's bonus.
	var ice_bonus: float = bm._sum_equipment_special_effect(c, "ice_damage_bonus")
	assert_eq(ice_bonus, 0.0,
		"fire weapon must not contribute to ice_damage_bonus")
