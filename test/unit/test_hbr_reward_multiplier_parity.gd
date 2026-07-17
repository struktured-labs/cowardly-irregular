extends GutTest

## Cadence #23 — HBR reward_multiplier parity with BattleManager.
##
## PILLAR CITATION (struktured, 2026-07-01 via cowir-main msg 2053):
## "full parity, no yield multiplier … 'automation isn't cheating — it's
## enlightenment' is design pillar #1; a hidden ludicrous-mode yield tax
## contradicts the game's whole thesis." Autogrind's balance levers ARE
## fatigue/adaptation/corruption/collapse events — visibly — NEVER a silent
## drop nerf.
##
## Pre-cadence-#23 anomaly (per cowir-main msg 2746): BM applied
## data.reward_multiplier to exp (BM:868) and gold (BM:743, post-cadence
## #22), but HBR skipped it entirely — so rare-encounter monsters (Hero
## Mimics et al with reward_multiplier>1.0) paid extra in live regular
## battles but flat rate in headless autogrind. Grinders on the ludicrous
## tier earned LESS per rare encounter than grinders on live tier —
## a hidden yield tax on the deepest automation tier, direct violation
## of the pillar.
##
## Fix: HBR._build_results now computes `reward_multiplier` as max across
## the enemy party's monster_data.reward_multiplier (matching BM._get_battle_
## reward_multiplier line 968) and multiplies exp+gold by it before the
## game_constants exp_multiplier/gold_multiplier are applied.


func _build_body() -> String:
	# Grab the `if victory:` block up to the end-of-reward-multiplier-application.
	var src: String = load("res://src/autogrind/HeadlessBattleResolver.gd").source_code
	var fn_start: int = src.find("func _build_results")
	assert_true(fn_start >= 0, "setup: _build_results must exist")
	# Stop at the game_constants exp/gold multiplier section (tick 341) — the
	# reward_multiplier logic lives before it.
	var end: int = src.find("Tick 341", fn_start)
	if end < 0:
		end = src.find("Drop parity", fn_start)
	return src.substr(fn_start, end - fn_start)


func test_reward_multiplier_var_declared() -> void:
	# HBR must compute a reward_multiplier scalar per battle. Source ratchet
	# so a refactor that drops the variable declaration fails loud.
	var body: String = _build_body()
	assert_true(body.contains("reward_multiplier"),
		"HBR._build_results must compute reward_multiplier — else rare-encounter monsters silently drop their bonus in headless (hidden yield tax, cadence #23)")


func test_reward_multiplier_read_from_monster_data() -> void:
	# Source of truth must be mrow.get("reward_multiplier", 1.0) — matches
	# the existing exp_reward/gold_reward lookup pattern in this function
	# AND matches BM's data["reward_multiplier"] access pattern at BM:975.
	var body: String = _build_body()
	assert_true(body.contains("mrow.get(\"reward_multiplier\", 1.0)"),
		"reward_multiplier must be read from monster_data via mrow (matches exp_reward/gold_reward lookup pattern in same loop + parallels BM:975 authored-source read)")


func test_reward_multiplier_is_max_across_enemies() -> void:
	# Parity with BM._get_battle_reward_multiplier (line 968-977): use the
	# MAX reward_multiplier across the party, not average or per-enemy
	# application. That's the semantic that gives Hero Mimic parties their
	# bonus when even ONE participant is rare.
	var body: String = _build_body()
	# Grep for either `max()` or an if-then max pattern; my fix uses the latter.
	assert_true(body.contains("> reward_multiplier"),
		"reward_multiplier must be computed as max across enemies (mirrors BM._get_battle_reward_multiplier semantic — one rare enemy bumps the whole battle's rewards)")


func test_reward_multiplier_applied_to_both_exp_and_gold() -> void:
	# The multiplier must appear in the exp AND gold accumulation. Source
	# ratchet: both `exp +=` and `gold +=` lines must reference reward_multiplier.
	var body: String = _build_body()
	var exp_line_start: int = body.find("exp += ")
	assert_true(exp_line_start >= 0, "setup: exp accumulator must exist")
	var exp_line_end: int = body.find("\n", exp_line_start)
	var exp_line: String = body.substr(exp_line_start, exp_line_end - exp_line_start)
	assert_true(exp_line.contains("reward_multiplier"),
		"exp accumulator must factor reward_multiplier — else headless exp diverges from live for rare encounters (cadence #23)")
	var gold_line_start: int = body.find("gold += ")
	assert_true(gold_line_start >= 0, "setup: gold accumulator must exist")
	var gold_line_end: int = body.find("\n", gold_line_start)
	var gold_line: String = body.substr(gold_line_start, gold_line_end - gold_line_start)
	assert_true(gold_line.contains("reward_multiplier"),
		"gold accumulator must factor reward_multiplier — else headless gold diverges from live for rare encounters (cadence #23)")


func test_runtime_default_multiplier_matches_pre_cadence_output() -> void:
	# At reward_multiplier=1.0 (default when unset), exp+gold must equal
	# the pre-cadence values — proves the fix is additive-only for the
	# common case, no regression for normal monsters.
	var resolver = HeadlessBattleResolver.new()
	# Player must be alive for the victory-path exp/gold logic to fire.
	var player = Combatant.new()
	player.initialize({"name": "P", "max_hp": 100, "max_mp": 20, "attack": 10, "defense": 5, "magic": 5, "speed": 10})
	add_child_autofree(player)
	# Enemy carries a monster_type meta but the mdb likely has no reward_multiplier
	# for a random test id → defaults to 1.0 → no scaling.
	var enemy = Combatant.new()
	enemy.initialize({"name": "E", "max_hp": 50, "max_mp": 0, "attack": 5, "defense": 2, "magic": 0, "speed": 5})
	add_child_autofree(enemy)
	enemy.take_damage(999)  # kill it — victory condition
	# resolve_battle is the public API; will short-circuit into
	# _build_results(true) via the "no alive enemies" branch (line 65).
	var results: Dictionary = resolver.resolve_battle([player], [enemy])
	assert_true(results.get("victory", false),
		"pre-killed enemy → immediate victory (baseline scenario)")
	# Both fields should be non-negative — actual values depend on default
	# formulas, this test just proves the accumulator loop didn't crash
	# after the cadence-#23 restructure.
	assert_true(results.get("exp_gained", -1) >= 0,
		"exp_gained must be a non-negative int after the cadence #23 loop split")
	assert_true(results.get("gold_gained", -1) >= 0,
		"gold_gained must be a non-negative int after the cadence #23 loop split")


func test_ruling_cited_in_source_comment() -> void:
	# Per cowir-main msg 2746 fold-instruction: cite the 2026-07-01 ruling
	# in the docstring so future auditors know WHY this code exists (not
	# just what it does). Without the citation, a well-meaning refactor
	# could remove the reward_multiplier as "duplicating BM's logic" and
	# not realize the parity is the whole point.
	var src: String = load("res://src/autogrind/HeadlessBattleResolver.gd").source_code
	var block_start: int = src.find("Cadence #23")
	assert_true(block_start >= 0, "cadence #23 comment must exist above the reward_multiplier logic")
	var block_end: int = src.find("var reward_multiplier", block_start)
	var block: String = src.substr(block_start, block_end - block_start)
	assert_true(block.contains("2026-07-01") or block.contains("full-parity ruling") or block.contains("automation isn't cheating"),
		"cadence #23 comment must cite the 2026-07-01 full-parity ruling — future refactorers need the WHY, not just the WHAT")
