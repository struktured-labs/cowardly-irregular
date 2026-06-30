extends GutTest

## tick 453: pattern_recognition passive's meta_effects.boss_pattern
## _memory now actually grants +20% damage vs previously-fought
## bosses on top of the baseline stat_mods.attack_multiplier.
##
## Pre-fix passives.json authored:
##   pattern_recognition: {meta_effects: {boss_pattern_memory: true}}
##   description: "Learn boss attack patterns faster, +20% damage vs
##                 previously fought bosses"
## The stat_mods.attack_multiplier = 1.2 baseline was wired (always
## active at Combatant init), but boss_pattern_memory itself was
## decoration — the "vs previously fought bosses" conditionality was
## never realized.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"
const GAME_STATE_PATH := "res://src/meta/GameState.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": 1000, "max_mp": 50,
		"attack": 50, "defense": 0, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func test_field_persisted_in_to_dict() -> void:
	var src := _read(GAME_STATE_PATH)
	assert_true(src.contains("var previously_fought_bosses: Array[String] = []"),
		"GameState must declare typed Array[String] previously_fought_bosses")
	assert_true(src.contains("\"previously_fought_bosses\": previously_fought_bosses"),
		"GameState.to_dict must persist previously_fought_bosses")
	assert_true(src.contains("if save_data.has(\"previously_fought_bosses\"):"),
		"GameState load path must restore previously_fought_bosses")


func test_load_uses_typed_str_coercion() -> void:
	# Critical: typed-Array silent-fail trap (CLAUDE.md). Must use
	# explicit per-entry str() append, not generic-Array assignment.
	var src := _read(GAME_STATE_PATH)
	var idx: int = src.find("if save_data.has(\"previously_fought_bosses\"):")
	assert_gt(idx, -1)
	var window: String = src.substr(idx, 400)
	assert_true(window.contains("previously_fought_bosses.append(str(b))"),
		"load must use per-entry str() coercion to dodge the typed-array silent-fail trap")


func test_helper_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("func _apply_pattern_recognition_bonus"),
		"BattleManager must declare _apply_pattern_recognition_bonus")
	assert_true(src.contains("me.get(\"boss_pattern_memory\", false)"),
		"helper must check the meta_effect flag")
	# Multiplier must match the description's +20%.
	assert_true(src.contains("damage * 1.2"),
		"helper must apply the +20% bonus")


func test_basic_attack_consults_helper() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# _execute_attack is the path; the bonus wraps the take_damage
	# argument right above the basic-attack damage emit.
	var idx: int = src.find("_apply_pattern_recognition_bonus(attacker, actual_target, damage)")
	assert_gt(idx, -1,
		"_execute_attack must wrap damage in _apply_pattern_recognition_bonus before take_damage")


func test_victory_records_boss() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var idx: int = src.find("\"previously_fought_bosses\" in GameState")
	assert_gt(idx, -1,
		"end_battle must check GameState.previously_fought_bosses on victory")
	var window: String = src.substr(idx, 1500)
	assert_true(window.contains("GameState.previously_fought_bosses.append(boss_id)"),
		"end_battle must append boss_id to the memory list")
	assert_true(window.contains("not (boss_id in GameState.previously_fought_bosses)"),
		"end_battle must dedupe before appending so the list doesn't grow per repeat fight")


func test_data_still_authors_flag() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/passives.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("pattern_recognition"))
	var me: Variant = data["pattern_recognition"].get("meta_effects", {})
	assert_true(me is Dictionary)
	assert_true(bool(me.get("boss_pattern_memory", false)),
		"pattern_recognition must still author boss_pattern_memory")


func test_runtime_helper_no_passive_no_bonus() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var attacker: Combatant = _make("Vanilla")
	attacker.equipped_passives = []
	var boss: Combatant = _make("Boss")
	boss.set_meta("is_boss", true)
	boss.set_meta("monster_type", "test_boss")
	var out: int = bm._apply_pattern_recognition_bonus(attacker, boss, 100)
	assert_eq(out, 100,
		"vanilla attacker must NOT get the bonus — fix must be passive-gated")


func test_runtime_helper_no_history_no_bonus() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null or not ps.passives.has("pattern_recognition"):
		pending("pattern_recognition passive required")
		return
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		return
	var prior_bosses: Array[String] = []
	for b in gs.previously_fought_bosses:
		prior_bosses.append(str(b))
	gs.previously_fought_bosses.clear()  # no memory yet
	var attacker: Combatant = _make("Pat")
	attacker.equipped_passives = ["pattern_recognition"]
	var boss: Combatant = _make("FirstBoss")
	boss.set_meta("is_boss", true)
	boss.set_meta("monster_type", "first_boss")
	var out: int = bm._apply_pattern_recognition_bonus(attacker, boss, 100)
	assert_eq(out, 100,
		"first encounter (no history) must get no bonus — memory has to be built first")
	gs.previously_fought_bosses = prior_bosses


func test_runtime_helper_repeat_boss_gets_bonus() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null or not ps.passives.has("pattern_recognition"):
		pending("pattern_recognition passive required")
		return
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		return
	var prior_bosses: Array[String] = []
	for b in gs.previously_fought_bosses:
		prior_bosses.append(str(b))
	gs.previously_fought_bosses.append("repeat_boss")
	var attacker: Combatant = _make("PatB")
	attacker.equipped_passives = ["pattern_recognition"]
	var boss: Combatant = _make("RepeatBoss")
	boss.set_meta("is_boss", true)
	boss.set_meta("monster_type", "repeat_boss")
	var out: int = bm._apply_pattern_recognition_bonus(attacker, boss, 100)
	assert_eq(out, 120,
		"repeat-fought boss must get the +20% bonus damage")
	gs.previously_fought_bosses = prior_bosses


func test_runtime_helper_non_boss_no_bonus() -> void:
	# A goblin without is_boss/is_miniboss meta must not trigger
	# the bonus even with the passive equipped.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null or not ps.passives.has("pattern_recognition"):
		pending("pattern_recognition passive required")
		return
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		return
	var prior_bosses: Array[String] = []
	for b in gs.previously_fought_bosses:
		prior_bosses.append(str(b))
	gs.previously_fought_bosses.append("goblin")
	var attacker: Combatant = _make("PatC")
	attacker.equipped_passives = ["pattern_recognition"]
	var goblin: Combatant = _make("Goblin")
	goblin.set_meta("monster_type", "goblin")  # no is_boss
	var out: int = bm._apply_pattern_recognition_bonus(attacker, goblin, 100)
	assert_eq(out, 100,
		"non-boss target must not get the bonus even if monster_type is in memory")
	gs.previously_fought_bosses = prior_bosses
