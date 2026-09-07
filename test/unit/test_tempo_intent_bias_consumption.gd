extends GutTest

## tick 118 regression: the tempo masterite ladder must consume the
## LLM intent's attack_weight bias. Continuation of tick 117 (arbiter).
## Pre-fix, tempo ignored llm_bias entirely; an "aggress" or "turtle"
## intent on a tempo boss had ZERO effect on its strike/debuff rates.
##
## Three rolls scale by tempo_attack_bias:
## - tempo_combo_chance (phase-3 advance double-strike)
## - tax_chance (time_tax debuff)
## - slow_chance (slow debuff)
##
## haste self-buff intentionally NOT scaled — that's a setup move
## tempo always uses; biasing it would be a no-op since the gate is
## just "do you already have the buff".

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


func _tempo_arm() -> String:
	var body := _make_masterite_decision_body()
	var tempo_idx: int = body.find("\"tempo\":")
	assert_gt(tempo_idx, -1, "tempo arm must exist")
	var curator_idx: int = body.find("\"curator\":", tempo_idx + 1)
	assert_gt(curator_idx, -1, "curator arm must follow tempo")
	return body.substr(tempo_idx, curator_idx - tempo_idx)


func test_tempo_reads_attack_weight_bias() -> void:
	var arm := _tempo_arm()
	assert_true(arm.contains("var tempo_attack_bias: float = float(llm_bias.get(\"attack_weight\", 1.0))"),
		"tempo ladder must read llm_bias.attack_weight via safe default")


func test_tempo_combo_chance_scaled_by_bias() -> void:
	var arm := _tempo_arm()
	assert_true(arm.contains("var tempo_combo_chance: float = clampf(0.45 * tempo_attack_bias, 0.0, 1.0)"),
		"tempo phase-3 combo chance must scale by attack_weight + clampf [0.0, 1.0]")


func test_tempo_tax_chance_scaled_by_bias() -> void:
	var arm := _tempo_arm()
	assert_true(arm.contains("var tax_chance = clampf([0.35, 0.5, 0.7][battle_phase - 1] * tempo_attack_bias, 0.0, 1.0)"),
		"tempo tax_chance must scale by attack_weight + clampf")


func test_tempo_slow_chance_scaled_by_bias() -> void:
	var arm := _tempo_arm()
	assert_true(arm.contains("var slow_chance = clampf([0.4, 0.55, 0.7][battle_phase - 1] * tempo_attack_bias, 0.0, 1.0)"),
		"tempo slow_chance must scale by attack_weight + clampf")


func test_tempo_haste_setup_not_biased() -> void:
	# Negative pin: the haste self-buff arm must NOT be biased —
	# it's a setup move with a binary "already have buff" gate.
	# Biasing it would be a no-op since the gate isn't a chance roll.
	var arm := _tempo_arm()
	# The haste call sits right after the bias var declaration, and
	# the gate is `if not has_spd_buff and not find_ability...`.
	# Pin that the gate doesn't reference tempo_attack_bias.
	var haste_idx: int = arm.find("if not has_spd_buff")
	assert_gt(haste_idx, -1, "haste setup gate must exist")
	# Look forward to the next return-or-newline-fn boundary.
	var return_idx: int = arm.find("masterite_haste", haste_idx)
	assert_gt(return_idx, -1, "masterite_haste return must exist")
	var haste_block: String = arm.substr(haste_idx, return_idx - haste_idx + 50)
	assert_false(haste_block.contains("tempo_attack_bias"),
		"haste setup gate must NOT scale by tempo_attack_bias — it's a binary state check, not a chance roll")


func test_tempo_attack_bias_var_scoped_to_tempo_arm() -> void:
	# Don't leak the var name. Defensive against future copy-paste
	# to other arms with the same identifier.
	var src := _read(BATTLE_MANAGER)
	var count: int = 0
	var pos: int = 0
	while true:
		var p: int = src.find("var tempo_attack_bias", pos)
		if p == -1:
			break
		count += 1
		pos = p + 1
	assert_eq(count, 1,
		"tempo_attack_bias must be declared EXACTLY ONCE — scoped to the tempo arm")


func test_arbiter_bias_path_preserved() -> void:
	# Don't regress tick 117's arbiter wiring.
	var body := _make_masterite_decision_body()
	assert_true(body.contains("var arb_attack_bias: float = float(llm_bias.get(\"attack_weight\", 1.0))"),
		"arbiter bias path from tick 117 must remain")


func test_curator_arm_now_consumes_llm_bias() -> void:
	# Tick 119 wired the curator arm. This was a negative pin in
	# tick 118; flipped to positive once curator got its bias reads.
	var body := _make_masterite_decision_body()
	var curator_idx: int = body.find("\"curator\":")
	assert_gt(curator_idx, -1, "curator arm must exist")
	# Slice to end of function body.
	var curator_arm: String = body.substr(curator_idx, 4000)
	assert_true(curator_arm.contains("llm_bias.get("),
		"curator arm must consume llm_bias — wired in tick 119 (see test_curator_intent_bias_consumption.gd for specific pins)")
