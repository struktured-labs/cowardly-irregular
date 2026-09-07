extends GutTest

## tick 109 regression: GameState.game_constants["exp_multiplier"]
## must be consumed by BattleManager when awarding EXP. Pre-fix, the
## value was set + persisted via save/load AND modified by the
## RebalanceDaemon (one of its 3 ALLOWED_CONSTANTS), but NO combat
## code read it. A daemon proposal to nudge XP from 1.0 to 1.10 went
## through every layer (proposed → applied → audit log → save)
## producing zero gameplay change. The daemon's primary XP knob was
## entirely cosmetic.

const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_battle_manager_reads_exp_multiplier_from_game_constants() -> void:
	# Pin the read site.
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("GameState.game_constants.get(\"exp_multiplier\", 1.0)"),
		"BattleManager must read game_constants['exp_multiplier'] when awarding EXP")


func test_exp_multiplier_factors_into_exp_gained_formula() -> void:
	# Pin: the multiplier is in the actual exp_gained computation,
	# not just read and ignored.
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("base_exp * reward_multiplier * one_shot_exp_bonus * autobattle_exp_bonus * exp_multiplier"),
		"exp_gained formula must include exp_multiplier — otherwise the read is dead")


func test_exp_multiplier_clamped_defensively() -> void:
	# Defensive: clamp into a sane band so debug paths or post-load
	# corruption can't blow up the EXP economy. Daemon's own
	# SAFE_DELTA gates keep it tighter; this is belt + suspenders.
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("clampf("),
		"exp_multiplier must be clampf'd before use — defensive against extreme values")
	assert_true(src.contains("0.1, 10.0"),
		"exp_multiplier clamp must use the 0.1..10.0 band — wide enough for daemon nudges, narrow enough to prevent runaway")


func test_default_multiplier_is_one() -> void:
	# Vanilla play (daemon off, no Scriptweaver edits) must produce
	# unchanged EXP — multiplier defaults to 1.0.
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("var exp_multiplier: float = 1.0"),
		"exp_multiplier local must default to 1.0 — vanilla play unchanged")


func test_read_guarded_against_missing_gamestate() -> void:
	# Defensive: tests + autoload boot order can leave GameState
	# transiently null. The read must guard for that.
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("if GameState and \"game_constants\" in GameState:"),
		"exp_multiplier read must guard on GameState presence + game_constants field — keeps unit tests passing without a full autoload boot")


func test_game_state_still_initializes_exp_multiplier_to_one() -> void:
	# Sanity: GameState.game_constants's default for exp_multiplier
	# must still be 1.0. If the default ever drifts, vanilla play
	# changes silently.
	var src := _read("res://src/meta/GameState.gd")
	assert_true(src.contains("\"exp_multiplier\": 1.0"),
		"GameState.game_constants['exp_multiplier'] must default to 1.0 — daemon proposals scale from this baseline")


func test_rebalance_daemon_still_lists_exp_multiplier_as_allowed() -> void:
	# Sanity: the daemon's ALLOWED_CONSTANTS still includes
	# exp_multiplier. If it were removed, the daemon couldn't propose
	# changes — making the BattleManager read pointless.
	var src := _read("res://src/llm/RebalanceDaemon.gd")
	assert_true(src.contains("\"exp_multiplier\""),
		"RebalanceDaemon ALLOWED_CONSTANTS must still include exp_multiplier — it's the knob the BattleManager read consumes")
