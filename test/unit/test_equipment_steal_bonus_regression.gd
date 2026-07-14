extends GutTest

## tick 462: equipment.json special_effects.steal_bonus now actually
## boosts the Steal ability's per-cast success rate.
##
## Pre-tick equipment authored:
##   thiefs_glove: special_effects.steal_bonus = 0.25
## but no code path read the field. The glove gave the stat boost
## (stat_mods) but not the headline +25% steal success the name
## promised.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_steal_branch_reads_bonus() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# Find the steal effect branch and pin the helper call inside it.
	var idx: int = src.find("\"steal\":")
	assert_gt(idx, -1)
	# Window covers the comment + bonus pull + clamp + loop.
	var window: String = src.substr(idx, 1200)
	assert_true(window.contains("_sum_equipment_special_effect(caster, \"steal_bonus\")"),
		"steal branch must read steal_bonus via the generic helper")


func test_effective_rate_clamps_at_1_0() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var idx: int = src.find("\"steal\":")
	var window: String = src.substr(idx, 1200)
	assert_true(window.contains("clampf(success_rate + steal_bonus, 0.0, 1.0)"),
		"effective rate must clamp at 1.0 so stacked gloves don't bend math")


func test_steal_loop_uses_effective_rate() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var idx: int = src.find("\"steal\":")
	var window: String = src.substr(idx, 1500)
	# The randf check must use effective_rate, not success_rate.
	assert_true(window.contains("if randf() < effective_rate:"),
		"steal randf check must consult the bonus-adjusted effective_rate (not the raw success_rate)")


func test_data_still_authors_steal_bonus() -> void:
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
			if se is Dictionary and float(se.get("steal_bonus", 0.0)) > 0.0:
				found = true
				break
		if found:
			break
	assert_true(found,
		"equipment.json must still author steal_bonus on at least one piece")


func test_runtime_helper_path_bare_zero() -> void:
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
	c.equipped_accessory = ""
	c.equipped_armor = ""
	assert_eq(bm._sum_equipment_special_effect(c, "steal_bonus"), 0.0,
		"bare combatant must report 0.0 steal_bonus")


func test_runtime_thiefs_glove_gives_bonus() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var es = Engine.get_main_loop().root.get_node_or_null("EquipmentSystem")
	if es == null:
		pending("EquipmentSystem autoload required")
		return
	# Find any piece authoring steal_bonus and determine its slot.
	var target_slot: String = ""
	var target_id: String = ""
	for slot_pair in [["weapons", "equipped_weapon"], ["armors", "equipped_armor"], ["accessories", "equipped_accessory"]]:
		var cat: String = slot_pair[0]
		var slot: String = slot_pair[1]
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
			if se is Dictionary and float(se.get("steal_bonus", 0.0)) > 0.0:
				target_slot = slot
				target_id = str(k)
				break
		if target_id != "":
			break
	if target_id == "":
		pending("no steal_bonus equipment found")
		return
	var c_script: GDScript = load("res://src/battle/Combatant.gd")
	var c: Combatant = c_script.new()
	c.initialize({"name": "Rogue", "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 5, "magic": 10, "speed": 10})
	add_child_autofree(c)
	c.set(target_slot, target_id)
	var bonus: float = bm._sum_equipment_special_effect(c, "steal_bonus")
	assert_gt(bonus, 0.0,
		"thiefs_glove (or equivalent) must produce a positive steal_bonus reading")
