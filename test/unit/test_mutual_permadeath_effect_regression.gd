extends GutTest

## tick 399: mutual_permadeath (mutual_destruction ability) now kills
## both caster and target permanently.
##
## Pre-fix the meta_effect fell through to `_:` push_warning. The 99-
## MP terminal-sacrifice ability ("Kill both you and the bound boss
## instantly. Permanent. No takebacks.") consumed 99 MP and did
## absolutely nothing.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _make(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": 100, "max_mp": 100,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func test_arm_exists() -> void:
	var src: String = FileAccess.get_file_as_string(BATTLE_MANAGER_PATH)
	assert_true(src.contains("\"mutual_permadeath\":"),
		"BattleManager._execute_meta_ability must have a mutual_permadeath arm")
	var arm_idx: int = src.find("\"mutual_permadeath\":")
	var window: String = src.substr(arm_idx, 1200)
	assert_true(window.contains("caster.die()"),
		"mutual_permadeath must call die() on the caster")
	assert_true(window.contains("target.die()"),
		"mutual_permadeath must call die() on the targets")
	assert_true(window.contains("permakilled"),
		"mutual_permadeath must apply the permakilled status (mirrors permanent_death)")


func test_data_authors_mutual_permadeath() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("mutual_destruction"))
	assert_eq(str(data["mutual_destruction"].get("meta_effect", "")), "mutual_permadeath")


func test_caster_and_target_both_die() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var caster: Combatant = _make("Bossbinder")
	var target: Combatant = _make("Boss")
	assert_true(caster.is_alive)
	assert_true(target.is_alive)

	var ability: Dictionary = {
		"id": "test_mutual_destruction",
		"meta_effect": "mutual_permadeath",
		"corruption_risk": 0.0,
	}
	bm._execute_meta_ability(caster, ability, [target])

	assert_false(caster.is_alive,
		"caster must die after mutual_permadeath")
	assert_false(target.is_alive,
		"target must die after mutual_permadeath")
	assert_true("permakilled" in caster.status_effects,
		"caster must be permakilled (no revival)")
	assert_true("permakilled" in target.status_effects,
		"target must be permakilled")
