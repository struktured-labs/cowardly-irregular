extends GutTest

## tick 429: monsters.json `learns_from` flag now drives a
## per-battle elemental-resistance adaptation.
##
## Pre-fix 22 monsters authored learns_from but no code read the
## flag — bosses (including the 4 W1 dragons, Mordaine, and the
## permadeath_reaper) advertised adaptive learning that never
## happened. Boss fights were as static as random encounters.
##
## Implementation: when a flagged enemy gets hit by the SAME element
## 3 times in a single battle, the enemy adds that element to
## elemental_resistances (so further damage is halved). Capped at
## one adaptation per enemy per battle.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String, monster_type: String = "") -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	if monster_type != "":
		c.set_meta("monster_type", monster_type)
	return c


func test_helper_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("func _maybe_apply_elemental_adaptation"),
		"BattleManager must declare _maybe_apply_elemental_adaptation helper")
	assert_true(src.contains("data.get(\"learns_from\", [])"),
		"helper must read learns_from from monsters.json")


func test_threshold_constant_declared() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("const _LEARNS_FROM_THRESHOLD"),
		"BattleManager must declare _LEARNS_FROM_THRESHOLD constant")


func test_helper_wired_into_magic_path() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("_maybe_apply_elemental_adaptation(target, element)"),
		"magic-ability damage path must call _maybe_apply_elemental_adaptation")


func test_data_still_authors_learns_from() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/monsters.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	# At least the 4 W1 dragons should still author it.
	for dragon in ["fire_dragon", "ice_dragon", "lightning_dragon", "shadow_dragon"]:
		assert_true(data.has(dragon))
		var lf: Variant = data[dragon].get("learns_from", [])
		assert_true(lf is Array)
		assert_gt((lf as Array).size(), 0,
			"%s must still author a non-empty learns_from array" % dragon)


func test_runtime_threshold_triggers_adaptation() -> void:
	# Hit a flagged enemy with the same element threshold times;
	# verify the resistance gets added.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	if not (EncounterSystem and EncounterSystem.monster_database.has("fire_dragon")):
		pending("fire_dragon must be in EncounterSystem.monster_database")
		return
	var target: Combatant = _make("Fire Dragon", "fire_dragon")
	# Clear any pre-existing resistances.
	target.elemental_resistances = []
	# First two ice hits: no resistance yet.
	bm._maybe_apply_elemental_adaptation(target, "ice")
	assert_false("ice" in target.elemental_resistances,
		"adaptation must NOT trigger before threshold — 1st hit")
	bm._maybe_apply_elemental_adaptation(target, "ice")
	assert_false("ice" in target.elemental_resistances,
		"adaptation must NOT trigger before threshold — 2nd hit")
	# Third hit: resistance added.
	bm._maybe_apply_elemental_adaptation(target, "ice")
	assert_true("ice" in target.elemental_resistances,
		"adaptation must trigger on 3rd hit with same element")


func test_runtime_one_adaptation_per_enemy() -> void:
	# A flagged enemy can only adapt ONCE per battle — even if a second
	# element crosses the threshold later, the enemy stays at one
	# resistance (no infinite stacking).
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	if not (EncounterSystem and EncounterSystem.monster_database.has("fire_dragon")):
		pending("fire_dragon must be in EncounterSystem.monster_database")
		return
	var target: Combatant = _make("Fire Dragon", "fire_dragon")
	target.elemental_resistances = []
	# Hit with ice 3 times → resistance.
	for i in range(3):
		bm._maybe_apply_elemental_adaptation(target, "ice")
	assert_true("ice" in target.elemental_resistances)
	# Hit with lightning 3 more times.
	for i in range(3):
		bm._maybe_apply_elemental_adaptation(target, "lightning")
	# lightning must NOT be added — already adapted.
	assert_false("lightning" in target.elemental_resistances,
		"only ONE adaptation per enemy per battle — lightning must stay un-resisted")


func test_runtime_skips_non_flagged_monster() -> void:
	# A normal monster (no learns_from flag) must not adapt.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var target: Combatant = _make("Slime", "slime")
	target.elemental_resistances = []
	for i in range(10):
		bm._maybe_apply_elemental_adaptation(target, "ice")
	assert_false("ice" in target.elemental_resistances,
		"normal monster must NOT adapt — fix must not silently buff baseline")


func test_runtime_skips_physical_and_empty() -> void:
	# Physical and empty-element hits don't count toward adaptation.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	if not (EncounterSystem and EncounterSystem.monster_database.has("fire_dragon")):
		pending("fire_dragon must be in EncounterSystem.monster_database")
		return
	var target: Combatant = _make("Fire Dragon", "fire_dragon")
	target.elemental_resistances = []
	for i in range(10):
		bm._maybe_apply_elemental_adaptation(target, "")
		bm._maybe_apply_elemental_adaptation(target, "physical")
	assert_eq(target.elemental_resistances.size(), 0,
		"physical and empty-element hits must NOT trigger adaptation")
