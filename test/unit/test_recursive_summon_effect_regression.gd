extends GutTest

## tick 408: recursive_summon (Summoner meta ability) stacks magic
## buffs up to max_depth. Pre-fix the meta_effect fell through to
## `_:` push_warning — 45 MP burned for nothing.
##
## Each cast adds a "Recursive Summon N" buff (distinct effect name
## so add_buff doesn't refresh-in-place). Three separate 2.0x buffs
## multiply in get_buffed_stat, capped at 4x base by the existing
## clamp — matches the engine's overall power ceiling.

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
	var arm_idx: int = src.find("\"recursive_summon\":")
	assert_gt(arm_idx, -1, "BattleManager must have a recursive_summon arm")
	var window: String = src.substr(arm_idx, 1500)
	assert_true(window.contains("max_depth"),
		"recursive_summon arm must respect max_depth field")
	assert_true(window.contains("Recursive Summon"),
		"recursive_summon arm must apply the 'Recursive Summon N' buff series")


func test_data_authors_recursive_summon() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("recursive_summon"))
	assert_eq(str(data["recursive_summon"].get("meta_effect", "")), "recursive_summon")
	assert_gt(int(data["recursive_summon"].get("max_depth", 0)), 0,
		"recursive_summon must author a positive max_depth")


func test_first_cast_adds_one_stack() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var caster: Combatant = _make("Summoner")
	assert_eq(caster.active_buffs.size(), 0)
	var ability: Dictionary = {
		"id": "test_recursive_summon",
		"meta_effect": "recursive_summon",
		"max_depth": 3,
		"damage_multiplier": 2.0,
		"duration": 3,
	}
	bm._execute_meta_ability(caster, ability, [caster])
	assert_eq(caster.active_buffs.size(), 1,
		"first recursive_summon cast must add 1 buff")
	assert_eq(str(caster.active_buffs[0].get("effect", "")), "Recursive Summon 1",
		"first buff must be 'Recursive Summon 1'")


func test_stacks_up_to_max_depth() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var caster: Combatant = _make("Summoner")
	var ability: Dictionary = {
		"id": "test_recursive_summon",
		"meta_effect": "recursive_summon",
		"max_depth": 3,
		"damage_multiplier": 2.0,
		"duration": 3,
	}
	# Three casts → three stacks.
	bm._execute_meta_ability(caster, ability, [caster])
	bm._execute_meta_ability(caster, ability, [caster])
	bm._execute_meta_ability(caster, ability, [caster])
	assert_eq(caster.active_buffs.size(), 3,
		"three recursive_summon casts must add 3 stacks")
	# Fourth cast must be refused (max depth).
	bm._execute_meta_ability(caster, ability, [caster])
	assert_eq(caster.active_buffs.size(), 3,
		"fourth cast must NOT exceed max_depth")


func test_buffs_use_magic_stat() -> void:
	# Pin that the buffs land on the magic stat (eidolon damage path).
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var caster: Combatant = _make("Summoner")
	var ability: Dictionary = {
		"id": "test_recursive_summon",
		"meta_effect": "recursive_summon",
		"max_depth": 3,
		"damage_multiplier": 2.0,
		"duration": 3,
	}
	bm._execute_meta_ability(caster, ability, [caster])
	assert_eq(str(caster.active_buffs[0].get("stat", "")), "magic",
		"recursive_summon buff must target the magic stat")
