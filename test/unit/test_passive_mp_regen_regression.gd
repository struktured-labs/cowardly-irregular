extends GutTest

## tick 438: passives.json mp_recovery's meta_effects.mp_regen_percent
## now actually restores MP each round.
##
## Pre-fix the passive authored "Recover 5% MP at end of each turn"
## but no code path read meta_effects.mp_regen_percent. Players
## equipped the passive and got nothing.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String, max_mp: int = 100) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": 100, "max_mp": max_mp,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func test_helper_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("func _apply_passive_mp_regen"),
		"BattleManager must declare _apply_passive_mp_regen helper")
	# Pin the meta_effects.mp_regen_percent read.
	assert_true(src.contains("me.get(\"mp_regen_percent\", 0.0)"),
		"helper must read mp_regen_percent from passive meta_effects")


func test_helper_called_at_round_start() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _start_new_round")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_apply_passive_mp_regen(combatant)"),
		"_start_new_round must call _apply_passive_mp_regen on each alive combatant")


func test_helper_sums_across_passives() -> void:
	# Pin the accumulation pattern so a future stacked-passive build
	# can rely on the regen scaling.
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _apply_passive_mp_regen")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("total_pct += float"),
		"helper must SUM contributions across all equipped passives")
	# Floor at 1 MP so a small percent on a low max_mp doesn't round
	# to nothing.
	assert_true(body.contains("max(1, int(round(combatant.max_mp * total_pct)))"),
		"helper must floor regen at 1 MP when any regen is active")


func test_data_still_authors_mp_regen() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/passives.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("mp_recovery"))
	var me: Variant = data["mp_recovery"].get("meta_effects", {})
	assert_true(me is Dictionary)
	assert_gt(float(me.get("mp_regen_percent", 0.0)), 0.0,
		"mp_recovery must still author meta_effects.mp_regen_percent > 0")


func test_runtime_regen_restores_mp() -> void:
	# Equip mp_recovery on a combatant with 100 max_mp and 50 current.
	# Expect ~5 MP restored (5% of 100).
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null:
		pending("PassiveSystem autoload required")
		return
	if not ps.passives.has("mp_recovery"):
		pending("mp_recovery passive required")
		return
	var c: Combatant = _make("Mage", 100)
	c.current_mp = 50
	c.equipped_passives = ["mp_recovery"]
	bm._apply_passive_mp_regen(c)
	assert_gt(c.current_mp, 50,
		"mp_recovery must restore MP — pre-fix the meta_effect was silently dropped")


func test_runtime_no_passive_no_regen() -> void:
	# Regression guard: a combatant without the passive must NOT gain MP.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var c: Combatant = _make("Vanilla", 100)
	c.current_mp = 50
	c.equipped_passives = []
	bm._apply_passive_mp_regen(c)
	assert_eq(c.current_mp, 50,
		"vanilla combatant must NOT gain MP from the regen pass — fix must not silently buff baseline")
