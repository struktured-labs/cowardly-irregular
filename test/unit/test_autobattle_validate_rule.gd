extends GutTest

## Autobattle rule grammar hard-validation.
## Composer output MUST pass this or the preview is refused.

var autobattle_system

func before_each() -> void:
    autobattle_system = get_node_or_null("/root/AutobattleSystem")
    assert_not_null(autobattle_system, "AutobattleSystem autoload not available")

func test_valid_rule_returns_empty_errors() -> void:
    var rule := {
        "conditions": [{"type": "hp_percent", "op": "<", "value": 30}],
        "actions": [{"type": "ability", "id": "cure", "target": "lowest_hp_ally"}],
        "enabled": true,
    }
    var errors: Array = autobattle_system.validate_rule(rule)
    assert_eq(errors.size(), 0, "valid rule must produce zero errors; got: %s" % [errors])

func test_missing_conditions_key() -> void:
    var rule := {"actions": [{"type": "attack"}]}
    var errors: Array = autobattle_system.validate_rule(rule)
    assert_gt(errors.size(), 0, "missing conditions must produce an error")
    var joined: String = "|".join(errors)
    assert_true("conditions" in joined, "error should mention 'conditions'")

func test_missing_actions_key() -> void:
    var rule := {"conditions": [{"type": "always"}]}
    var errors: Array = autobattle_system.validate_rule(rule)
    assert_gt(errors.size(), 0, "missing actions must produce an error")
    var joined: String = "|".join(errors)
    assert_true("actions" in joined, "error should mention 'actions'")

func test_unknown_condition_type() -> void:
    var rule := {
        "conditions": [{"type": "hp_zorp", "op": "<", "value": 30}],
        "actions": [{"type": "attack"}],
    }
    var errors: Array = autobattle_system.validate_rule(rule)
    assert_gt(errors.size(), 0, "unknown condition type must produce an error")
    var joined: String = "|".join(errors)
    assert_true("hp_zorp" in joined, "error should include the unknown type name")

func test_unknown_operator() -> void:
    var rule := {
        "conditions": [{"type": "hp_percent", "op": "!<>", "value": 30}],
        "actions": [{"type": "attack"}],
    }
    var errors: Array = autobattle_system.validate_rule(rule)
    assert_gt(errors.size(), 0, "unknown operator must produce an error")

func test_unknown_action_type() -> void:
    var rule := {
        "conditions": [{"type": "always"}],
        "actions": [{"type": "yeet"}],
    }
    var errors: Array = autobattle_system.validate_rule(rule)
    assert_gt(errors.size(), 0, "unknown action type must produce an error")
    var joined: String = "|".join(errors)
    assert_true("yeet" in joined, "error should include the unknown action name")

func test_ability_action_missing_id() -> void:
    var rule := {
        "conditions": [{"type": "always"}],
        "actions": [{"type": "ability", "target": "self"}],
    }
    var errors: Array = autobattle_system.validate_rule(rule)
    assert_gt(errors.size(), 0, "ability action without id must produce an error")

func test_unknown_target_type() -> void:
    var rule := {
        "conditions": [{"type": "always"}],
        "actions": [{"type": "attack", "target": "highest_luck_ally"}],
    }
    var errors: Array = autobattle_system.validate_rule(rule)
    assert_gt(errors.size(), 0, "unknown target type must produce an error")
