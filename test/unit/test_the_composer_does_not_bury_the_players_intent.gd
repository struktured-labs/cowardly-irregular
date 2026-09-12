extends GutTest

## The composer put the catch-all first and buried what the player asked for.
##
## Autobattle rules are evaluated top-to-bottom, first match wins
## (AutobattleSystem: "Evaluate rules in order"). A rule whose conditions are all
## `always` fires every turn, so everything below it is unreachable.
##
## The prompt already asks for this — "Put the fallback (a rule with
## {type:'always'} condition and an attack action) last." Measured against live
## llama3 on the real composer prompt, four player intents, five samples each:
##
##     multi-rule compositions      13
##     led with a catch-all          2      -> 2 rules made unreachable
##
## ⚠️ 2 of 13, NOT the 3 of 4 my first sample suggested. That came from n=4 on a
## single intent and did not survive widening. The defect is real and the rate is
## modest; it should not be quoted as a majority.
##
## What it costs when it fires is the whole composition: a player who asked to
## "heal the moment anyone drops low" got {always}->attack first and the cure
## rules beneath it, so the character attacks forever and the feature silently
## did nothing.
##
## SINKING IS SAFE BY CONSTRUCTION. An always-rule matches regardless of position,
## so moving it last preserves it as the fallback it already is and un-shadows the
## rest. This is a deterministic repair rather than more prompt text, because the
## prompt's instruction exists and is ignored.

const RC := preload("res://src/llm/RuleComposer.gd")


func _rc():
	var c = RC.new()
	if c is Node:
		add_child_autofree(c)
	return c


func _rule(conds: Array, action_id: String) -> Dictionary:
	return {"conditions": conds, "actions": [{"type": "ability", "id": action_id}], "enabled": true}


func _always() -> Dictionary:
	return {"conditions": [{"type": "always"}], "actions": [{"type": "attack"}], "enabled": true}


func _hp(op: String, v: int) -> Array:
	return [{"type": "hp_percent", "op": op, "value": v}]


# ── the defect ────────────────────────────────────────────────────────────────

func test_a_leading_catch_all_is_moved_below_the_specific_rules() -> void:
	## THE ARM. This is the shape live llama3 produced: fallback first, intent after.
	var rules: Array = [_always(), _rule(_hp("<", 30), "cure"), _rule(_hp("<", 60), "protect")]
	var notes: Array = _rc()._sink_unconditional_rules(rules)
	assert_eq(rules.size(), 3, "sinking must not drop a rule")
	assert_eq(str((rules[0]["actions"][0] as Dictionary).get("id", "")), "cure",
		"the player's first specific rule must now run first")
	assert_true((rules[2]["conditions"][0] as Dictionary).get("type") == "always",
		"the catch-all must end up last")
	assert_eq(notes.size(), 1, "the repair must tell the player what moved")
	assert_true(str(notes[0]).find("could never run") != -1,
		"and say why: %s" % str(notes[0]))


func test_the_note_counts_the_rules_that_were_dead() -> void:
	var rules: Array = [_always(), _rule(_hp("<", 30), "cure"), _rule(_hp("<", 60), "protect")]
	var notes: Array = _rc()._sink_unconditional_rules(rules)
	assert_true(str(notes[0]).find("2 rules") != -1,
		"two rules were below the catch-all: %s" % str(notes[0]))


# ── it must not fire on correct input ─────────────────────────────────────────

func test_a_catch_all_already_last_is_left_alone_and_silent() -> void:
	## CORRECT-WORK. The prompt asks for exactly this shape; a repair that
	## "fixes" it would emit a note on every well-formed composition, and a
	## note the player sees on correct work is how a feature gets distrusted.
	var rules: Array = [_rule(_hp("<", 30), "cure"), _always()]
	var before: Array = rules.duplicate(true)
	var notes: Array = _rc()._sink_unconditional_rules(rules)
	assert_eq(notes.size(), 0, "nothing was shadowed, so nothing should be reported")
	assert_eq(rules, before, "and the rules must be untouched")


func test_a_ruleset_with_no_catch_all_is_untouched() -> void:
	var rules: Array = [_rule(_hp("<", 30), "cure"), _rule(_hp("<", 60), "protect")]
	var before: Array = rules.duplicate(true)
	assert_eq(_rc()._sink_unconditional_rules(rules).size(), 0, "no catch-all, no repair")
	assert_eq(rules, before, "and no reordering")


func test_always_ANDED_with_a_real_condition_is_not_a_catch_all() -> void:
	## The discriminator, and llama3 really emits this: {ally_hp_percent, always}.
	## Conditions are AND-chained, so that rule is GATED by the real condition and
	## shadows nothing. Treating it as a catch-all would sink a rule the player
	## wanted first, which is the opposite defect.
	var gated: Dictionary = _rule([{"type": "ally_hp_percent", "op": "<", "value": 40},
		{"type": "always"}], "cure")
	var rules: Array = [gated, _rule(_hp("<", 60), "protect")]
	var before: Array = rules.duplicate(true)
	assert_eq(_rc()._sink_unconditional_rules(rules).size(), 0,
		"an AND-chained always is gated, not a catch-all")
	assert_eq(rules, before, "so nothing may move")


