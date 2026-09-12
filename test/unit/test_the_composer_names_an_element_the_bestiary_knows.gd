extends GutTest

## The player asked for "only cast a spell when they're weak to it" and got a rule
## that can never fire.
##
## `enemy_weak_to` (shipped in .319) matches `element in enemy.elemental_weaknesses`
## — a case-sensitive compare against the bestiary's own words. `validate_rule`
## checks the field is PRESENT and never what it says. `weather` is the one payload
## with a vocabulary check, and its own comment gives the reason:
##
##     "Weather values validate against the flat vocabulary so an LLM-composed or
##      hand-typed bad value fails at decode, not silently-never-fires in battle."
##
## An element does neither. Driven against the real validator:
##
##     element "thunder"  (an ability, not an element)   0 errors
##     element "blizzard"                                 0 errors
##     element "Fire"     (wrong case)                    0 errors
##     element "shadow"   (invented)                      0 errors
##     element MISSING    <- CONTROL, this one IS checked 1 error
##     weather "blizzardy" <- CONTROL, weather IS checked 1 error
##
## MEASURED against live llama3 on the real composer prompt, four weakness intents,
## 48 compositions: 36 `enemy_weak_to` conditions — 35 valid and ONE naming the
## ability instead of the element:
##
##     {"type":"enemy_weak_to","element":"thunder"}
##     beside {"type":"ability","id":"thunder","target":"weakest_to_ability"}
##
## `thunder`'s element is `lightning`. The rule is dead, the grid reads "Enemy weak
## to Thunder", and nothing anywhere says otherwise. **The kit invites it: two of
## the mage's three spells are named for something other than the element they deal
## — blizzard/ice, thunder/lightning.**
##
## 1 in 36 is a low rate and the prompt already lists the valid elements, which is
## the point: more prompt text is not the repair for an instruction the model
## already has. This one MAPS instead — the model named a real ability and the
## ability knows its element, so the rule the player asked for is recoverable.

const RC := preload("res://src/llm/RuleComposer.gd")

## Every word monsters.json actually uses as a weakness.
const WEAKNESS_WORDS: Array[String] = ["fire", "holy", "lightning", "ice",
	"physical", "dark", "water"]


func _rc():
	var c = RC.new()
	if c is Node:
		add_child_autofree(c)
	return c


func _rule(element: String) -> Dictionary:
	return {"conditions": [{"type": "enemy_weak_to", "element": element}],
		"actions": [{"type": "ability", "id": "thunder"}], "enabled": true}


func _element_of(rules: Array) -> String:
	return str(((rules[0]["conditions"][0]) as Dictionary).get("element", ""))


# ── the defect ────────────────────────────────────────────────────────────────

func test_an_ability_named_as_an_element_is_read_as_its_element() -> void:
	## THE ARM — the exact composition live llama3 produced.
	var rules: Array = [_rule("thunder")]
	var notes: Array = _rc()._repair_weakness_elements(rules)
	assert_eq(_element_of(rules), "lightning",
		"'thunder' is an ability whose element is lightning; as an element it matches nothing")
	assert_eq(notes.size(), 1, "the player must be told the rule was changed")
	assert_true(str(notes[0]).find("lightning") != -1,
		"and the note must name what it became: %s" % str(notes[0]))


func test_the_other_spell_named_for_something_else_is_repaired_too() -> void:
	## blizzard/ice is the same trap and the mage carries both.
	var rules: Array = [_rule("blizzard")]
	_rc()._repair_weakness_elements(rules)
	assert_eq(_element_of(rules), "ice", "'blizzard' deals ice")


func test_the_repair_reaches_a_composition_not_just_the_helper() -> void:
	## EXECUTION IS NOT SELECTION. Every arm here calls the helper directly, so
	## deleting its call site would leave them green while no composition was ever
	## repaired — and it must run BEFORE the grammar check that judges the result.
	var src: String = _code_only(FileAccess.get_file_as_string("res://src/llm/RuleComposer.gd"))
	assert_false(src.is_empty(), "CONTROL: source must load")
	var call_at: int = src.find("_repair_weakness_elements(v[\"rules\"])")
	assert_true(call_at != -1, "compose_async must run the repair on the validated rules")
	var check_at: int = src.find("has_method(\"validate_rule\")")
	assert_true(check_at != -1, "CONTROL: the grammar check must still exist")
	assert_true(call_at < check_at,
		"the repair must run before the grammar check, or it judges the unrepaired rule")


# ── the premise: the validator really does wave these through ─────────────────

func test_the_validator_does_not_check_the_element_today() -> void:
	## THE PREMISE, observed rather than asserted. If battle ever gives the element
	## a vocabulary check like weather's, this repair becomes belt-and-braces and
	## this file should be re-read rather than worked around.
	var abs_sys = get_tree().root.get_node_or_null("AutobattleSystem")
	assert_not_null(abs_sys, "CONTROL: AutobattleSystem autoload must exist")
	if abs_sys == null:
		return
	for bad in ["thunder", "blizzard", "shadow"]:
		assert_eq(abs_sys.validate_rule(_rule(bad), "").size(), 0,
			("validate_rule rejects element '%s' now, so RuleComposer._repair_weakness_elements is no longer "
			+ "the only thing between a model-named ability and a dead rule. If AutobattleSystem gained an "
			+ "element vocabulary check, that is GOOD: re-read this file's header, then either delete the "
			+ "repair as superseded or keep it and change this arm to assert the new rejection.") % bad)
	## POSITIVE CONTROL: the same probe must be able to report an error, or the
	## zeros above mean nothing.
	var missing: Dictionary = {"conditions": [{"type": "enemy_weak_to"}],
		"actions": [{"type": "attack"}], "enabled": true}
	assert_gt(abs_sys.validate_rule(missing, "").size(), 0,
		"CONTROL: a MISSING element is checked — if this passes too, the probe is broken")


