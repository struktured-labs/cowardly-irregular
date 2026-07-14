extends GutTest

## tick 217: closes the autobattle silent-failure audit started in
## tick 216. Three more match fall-throughs in the action-dispatch
## path now push_warn instead of silently degrading.
##
## Pre-fix:
##   _rule_to_action() — match on ActionType had no fallthrough at
##     all. Unknown enum value returned an action with only
##     {"type": "..."} and no target/ability/item — execution
##     misbehaves silently.
##   _get_target_for_rule() — wildcard `_:` silently defaulted to
##     lowest_hp_enemy. Player's rule says "self" or "lowest_hp_ally"
##     but a typo'd value invisibly attacks the wrong target.
##   _action_type_to_string() — fell through to `return "attack"`.
##     A stale enum makes a brave-action rule attack instead.
##
## Same audit philosophy as tick 216 (_evaluate_condition / _compare
## / _compare_str). Together: every autobattle match statement now
## surfaces unknown values loudly.
##
## Returns are preserved as defensive fallbacks so a bad rule
## degrades gracefully (skipped or attack-defaulted, not crashed).

const AUTOBATTLE_SYSTEM := "res://src/autobattle/AutobattleSystem.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _fn_body(fn_signature: String) -> String:
	var src := _read(AUTOBATTLE_SYSTEM)
	var fn_idx: int = src.find(fn_signature)
	assert_gt(fn_idx, -1, "%s must exist" % fn_signature)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	return src.substr(fn_idx, next_fn - fn_idx) if next_fn > -1 else src.substr(fn_idx)


# ── _rule_to_action ───────────────────────────────────────────────────

func test_rule_to_action_warns_on_unknown_actiontype() -> void:
	var body := _fn_body("func _rule_to_action(combatant: Combatant, rule: Dictionary) -> Dictionary:")
	assert_true(body.contains("[AutobattleSystem] _rule_to_action: unknown ActionType"),
		"_rule_to_action must push_warning on unknown ActionType")
	assert_true(body.contains("action will lack target data"),
		"warning must mention the consequence (missing target data)")
	assert_true(body.contains("stale action_type values"),
		"warning must hint at the cause (stale rule JSON)")


func test_rule_to_action_has_wildcard_match_arm() -> void:
	# Pin: the match now has a `_:` arm (previously missing entirely).
	var body := _fn_body("func _rule_to_action(combatant: Combatant, rule: Dictionary) -> Dictionary:")
	# The wildcard arm sits between SKIP and the final `return action`.
	assert_true(body.contains("ActionType.SKIP:") and body.contains("\n\t\t_:\n"),
		"_rule_to_action match must have a `_:` wildcard arm")


# ── _get_target_for_rule ──────────────────────────────────────────────

func test_get_target_for_rule_warns_on_unknown_target_type() -> void:
	var body := _fn_body("func _get_target_for_rule(combatant: Combatant, rule: Dictionary) -> Combatant:")
	assert_true(body.contains("[AutobattleSystem] _get_target_for_rule: unknown target_type"),
		"_get_target_for_rule must push_warning on unknown target_type")
	assert_true(body.contains("defaulting to lowest_hp_enemy"),
		"warning must state the default behavior")
	assert_true(body.contains("stale target_type values"),
		"warning must hint at stale rule JSON")


func test_get_target_for_rule_defensive_fallback_preserved() -> void:
	# Pin: the warning sits next to the defensive `return _get_lowest_hp_enemy(combatant)`
	# fallback — bad rules don't crash, just behave defensively.
	var body := _fn_body("func _get_target_for_rule(combatant: Combatant, rule: Dictionary) -> Combatant:")
	assert_true(body.contains("return _get_lowest_hp_enemy(combatant)"),
		"defensive return _get_lowest_hp_enemy(combatant) must be preserved")


# ── _action_type_to_string ────────────────────────────────────────────

func test_action_type_to_string_warns_on_unknown_enum() -> void:
	var body := _fn_body("func _action_type_to_string(action_type: ActionType) -> String:")
	assert_true(body.contains("[AutobattleSystem] _action_type_to_string: unknown ActionType"),
		"_action_type_to_string must push_warning on unknown ActionType")
	assert_true(body.contains("falling back to 'attack'"),
		"warning must state the default behavior")


func test_action_type_to_string_fallback_preserved() -> void:
	# Pin: defensive `return "attack"` fallback preserved.
	var body := _fn_body("func _action_type_to_string(action_type: ActionType) -> String:")
	assert_true(body.contains("return \"attack\""),
		"defensive return 'attack' fallback preserved")


# ── Symmetry: cross-pin tick 216's warnings still in place ────────────

func test_tick_216_evaluate_condition_warning_preserved() -> void:
	var src := _read(AUTOBATTLE_SYSTEM)
	assert_true(src.contains("[AutobattleSystem] _evaluate_condition: unknown ConditionType"),
		"tick 216 _evaluate_condition warning preserved")


func test_tick_216_compare_warnings_preserved() -> void:
	var src := _read(AUTOBATTLE_SYSTEM)
	assert_true(src.contains("[AutobattleSystem] _compare: unknown CompareOp"),
		"tick 216 _compare warning preserved")
	assert_true(src.contains("[AutobattleSystem] _compare_str: unknown op="),
		"tick 216 _compare_str warning preserved")


# ── Symmetry: pre-existing warnings still preserved ───────────────────

func test_existing_action_def_to_action_warning_preserved() -> void:
	# Pin: _action_def_to_action's pre-existing unknown-type warning
	# from the grid-format landing is still there. Tick 217 brings
	# the legacy CTB-format _rule_to_action up to symmetry.
	var src := _read(AUTOBATTLE_SYSTEM)
	assert_true(src.contains("AutobattleSystem: Unknown action type"),
		"_action_def_to_action's existing warning preserved")


func test_existing_get_target_by_type_warning_preserved() -> void:
	var src := _read(AUTOBATTLE_SYSTEM)
	assert_true(src.contains("AutobattleSystem: Unknown target type"),
		"_get_target_by_type's existing warning preserved")
