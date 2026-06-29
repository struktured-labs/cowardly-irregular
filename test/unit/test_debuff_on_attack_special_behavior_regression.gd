extends GutTest

## tick 424: empty_set.special_behavior.debuff_on_attack now applies
## a random debuff from the authored pool on every basic attack.
##
## Pre-fix empty_set (W6 abstract) authored:
##   special_behavior: {
##     debuff_on_attack: true,
##     debuff_types: [attack_down, defense_down, magic_down, speed_down]
##   }
##
## But no code read these fields — empty_set's attacks dealt regular
## damage with no debuff side-effect, defeating the "erases what you
## have" design.

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
	assert_true(src.contains("func _maybe_apply_debuff_on_attack"),
		"BattleManager must declare _maybe_apply_debuff_on_attack helper")
	assert_true(src.contains("sb.get(\"debuff_on_attack\", false)"),
		"helper must read special_behavior.debuff_on_attack")
	assert_true(src.contains("sb.get(\"debuff_types\""),
		"helper must read debuff_types pool")


func test_debuff_map_covers_all_pool_types() -> void:
	# Pin that the map handles all 4 debuff types from the
	# empty_set authored pool — adding a new debuff_type to the
	# data without extending the map would silently skip it.
	var src := _read(BATTLE_MANAGER_PATH)
	for tag in ["attack_down", "defense_down", "magic_down", "speed_down"]:
		assert_true(src.contains("\"%s\":" % tag),
			"_DEBUFF_ON_ATTACK_MAP must include '%s'" % tag)


func test_helper_wired_into_attack_path() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("_maybe_apply_debuff_on_attack(attacker, actual_target)"),
		"basic-attack damage path must call _maybe_apply_debuff_on_attack")


func test_data_still_authors_empty_set_debuff_pool() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/monsters.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("empty_set"))
	var sb: Variant = data["empty_set"].get("special_behavior", {})
	assert_true(sb is Dictionary)
	assert_true(bool(sb.get("debuff_on_attack", false)),
		"empty_set must still author debuff_on_attack=true")
	var pool: Variant = sb.get("debuff_types", [])
	assert_true(pool is Array)
	assert_gt((pool as Array).size(), 0,
		"empty_set debuff_types pool must not be empty")


func test_runtime_helper_applies_a_debuff() -> void:
	# Cast multiple times to defeat randomness — at least one of the
	# four debuff types should land within ~10 trials.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	if not (EncounterSystem and EncounterSystem.monster_database.has("empty_set")):
		pending("empty_set must be in EncounterSystem.monster_database")
		return
	var attacker: Combatant = _make_target("Empty Set", "empty_set")
	var target: Combatant = _make_target("Hero", "")
	# Run multiple trials.
	for _i in range(20):
		bm._maybe_apply_debuff_on_attack(attacker, target)
	assert_gt(target.active_debuffs.size(), 0,
		"empty_set's _maybe_apply_debuff_on_attack must apply at least one debuff over 20 trials")
	# All applied debuffs should be "Erased" variants.
	for d in target.active_debuffs:
		var effect: String = str(d.get("effect", ""))
		assert_true(effect.contains("Erased"),
			"applied debuff must use an 'Erased' label — got '%s'" % effect)


func test_runtime_helper_skips_non_empty_set() -> void:
	# Sanity: a regular monster (no debuff_on_attack flag) must NOT
	# apply debuffs to the target.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var attacker: Combatant = _make_target("Slime", "slime")
	var target: Combatant = _make_target("Hero", "")
	bm._maybe_apply_debuff_on_attack(attacker, target)
	assert_eq(target.active_debuffs.size(), 0,
		"normal monster must NOT apply debuffs on attack — fix must not buff baseline")
