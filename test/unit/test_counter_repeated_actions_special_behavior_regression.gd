extends GutTest

## tick 427: optimization_itself.special_behavior.counter_repeated_actions
## now actually reduces damage when the same ability is used twice
## in a row against the same target.
##
## Pre-fix monsters.json authored the flag + counter_description but
## no code path read them — repeating an ability did normal damage.
##
## Helper checks the target's monster flag + per-target meta tracking
## of "_last_ability_against". On match, returns 50% damage; always
## updates the meta so the next call sees the current ability as the
## "previous".

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
	assert_true(src.contains("func _apply_counter_repeated_damage_mod"),
		"BattleManager must declare _apply_counter_repeated_damage_mod helper")
	assert_true(src.contains("sb.get(\"counter_repeated_actions\", false)"),
		"helper must read special_behavior.counter_repeated_actions")


func test_helper_wired_into_both_ability_paths() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# Both physical and magic ability paths call the helper.
	var occurrences: int = 0
	var idx: int = 0
	while true:
		idx = src.find("_apply_counter_repeated_damage_mod(target, ability.get", idx)
		if idx < 0:
			break
		occurrences += 1
		idx += 1
	assert_eq(occurrences, 2,
		"_apply_counter_repeated_damage_mod must be called from BOTH physical and magic ability paths (got %d)" % occurrences)


func test_data_still_authors_counter() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/monsters.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("optimization_itself"))
	var sb: Variant = data["optimization_itself"].get("special_behavior", {})
	assert_true(sb is Dictionary)
	assert_true(bool(sb.get("counter_repeated_actions", false)),
		"optimization_itself must still author counter_repeated_actions=true")


func test_first_cast_full_damage() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	if not (EncounterSystem and EncounterSystem.monster_database.has("optimization_itself")):
		pending("optimization_itself must be in EncounterSystem.monster_database")
		return
	var target: Combatant = _make("Optimization", "optimization_itself")
	# First cast — no prior — should return damage unchanged.
	var got: int = bm._apply_counter_repeated_damage_mod(target, "fire", 100)
	assert_eq(got, 100,
		"first cast must take full damage — no prior ability to match against")


func test_second_cast_same_ability_reduced() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	if not (EncounterSystem and EncounterSystem.monster_database.has("optimization_itself")):
		pending("optimization_itself must be in EncounterSystem.monster_database")
		return
	var target: Combatant = _make("Optimization", "optimization_itself")
	bm._apply_counter_repeated_damage_mod(target, "fire", 100)  # arm
	var got: int = bm._apply_counter_repeated_damage_mod(target, "fire", 100)  # repeat
	assert_lt(got, 100,
		"repeated cast of same ability must reduce damage — pre-fix flag was silent")
	# Conservative 50% reduction per the helper.
	assert_eq(got, 50,
		"repeated cast must yield 50% damage")


func test_different_ability_full_damage() -> void:
	# Switching abilities resets the adaptation.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	if not (EncounterSystem and EncounterSystem.monster_database.has("optimization_itself")):
		pending("optimization_itself must be in EncounterSystem.monster_database")
		return
	var target: Combatant = _make("Optimization", "optimization_itself")
	bm._apply_counter_repeated_damage_mod(target, "fire", 100)
	var got: int = bm._apply_counter_repeated_damage_mod(target, "ice", 100)
	assert_eq(got, 100,
		"different ability must NOT trigger adaptation — full damage")


func test_non_flagged_monster_unaffected() -> void:
	# A normal monster doesn't adapt — both casts take full damage.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var target: Combatant = _make("Slime", "slime")
	bm._apply_counter_repeated_damage_mod(target, "fire", 100)
	var got: int = bm._apply_counter_repeated_damage_mod(target, "fire", 100)
	assert_eq(got, 100,
		"non-flagged monster must NOT reduce damage on repeat")
