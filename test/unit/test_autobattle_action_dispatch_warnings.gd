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


# ── the LIVE dispatch path ────────────────────────────────────────────
## RETARGETED 2026-09-11. Four arms here pinned `_rule_to_action` and `_get_target_for_rule`, which
## had zero and zero production callers — the latter's three call sites were all INSIDE the former,
## so a one-level caller scan reported it live. Both are now retired from the source.
##
## The live chain is `_rule_to_actions` (plural — ONE CHARACTER from the dead name) ->
## `_action_def_to_action` -> `_get_target_by_type`, and the two functions differed in CONTRACT, not
## just in name: the dead one returned an action with no target on an unknown type, the live one
## returns a targeted attack. So this file was green, correct about the functions it called, and
## silent about what autobattle actually does — cowir-autogrind's find, cowir-ai's discriminator.
##
## These are BEHAVIOURAL. The two arms that survive below are whole-file `src.contains`, which would
## pass if the warning string existed anywhere in the file — including inside the dead functions I
## just deleted. Calling the thing is what makes the difference.

func test_the_live_dispatch_defaults_an_unknown_action_to_a_targeted_attack() -> void:
	var abs_node = Engine.get_main_loop().root.get_node_or_null("AutobattleSystem")
	if abs_node == null:
		pending("AutobattleSystem autoload required")
		return
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Caster"
	c.max_hp = 100; c.current_hp = 100
	var out: Dictionary = abs_node._action_def_to_action(c, {"type": "zzz_not_a_real_action"})
	assert_eq(str(out.get("type", "")), "attack",
		"an unknown action type must degrade to attack, not to an untargeted action")
	assert_true(out.has("target"),
		"and it must carry a target — the retired twin returned one without, which is the defect")

func test_the_live_dispatch_still_handles_a_known_action() -> void:
	## CONTROL: if the dispatcher returned "attack" for everything, the arm above would pass for the
	## wrong reason. A known type must NOT come back as the fallback.
	var abs_node = Engine.get_main_loop().root.get_node_or_null("AutobattleSystem")
	if abs_node == null:
		pending("AutobattleSystem autoload required")
		return
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Caster"
	c.max_hp = 100; c.current_hp = 100
	var out: Dictionary = abs_node._action_def_to_action(c, {"type": "defer"})
	assert_eq(str(out.get("type", "")), "defer",
		"a known action type must come back as itself, not as the unknown-type fallback")
	assert_false(out.has("target"),
		"and defer takes no target — proof this is the defer ARM, not the attack fallback")

func test_the_retired_twins_are_gone() -> void:
	## Bidirectional: if either comes back, this file must be revisited rather than silently
	## re-covering a dead path. Names one character apart is how the original trap worked.
	var src := _read(AUTOBATTLE_SYSTEM)
	assert_false(src.contains("func _rule_to_action("),
		"the singular twin had no production callers — it is retired, do not reinstate it")
	assert_false(src.contains("func _get_target_for_rule("),
		"dead by transitivity — every caller lived inside the singular twin")
	assert_true(src.contains("func _rule_to_actions("),
		"CONTROL: the LIVE plural dispatcher is still here")


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
