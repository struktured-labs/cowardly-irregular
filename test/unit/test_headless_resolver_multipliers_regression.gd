extends GutTest

## tick 341: HeadlessBattleResolver._build_results now applies
## game_constants["exp_multiplier"] and ["gold_multiplier"] so
## Scriptweaver / RebalanceDaemon nudges affect the headless
## autogrind path too.
##
## Pre-fix _build_results returned raw enemy-stat sums:
##   exp += int(enemy.max_hp * 0.5 + enemy.attack * 2)
##   gold += int(enemy.max_hp * 0.3 + enemy.defense)
##
## AutogrindSystem.on_battle_victory consumed exp directly via
## gain_job_exp without re-applying the multiplier, so a Scriptweaver
## knob set to 2.0 had ZERO effect on headless autogrind. Same gap
## as tick 340 (live autogrind path) but on the headless side.
##
## Parallel fix: clampf([0.1, 10.0]) safe band, applied AFTER the
## per-enemy sum so the multiplier doesn't compound per enemy.

const RESOLVER_PATH := "res://src/autogrind/HeadlessBattleResolver.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: both multipliers applied ────────────────────────────

func test_exp_and_gold_multipliers_applied() -> void:
	var src := _read(RESOLVER_PATH)
	var fn_idx: int = src.find("func _build_results")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("exp_multiplier"),
		"_build_results must reference exp_multiplier")
	assert_true(body.contains("gold_multiplier"),
		"_build_results must reference gold_multiplier")
	assert_true(body.contains("exp = int(exp * exp_mult)"),
		"must multiply exp by the read value")
	assert_true(body.contains("gold = int(gold * gold_mult)"),
		"must multiply gold by the read value")


# ── Source pin: defensive clampf pattern ────────────────────────────

func test_defensive_clampf_pattern() -> void:
	var src := _read(RESOLVER_PATH)
	var fn_idx: int = src.find("func _build_results")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# Two clampf calls (one per multiplier).
	var clampf_count: int = body.count("clampf(")
	assert_gte(clampf_count, 2,
		"must defensively clampf both multipliers. Found: %d" % clampf_count)
	assert_true(body.contains("0.1, 10.0"),
		"must use the same [0.1, 10.0] safe band as BattleManager")


# ── Source pin: multiplier applied AFTER the loop ───────────────────

func test_multiplier_applied_after_loop() -> void:
	var src := _read(RESOLVER_PATH)
	var fn_idx: int = src.find("func _build_results")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)

	var loop_idx: int = body.find("for enemy in _enemy_party:")
	assert_gt(loop_idx, -1)
	var mult_idx: int = body.find("exp = int(exp * exp_mult)")
	assert_gt(mult_idx, -1)
	assert_lt(loop_idx, mult_idx,
		"multiplier must be applied AFTER the enemy loop — else it compounds per enemy")


# ── Source pin: GameState resolved via scene tree (resolver is RefCounted) ─

func test_resolver_uses_scene_tree_lookup() -> void:
	# HeadlessBattleResolver extends RefCounted (not Node), so it can't
	# do `GameState.x` directly. It must resolve via Engine.get_main_loop().
	var src := _read(RESOLVER_PATH)
	var fn_idx: int = src.find("func _build_results")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("Engine.get_main_loop()") or body.contains("tree.root.get_node_or_null(\"GameState\")"),
		"must resolve GameState via scene tree lookup (resolver is RefCounted, no direct autoload access)")
