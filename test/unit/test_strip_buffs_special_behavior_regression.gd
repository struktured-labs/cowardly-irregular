extends GutTest

## tick 426: optimization_itself.special_behavior.strip_buffs now
## actually removes party buffs each round.
##
## monsters.json authored:
##   special_behavior: {
##     strip_buffs: true,
##     strip_buffs_per_turn: 1,
##     strip_description: "...removes one random party member's buffs each turn"
##   }
##
## Pre-fix the flags were authored but no code path read them — the
## "buffs are unnecessary overhead to be eliminated" gimmick was
## pure flavor.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make_combatant(name_str: String, monster_type: String = "") -> Combatant:
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
	assert_true(src.contains("func _apply_strip_buffs_on_round_start"),
		"BattleManager must declare _apply_strip_buffs_on_round_start helper")
	assert_true(src.contains("sb.get(\"strip_buffs\", false)"),
		"helper must read special_behavior.strip_buffs")
	assert_true(src.contains("sb.get(\"strip_buffs_per_turn\", 1)"),
		"helper must read strip_buffs_per_turn with default 1")


func test_helper_wired_into_round_start() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _start_new_round")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_apply_strip_buffs_on_round_start()"),
		"_start_new_round must call _apply_strip_buffs_on_round_start")


func test_data_still_authors_strip_buffs() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/monsters.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("optimization_itself"))
	var sb: Variant = data["optimization_itself"].get("special_behavior", {})
	assert_true(sb is Dictionary)
	assert_true(bool(sb.get("strip_buffs", false)),
		"optimization_itself must still author strip_buffs=true")


func test_runtime_strips_one_buff() -> void:
	# End-to-end: set up a battle with optimization_itself as enemy
	# and a buffed party member. Call the helper directly (more
	# reliable than triggering through start_battle round flow).
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	if not (EncounterSystem and EncounterSystem.monster_database.has("optimization_itself")):
		pending("optimization_itself must be in EncounterSystem.monster_database")
		return
	var hero: Combatant = _make_combatant("Hero")
	hero.add_buff("Power Up", "attack", 1.5, 3)
	assert_eq(hero.active_buffs.size(), 1)
	var optimizer: Combatant = _make_combatant("Optimization", "optimization_itself")
	# Inject directly into BattleManager state (bypass start_battle's
	# full flow which is hard to fixture for a unit test).
	var typed_player: Array[Combatant] = [hero]
	var typed_enemy: Array[Combatant] = [optimizer]
	bm.player_party = typed_player
	bm.enemy_party = typed_enemy
	bm._apply_strip_buffs_on_round_start()
	assert_eq(hero.active_buffs.size(), 0,
		"hero's buff must be stripped after _apply_strip_buffs_on_round_start fires")


func test_runtime_skips_non_optimization_enemy() -> void:
	# Regression guard: a normal monster must NOT strip party buffs.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var hero: Combatant = _make_combatant("Hero")
	hero.add_buff("Power Up", "attack", 1.5, 3)
	var slime: Combatant = _make_combatant("Slime", "slime")
	var typed_player: Array[Combatant] = [hero]
	var typed_enemy: Array[Combatant] = [slime]
	bm.player_party = typed_player
	bm.enemy_party = typed_enemy
	bm._apply_strip_buffs_on_round_start()
	assert_eq(hero.active_buffs.size(), 1,
		"normal monster (no strip_buffs flag) must NOT remove buffs")


func test_runtime_skips_when_no_party_buffs() -> void:
	# Sanity: empty buff pool is a clean no-op (no crash).
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	if not (EncounterSystem and EncounterSystem.monster_database.has("optimization_itself")):
		pending("optimization_itself must be in EncounterSystem.monster_database")
		return
	var hero: Combatant = _make_combatant("Hero")
	# No buffs.
	var optimizer: Combatant = _make_combatant("Optimization", "optimization_itself")
	var typed_player: Array[Combatant] = [hero]
	var typed_enemy: Array[Combatant] = [optimizer]
	bm.player_party = typed_player
	bm.enemy_party = typed_enemy
	bm._apply_strip_buffs_on_round_start()  # must not crash
	assert_eq(hero.active_buffs.size(), 0,
		"empty buff pool is a clean no-op — fix must not crash on empty input")
