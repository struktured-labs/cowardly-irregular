extends GutTest

## Regression test for cowir-battle msg 1995 / spec §4.3.
##
## Verifies the strategy-override + gate widening at _make_ai_decision:
## when a boss's llm_intent is one of the widened counter-strategy tags,
## the deterministic counter_strategy from AutogrindSystem is overridden
## AND the adaptation_level > 0 gate is bypassed for that specific fire.

const _COUNTER_INTENT_TAGS := ["fire_resist", "ice_resist", "lightning_resist",
								"focus_healer", "defense_boost", "rotate_aggro"]

var battle_manager
var autogrind_system

func before_each() -> void:
	battle_manager = get_node_or_null("/root/BattleManager")
	autogrind_system = get_node_or_null("/root/AutogrindSystem")
	assert_not_null(battle_manager)
	assert_not_null(autogrind_system)

func test_intent_forces_counter_helper_returns_true_for_widened_tags() -> void:
	for tag in _COUNTER_INTENT_TAGS:
		assert_true(battle_manager._intent_forces_counter(tag),
					"widened tag '%s' must set intent_forces_counter=true" % tag)

func test_intent_forces_counter_helper_returns_false_for_originals() -> void:
	for tag in ["aggress", "turtle", "exploit_pattern", "", "unknown"]:
		assert_false(battle_manager._intent_forces_counter(tag),
					"non-widened tag '%s' must NOT force counter" % tag)

func test_strategy_override_helper() -> void:
	var region_id := "test_region_no_patterns"
	for tag in _COUNTER_INTENT_TAGS:
		var strategy: String = battle_manager._resolve_counter_strategy(region_id, tag)
		assert_eq(strategy, tag,
				"intent '%s' must override empty deterministic strategy" % tag)

func test_strategy_falls_back_to_deterministic_for_non_widened_intent() -> void:
	var region_id := "test_region_no_patterns"
	var strategy: String = battle_manager._resolve_counter_strategy(region_id, "aggress")
	var expected: String = autogrind_system.get_counter_strategy(region_id)
	assert_eq(strategy, expected,
			"non-widened intent must not override deterministic strategy")
