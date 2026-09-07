extends GutTest

## tick 422: monsters.json special_behavior.phase_out is now read by
## the dodge checks. null_entity (W6 abstract) authors:
##   special_behavior: {phase_out: true, phase_out_chance: 0.2, ...}
##
## Pre-fix the flag was authored but no code path read it — players
## hit null_entity with 100% reliability instead of the intended 80%.
## The phase_out_description says "all actions targeting it this turn
## fail", so the check applies to physical AND magical paths.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_helper_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("func _monster_phase_out_check"),
		"BattleManager must declare _monster_phase_out_check helper")
	# Pin the special_behavior.phase_out read.
	assert_true(src.contains("sb.get(\"phase_out\", false)"),
		"helper must read special_behavior.phase_out")
	assert_true(src.contains("sb.get(\"phase_out_chance\", 0.2)"),
		"helper must read phase_out_chance with 0.2 default (matches data)")


func test_helper_used_in_physical_dodge() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _target_dodges_physical")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_monster_phase_out_check(target)"),
		"_target_dodges_physical must call _monster_phase_out_check")


func test_helper_used_in_magic_path() -> void:
	# The magic ability loop must also gate on phase_out — the
	# description says "all actions targeting it" so spells miss too.
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("phases out — %s's spell finds nothing"),
		"magic ability path must show 'phases out — spell finds nothing' when triggered")


func test_data_still_authors_phase_out() -> void:
	# Sanity: null_entity must still author the flag.
	var raw: String = FileAccess.get_file_as_string("res://data/monsters.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("null_entity"))
	var sb: Variant = data["null_entity"].get("special_behavior", {})
	assert_true(sb is Dictionary)
	assert_true(bool(sb.get("phase_out", false)),
		"null_entity must still author special_behavior.phase_out=true")
	assert_gt(float(sb.get("phase_out_chance", 0.0)), 0.0,
		"null_entity must still author a positive phase_out_chance")


func test_helper_returns_false_for_non_phase_monster() -> void:
	# Sanity: helper returns false when monster doesn't have the flag.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var c_script: GDScript = load("res://src/battle/Combatant.gd")
	var target: Combatant = c_script.new()
	target.initialize({"name": "Slime", "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(target)
	target.set_meta("monster_type", "slime")  # slime has no phase_out
	# Run 30 trials — should never return true.
	var phased_count: int = 0
	for i in range(30):
		if bm._monster_phase_out_check(target):
			phased_count += 1
	assert_eq(phased_count, 0,
		"phase_out check on a non-phasing monster must return false on every roll")


func test_helper_phases_null_entity_at_authored_rate() -> void:
	# Sanity: helper actually fires for null_entity. Phase chance is
	# small (~0.2) so we run many trials and verify SOME of them
	# returned true.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	if not (EncounterSystem and EncounterSystem.monster_database.has("null_entity")):
		pending("null_entity must be in EncounterSystem.monster_database")
		return
	var c_script: GDScript = load("res://src/battle/Combatant.gd")
	var target: Combatant = c_script.new()
	target.initialize({"name": "Null Entity", "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(target)
	target.set_meta("monster_type", "null_entity")
	var phased_count: int = 0
	for i in range(300):
		if bm._monster_phase_out_check(target):
			phased_count += 1
	# With chance=0.2 and 300 trials, expected ~60. Test loose bounds.
	assert_gt(phased_count, 20,
		"null_entity phase_out_check must fire occasionally — got %d/300 phases" % phased_count)
	assert_lt(phased_count, 200,
		"null_entity phase_out_check must NOT fire always — got %d/300 phases" % phased_count)
