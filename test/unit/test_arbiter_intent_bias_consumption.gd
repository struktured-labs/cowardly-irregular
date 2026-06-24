extends GutTest

## tick 117 regression: the arbiter masterite ladder must consume
## the LLM intent's attack_weight bias on its primary offensive rolls.
## Pre-fix, only the warden ladder read llm_bias (lines 1424/1428/1432).
## arbiter / tempo / curator ladders ignored llm_bias entirely, so
## an "aggress" intent on those bosses produced ZERO change in their
## attack frequency — the LLM intent system was warden-only.
##
## This tick wires the arbiter ladder. Tempo + curator deferred to
## follow-up ticks (each ladder needs its own ability-specific bias
## decisions and this scope keeps changes focused).

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


func _arbiter_arm() -> String:
	# Slice the arbiter case body between its arm marker and the next
	# masterite arm (tempo).
	var body := _make_masterite_decision_body()
	var arb_idx: int = body.find("\"arbiter\":")
	assert_gt(arb_idx, -1, "arbiter arm must exist in _make_masterite_decision")
	var tempo_idx: int = body.find("\"tempo\":", arb_idx + 1)
	assert_gt(tempo_idx, -1, "tempo arm must follow arbiter")
	return body.substr(arb_idx, tempo_idx - arb_idx)


func test_arbiter_reads_attack_weight_bias() -> void:
	# Pin: the arbiter ladder reads llm_bias.attack_weight via
	# .get with safe default. This is the local var
	# `arb_attack_bias` that the chance computations multiply by.
	var arm := _arbiter_arm()
	assert_true(arm.contains("var arb_attack_bias: float = float(llm_bias.get(\"attack_weight\", 1.0))"),
		"arbiter ladder must read llm_bias.attack_weight with safe default — otherwise intent bias is dead for arbiter")


func test_arbiter_strike_chance_scaled_by_bias() -> void:
	# Pin: strike_chance multiplies arb_attack_bias into the phase
	# table, then clampfs to [0.0, 1.0] so an aggressive bias can
	# still saturate at 100%.
	var arm := _arbiter_arm()
	assert_true(arm.contains("var strike_chance = clampf([0.5, 0.65, 0.8][battle_phase - 1] * arb_attack_bias, 0.0, 1.0)"),
		"arbiter strike_chance must scale by attack_weight bias and clampf to probability range")


func test_arbiter_aoe_chance_scaled_by_bias() -> void:
	# Pin: aoe_chance ALSO scales by the bias, so a turtle intent
	# damps BOTH strike and AoE (not just strike). Asymmetric scaling
	# would be misleading.
	var arm := _arbiter_arm()
	assert_true(arm.contains("var aoe_chance = clampf([0.4, 0.55, 0.75][battle_phase - 1] * arb_attack_bias, 0.0, 1.0)"),
		"arbiter aoe_chance must also scale by attack_weight — symmetric with strike_chance")


func test_arbiter_does_not_break_warden_bias_path() -> void:
	# Don't regress the warden ladder which already consumes its
	# bias keys (iron_guard, endurance_test, crushing_blow).
	var body := _make_masterite_decision_body()
	assert_true(body.contains("llm_bias.get(\"iron_guard\", 1.0)"),
		"warden ladder must keep iron_guard bias consumer")
	assert_true(body.contains("llm_bias.get(\"endurance_test\", 1.0)"),
		"warden ladder must keep endurance_test bias consumer")
	assert_true(body.contains("llm_bias.get(\"crushing_blow\", 1.0)"),
		"warden ladder must keep crushing_blow bias consumer")


func test_arbiter_attack_bias_var_scoped_to_arbiter_arm() -> void:
	# Defensive: arb_attack_bias must be declared INSIDE the arbiter
	# arm, not leaked into outer scope. GDScript shadowing rules
	# allow this but reusing a name across arms is bug-prone.
	var src := _read(BATTLE_MANAGER)
	# Count the occurrences of the var declaration. Should be exactly 1.
	var count: int = 0
	var pos: int = 0
	while true:
		var p: int = src.find("var arb_attack_bias", pos)
		if p == -1:
			break
		count += 1
		pos = p + 1
	assert_eq(count, 1,
		"arb_attack_bias must be declared EXACTLY ONCE — scoped to the arbiter arm")


func test_tempo_and_curator_ladders_marked_for_followup() -> void:
	# Coverage doc: tempo + curator ladders STILL don't consume
	# llm_bias as of this tick. Negative pin so a future "all done"
	# claim is caught — actually this just documents the gap; a
	# follow-up tick should wire them too.
	var body := _make_masterite_decision_body()
	# Find the tempo arm.
	var tempo_idx: int = body.find("\"tempo\":")
	var curator_idx: int = body.find("\"curator\":")
	assert_gt(tempo_idx, -1, "tempo arm must exist")
	assert_gt(curator_idx, -1, "curator arm must exist")
	var tempo_arm: String = body.substr(tempo_idx, curator_idx - tempo_idx)
	# Tempo arm currently has NO llm_bias reads — that's the known
	# gap. Assert it explicitly so a future fix removes this guard
	# along with the fix.
	assert_false(tempo_arm.contains("llm_bias.get("),
		"tempo arm STILL doesn't consume llm_bias — known gap, remove this assertion when wiring tempo")
