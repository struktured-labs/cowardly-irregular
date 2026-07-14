extends GutTest

## tick 452: boss_insight passive's meta_effects.show_boss_hp /
## show_boss_weakness now actually surface intel at battle start.
##
## Pre-fix passives.json authored:
##   boss_insight: {meta_effects: {show_boss_hp: true,
##                                  show_boss_weakness: true,
##                                  show_boss_intent: true}}
##   description: "See boss HP, weaknesses, and next action"
## but no code path read any of the three flags. Players equipped
## Boss Insight and got no extra intel — the whole passive was
## decoration. (show_boss_intent partially overlaps with the
## time_sense preview wired in tick 451; HP+weakness here is the
## complementary high-leverage half.)

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String, max_hp: int = 100) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": max_hp, "max_mp": 50,
		"attack": 10, "defense": 5, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func test_flags_helper_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("func _party_boss_insight_flags"),
		"BattleManager must declare _party_boss_insight_flags helper")
	for key in ["show_boss_hp", "show_boss_weakness", "show_boss_intent"]:
		assert_true(src.contains("\"" + key + "\""),
			"helper must scan for " + key)


func test_emit_helper_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("func _maybe_emit_boss_insight"),
		"BattleManager must declare _maybe_emit_boss_insight helper")
	assert_true(src.contains("[Boss Insight]"),
		"emit must badge the line with [Boss Insight]")


func test_battle_start_calls_emit() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# Find the battle_started.emit (single occurrence in start_battle).
	var idx: int = src.find("battle_started.emit()")
	assert_gt(idx, -1)
	var window: String = src.substr(idx, 700)
	assert_true(window.contains("_maybe_emit_boss_insight()"),
		"_maybe_emit_boss_insight must be called right after battle_started.emit")


func test_emit_skips_non_bosses() -> void:
	# Pin the is_boss / is_miniboss gate so a random goblin doesn't
	# spam the player with Boss Insight intel.
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _maybe_emit_boss_insight")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("is_boss"),
		"_maybe_emit_boss_insight must gate on the is_boss / is_miniboss meta")


func test_flag_union_semantics() -> void:
	# Two party members each with one half of the passive should
	# combine: a member with show_boss_hp and another with show_boss
	# _weakness should both surface in one line.
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _party_boss_insight_flags")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# OR-union pattern: write true when bool(me.get(key)) is true,
	# don't overwrite from a later false.
	assert_true(body.contains("if bool(me.get(key, false)):") and body.contains("result[key] = true"),
		"helper must do OR-union (set true on hit, never clear)")


func test_data_still_authors_flags() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/passives.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("boss_insight"))
	var me: Variant = data["boss_insight"].get("meta_effects", {})
	assert_true(me is Dictionary)
	assert_true(bool(me.get("show_boss_hp", false)))
	assert_true(bool(me.get("show_boss_weakness", false)))
	assert_true(bool(me.get("show_boss_intent", false)))


func test_runtime_no_passive_empty_flags() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var hero: Combatant = _make("Hero")
	hero.equipped_passives = []
	var prior_party: Array = bm.player_party.duplicate()
	var party: Array[Combatant] = [hero]
	bm.player_party = party
	var flags: Dictionary = bm._party_boss_insight_flags()
	assert_true(flags.is_empty(),
		"vanilla party must produce empty flags dict — no silent baseline")
	var restore: Array[Combatant] = []
	for c in prior_party:
		if c is Combatant:
			restore.append(c)
	bm.player_party = restore


func test_runtime_with_passive_returns_flags() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null or not ps.passives.has("boss_insight"):
		pending("boss_insight passive required")
		return
	var hero: Combatant = _make("Inspector")
	hero.equipped_passives = ["boss_insight"]
	var prior_party: Array = bm.player_party.duplicate()
	var party: Array[Combatant] = [hero]
	bm.player_party = party
	var flags: Dictionary = bm._party_boss_insight_flags()
	assert_true(bool(flags.get("show_boss_hp", false)),
		"boss_insight-equipped party must surface show_boss_hp")
	assert_true(bool(flags.get("show_boss_weakness", false)),
		"boss_insight-equipped party must surface show_boss_weakness")
	var restore: Array[Combatant] = []
	for c in prior_party:
		if c is Combatant:
			restore.append(c)
	bm.player_party = restore