# ── shape preservation ────────────────────────────────────────────────────────

func test_the_specific_rules_keep_their_relative_order() -> void:
	## Order IS the strategy — "rules are numbered because first match wins".
	## The repair may only move catch-alls; it must not resort the rest.
	var rules: Array = [_always(), _rule(_hp("<", 20), "cure"),
		_rule(_hp("<", 50), "protect"), _rule(_hp("<", 80), "esuna")]
	_rc()._sink_unconditional_rules(rules)
	var ids: Array[String] = []
	for r in rules:
		var a: Dictionary = (r["actions"][0] as Dictionary)
		ids.append(str(a.get("id", a.get("type", ""))))
	assert_eq(ids, (["cure", "protect", "esuna", "attack"] as Array[String]),
		"specific rules keep their authored order; only the catch-all moves")


func test_two_catch_alls_both_sink_and_keep_their_own_order() -> void:
	var first_ca: Dictionary = _always()
	first_ca["actions"] = [{"type": "defer"}]
	var rules: Array = [first_ca, _rule(_hp("<", 30), "cure"), _always()]
	_rc()._sink_unconditional_rules(rules)
	assert_eq(str((rules[0]["actions"][0] as Dictionary).get("id", "")), "cure",
		"the specific rule rises to the top")
	assert_eq(str((rules[1]["actions"][0] as Dictionary).get("type", "")), "defer",
		"and the two catch-alls keep the order the model gave them")


func test_a_lone_catch_all_is_not_disturbed() -> void:
	## CONTROL: a single always-rule is a complete, valid strategy.
	var rules: Array = [_always()]
	assert_eq(_rc()._sink_unconditional_rules(rules).size(), 0, "one rule shadows nothing")
	assert_eq(rules.size(), 1, "and must survive")


# ── a rule with NO conditions is a catch-all too ──────────────────────────────
#
# Found by measuring the AUTOGRIND domain, which I had never sampled: llama3
# emitted {} -> stop_grinding + flee_battle. Both engines treat an absent or empty
# condition list as a match, so that rule fires every turn — and the first version
# of this repair read it as "not a catch-all" and left it shadowing.

func test_a_rule_with_no_conditions_is_sunk() -> void:
	var no_conds: Dictionary = {"conditions": [], "actions": [{"type": "stop_grinding"}], "enabled": true}
	var rules: Array = [no_conds, _rule(_hp("<", 30), "cure")]
	var notes: Array = _rc()._sink_unconditional_rules(rules)
	assert_eq(str((rules[0]["actions"][0] as Dictionary).get("id", "")), "cure",
		"an empty condition list matches every turn, so it must not run first")
	assert_eq(notes.size(), 1, "and the player must be told a rule was unreachable")


func test_a_rule_MISSING_its_conditions_key_is_sunk_too() -> void:
	## `rule.get("conditions", [])` yields [] for an absent key, and
	## AutobattleSystem checks `not rule.has("conditions")` explicitly.
	var absent: Dictionary = {"actions": [{"type": "attack"}], "enabled": true}
	var rules: Array = [absent, _rule(_hp("<", 30), "cure")]
	_rc()._sink_unconditional_rules(rules)
	assert_true(rules[0].has("conditions"),
		"the conditioned rule must rise above the unconditioned one")


func test_an_empty_conditions_rule_already_last_stays_silent() -> void:
	## CORRECT-WORK, same as the always-form: last is where it belongs.
	var no_conds: Dictionary = {"conditions": [], "actions": [{"type": "stop_grinding"}], "enabled": true}
	var rules: Array = [_rule(_hp("<", 30), "cure"), no_conds]
	var before: Array = rules.duplicate(true)
	assert_eq(_rc()._sink_unconditional_rules(rules).size(), 0, "nothing shadowed, nothing reported")
	assert_eq(rules, before, "and nothing moved")


