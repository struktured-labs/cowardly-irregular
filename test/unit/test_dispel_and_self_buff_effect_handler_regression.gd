extends GutTest

## tick 385: dispel_and_self_buff (reduce_overhead ability) now both
## strips the target ally's buffs AND grants the caster an attack
## buff.
##
## Pre-fix the effect fell through to `_:` push_warning default —
## 15 MP + AP burned for no mechanical change.
##
## Default modifiers (no data fields authored): caster gets attack_up
## 1.3x for 3 turns. Future abilities sharing this effect can author
## self_buff_stat / self_buff_modifier / self_buff_duration to override.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({
		"name": name_str, "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10,
	})
	add_child_autofree(c)
	return c


func test_arm_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var arm_idx: int = src.find("\"dispel_and_self_buff\":")
	assert_gt(arm_idx, -1, "BattleManager dispatch must have a dispel_and_self_buff arm")
	var window: String = src.substr(arm_idx, 2000)
	assert_true(window.contains("target.active_buffs.clear()"),
		"dispel_and_self_buff must clear target's active_buffs")
	assert_true(window.contains("caster.add_buff(\"Overhead Reduced\""),
		"dispel_and_self_buff must apply a self-buff with the 'Overhead Reduced' label")


func test_data_still_authors_effect() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	assert_eq(typeof(parsed), TYPE_DICTIONARY)
	var data: Dictionary = parsed
	assert_true(data.has("reduce_overhead"))
	assert_eq(str(data["reduce_overhead"].get("effect", "")), "dispel_and_self_buff")


func test_dispels_target_and_buffs_caster() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	if bm == null or js == null:
		pending("BattleManager + JobSystem autoloads required")
		return
	if not js.abilities.has("reduce_overhead"):
		pending("reduce_overhead ability required")
		return
	var caster: Combatant = _make("Sacrifice")
	var ally: Combatant = _make("Target")
	# Seed buffs on the ally that should be stripped.
	ally.add_buff("Power Up", "attack", 1.5, 3)
	ally.add_buff("Shell", "magic", 1.2, 2)
	assert_eq(ally.active_buffs.size(), 2)
	# Caster starts with no buffs.
	assert_eq(caster.active_buffs.size(), 0)

	var ability: Dictionary = js.abilities["reduce_overhead"].duplicate(true)
	var typed_targets: Array[Combatant] = [ally]
	bm._execute_support_ability(caster, ability, typed_targets)

	assert_eq(ally.active_buffs.size(), 0,
		"target ally's buffs must be stripped — pre-fix the effect silently fizzled")
	assert_eq(caster.active_buffs.size(), 1,
		"caster must gain the 'Overhead Reduced' self-buff")
	assert_eq(caster.active_buffs[0].get("effect", ""), "Overhead Reduced",
		"the self-buff must use the 'Overhead Reduced' effect label")


func test_data_can_override_self_buff_defaults() -> void:
	# Future abilities reusing this effect can author overrides.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var caster: Combatant = _make("Sacrifice")
	var ally: Combatant = _make("Target")
	var ability: Dictionary = {
		"name": "Custom",
		"effect": "dispel_and_self_buff",
		"self_buff_stat": "magic",
		"self_buff_modifier": 1.6,
		"self_buff_duration": 5,
	}
	var typed_targets: Array[Combatant] = [ally]
	bm._execute_support_ability(caster, ability, typed_targets)
	assert_eq(caster.active_buffs.size(), 1)
	assert_eq(str(caster.active_buffs[0].get("stat", "")), "magic",
		"self_buff_stat override must apply")
	assert_eq(int(caster.active_buffs[0].get("duration", 0)), 5,
		"self_buff_duration override must apply")
