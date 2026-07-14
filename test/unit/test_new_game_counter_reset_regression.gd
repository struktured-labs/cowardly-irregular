extends GutTest

## Leak fix 2026-07-04 (same class as the 2026-04-30 story-flag and
## 2026-07-02 quest/crystal leaks): reset_game_state didn't clear four
## persisted fields, so a second New Game inherited the prior run's:
##  - battles_won → skews CutsceneDirector's "battles >= N" gates
##  - previously_fought_bosses → fresh party gets the pattern_recognition
##    damage bonus vs bosses it never fought
##  - boss_splits → shows last-run defeat times until re-killed
##  - rebalance_daemon pending/applied → inherits prior balance nudges
## boss_personal_best is DELIBERATELY cross-run (a PB survives New Game).

const GS := preload("res://src/meta/GameState.gd")
const DAEMON := preload("res://src/llm/RebalanceDaemon.gd")


func _seeded_state():
	var gs = GS.new()
	autofree(gs)
	gs.battles_won = 42
	gs.previously_fought_bosses = ["cave_rat_king", "pyrroth"] as Array[String]
	gs.boss_splits = {"cave_rat_king": 61.5}
	gs.boss_personal_best = {"cave_rat_king": 44.0}
	return gs


func test_new_game_clears_battle_count_and_boss_memory() -> void:
	var gs = _seeded_state()
	gs.reset_game_state()
	assert_eq(gs.battles_won, 0, "battles_won must reset — it gates story cutscenes")
	assert_eq(gs.previously_fought_bosses.size(), 0,
		"previously_fought_bosses must clear — else the fresh party gets the pattern bonus vs unfought bosses")
	assert_eq(gs.boss_splits.size(), 0, "boss_splits (run-specific defeat times) must clear")


func test_new_game_preserves_personal_bests() -> void:
	var gs = _seeded_state()
	gs.reset_game_state()
	assert_eq(gs.boss_personal_best, {"cave_rat_king": 44.0},
		"boss_personal_best is cross-run by design — a PB must SURVIVE New Game")


func test_new_game_clears_rebalance_daemon_history() -> void:
	var gs = _seeded_state()
	gs.rebalance_daemon = DAEMON.new()
	gs.rebalance_daemon.pending.append({"proposal": "x"})
	gs.rebalance_daemon.applied.append({"proposal": "y"})
	gs.reset_game_state()
	assert_eq(gs.rebalance_daemon.pending.size(), 0, "daemon pending must clear on New Game")
	assert_eq(gs.rebalance_daemon.applied.size(), 0, "daemon applied must clear on New Game")


func test_null_daemon_reset_does_not_crash() -> void:
	var gs = GS.new()
	autofree(gs)
	gs.rebalance_daemon = null
	gs.reset_game_state()  # must not crash on the null-daemon guard
	assert_null(gs.rebalance_daemon)
