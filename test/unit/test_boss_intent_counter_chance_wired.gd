extends GutTest

## tick 116 regression: the LLM boss "exploit_pattern" intent's
## counter_action_chance bias must scale the boss's counter rate.
## Pre-fix, _bias_by_intent set counter_action_chance = 1.6 for
## "exploit_pattern" but NO consumer read it. So an LLM picking
## "exploit_pattern" produced identical counter behavior to no
## intent at all — the intent's whole purpose ("counter player
## patterns more aggressively") was cosmetic.
##
## attack_weight bias is consumed at line 1187 (generic spell cast),
## and iron_guard / endurance_test / crushing_blow are consumed in
## the warden masterite ladder. This tick wires counter_action_chance
## into the adaptive AI's counter check.

const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_counter_chance_reads_intent_bias() -> void:
	# Pin the read: _bias_by_intent on the boss's stored intent meta,
	# .get("counter_action_chance", 1.0) for safe default.
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("ci_bias.get(\"counter_action_chance\", 1.0)"),
		"counter_chance computation must read intent's counter_action_chance bias — otherwise exploit_pattern intent is dead")


func test_counter_chance_uses_intent_from_meta() -> void:
	# Pin the source: the intent comes from combatant.get_meta("llm_intent",
	# "") — same key used elsewhere in BattleManager. A typo here
	# silently breaks the wiring.
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("_bias_by_intent(combatant.get_meta(\"llm_intent\", \"\"))"),
		"counter_chance must read intent via combatant.get_meta('llm_intent', '') — consistent with masterite path")


func test_counter_chance_multiplied_not_replaced() -> void:
	# Pin: the bias MULTIPLIES the existing counter_chance (which
	# already factors in adaptation_level). Replacing would lose the
	# adaptation-level scaling.
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("counter_chance * float(ci_bias.get(\"counter_action_chance\", 1.0))"),
		"counter_chance must be multiplied by the bias, not replaced — preserves adaptation-level scaling")


func test_counter_chance_clamped_to_valid_probability_range() -> void:
	# Pin: clampf [0.0, 1.0] keeps the probability in valid range.
	# At adaptation_level 3 (90%) × 1.6 bias = 144%, which without
	# the clamp would always counter — but `randf() < 1.44` is
	# always true anyway, so the clamp is mostly documentation.
	# Still pin it — explicit > implicit.
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("clampf(counter_chance * float(ci_bias.get(\"counter_action_chance\", 1.0)), 0.0, 1.0)"),
		"counter_chance must clampf to [0.0, 1.0] — explicit probability bounds")


func test_existing_attack_weight_consumer_preserved() -> void:
	# Don't regress the existing attack_weight read at line ~1187.
	# That's the generic spell-cast bias used by ALL bosses, not
	# just exploit_pattern.
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("0.75 * float(bias.get(\"attack_weight\", 1.0))"),
		"existing attack_weight consumer at the generic spell-cast site must remain — different from this tick's wiring")


func test_exploit_pattern_bias_dict_still_contains_counter_action_chance() -> void:
	# Sanity: _bias_by_intent's "exploit_pattern" arm must still
	# set counter_action_chance. If the key is renamed or removed,
	# the new consumer reads back 1.0 (default), silently making
	# the wiring a no-op.
	var src := _read(BATTLE_MANAGER)
	var idx: int = src.find("\"exploit_pattern\":")
	assert_gt(idx, -1, "exploit_pattern arm of _bias_by_intent must exist")
	var next_arm: int = src.find("\"_\":", idx + 1)
	if next_arm == -1:
		next_arm = src.find("\n}", idx + 1)
	var arm_body: String = src.substr(idx, next_arm - idx) if next_arm > -1 else src.substr(idx)
	assert_true(arm_body.contains("\"counter_action_chance\": 1.6"),
		"exploit_pattern bias arm must still set counter_action_chance = 1.6 — the value the new consumer reads")
