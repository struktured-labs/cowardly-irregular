extends GutTest

## tick 459: equipment.json special_effects.evasion_bonus now
## actually gives a chance-based miss in _target_dodges_physical.
##
## Pre-tick equipment authored:
##   elven_cloak, thiefs_glove, speed_boots: special_effects.evasion_bonus
## but no code path read the field. The dodge chance the gear name
## promised was decoration — equipping elven_cloak gave the stat
## boost (stat_mods.speed etc.) but NOT the dodge chance.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_dodge_check_reads_equip_bonus() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _target_dodges_physical")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_sum_equipment_special_effect(target, \"evasion_bonus\")"),
		"_target_dodges_physical must consult equipment evasion_bonus on the target")
	# Cap at 50% so stacked items don't make target untouchable.
	assert_true(body.contains("clampf(_sum_equipment_special_effect(target, \"evasion_bonus\"), 0.0, 0.50)"),
		"equip_dodge must clamp [0.0, 0.50]")
	# Separate emit so the log line says evade rather than fold into
	# the passive_dodge emit.
	assert_true(body.contains("emit(target)") and body.contains("equip_dodge"),
		"equip_dodge path must emit attack_missed independently")


func test_equip_dodge_after_passive() -> void:
	# Pin ordering: equip dodge comes AFTER the passive dodge so
	# the two are independent rolls (additive in probability sense).
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _target_dodges_physical")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	var passive_idx: int = body.find("passive_dodge")
	var equip_idx: int = body.find("equip_dodge")
	assert_gt(passive_idx, -1)
	assert_gt(equip_idx, -1)
	assert_lt(passive_idx, equip_idx,
		"equip_dodge check must come AFTER passive_dodge for independent rolls")


func test_data_still_authors_evasion_bonus() -> void:
	# Walk equipment.json and confirm at least one piece still
	# authors evasion_bonus.
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
			if se is Dictionary and float(se.get("evasion_bonus", 0.0)) > 0.0:
				found = true
				break
		if found:
			break
	assert_true(found,
		"equipment.json must still author evasion_bonus on at least one piece")


func test_runtime_helper_path_for_evasion() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var c_script: GDScript = load("res://src/battle/Combatant.gd")
	var c: Combatant = c_script.new()
	c.initialize({"name": "Bare", "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 5, "magic": 10, "speed": 10})
	add_child_autofree(c)
	c.equipped_weapon = ""
	c.equipped_armor = ""
	c.equipped_accessory = ""
	assert_eq(bm._sum_equipment_special_effect(c, "evasion_bonus"), 0.0,
		"bare target must report 0.0 evasion_bonus")


func test_runtime_with_authored_item() -> void:
	# Find any piece authoring evasion_bonus, equip it, verify
	# helper returns >0.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var es = Engine.get_main_loop().root.get_node_or_null("EquipmentSystem")
	if es == null:
		pending("EquipmentSystem autoload required")
		return
	var found_slot: String = ""
	var found_id: String = ""
	for slot_pair in [["weapons", "equipped_weapon"], ["armors", "equipped_armor"], ["accessories", "equipped_accessory"]]:
		var cat: String = slot_pair[0]
		var ep_slot: String = slot_pair[1]
		var bucket: Variant = null
		match cat:
			"weapons":
				bucket = es.weapons
			"armors":
				bucket = es.armors
			"accessories":
				bucket = es.accessories
		if not (bucket is Dictionary):
			continue
		for k in bucket.keys():
			var entry: Dictionary = bucket[k]
			var se: Variant = entry.get("special_effects", {})
			if se is Dictionary and float(se.get("evasion_bonus", 0.0)) > 0.0:
				found_slot = ep_slot
				found_id = str(k)
				break
		if found_id != "":
			break
	if found_id == "":
		pending("no evasion_bonus equipment found")
		return
	var c_script: GDScript = load("res://src/battle/Combatant.gd")
	var c: Combatant = c_script.new()
	c.initialize({"name": "Dodger", "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 5, "magic": 10, "speed": 10})
	add_child_autofree(c)
	c.set(found_slot, found_id)
	var bonus: float = bm._sum_equipment_special_effect(c, "evasion_bonus")
	assert_gt(bonus, 0.0,
		"equipping an evasion_bonus piece must produce a positive helper read")
