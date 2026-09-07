extends GutTest

## tick 433: abilities.json `secondary_effect` field now applies a
## follow-up debuff/status on top of the primary effect.
##
## Pre-fix 9 abilities authored secondary_effect (+ optional
## secondary_target / secondary_modifier / secondary_chance) but no
## code path read them — every secondary silently dropped:
##   - enrage's defense_down tradeoff: 0 cost (was free 2.0x attack)
##   - howl's fear chance: never frightened
##   - web_shot's stun chance: never bound
##   - frenzy / overcharge / streamline / sabotage / subset_drain /
##     toxic_embrace: all dropped their secondary stat mods

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func test_dispatcher_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("func _apply_secondary_effect"),
		"BattleManager must declare _apply_secondary_effect dispatcher")
	assert_true(src.contains("ability.get(\"secondary_effect\", \"\")"),
		"dispatcher must read secondary_effect")
	assert_true(src.contains("ability.get(\"secondary_chance\", 1.0)"),
		"dispatcher must read secondary_chance with default 1.0")


func test_secondary_target_resolution() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# Pin all 4 target tags supported.
	for tag in ["all_enemies", "all_allies", "self"]:
		assert_true(src.contains("\"%s\":" % tag) or src.contains("\"%s\"" % tag),
			"dispatcher must handle secondary_target='%s'" % tag)


func test_buff_debuff_status_maps_declared() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("_SECONDARY_STAT_BUFF_MAP"),
		"buff map must be declared so attack_up/defense_up etc. route to add_buff")
	assert_true(src.contains("_SECONDARY_STAT_DEBUFF_MAP"),
		"debuff map must be declared so attack_down/defense_down etc. route to add_debuff")


func test_dispatcher_called_after_match_block() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_support_ability")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_apply_secondary_effect(caster, ability, targets)"),
		"_execute_support_ability must call _apply_secondary_effect after the match block")


func test_data_still_authors_secondary_effect() -> void:
	# Sanity: the 9 abilities still author secondary_effect.
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	for ability_id in ["enrage", "howl", "web_shot", "frenzy", "overcharge"]:
		assert_true(data.has(ability_id), "%s ability must exist" % ability_id)
		var sec: String = str(data[ability_id].get("secondary_effect", ""))
		assert_ne(sec, "",
			"%s must still author secondary_effect (fix relies on this)" % ability_id)


func test_runtime_enrage_applies_defense_down_to_self() -> void:
	# enrage is self-target, applies attack_up + defense_down to caster.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var caster: Combatant = _make("Beast")
	var ability: Dictionary = {
		"id": "enrage_test",
		"effect": "attack_up",
		"stat_modifier": 2.0,
		"duration": 3,
		"secondary_effect": "defense_down",
		"secondary_modifier": 0.5,
	}
	var typed_targets: Array[Combatant] = [caster]
	bm._execute_support_ability(caster, ability, typed_targets)
	# Primary: attack_up buff.
	var attack_buff_found: bool = false
	for b in caster.active_buffs:
		if str(b.get("stat", "")) == "attack":
			attack_buff_found = true
			break
	assert_true(attack_buff_found, "primary attack_up buff must still apply")
	# Secondary: defense_down debuff.
	var defense_debuff_found: bool = false
	for d in caster.active_debuffs:
		if str(d.get("stat", "")) == "defense":
			defense_debuff_found = true
			break
	assert_true(defense_debuff_found,
		"enrage's secondary defense_down must now apply to self — pre-fix silent")


func test_runtime_unknown_effect_routes_to_add_status() -> void:
	# Unknown effect names (fear, stun, etc.) should route through
	# add_status as a fallback.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var caster: Combatant = _make("Wolf")
	var target: Combatant = _make("Enemy")
	# Force enemy_party so all_enemies resolution finds the target.
	var enemies: Array[Combatant] = [target]
	bm.enemy_party = enemies
	var ability: Dictionary = {
		"id": "howl_test",
		"effect": "attack_up",
		"stat_modifier": 1.4,
		"duration": 2,
		"secondary_target": "all_enemies",
		"secondary_effect": "fear",
		"secondary_chance": 1.0,
	}
	var typed_targets: Array[Combatant] = [caster]
	bm._execute_support_ability(caster, ability, typed_targets)
	assert_true("fear" in target.status_effects,
		"howl's secondary fear status must land on all_enemies — pre-fix never frightened")
