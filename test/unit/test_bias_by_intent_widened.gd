extends GutTest

const _COUNTER_INTENT_TAGS := ["fire_resist", "ice_resist", "lightning_resist",
                                "focus_healer", "defense_boost", "rotate_aggro"]

var battle_manager

func before_each() -> void:
	battle_manager = get_node_or_null("/root/BattleManager")
	assert_not_null(battle_manager, "BattleManager autoload not available")

func test_widened_tags_boost_counter_chance() -> void:
	for tag in _COUNTER_INTENT_TAGS:
		var bias: Dictionary = battle_manager._bias_by_intent(tag, "warden")
		assert_true(bias.has("counter_action_chance"),
				"%s must set counter_action_chance in bias dict" % tag)
		assert_almost_eq(float(bias["counter_action_chance"]), 2.0, 0.01,
				"%s counter_action_chance should be 2.0" % tag)

func test_original_tags_still_present() -> void:
	var aggress: Dictionary = battle_manager._bias_by_intent("aggress", "warden")
	var turtle: Dictionary = battle_manager._bias_by_intent("turtle", "warden")
	var exploit: Dictionary = battle_manager._bias_by_intent("exploit_pattern", "warden")
	assert_gt(aggress.size(), 0, "aggress bias must not be empty")
	assert_gt(turtle.size(), 0, "turtle bias must not be empty")
	assert_gt(exploit.size(), 0, "exploit_pattern bias must not be empty")
	assert_true(exploit.has("counter_action_chance"),
			"exploit_pattern must keep counter_action_chance boost")

func test_unknown_intent_returns_empty_or_default() -> void:
	var bias: Dictionary = battle_manager._bias_by_intent("hokum_pokum", "warden")
	var chance: float = float(bias.get("counter_action_chance", 1.0))
	assert_almost_eq(chance, 1.0, 0.01,
			"unknown intent must NOT boost counter_action_chance (default 1.0)")
