extends GutTest

## tick 216: AutobattleSystem now push_warns on three previously-
## silent failure paths.
##
## Pre-fix _evaluate_condition, _compare, _compare_str all fell
## through their match statements with `return false` when an
## unknown enum value or operator arrived. Autobattle rules with
## corrupted JSON (save drift, deprecated enum values, Scriptweaver
## custom conditions, typo'd ops like "=" or ">>") silently never
## matched. Players saw "my carefully-tuned autobattle script
## doesn't do anything" with no diagnostic.
##
## Same silent-failure class as the cutscene flag audits in ticks
## 212-214. Autobattle scripting is described in CLAUDE.md as
## "first-class game mechanic, not a convenience feature" — silent
## rule misbehavior would kill the experience.
##
## Fix: each fall-through path now push_warns with the offending
## value AND a hint at the likely cause (rule JSON drift). The
## return-false behavior is preserved (defensive fallback) so a
## bad rule still doesn't crash the battle.

const AUTOBATTLE_SYSTEM := "res://src/autobattle/AutobattleSystem.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── _evaluate_condition: unknown ConditionType ────────────────────────

func test_evaluate_condition_warns_on_unknown_type() -> void:
	var src := _read(AUTOBATTLE_SYSTEM)
	# Find _evaluate_condition body.
	var fn_idx: int = src.find("func _evaluate_condition(combatant: Combatant, condition: Dictionary) -> bool:")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("[AutobattleSystem] _evaluate_condition: unknown ConditionType"),
		"_evaluate_condition must push_warning on unknown enum value")
	assert_true(body.contains("autobattle may silently misbehave"),
		"warning must mention silent-misbehavior consequence")
	assert_true(body.contains("check rule JSON for stale type values"),
		"warning must hint at the likely cause (stale rule JSON)")


func test_evaluate_condition_still_returns_false_on_unknown() -> void:
	# Pin: defensive fallback preserved — bad enum value doesn't
	# crash the battle, just refuses to match the rule.
	var src := _read(AUTOBATTLE_SYSTEM)
	var fn_idx: int = src.find("func _evaluate_condition(combatant: Combatant, condition: Dictionary) -> bool:")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	# After the push_warning, the function must still `return false`.
	var warn_idx: int = body.find("[AutobattleSystem] _evaluate_condition: unknown ConditionType")
	assert_gt(warn_idx, -1)
	var post_warn: String = body.substr(warn_idx, 400)
	assert_true(post_warn.contains("return false"),
		"defensive `return false` fallback must follow the warning")


# ── _compare: unknown CompareOp ───────────────────────────────────────

func test_compare_warns_on_unknown_op() -> void:
	var src := _read(AUTOBATTLE_SYSTEM)
	var fn_idx: int = src.find("func _compare(a: float, op: CompareOp, b: float) -> bool:")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("[AutobattleSystem] _compare: unknown CompareOp"),
		"_compare must push_warning on unknown enum value")


# ── _compare_str: unknown op string ───────────────────────────────────

func test_compare_str_warns_on_unknown_op() -> void:
	var src := _read(AUTOBATTLE_SYSTEM)
	var fn_idx: int = src.find("func _compare_str(a: float, op: String, b: float) -> bool:")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("[AutobattleSystem] _compare_str: unknown op="),
		"_compare_str must push_warning on unknown op string")
	# Pin the list of valid ops in the warning so devs know what was expected.
	assert_true(body.contains("expected <, <=, ==, >=, >, !="),
		"warning must enumerate valid op strings for diagnostic ease")


# ── Symmetry: pre-existing grid-condition warning still present ──────

func test_existing_grid_condition_warning_preserved() -> void:
	# Pin: tick 216's three new warnings join the existing
	# _evaluate_grid_condition unknown-type warning that's been
	# there since the grid format landed. Verify it survives.
	var src := _read(AUTOBATTLE_SYSTEM)
	assert_true(src.contains("AutobattleSystem: Unknown condition type"),
		"existing _evaluate_grid_condition unknown-type warning preserved")


# ── Match coverage is complete: warnings only fire on unknown ─────────

func test_evaluate_condition_match_covers_known_types() -> void:
	# Negative-regression: verify every ConditionType enum value
	# still has a match arm. A new enum value forgotten in the match
	# would trip the new warning at runtime — but better to catch
	# it statically.
	var src := _read(AUTOBATTLE_SYSTEM)
	# Pin a representative subset of the existing match arms.
	for arm in ["ConditionType.HP_PERCENT:", "ConditionType.MP_PERCENT:",
			"ConditionType.AP_VALUE:", "ConditionType.HAS_STATUS:",
			"ConditionType.TARGET_HP_PERCENT:", "ConditionType.TURN_COUNT:",
			"ConditionType.ENEMY_COUNT:", "ConditionType.ALLY_COUNT:",
			"ConditionType.ITEM_COUNT:", "ConditionType.ALWAYS:",
			"ConditionType.CUSTOM:"]:
		assert_true(src.contains(arm),
			"match arm '%s' must remain" % arm)


# ── Cross-pin: prior cutscene silent-failure work preserved ───────────

func test_tick_214_defeat_flag_audit_present() -> void:
	# Same silent-fail audit philosophy across multiple subsystems.
	assert_true(FileAccess.file_exists("res://test/unit/test_defeat_cutscene_flag_audit.gd"),
		"tick 214 defeat flag audit must still exist")
