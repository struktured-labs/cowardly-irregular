extends GutTest

## The LLM Rule Composer told the model a rule holds four actions. It holds five.
##
## Full Bank raised the bank to five actions at +4 AP, and
## `test_a_five_action_rule_survives_the_whole_chain` pinned the fifth slot across the four
## surfaces it crosses — grid editor, validation, share codec, execution. The composer is a
## FIFTH surface that list never included, and it carried its own cap in prose:
##
##     AutobattleGridEditor.MAX_ACTIONS     5
##     BattleManager.FULL_BANK_ACTIONS      5
##     AUTOBATTLE_GRAMMAR_DESCRIPTION       "Actions (executed in order, up to 4 per rule)"
##
## Nothing in validation or in the composer's repair passes caps actions — measured, no cap
## exists in AutobattleSystem, RuleComposer or DialoguePrompts — so that one sentence was the
## ONLY thing keeping an LLM-composed rule at four. A player who asks the composer for a
## full-bank opener gets a rule that can never reach the bank the grid editor offers.
##
## The grammar now says five, and says what the chain actually does with a fifth: it fires
## only at a full bank, and below that the rule is cut to its first four, not rejected
## (BattleManager._apply_full_bank_rule slices to ADVANCE_CAP). That last half matters to a
## model more than the number does — without it, "put the heal fifth" reads as safe.
##
## Every number below is read from the live constants, and every assertion is EQUALITY, per
## the existing pin's own lesson: an inequality let a six-slot editor pass while the bank kept
## five. If the bank changes, this reds until the grammar follows.

const GridEditor = preload("res://src/ui/autobattle/AutobattleGridEditor.gd")
const BattleManagerScript = preload("res://src/battle/BattleManager.gd")
const DP := preload("res://src/llm/DialoguePrompts.gd")


func before_each() -> void:
	AutobattleSystem._test_disable_persistence = true


func _grammar() -> String:
	return DP.AUTOBATTLE_GRAMMAR_DESCRIPTION


func _first_int(pattern: String) -> int:
	var re := RegEx.new()
	re.compile(pattern)
	var m := re.search(_grammar())
	return int(m.get_string(1)) if m != null else -1


# ── the defect ────────────────────────────────────────────────────────────────

func test_the_grammar_offers_exactly_what_a_full_bank_spends() -> void:
	## THE ARM. It said "up to 4 per rule" while the editor and the bank both said 5.
	var told: int = _first_int("up to (\\d+) per rule")
	assert_ne(told, -1, "CONTROL: the grammar must still state a per-rule action cap")
	assert_eq(told, BattleManagerScript.FULL_BANK_ACTIONS,
		("the composer tells the model a rule holds %d actions; a full bank spends %d. An "
		+ "LLM-composed rule can never reach the bank the grid editor offers.")
		% [told, BattleManagerScript.FULL_BANK_ACTIONS])
	assert_eq(told, GridEditor.MAX_ACTIONS,
		"and the grid editor offers %d — the composer and the editor must agree" % GridEditor.MAX_ACTIONS)


func test_the_grammar_states_what_happens_to_the_fifth_below_a_full_bank() -> void:
	## A model told only "up to 5" will happily put the heal fifth. The chain trims to
	## ADVANCE_CAP below FULL_BANK_AP, so the grammar must say both numbers, and say them right.
	assert_eq(_first_int("AP \\+(\\d+)"), BattleManagerScript.FULL_BANK_AP,
		"the grammar must name the full-bank AP threshold the engine uses")
	assert_eq(_first_int("first (\\d+) actions"), BattleManagerScript.ADVANCE_CAP,
		"and the size a rule is cut to below it, which is ADVANCE_CAP")
	assert_true(_grammar().contains("not rejected"),
		"and that the rule is trimmed rather than refused — a model that expects refusal writes differently")


func test_the_recommended_condition_is_real_vocabulary_at_the_real_threshold() -> void:
	## The grammar recommends a condition for rules whose fifth action matters. A condition the
	## validator rejects would, per this same grammar, discard the whole rule set.
	var re := RegEx.new()
	re.compile("\\{\"type\":\"ap\"[^}]*\\}")
	var m := re.search(_grammar())
	assert_not_null(m, "the grammar must still show the full-bank condition example")
	if m == null:
		return
	var cond: Variant = JSON.parse_string(m.get_string())
	assert_true(cond is Dictionary, "the example must be valid JSON: %s" % m.get_string())
	var d: Dictionary = cond as Dictionary
	assert_eq(int(d.get("value", -1)), BattleManagerScript.FULL_BANK_AP,
		"the example must gate at the engine's full-bank AP, not a remembered number")
	var actions: Array = []
	for i in BattleManagerScript.FULL_BANK_ACTIONS:
		actions.append({"type": "attack"})
	var errors: Array = AutobattleSystem.validate_rule({"conditions": [d], "actions": actions})
	assert_eq(errors.size(), 0, "a five-action rule gated by the example must validate: %s" % str(errors))


# ── the composer's own passes must not quietly reinstate the old cap ──────────

func test_the_composers_repair_passes_keep_all_five() -> void:
	## The prompt was the cap; this pins that nothing downstream of the model became one.
	var rc: Node = get_tree().root.get_node_or_null("RuleComposer")
	assert_not_null(rc, "CONTROL: RuleComposer autoload must exist")
	if rc == null:
		return
	var actions: Array = []
	for i in BattleManagerScript.FULL_BANK_ACTIONS:
		actions.append({"type": "attack", "target": "lowest_hp_enemy"})
	var rules: Array = [{"conditions": [{"type": "always"}], "actions": actions, "enabled": true}]
	rc._drop_null_targets(rules)
	rc._repair_weakness_elements(rules)
	rc._sink_unconditional_rules(rules)
	assert_eq(((rules[0] as Dictionary)["actions"] as Array).size(), BattleManagerScript.FULL_BANK_ACTIONS,
		"a composed five-action rule must leave the composer's passes with five actions")


# ── controls ──────────────────────────────────────────────────────────────────

func test_the_grammar_really_loaded() -> void:
	## CONTROL: every arm reads one constant. An empty grammar would fail them for the wrong reason.
	assert_gt(_grammar().length(), 500, "the autobattle grammar must be the real text")
	assert_true(_grammar().contains("Actions (executed in order"), "and still carry its Actions section")
