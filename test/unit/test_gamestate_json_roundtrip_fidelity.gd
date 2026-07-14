extends GutTest

## Sibling of test_combatant_json_roundtrip_fidelity (2026-07-03):
## GameState is the other half of the save file — quests, flags, gold,
## corruption, splits. Same ratchet: to_dict → JSON string → from_dict
## → to_dict must be identical, so field drift fails by name instead of
## rotting in a hand-maintained key list.

## timestamp is stamped at write time by design; rebalance_daemon is
## instantiated with defaults on load (a bare test instance has none).
const VOLATILE := ["timestamp", "rebalance_daemon"]

## Tick 112/150 design: these MERGE loaded keys onto defaults rather
## than replace — compare as "every written key survives", not equality.
const MERGE_SEMANTICS := ["game_constants", "meta_features"]


func _populated_state(gs) -> void:
	gs.playtime_seconds = 4321.5
	gs.corruption_level = 0.25
	gs.macro_volatility = 0.1
	gs.party_gold = 777
	var pp: Array[Dictionary] = [{"name": "Hero", "job_id": "fighter", "job_level": 3.0}]
	gs.player_party = pp
	gs.party_leader_index = 0
	gs.game_constants = {"quest_c3_auto_streak": 1.0}
	gs.corruption_effects = ["visual_glitch"] as Array[String]
	gs.current_world = 1
	gs.worlds_unlocked = 2
	gs.story_flags = {"cutscene_flag_rat_king_defeated": true}
	gs.current_save_name = "fidelity"
	gs.dash_always_on = true
	gs.activated_crystals = {"harmonia": true}
	gs.quests = {"world1_fools_spread": {"state": "active", "objective_index": 2.0}}
	gs.battles_won = 12
	var pfb: Array[String] = ["cave_rat_king"]
	gs.previously_fought_bosses = pfb
	gs.boss_splits = {"cave_rat_king": 61.5}
	gs.boss_personal_best = {"cave_rat_king": 44.25}


func test_to_dict_json_from_dict_to_dict_is_identity() -> void:
	var GS = load("res://src/meta/GameState.gd")
	var a = GS.new()
	autofree(a)
	_populated_state(a)
	var d1: Dictionary = a.to_dict()
	var parsed = JSON.parse_string(JSON.stringify(d1))
	assert_true(parsed is Dictionary, "roundtrip parse must yield a Dictionary")
	var b = GS.new()
	autofree(b)
	b.from_dict(parsed)
	var d2: Dictionary = b.to_dict()
	var diffs: Array = []
	for key in d1:
		if key in VOLATILE:
			continue
		if not d2.has(key):
			diffs.append("%s: dropped by from_dict/to_dict" % key)
		elif key in MERGE_SEMANTICS:
			for sub_key in d1[key]:
				if not d2[key].has(sub_key) or JSON.stringify(d2[key][sub_key]) != JSON.stringify(d1[key][sub_key]):
					diffs.append("%s.%s: %s → %s" % [key, sub_key, JSON.stringify(d1[key][sub_key]), JSON.stringify(d2[key].get(sub_key))])
		elif JSON.stringify(d2[key]) != JSON.stringify(d1[key]):
			diffs.append("%s: %s → %s" % [key, JSON.stringify(d1[key]).left(120), JSON.stringify(d2[key]).left(120)])
	for key in d2:
		if not d1.has(key) and key not in VOLATILE:
			diffs.append("%s: invented by roundtrip" % key)
	assert_eq(diffs.size(), 0,
		"GameState fields that did not survive save→load: %s" % str(diffs))
