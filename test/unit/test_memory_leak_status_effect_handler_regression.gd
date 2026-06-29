extends GutTest

## tick 383: memory_leak_status effect from memory_leak now applies
## a 3%/turn HP DOT for the authored duration.
##
## Pre-fix: memory_leak (effect=memory_leak_status, duration=4,
## damage_multiplier=0.5) landed its upfront damage via the magic
## path but the advertised 4-turn HP drain was silently dropped —
## the effect arm fell through to `_:` push_warning default.
##
## Post-fix: dispatch applies a "memory_leak" status; Combatant.update_
## buff_durations adds a DOT block at 3% max_hp per turn (lighter than
## burn/poison/static because memory_leak has upfront damage AND lasts
## a full 4 turns — 12% total over the duration).

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
	var arm_idx: int = src.find("\"memory_leak_status\":")
	assert_gt(arm_idx, -1, "BattleManager dispatch must have a memory_leak_status arm")
	var window: String = src.substr(arm_idx, 400)
	assert_true(window.contains("add_status(\"memory_leak\""),
		"memory_leak_status arm must apply the memory_leak status")


func test_dot_block_in_combatant() -> void:
	var src := _read(COMBATANT_PATH)
	assert_true(src.contains("\"memory_leak\" in status_effects"),
		"update_buff_durations must have a memory_leak DOT block")
	assert_true(src.contains("status_tick_damage.emit(leak_damage, \"memory_leak\")"),
		"memory_leak DOT must emit status_tick_damage so BattleScene shows the popup")


func test_data_still_authors_effect() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	assert_eq(typeof(parsed), TYPE_DICTIONARY)
	var data: Dictionary = parsed
	assert_true(data.has("memory_leak"))
	assert_eq(str(data["memory_leak"].get("effect", "")), "memory_leak_status")


func test_dispatch_applies_status() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	if bm == null or js == null:
		pending("BattleManager + JobSystem autoloads required")
		return
	if not js.abilities.has("memory_leak"):
		pending("memory_leak ability required")
		return
	var target: Combatant = _make("Goblin")
	var ability: Dictionary = js.abilities["memory_leak"].duplicate(true)
	ability["success_rate"] = 1.0
	var typed_targets: Array[Combatant] = [target]
	bm._execute_support_ability(null, ability, typed_targets)
	assert_true("memory_leak" in target.status_effects,
		"memory_leak status must be present after the cast")


func test_dot_tick_deals_damage() -> void:
	var c: Combatant = _make("Hero")
	c.current_hp = 100
	c.add_status("memory_leak", 4)
	c.update_buff_durations()
	var damage: int = 100 - c.current_hp
	assert_true(damage >= 2 and damage <= 4,
		"memory_leak DOT must deal ~3%% max_hp (2-4 HP on 100-max target) — got %d" % damage)


func test_no_status_no_dot() -> void:
	var c: Combatant = _make("Vanilla")
	c.current_hp = 100
	c.status_effects.clear()
	c.update_buff_durations()
	assert_eq(c.current_hp, 100,
		"target without memory_leak status must NOT take DOT damage")
