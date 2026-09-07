extends GutTest

## tick 400: reverse_permadeath (undo_death ability) now actually
## revives a permakilled ally.
##
## Pre-fix: 40-MP rescue ability silently fizzled to `_:`
## push_warning. Players burned 40 MP on dead allies to bring them
## back — got nothing.

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
	assert_true(src.contains("\"reverse_permadeath\":"),
		"BattleManager._execute_meta_ability must have a reverse_permadeath arm")
	var arm_idx: int = src.find("\"reverse_permadeath\":")
	var window: String = src.substr(arm_idx, 1200)
	assert_true(window.contains("target.revive"),
		"reverse_permadeath must call target.revive()")
	assert_true(window.contains("remove_status(\"permakilled\")"),
		"reverse_permadeath must remove the permakilled marker before revive")


func test_data_authors_reverse_permadeath() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("undo_death"))
	assert_eq(str(data["undo_death"].get("meta_effect", "")), "reverse_permadeath")


func test_dead_ally_revived() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var caster: Combatant = _make("TimeMage")
	var target: Combatant = _make("DeadAlly")
	target.die()
	target.add_status("permakilled")
	assert_false(target.is_alive)
	assert_true("permakilled" in target.status_effects)

	var ability: Dictionary = {
		"id": "test_undo_death",
		"meta_effect": "reverse_permadeath",
	}
	bm._execute_meta_ability(caster, ability, [target])

	assert_true(target.is_alive,
		"target must be alive again after reverse_permadeath")
	assert_false("permakilled" in target.status_effects,
		"permakilled marker must be removed so death isn't re-applied")
	assert_gt(target.current_hp, 0,
		"target must have positive HP after revive")


func test_alive_target_not_affected() -> void:
	# Regression guard: the cast on an alive ally must not damage them.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var caster: Combatant = _make("TimeMage")
	var target: Combatant = _make("AliveAlly")
	var hp_before: int = target.current_hp
	var ability: Dictionary = {
		"id": "test_undo_death",
		"meta_effect": "reverse_permadeath",
	}
	bm._execute_meta_ability(caster, ability, [target])
	# An already-alive target shouldn't be revived or damaged.
	assert_eq(target.current_hp, hp_before,
		"alive target must NOT have HP changed by reverse_permadeath")
