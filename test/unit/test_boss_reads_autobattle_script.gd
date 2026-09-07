extends GutTest

## The boss-intent prompt used to receive the player's automation as raw JSON,
## for slot 0 only. These pin the readable rendering, the multi-PC context field,
## and the to_dict hop — without which the whole feature is a silent no-op.

const FIGHTER_RULES: Array = [
	{
		"conditions": [
			{"type": "has_status", "status": "poison"},
			{"type": "item_count", "item_id": "antidote", "op": ">", "value": 0},
		],
		"actions": [{"type": "item", "id": "antidote", "target": "self"}],
	},
	{
		"conditions": [{"type": "hp_percent", "op": "<", "value": 50}],
		"actions": [{"type": "item", "id": "potion", "target": "self"}],
	},
	{
		"conditions": [{"type": "always"}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}],
	},
]


func _abs() -> Node:
	return get_tree().root.get_node_or_null("AutobattleSystem") if get_tree() else null


func test_rule_renders_as_readable_strategy_not_json() -> void:
	var a: Node = _abs()
	if a == null:
		fail_test("AutobattleSystem autoload missing — this test cannot be vacuous")
		return
	var text: String = a.describe_rule_for_llm(FIGHTER_RULES[1])
	assert_string_contains(text, "IF ", "a rule must read as a conditional")
	assert_string_contains(text, "THEN ", "a rule must name its action")
	# The label comes from CONDITION_TYPES so the prose cannot drift from the editor.
	assert_string_contains(text, "Self HP %", "condition should use the editor's own label")
	assert_string_contains(text, "< 50", "threshold must survive rendering")
	assert_false(text.contains("hp_percent"), "raw key should not leak into the prose")


func test_always_condition_reads_as_always() -> void:
	var a: Node = _abs()
	if a == null:
		fail_test("AutobattleSystem autoload missing")
		return
	assert_string_contains(a.describe_rule_for_llm(FIGHTER_RULES[2]), "IF ALWAYS THEN",
		"the catch-all rule is the most strategically legible one; it must not render blank")


func test_subject_bearing_condition_keeps_its_subject() -> void:
	var a: Node = _abs()
	if a == null:
		fail_test("AutobattleSystem autoload missing")
		return
	var text: String = a.describe_rule_for_llm(FIGHTER_RULES[0])
	assert_string_contains(text, "poison", "has_status must name WHICH status")
	assert_string_contains(text, "antidote", "item_count must name WHICH item")


func test_priority_order_is_numbered_because_first_match_wins() -> void:
	var a: Node = _abs()
	if a == null:
		fail_test("AutobattleSystem autoload missing")
		return
	var text: String = a.describe_rules_for_llm(FIGHTER_RULES, 6)
	assert_string_contains(text, "1. ", "ordering IS the strategy — it must be visible")
	assert_string_contains(text, "3. ", "all rules within budget should be numbered")
	assert_lt(text.find("1. "), text.find("3. "), "rules must render in evaluation order")


func test_truncation_is_announced_never_silent() -> void:
	var a: Node = _abs()
	if a == null:
		fail_test("AutobattleSystem autoload missing")
		return
	var text: String = a.describe_rules_for_llm(FIGHTER_RULES, 1)
	assert_string_contains(text, "1. ", "the kept rule still renders")
	assert_string_contains(text, "+2 further rules",
		"a silently truncated script reads to the model as the WHOLE strategy")


func test_empty_rules_render_empty_not_a_stub() -> void:
	var a: Node = _abs()
	if a == null:
		fail_test("AutobattleSystem autoload missing")
		return
	assert_eq(a.describe_rules_for_llm([], 6), "",
		"no rules must yield no block, so the prompt omits the section entirely")


func test_context_carries_party_scripts_through_to_dict() -> void:
	# Without this hop the prompt reads a Dictionary that never had the key.
	var ctx := BossIntentContext.new()
	ctx.party_scripts = [{"name": "Rook", "job_id": "fighter", "rules": "1. IF ALWAYS THEN attack"}]
	var d: Dictionary = ctx.to_dict()
	assert_true(d.has("party_scripts"), "to_dict must carry party_scripts or the feature is inert")
	assert_eq((d["party_scripts"] as Array).size(), 1, "the entry must survive serialization")


func test_context_object_reaches_the_prompt_end_to_end() -> void:
	# The hand-built-Dictionary tests below bypass to_dict entirely; without this
	# one, breaking that hop leaves the prompt tests green and the feature dead.
	var ctx := BossIntentContext.new()
	ctx.persona = "A tired auditor."
	ctx.available_intents = ["aggress"]
	ctx.party_scripts = [{"name": "Rook", "job_id": "fighter", "rules": "1. IF Self HP % < 50 THEN item potion"}]
	var prompt: String = DialoguePrompts.build_boss_intent("The Calibrant", ctx.to_dict())
	assert_string_contains(prompt, "Rook",
		"a real context object must carry the script all the way into the prompt")
	assert_string_contains(prompt, "IF Self HP % < 50", "the rule text must survive the to_dict hop")


func test_prompt_renders_the_script_when_present() -> void:
	var ctx: Dictionary = {
		"persona": "A tired auditor.",
		"available_intents": ["aggress"],
		"party_scripts": [{"name": "Rook", "job_id": "fighter", "rules": "1. IF Self HP % < 50 THEN item potion"}],
	}
	var prompt: String = DialoguePrompts.build_boss_intent("The Calibrant", ctx)
	assert_string_contains(prompt, "Rook", "the boss must be told whose script it is")
	assert_string_contains(prompt, "IF Self HP % < 50", "the authored rule must reach the model")
	assert_string_contains(prompt, "FIRST rule whose conditions",
		"the model must know evaluation is top-down or it cannot find the gap")


func test_prompt_falls_back_to_lead_pc_json_when_no_scripts() -> void:
	# Back-compat: the older single-PC path must still emit rather than go silent.
	var ctx: Dictionary = {
		"persona": "A tired auditor.",
		"available_intents": ["aggress"],
		"player_lead_pc_rules": [{"type": "hp_percent"}],
		"party_scripts": [],
	}
	var prompt: String = DialoguePrompts.build_boss_intent("The Calibrant", ctx)
	assert_string_contains(prompt, "autobattle strategy", "the legacy block must still fire")


func test_prompt_omits_the_section_entirely_for_a_manual_party() -> void:
	var ctx: Dictionary = {"persona": "A tired auditor.", "available_intents": ["aggress"]}
	var prompt: String = DialoguePrompts.build_boss_intent("The Calibrant", ctx)
	assert_false(prompt.contains("HAS WRITTEN THE PARTY'S BEHAVIOUR"),
		"a hand-played party must not be described as automated")
