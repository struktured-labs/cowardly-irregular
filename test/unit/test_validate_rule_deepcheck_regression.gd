extends GutTest

## Item 13 fast-follow (cowir-ai convergence, msgs 2035/2038): fizzle deep-check
## on AutobattleSystem.validate_rule via the optional deep_check_character_id arg.
##
## Contract pinned here:
##  - No character_id → shallow grammar only, byte-identical to pre-extension
##    behavior (a hallucinated-but-grammatical ability id PASSES shallow).
##  - With character_id → three deep classes error: unknown ability id,
##    ability outside the character's level-1 kit (level-gated or wrong job),
##    MP-starved rule (summed multi-action cost vs job base pool, per-rule
##    mp_percent >= guard required — stricter than the catalog's whole-script
##    lint, no earlier-refill credit). Plus unknown item ids.
##  - free_move ability (pray/channel/riff) counts as in-kit.
##  - Unresolvable job → loud "deep check unavailable" error, not silence.

const AutobattleSystemScript = preload("res://src/autobattle/AutobattleSystem.gd")

var _ab: Node


func before_each() -> void:
	_ab = AutobattleSystemScript.new()


func after_each() -> void:
	_ab.free()


func _rule(conditions: Array, actions: Array) -> Dictionary:
	return {"conditions": conditions, "actions": actions, "enabled": true}


## ── Shallow behavior unchanged ───────────────────────────────────────────

func test_shallow_passes_hallucinated_ability_id() -> void:
	var rule := _rule([{"type": "always"}], [{"type": "ability", "id": "summon_meteor_9000", "target": "lowest_hp_enemy"}])
	assert_eq(_ab.validate_rule(rule).size(), 0,
		"without character_id, grammar-valid rules pass even with unknown ability ids (pre-extension behavior)")


func test_shallow_still_rejects_grammar_errors() -> void:
	var rule := _rule([{"type": "made_up_condition"}], [{"type": "attack", "target": "lowest_hp_enemy"}])
	assert_gt(_ab.validate_rule(rule).size(), 0, "grammar errors still caught without character_id")


## ── Deep: ability resolution + kit membership ────────────────────────────

func test_deep_rejects_unknown_ability() -> void:
	var rule := _rule([{"type": "always"}], [{"type": "ability", "id": "summon_meteor_9000", "target": "lowest_hp_enemy"}])
	var errors: Array = _ab.validate_rule(rule, "hero")
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "unknown ability")


func test_deep_rejects_out_of_kit_ability() -> void:
	## cure is a real ability but not in the fighter's kit.
	var rule := _rule(
		[{"type": "mp_percent", "op": ">=", "value": 50}],
		[{"type": "ability", "id": "cure", "target": "lowest_hp_ally"}])
	var errors: Array = _ab.validate_rule(rule, "hero")
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "not in fighter's level-1 kit")


func test_deep_rejects_level_gated_ability() -> void:
	## shield_bash unlocks at level 3 — not level-1 kit, would fizzle for a fresh fighter.
	var rule := _rule(
		[{"type": "mp_percent", "op": ">=", "value": 60}],
		[{"type": "ability", "id": "shield_bash", "target": "lowest_hp_enemy"}])
	var errors: Array = _ab.validate_rule(rule, "hero")
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "not in fighter's level-1 kit")


func test_deep_accepts_free_move_ability() -> void:
	## pray is the cleric's free_move, not in the abilities array — must count as in-kit.
	var rule := _rule([{"type": "mp_percent", "op": "<", "value": 15}], [{"type": "ability", "id": "pray", "target": "self"}])
	assert_eq(_ab.validate_rule(rule, "mira").size(), 0, "free_move ability must pass deep check (0-cost, in kit)")


## ── Deep: MP-starvation ──────────────────────────────────────────────────

func test_deep_rejects_unguarded_costed_rule() -> void:
	## power_strike = 8 MP on a 30 MP base pool = 27% — unguarded rule fizzles when dry.
	var rule := _rule([{"type": "always"}], [{"type": "ability", "id": "power_strike", "target": "lowest_hp_enemy"}])
	var errors: Array = _ab.validate_rule(rule, "hero")
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "fizzle")


