extends GutTest

## tick 119 regression: the curator masterite ladder must consume
## the LLM intent's attack_weight bias. Closes the masterite intent
## series (warden tick 116, arbiter tick 117, tempo tick 118,
## curator now).
##
## Three rolls scale by curator_attack_bias:
## - curator_combo_chance (phase-3 drain+audit advance combo)
## - drain_chance (mana_drain)
## - cut_chance (resource_cut)
##
## dispel intentionally NOT scaled — it's gated on the player having
## buffs to dispel, not on a chance roll. Same rationale as tempo's
## haste exclusion.

const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _make_masterite_decision_body() -> String:
	var src := _read(BATTLE_MANAGER)
	var idx: int = src.find("func _make_masterite_decision")
	assert_gt(idx, -1, "_make_masterite_decision must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func _curator_arm() -> String:
	# Slice from curator marker to the fallback `# Fallback: basic attack`
	# (end of the match).
	var body := _make_masterite_decision_body()
	var curator_idx: int = body.find("\"curator\":")
	assert_gt(curator_idx, -1, "curator arm must exist")
	var fallback_idx: int = body.find("# Fallback: basic attack", curator_idx + 1)
	assert_gt(fallback_idx, -1, "fallback marker must follow curator (end of match)")
	return body.substr(curator_idx, fallback_idx - curator_idx)


func test_curator_reads_attack_weight_bias() -> void:
	var arm := _curator_arm()
	assert_true(arm.contains("var curator_attack_bias: float = float(llm_bias.get(\"attack_weight\", 1.0))"),
		"curator ladder must read llm_bias.attack_weight via safe default")


func test_curator_combo_chance_scaled_by_bias() -> void:
	var arm := _curator_arm()
	assert_true(arm.contains("var curator_combo_chance: float = clampf(0.45 * curator_attack_bias, 0.0, 1.0)"),
		"curator phase-3 combo chance must scale by attack_weight + clampf")


func test_curator_drain_chance_scaled_by_bias() -> void:
	var arm := _curator_arm()
	assert_true(arm.contains("var drain_chance = clampf([0.45, 0.6, 0.8][battle_phase - 1] * curator_attack_bias, 0.0, 1.0)"),
		"curator drain_chance must scale by attack_weight + clampf")


func test_curator_cut_chance_scaled_by_bias() -> void:
	var arm := _curator_arm()
	assert_true(arm.contains("var cut_chance = clampf([0.4, 0.55, 0.7][battle_phase - 1] * curator_attack_bias, 0.0, 1.0)"),
		"curator cut_chance must scale by attack_weight + clampf")


func test_curator_dispel_gate_not_biased() -> void:
	# Negative pin: dispel is gated on player having buffs, not on
	# a chance roll. Biasing it would be a no-op since the gate is
	# a binary state check.
	var arm := _curator_arm()
	var dispel_idx: int = arm.find("if buffed_targets.size() > 0")
	assert_gt(dispel_idx, -1, "dispel gate must exist")
	# The dispel return is right after. Slice that block.
	var return_idx: int = arm.find("masterite_dispel", dispel_idx)
	assert_gt(return_idx, -1, "dispel return must exist")
	# Search 200 chars around the gate for the bias var name.
	var gate_block: String = arm.substr(dispel_idx, return_idx - dispel_idx + 50)
	assert_false(gate_block.contains("curator_attack_bias"),
		"dispel gate must NOT scale by curator_attack_bias — it's a binary buff check")


func test_curator_attack_bias_var_scoped_to_curator_arm() -> void:
	var src := _read(BATTLE_MANAGER)
	var count: int = 0
	var pos: int = 0
	while true:
		var p: int = src.find("var curator_attack_bias", pos)
		if p == -1:
			break
		count += 1
		pos = p + 1
	assert_eq(count, 1,
		"curator_attack_bias must be declared EXACTLY ONCE — scoped to the curator arm")


func test_all_four_masterite_ladders_now_consume_bias() -> void:
	# Coverage assertion: closes the masterite intent bias series.
	# Every masterite ladder (warden / arbiter / tempo / curator) now
	# reads llm_bias in some form. Any future ladder regression that
	# drops the read fails this test.
	var body := _make_masterite_decision_body()
	# warden — iron_guard/endurance_test/crushing_blow biases
	assert_true(body.contains("llm_bias.get(\"iron_guard\", 1.0)"),
		"warden must keep iron_guard bias (tick 116-prior)")
	assert_true(body.contains("llm_bias.get(\"endurance_test\", 1.0)"),
		"warden must keep endurance_test bias (tick 116-prior)")
	assert_true(body.contains("llm_bias.get(\"crushing_blow\", 1.0)"),
		"warden must keep crushing_blow bias (tick 116-prior)")
	# arbiter — attack_weight bias (tick 117)
	assert_true(body.contains("var arb_attack_bias"),
		"arbiter must keep attack_weight bias (tick 117)")
	# tempo — attack_weight bias (tick 118)
	assert_true(body.contains("var tempo_attack_bias"),
		"tempo must keep attack_weight bias (tick 118)")
	# curator — attack_weight bias (this tick)
	assert_true(body.contains("var curator_attack_bias"),
		"curator must consume attack_weight bias (tick 119)")
