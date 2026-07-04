extends GutTest

## Load-path half of the 2026-07-04 counter-leak fix. _apply_save_data
## set battles_won / previously_fought_bosses / boss_splits /
## boss_personal_best only `if save_data.has(...)`. GameState is a single
## autoload, so loading an OLD save (pre-tick-418/453/454, lacking those
## keys) after another game was loaded this session kept the PRIOR game's
## values — a cross-slot leak of the battle count (story gates) and boss
## memory (pattern_recognition damage bonus). Now absent keys reset to
## default (the loaded save is authoritative for its own state).

const GS := preload("res://src/meta/GameState.gd")


func test_old_save_missing_keys_resets_to_default() -> void:
	var gs = GS.new()
	autofree(gs)
	# Simulate a prior-loaded game's residue on the shared autoload.
	gs.battles_won = 99
	gs.previously_fought_bosses = ["pyrroth", "glacius"] as Array[String]
	gs.boss_splits = {"pyrroth": 120.0}
	gs.boss_personal_best = {"pyrroth": 90.0}
	# Load an OLD save that predates all four fields.
	gs.from_dict({"player_party": []})
	assert_eq(gs.battles_won, 0, "absent battles_won must default to 0, not inherit the prior game's count")
	assert_eq(gs.previously_fought_bosses.size(), 0,
		"absent boss memory must clear, not leak the pattern bonus across slots")
	assert_eq(gs.boss_splits.size(), 0, "absent boss_splits must clear")
	assert_eq(gs.boss_personal_best.size(), 0, "absent boss_personal_best must clear (loaded save is authoritative)")


func test_modern_save_still_loads_its_values() -> void:
	var gs = GS.new()
	autofree(gs)
	gs.from_dict({
		"player_party": [],
		"battles_won": 12,
		"previously_fought_bosses": ["cave_rat_king"],
		"boss_splits": {"cave_rat_king": 61.0},
		"boss_personal_best": {"cave_rat_king": 44.0},
	})
	assert_eq(gs.battles_won, 12)
	assert_eq(gs.previously_fought_bosses, ["cave_rat_king"] as Array[String])
	assert_eq(gs.boss_splits, {"cave_rat_king": 61.0})
	assert_eq(gs.boss_personal_best, {"cave_rat_king": 44.0})