func test_the_ability_data_really_says_what_the_repair_claims() -> void:
	## CONTROL: the mapping is read from the game's data, not invented here. A
	## fixture asserting thunder->lightning against a hand-written map would pass
	## while the repair read something else.
	var job_sys = get_tree().root.get_node_or_null("JobSystem")
	assert_not_null(job_sys, "CONTROL: JobSystem autoload must exist")
	if job_sys == null:
		return
	assert_eq(str((job_sys.get_ability("thunder") as Dictionary).get("element", "")), "lightning",
		"the repair's whole basis is that the ability knows its element")
	assert_eq(str((job_sys.get_ability("blizzard") as Dictionary).get("element", "")), "ice")


# ── it must not touch a real element ──────────────────────────────────────────

func test_every_real_weakness_word_is_left_alone_and_silent() -> void:
	## CORRECT-WORK. A note on a correct composition is how a repair gets distrusted.
	var touched: Array[String] = []
	for word in WEAKNESS_WORDS:
		var rules: Array = [_rule(word)]
		var notes: Array = _rc()._repair_weakness_elements(rules)
		if _element_of(rules) != word or notes.size() != 0:
			touched.append("%s -> %s (%d notes)" % [word, _element_of(rules), notes.size()])
	assert_eq(touched, ([] as Array[String]),
		"real weakness words must pass through untouched: %s" % ", ".join(touched))


func test_fire_is_both_an_ability_and_an_element_and_maps_to_itself() -> void:
	## THE COLLISION, called out because it is the one word where the repair's own
	## lookup succeeds on a correct input. It resolves to the same string, so the
	## rule is unchanged and the player is told nothing.
	var rules: Array = [_rule("fire")]
	var notes: Array = _rc()._repair_weakness_elements(rules)
	assert_eq(_element_of(rules), "fire", "fire's element is fire")
	assert_eq(notes.size(), 0, "a no-op must not announce itself")


func test_an_element_nothing_is_weak_to_is_left_alone() -> void:
	## The grammar promises exactly this: "An element nothing is weak to simply
	## never fires." poison and earth are real ability elements with no monster
	## weak to them, and rewriting them would be inventing intent.
	for inert in ["poison", "earth", "wind"]:
		var rules: Array = [_rule(inert)]
		var notes: Array = _rc()._repair_weakness_elements(rules)
		assert_eq(_element_of(rules), inert, "'%s' must survive as written" % inert)
		assert_eq(notes.size(), 0, "'%s' needs no note" % inert)


func test_a_word_that_is_neither_is_left_alone() -> void:
	## CONTROL on the repair's own limit: it maps, it does not guess. "shadow" is
	## not an ability, so nothing here knows the player meant dark.
	var rules: Array = [_rule("shadow")]
	assert_eq(_rc()._repair_weakness_elements(rules).size(), 0, "no guess, no note")
	assert_eq(_element_of(rules), "shadow", "and no silent rewrite")


# ── free, and unmeasured, and said so ─────────────────────────────────────────

func test_case_is_normalised() -> void:
	## NOT measured — 0 of 36 samples came back miscased. It is free and the compare
	## that reads this value is case-sensitive, so "Fire" would never fire.
	var rules: Array = [_rule("Fire")]
	_rc()._repair_weakness_elements(rules)
	assert_eq(_element_of(rules), "fire", "the bestiary stores every weakness lowercase")


func test_a_miscased_ability_name_is_still_read_as_its_element() -> void:
	var rules: Array = [_rule("Thunder")]
	_rc()._repair_weakness_elements(rules)
	assert_eq(_element_of(rules), "lightning", "both repairs must compose")


# ── shape ─────────────────────────────────────────────────────────────────────

func test_other_conditions_are_not_disturbed() -> void:
	var rules: Array = [{"conditions": [{"type": "hp_percent", "op": "<", "value": 30},
		{"type": "enemy_weak_to", "element": "thunder"}],
		"actions": [{"type": "ability", "id": "thunder"}], "enabled": true}]
	var before: Dictionary = (rules[0]["conditions"][0] as Dictionary).duplicate(true)
	_rc()._repair_weakness_elements(rules)
	assert_eq(rules[0]["conditions"][0], before, "an unrelated condition must be untouched")
	assert_eq(str((rules[0]["conditions"][1] as Dictionary).get("element", "")), "lightning",
		"and the weakness condition still repaired beside it")


func test_an_empty_ruleset_is_handled() -> void:
	var rules: Array = []
	assert_eq(_rc()._repair_weakness_elements(rules).size(), 0, "nothing to do")
	assert_eq(rules.size(), 0, "and nothing invented")


func _code_only(src: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	for line in src.split("\n"):
		var hash_at: int = line.find("#")
		out.append(line if hash_at == -1 else line.substr(0, hash_at))
	return "\n".join(out)
