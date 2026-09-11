extends GutTest

## One unusable rule threw away the player's entire strategy.
##
## compose_async validated every rule and refused the composition if ANY of them
## failed the deep check. Measured on live llama3 against the shipped prompt, 10
## samples per job, scored by compose_async's own verdict (source == "llm"):
##
##     fighter   6/10 reached the player        cleric   5/10
##
## and the dominant cause was a single rule naming an ability the character does
## not have — 'esuna' or 'fire' on a fighter — while the other three rules in the
## set were valid. The player asked for a strategy, one line of four was wrong,
## and they got a canned fallback that ignored what they asked for.
##
## Dropping the offending rule and keeping the rest, same shape as the
## _drop_null_targets normalisation already in the repair layer:
##
##     fighter   6/10 -> 10/10                  cleric   5/10 -> 8/10
##
## ⚠️ Same 20 captured replies scored BOTH ways — not two samples — so the
## comparison is on identical input. n=10 per job, one model, one intent: a
## demonstration, not a benchmark.
##
## ⛔ THE SUBSTANTIVE FLOOR IS THE HALF THAT MATTERS, and without it this change
## makes things WORSE. First version scored 10/10 on BOTH jobs, and three of those
## rescues had dropped everything except the trailing {always} -> attack line:
##
##     cleric/03   DROP esuna · DROP fire · KEEP [always] -> attack
##
## That scores as a success and hands the player plain attack, labelled as the
## strategy they asked for. A canned fallback is at least honest about being one.
## So a rescue only happens when a rule carrying a REAL condition survives; when
## it does not, the composition is refused exactly as before.

const RC := preload("res://src/llm/RuleComposer.gd")


## Minimal stand-in for AutobattleSystem: refuses any rule naming a banned ability.
class FakeSystem:
	extends Node
	var banned: Array[String] = ["esuna", "fire"]
	func validate_rule(rule: Dictionary, _cid: String = "") -> Array:
		for a in rule.get("actions", []):
			if str((a as Dictionary).get("id", "")) in banned:
				return ["ability '%s' not in kit" % str((a as Dictionary).get("id", ""))]
		return []


func _rc():
	var r = RC.new()
	add_child_autofree(r)
	return r


func _rule(cond_type: String, ability: String = "") -> Dictionary:
	var act: Dictionary = {"type": "attack"} if ability == "" else {"type": "ability", "id": ability}
	return {"conditions": [{"type": cond_type}], "actions": [act], "enabled": true}


# ── the defect ────────────────────────────────────────────────────────────────

func test_one_unusable_rule_no_longer_discards_the_others() -> void:
	var rules: Array = [_rule("ally_hp_percent"), _rule("mp_percent", "esuna"), _rule("always")]
	var sys := FakeSystem.new()
	add_child_autofree(sys)
	var notes: Array[String] = _rc()._drop_unusable_rules(rules, "fighter", sys)
	assert_eq(rules.size(), 2, "the two usable rules must survive; only the bad one goes")
	assert_eq(notes.size(), 1, "and exactly one note must be produced")
	assert_true(str(notes[0]).find("esuna") != -1,
		"the note must name what was dropped — silent edits are the thing notes exist to prevent")


func test_a_clean_ruleset_is_untouched() -> void:
	## CORRECT-WORK axis: a composition with nothing wrong must pass through with no
	## drops and no notes. A repair that taxes valid input is worse than no repair.
	var rules: Array = [_rule("ally_hp_percent"), _rule("always")]
	var sys := FakeSystem.new()
	add_child_autofree(sys)
	var notes: Array[String] = _rc()._drop_unusable_rules(rules, "fighter", sys)
	assert_eq(rules.size(), 2, "nothing may be dropped from a valid ruleset")
	assert_eq(notes.size(), 0, "and no note may be invented")


# ── the substantive floor ─────────────────────────────────────────────────────

func test_a_rescue_to_nothing_but_always_attack_is_refused() -> void:
	## THE DISCRIMINATOR, and the half that keeps this from being a regression.
	## Measured 3 of 10 times before the floor existed.
	var rules: Array = [_rule("mp_percent", "esuna"), _rule("mp_percent", "fire"), _rule("always")]
	var sys := FakeSystem.new()
	add_child_autofree(sys)
	var notes: Array[String] = _rc()._drop_unusable_rules(rules, "cleric", sys)
	assert_eq(notes.size(), 0, "no rescue may be reported")
	assert_eq(rules.size(), 3,
		"the rules must be left UNTOUCHED so the caller refuses normally — presenting "
		+ "'always attack' as the player's strategy is worse than an honest fallback")


func test_a_real_condition_surviving_is_enough_to_rescue() -> void:
	## The other side of the floor: one recognisable rule is worth keeping.
	var rules: Array = [_rule("ally_hp_percent"), _rule("mp_percent", "esuna")]
	var sys := FakeSystem.new()
	add_child_autofree(sys)
	var notes: Array[String] = _rc()._drop_unusable_rules(rules, "fighter", sys)
	assert_eq(rules.size(), 1, "the substantive rule survives alone")
	assert_eq(notes.size(), 1, "and the drop is reported")


func test_nothing_usable_leaves_the_set_alone() -> void:
	## An EMPTY ruleset is not a valid composition — it is the save-wiping one. The
	## caller must be allowed to refuse, so this never hands back zero rules.
	var rules: Array = [_rule("mp_percent", "esuna"), _rule("mp_percent", "fire")]
	var sys := FakeSystem.new()
	add_child_autofree(sys)
	var notes: Array[String] = _rc()._drop_unusable_rules(rules, "fighter", sys)
	assert_eq(rules.size(), 2, "rules must be untouched when nothing survives")
	assert_eq(notes.size(), 0, "and no rescue reported")


func test_a_missing_domain_system_changes_nothing() -> void:
	## CONTROL: the repair must no-op rather than erase when it cannot validate.
	var rules: Array = [_rule("always"), _rule("mp_percent", "esuna")]
	var notes: Array[String] = _rc()._drop_unusable_rules(rules, "fighter", null)
	assert_eq(rules.size(), 2, "with no validator, nothing may be dropped")
	assert_eq(notes.size(), 0, "and nothing reported")


# ── the wiring ────────────────────────────────────────────────────────────────

func test_compose_async_actually_calls_the_repair() -> void:
	## EXECUTION IS NOT SELECTION: the helper working proves nothing about whether
	## the composition path reaches it.
	var src: String = FileAccess.get_file_as_string("res://src/llm/RuleComposer.gd")
	assert_false(src.is_empty(), "CONTROL: source must load")
	assert_true(src.contains("_drop_unusable_rules(v[\"rules\"]"),
		"compose_async must run the repair on the validated rules")
	assert_true(src.contains("DOMAIN_AUTOBATTLE and character_id != \"\""),
		"and only for autobattle with a resolved character — autogrind has no PC to deep-check")
