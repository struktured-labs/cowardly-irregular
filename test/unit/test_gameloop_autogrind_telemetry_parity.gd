extends GutTest

## Cadence #24 — arc closer per cowir-main msg 2751.
##
## GameLoop._on_autogrind_battle_ended used to synthesize exp/gold telemetry
## from stat formulas (max_hp*0.5 + attack*2 for exp, max_hp*0.3 + defense
## for gold). That number IS what shows on the autogrind dashboard live —
## struktured watches it during grinds. It DRIFTED from actually-granted
## rewards (BM applies base_exp * reward_multiplier * one_shot_exp_bonus *
## autobattle_exp_bonus * exp_multiplier per BM:868, using authored
## monster_data.exp_reward). Dashboard ran HIGH vs actual — "free money"
## impression — trust-killer for the automation pillar per struktured's
## 2026-07-01 no-hidden-yield-tax ruling (msg 2053 relay).
##
## Fix: read authored rewards from BattleManager.get_battle_results()
## _battle_results dict (contains base_exp, total_gold, total_multiplier
## already populated at BM:921). Parity-by-construction — the SAME numbers
## BM used to grant the exp/gold via gain_job_exp + add_gold.


func _get_handler_body() -> String:
	var src: String = load("res://src/GameLoop.gd").source_code
	var start: int = src.find("func _on_autogrind_battle_ended")
	assert_true(start >= 0, "setup: _on_autogrind_battle_ended must exist")
	var end: int = src.find("\nfunc ", start + 20)
	if end < 0:
		end = src.length()
	return src.substr(start, end - start)


func test_reads_from_battle_results_not_stat_formula() -> void:
	# The primary path must call BattleManager.get_battle_results() —
	# stat-derived is now only the FALLBACK for mock-BM scenarios.
	var body: String = _get_handler_body()
	assert_true(body.contains("BattleManager.get_battle_results()"),
		"handler must read from BattleManager.get_battle_results() as its primary source — else the dashboard telemetry keeps drifting from actual grants (cadence #24)")


func test_uses_base_exp_field() -> void:
	# base_exp is the sum of authored monsters_db.exp_reward from BM:839.
	# Source ratchet on the specific field read so a rename on BM's side
	# fails loud in this file.
	var body: String = _get_handler_body()
	assert_true(body.contains("battle_results.get(\"base_exp\"") or body.contains("get(\"base_exp\""),
		"handler must read the authored `base_exp` field from _battle_results — the direct source of what BM granted (cadence #24)")


func test_uses_total_multiplier_field() -> void:
	# total_multiplier = reward_multiplier * one_shot_exp_bonus * autobattle_exp_bonus
	# (BM:928). The dashboard exp must factor these bonuses to match what
	# BM actually granted; without them, one-shots and fast autobattles look
	# under-rewarded on the display.
	var body: String = _get_handler_body()
	assert_true(body.contains("battle_results.get(\"total_multiplier\"") or body.contains("get(\"total_multiplier\""),
		"handler must factor total_multiplier (reward*one_shot*autobattle) — else one-shots + fast autobattles under-report on the dashboard (cadence #24)")


func test_uses_total_gold_field() -> void:
	# total_gold at BM:925 already has one_shot_gold_bonus * reward_multiplier
	# * gold_multiplier applied (BM:743, post-cadence #22). Reading as-is
	# is the correct parity — re-multiplying would double-apply gold_multiplier.
	var body: String = _get_handler_body()
	assert_true(body.contains("battle_results.get(\"total_gold\"") or body.contains("get(\"total_gold\""),
		"handler must read total_gold as-is from _battle_results — it already includes all gold multipliers (cadence #24)")


func test_no_double_apply_gold_multiplier_in_primary_path() -> void:
	# Regression guard: the primary (authored) path must NOT multiply the
	# authored total_gold by gold_multiplier — BM already did that.
	# Fallback path (mock BM) is allowed to. We check the ACTUAL gold-
	# assignment line, not comments — strict pin on the exact expression.
	var body: String = _get_handler_body()
	# The primary path assigns items_gained["gold"] from total_gold directly,
	# with NO additional multiplier operations after the .get() call.
	var target_line: String = 'items_gained["gold"] = int(battle_results.get("total_gold", 0))'
	assert_true(body.contains(target_line),
		"primary authored-rewards path must assign items_gained['gold'] = int(battle_results.get('total_gold', 0)) VERBATIM — no post-multiplication, else gold_multiplier double-applies (cadence #24 double-apply guard)")


func test_fallback_stat_formula_preserved() -> void:
	# The stat-derived fallback must remain for the mock-BM / instance-test
	# case where _battle_results is empty. Guards against a refactor that
	# removes the else branch and breaks tests that don't populate BM.
	var body: String = _get_handler_body()
	assert_true(body.contains("enemy.max_hp * 0.5 + enemy.attack * 2"),
		"fallback stat-derived exp formula must remain for the empty-battle-results case (mock-BM/instance-tests) — cadence #24 fallback preservation")
	assert_true(body.contains("enemy.max_hp * 0.3 + enemy.defense"),
		"fallback stat-derived gold formula must remain — same reason as exp fallback")


func test_exp_multiplier_still_applied_on_primary_path() -> void:
	# The primary path must still apply exp_multiplier — BM stores base_exp
	# BEFORE exp_multiplier (BM:868 applies it separately), so the dashboard
	# must multiply on top to reach the actual granted number.
	var body: String = _get_handler_body()
	var primary_start: int = body.find("if not battle_results.is_empty()")
	var else_pos: int = body.find("\n\t\telse:", primary_start)
	var primary: String = body.substr(primary_start, else_pos - primary_start)
	assert_true(primary.contains("exp_mult"),
		"primary path must still multiply by exp_mult — BM stores base_exp pre-exp_multiplier, so the dashboard needs to reach the same total BM.gain_job_exp'd (cadence #24)")


func test_ruling_cited_in_source_comment() -> void:
	# The 2026-07-01 pillar citation ("automation isn't cheating") must live
	# in the handler comment so future refactorers know WHY authored-rewards
	# parity matters, not just what the fix does.
	var body: String = _get_handler_body()
	assert_true(body.contains("2026-07-01") or body.contains("automation pillar") or body.contains("no-hidden-yield-tax") or body.contains("trust-killer"),
		"handler comment must cite the pillar (2026-07-01 ruling or 'automation pillar' / 'trust-killer') — future refactorers need the WHY not just the WHAT (cadence #24)")
