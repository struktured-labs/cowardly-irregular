extends GutTest

## tick 423: monsters.json special_behavior.heals_from_damage now
## actually converts incoming damage to healing. the_absence (W6
## abstract) authors heals_from_damage=true + heal_percentage=0.3
## as its signature mechanic ("Hitting it just fills the void").
##
## Pre-fix the flag was authored but no code read it — players
## damaged the_absence normally instead of feeding it.
##
## Holy element bypasses per the data's authored description
## ("Status effects, debuffs, and holy magic bypass this
## absorption").

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make_target(name_str: String, monster_type: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	c.set_meta("monster_type", monster_type)
	return c


func test_helper_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("func _maybe_heal_from_damage"),
		"BattleManager must declare _maybe_heal_from_damage helper")
	assert_true(src.contains("sb.get(\"heals_from_damage\", false)"),
		"helper must read special_behavior.heals_from_damage")
	assert_true(src.contains("sb.get(\"heal_percentage\", 0.3)"),
		"helper must read heal_percentage with 0.3 default (matches data)")


func test_holy_element_bypasses() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _maybe_heal_from_damage")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("element == \"holy\""),
		"helper must skip heal-from-damage when element=='holy' per the authored description")


func test_helper_wired_into_attack_paths() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# Basic attack path passes "" for element.
	assert_true(src.contains("_maybe_heal_from_damage(actual_target, actual_damage, \"\")"),
		"basic-attack path must call _maybe_heal_from_damage with empty element")
	# Physical ability path also passes "". Tick 431 renamed the
	# variable to hit_damage (per-hit) for multi-hit support — accept
	# either to stay forward-compatible.
	assert_true(
		src.contains("_maybe_heal_from_damage(target, actual_damage, \"\")")
		or src.contains("_maybe_heal_from_damage(target, hit_damage, \"\")"),
		"physical-ability path must call _maybe_heal_from_damage with empty element (actual_damage or per-hit hit_damage)")
	# Magic ability path passes the actual element (so holy bypass works).
	assert_true(src.contains("_maybe_heal_from_damage(target, actual_damage, element)"),
		"magic-ability path must call _maybe_heal_from_damage with element so holy bypasses")


func test_data_still_authors_heals_from_damage() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/monsters.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("the_absence"))
	var sb: Variant = data["the_absence"].get("special_behavior", {})
	assert_true(sb is Dictionary)
	assert_true(bool(sb.get("heals_from_damage", false)),
		"the_absence must still author heals_from_damage=true")
	assert_gt(float(sb.get("heal_percentage", 0.0)), 0.0,
		"the_absence must still author a positive heal_percentage")


func test_runtime_helper_heals_the_absence() -> void:
	# End-to-end: helper actually heals the_absence on damage.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	if not (EncounterSystem and EncounterSystem.monster_database.has("the_absence")):
		pending("the_absence must be in EncounterSystem.monster_database")
		return
	var target: Combatant = _make_target("The Absence", "the_absence")
	target.current_hp = 50  # half health
	bm._maybe_heal_from_damage(target, 30, "")  # 30 damage -> heal 30 * 0.3 = 9 HP
	assert_gt(target.current_hp, 50,
		"the_absence must heal when damaged — pre-fix the heal flag was ignored")


func test_runtime_helper_skips_holy_element() -> void:
	# Holy damage must bypass the heal.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	if not (EncounterSystem and EncounterSystem.monster_database.has("the_absence")):
		pending("the_absence must be in EncounterSystem.monster_database")
		return
	var target: Combatant = _make_target("The Absence", "the_absence")
	target.current_hp = 50
	bm._maybe_heal_from_damage(target, 30, "holy")
	assert_eq(target.current_hp, 50,
		"holy element must bypass the heal-from-damage absorption")


func test_runtime_helper_skips_non_absorbing_monster() -> void:
	# Sanity: regular monster (no special_behavior.heals_from_damage)
	# must not heal.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var target: Combatant = _make_target("Slime", "slime")
	target.current_hp = 50
	bm._maybe_heal_from_damage(target, 30, "")
	assert_eq(target.current_hp, 50,
		"normal monster must NOT heal from damage — fix must not buff baseline")