func test_deep_accepts_guarded_costed_rule() -> void:
	var rule := _rule(
		[{"type": "mp_percent", "op": ">=", "value": 30}],
		[{"type": "ability", "id": "power_strike", "target": "lowest_hp_enemy"}])
	assert_eq(_ab.validate_rule(rule, "hero").size(), 0)


func test_deep_sums_multi_action_cost() -> void:
	## fira ×2 = 32 MP on mage's 80 base pool = 40%. A single-cast guard (>=20)
	## is NOT enough for the double-cast burst.
	var under := _rule(
		[{"type": "ap", "op": ">=", "value": 2}, {"type": "mp_percent", "op": ">=", "value": 20}],
		[{"type": "ability", "id": "fira", "target": "lowest_magic_defense_enemy"},
		 {"type": "ability", "id": "fira", "target": "lowest_magic_defense_enemy"}])
	var errors: Array = _ab.validate_rule(under, "vex")
	assert_eq(errors.size(), 1, "guard below summed cost must fail")
	assert_string_contains(errors[0], "32 MP")
	var over := _rule(
		[{"type": "ap", "op": ">=", "value": 2}, {"type": "mp_percent", "op": ">=", "value": 45}],
		[{"type": "ability", "id": "fira", "target": "lowest_magic_defense_enemy"},
		 {"type": "ability", "id": "fira", "target": "lowest_magic_defense_enemy"}])
	assert_eq(_ab.validate_rule(over, "vex").size(), 0, "guard covering summed cost passes")


func test_deep_zero_cost_ability_needs_no_guard() -> void:
	## channel is 0 MP — unguarded is fine.
	var rule := _rule([{"type": "always"}], [{"type": "ability", "id": "channel", "target": "self"}])
	assert_eq(_ab.validate_rule(rule, "vex").size(), 0)


## ── Deep: items + job resolution ─────────────────────────────────────────

func test_deep_rejects_unknown_item() -> void:
	var rule := _rule([{"type": "always"}], [{"type": "item", "id": "elixir_of_debugging", "target": "self"}])
	var errors: Array = _ab.validate_rule(rule, "hero")
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "unknown item")


func test_deep_accepts_known_item() -> void:
	var rule := _rule(
		[{"type": "hp_percent", "op": "<", "value": 50}, {"type": "item_count", "item_id": "potion", "op": ">", "value": 0}],
		[{"type": "item", "id": "potion", "target": "self"}])
	assert_eq(_ab.validate_rule(rule, "hero").size(), 0)


func test_deep_unresolvable_job_errors_loudly() -> void:
	var rule := _rule([{"type": "always"}], [{"type": "attack", "target": "lowest_hp_enemy"}])
	var errors: Array = _ab.validate_rule(rule, "totally_unknown_character_xyz")
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "deep check unavailable")


## ── Catalog cross-check: every shipped preset passes its own deep check ──

func test_all_catalog_presets_pass_deep_check_or_have_refill_cover() -> void:
	## The catalog's whole-script lint allows an earlier 0-cost refill rule to
	## cover a later unguarded rule; the per-rule deep check is stricter. So:
	## every catalog rule must either pass the deep check outright, or fail
	## ONLY on the mp-guard class (never on unknown/out-of-kit abilities).
	AutobattleRuleTemplates._reset_cache_for_test()
	var char_for_job := {"fighter": "hero", "cleric": "mira", "mage": "vex", "rogue": "zack", "bard": "bard"}
	for t in AutobattleRuleTemplates.catalog():
		var cid: String = char_for_job.get(t.get("job_id", ""), "")
		assert_ne(cid, "", "job '%s' must map to a starter character" % t.get("job_id", ""))
		for rule in t.get("rules", []):
			for err in _ab.validate_rule(rule, cid):
				assert_string_contains(str(err), "fizzle",
					"catalog template '%s' may only diverge from deep check on the whole-script refill class, got: %s" % [t.get("id", "?"), err])