func test_both_engines_really_treat_no_conditions_as_always() -> void:
	## THE PREMISE. This repair is only correct because the evaluators match an
	## empty condition list. If either engine ever gates it instead, sinking
	## becomes wrong and this must be revisited rather than worked around.
	var ab_raw: String = FileAccess.get_file_as_string("res://src/autobattle/AutobattleSystem.gd")
	var ag_raw: String = FileAccess.get_file_as_string("res://src/autogrind/AutogrindSystem.gd")
	assert_false(ab_raw.is_empty() or ag_raw.is_empty(), "CONTROL: both sources must load")
	## Dropping docstring lines is safe only while neither file ASSIGNS a
	## triple-quoted region — an assigned one is shipping content (DialoguePrompts
	## keeps its two grammar constants that way), and dropping its lines would
	## delete the subject instead of prose. Measured 0 and 0; this keeps it true.
	assert_eq(_assigned_triple_quotes(ab_raw), 0,
		"AutobattleSystem now assigns a triple-quoted region — the strip below would eat content")
	assert_eq(_assigned_triple_quotes(ag_raw), 0,
		"AutogrindSystem now assigns a triple-quoted region — the strip below would eat content")
	var ab: String = _code_only(ab_raw)
	var ag: String = _code_only(ag_raw)
	## ANTI-VACUITY: both files are heavily commented (92 and 112 triple-quoted
	## lines), so the strip must remove something. A stripper with nothing to strip
	## is not evidence that the assert stands on code.
	assert_lt(ab.length(), ab_raw.length(), "nothing was stripped from AutobattleSystem")
	assert_lt(ag.length(), ag_raw.length(), "nothing was stripped from AutogrindSystem")
	assert_true(ab.contains("rule[\"conditions\"].size() == 0"),
		"AutobattleSystem must still branch on an empty condition list")
	assert_true(ag.contains("conditions.size() == 0"),
		"AutogrindSystem must still branch on an empty condition list")


# ── the repair must be REACHED, not merely correct ────────────────────────────

## Strip `#` comments — and so `##` docstrings — plus any line carrying a
## triple-quoted delimiter, so a source assert cannot be satisfied by prose. The
## triple-quote half is guarded by _assigned_triple_quotes at the call site: it is
## safe only where every such region is documentation rather than content.
func _code_only(src: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	for line in src.split("\n"):
		if line.find("\"\"\"") != -1:
			continue
		var hash_at: int = line.find("#")
		out.append(line if hash_at == -1 else line.substr(0, hash_at))
	return "\n".join(out)


func test_compose_async_actually_runs_the_sink() -> void:
	## EXECUTION IS NOT SELECTION. Every assert above calls the helper directly, so
	## deleting its call site in compose_async would leave them all green while the
	## repair never ran on a real composition.
	var src: String = _code_only(FileAccess.get_file_as_string("res://src/llm/RuleComposer.gd"))
	assert_false(src.is_empty(), "CONTROL: source must load")
	assert_true(src.contains("_sink_unconditional_rules(v[\"rules\"])"),
		"compose_async must run the sink on the validated rules")


func test_the_sink_runs_after_the_other_repairs() -> void:
	## Order matters: _drop_unusable_rules can REMOVE the specific rules that made a
	## catch-all shadowing. Sinking first would then reorder against a rule set that
	## no longer exists, and report a count for rules the player never sees.
	var src: String = _code_only(FileAccess.get_file_as_string("res://src/llm/RuleComposer.gd"))
	var drop_at: int = src.find("_drop_unusable_rules(v[\"rules\"]")
	var sink_at: int = src.find("_sink_unconditional_rules(v[\"rules\"])")
	assert_true(drop_at != -1 and sink_at != -1, "CONTROL: both call sites must be present")
	assert_true(sink_at > drop_at, "the sink must run last, on whatever the other repairs left")


func test_an_empty_ruleset_is_handled() -> void:
	var rules: Array = []
	assert_eq(_rc()._sink_unconditional_rules(rules).size(), 0, "nothing to do")
	assert_eq(rules.size(), 0, "and nothing invented")


func test_the_assigned_region_detector_can_fire() -> void:
	## POSITIVE CONTROL. The two zeros above are worth nothing unless the same
	## detector reports non-zero on a case already known to have one:
	## DialoguePrompts keeps AUTOBATTLE_GRAMMAR_DESCRIPTION and
	## AUTOGRIND_GRAMMAR_DESCRIPTION as assigned triple-quoted regions — shipping
	## prompt text, not documentation. Asserted as "more than zero" rather than a
	## count, so a third grammar constant is a correct change and not a red.
	var dp: String = FileAccess.get_file_as_string("res://src/llm/DialoguePrompts.gd")
	assert_false(dp.is_empty(), "CONTROL: DialoguePrompts must load")
	assert_gt(_assigned_triple_quotes(dp), 0,
		"the detector cannot report non-zero anywhere, so its zeros above mean nothing")


## Triple-quoted regions ASSIGNED to something — a const, a dict value, an
## argument. Those carry shipping content; free-standing ones are documentation.
## "docstring" is a per-file property, not a language fact.
func _assigned_triple_quotes(src: String) -> int:
	var n: int = 0
	for line in src.split("\n"):
		var at: int = line.find("\"\"\"")
		if at == -1:
			continue
		var before: String = line.substr(0, at).strip_edges()
		if before.ends_with("=") or before.ends_with(":") or before.ends_with("(") or before.ends_with(","):
			n += 1
	return n
