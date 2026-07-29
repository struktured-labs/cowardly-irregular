extends GutTest

## The grammar the LLM is handed must match the conditions the game can evaluate.
##
## THE TWO SOURCES: `DialoguePrompts.AUTOBATTLE_GRAMMAR_DESCRIPTION` is a
## hand-written list of condition verbs sent to the model; `AutobattleSystem.
## _evaluate_grid_condition` is a match statement that actually implements them.
## Nothing connected them, and they had drifted.
##
## FOUND LIVE (cowir-ai, 2026-07-29): `has_buff` and `not_has_buff` were
## implemented, validated, and used by the SHIPPED presets — and the grammar
## never mentioned them, so the Rule Composer could not produce them. "Buff only
## when the buff isn't already up" is one of the most common autobattle patterns
## and the game's own templates use it; a player asking the composer for it got
## something else.
##
## BOTH DIRECTIONS FAIL DIFFERENTLY, so both are asserted:
##   advertised but NOT implemented -> AutobattleSystem.validate_rule rejects the
##     composition, RuleComposer emits grammar_errors and falls back to the empty
##     draft. The player asked for a strategy and got "Draft — LLM unavailable"
##     with no indication the verb was the problem.
##   implemented but NOT advertised -> the capability is simply unreachable from
##     the composer. Silent, permanent, and invisible in every test that only
##     exercises verbs the grammar already lists. This is the one that bit.
##
## DERIVED, NOT LISTED. The implemented set is parsed out of the evaluator's own
## match arms and the advertised set out of the prompt constant, so adding a
## condition to AutobattleSystem fails this test until the model is told about
## it. There is no third list here to fall out of date — RuleComposer delegates
## validation to AutobattleSystem itself, which is why an unimplemented verb
## fails loudly rather than fizzling.

const DP := preload("res://src/llm/DialoguePrompts.gd")
const EVALUATOR_PATH: String = "res://src/autobattle/AutobattleSystem.gd"
const EVALUATOR_FUNC: String = "func _evaluate_grid_condition"


## Condition types the evaluator actually implements, from its own match arms.
func _implemented() -> Array:
	var src: String = FileAccess.get_file_as_string(EVALUATOR_PATH)
	assert_false(src.is_empty(), "AutobattleSystem must be readable")
	var start: int = src.find(EVALUATOR_FUNC)
	assert_gt(start, -1,
		"%s not found — if it was renamed this ratchet is measuring nothing" % EVALUATOR_FUNC)
	if start == -1:
		return []
	var end: int = src.find("\nfunc ", start + 1)
	if end == -1:
		end = src.length()
	var out: Array = []
	var re := RegEx.new()
	re.compile('^\\t\\t"([a-z_]+)":\\s*$')
	for line in src.substr(start, end - start).split("\n"):
		var m: RegExMatch = re.search(line)
		if m != null and not out.has(m.get_string(1)):
			out.append(m.get_string(1))
	return out


## Condition types the prompt advertises, from the type-list section only.
func _advertised() -> Array:
	var g: String = DP.AUTOBATTLE_GRAMMAR_DESCRIPTION
	var head: String = "type is one of:"
	var start: int = g.find(head)
	assert_gt(start, -1, "the grammar must still enumerate condition types")
	if start == -1:
		return []
	var stop: int = g.find("Each numeric condition", start)
	if stop == -1:
		stop = g.length()
	var out: Array = []
	var re := RegEx.new()
	re.compile("[a-z_]{2,}")
	for m in re.search_all(g.substr(start + head.length(), stop - start - head.length())):
		var v: String = m.get_string(0)
		if not out.has(v):
			out.append(v)
	return out


# ── Positive controls — a vacuous pass must be impossible ────────────────────

func test_evaluator_arms_are_actually_parsed() -> void:
	var impl: Array = _implemented()
	assert_gt(impl.size(), 8,
		"parsed only %d evaluator arms — the parse has broken, so agreement would prove nothing" % impl.size())
	assert_true(impl.has("hp_percent"),
		"hp_percent is the most basic condition in the game; not finding it means the parse is wrong, not the code")


func test_advertised_types_are_actually_parsed() -> void:
	var adv: Array = _advertised()
	assert_gt(adv.size(), 8,
		"parsed only %d advertised types — the grammar section markers have moved" % adv.size())
	assert_true(adv.has("hp_percent"), "the grammar must still advertise hp_percent")


# ── The guard, both directions ───────────────────────────────────────────────

func test_every_advertised_condition_is_implemented() -> void:
	var impl: Array = _implemented()
	for verb in _advertised():
		assert_true(impl.has(verb),
			("the prompt tells the LLM it may use condition '%s', but _evaluate_grid_condition has no arm " +
			"for it. AutobattleSystem.validate_rule will reject any composition using it, so the player's " +
			"request silently resolves to the empty fallback draft. Implemented: %s")
			% [verb, str(impl)])


func test_every_implemented_condition_is_advertised() -> void:
	var adv: Array = _advertised()
	for verb in _implemented():
		assert_true(adv.has(verb),
			("_evaluate_grid_condition implements condition '%s' and the grammar never mentions it, so the " +
			"Rule Composer can NEVER produce it — the capability is unreachable from the LLM path and no " +
			"test that only uses advertised verbs would notice. Add it to " +
			"DialoguePrompts.AUTOBATTLE_GRAMMAR_DESCRIPTION. Advertised: %s")
			% [verb, str(adv)])


func test_buff_conditions_reach_the_composer() -> void:
	# The specific regression. These shipped in the built-in presets while the
	# grammar omitted them, so "buff only when it isn't already up" — the reason
	# not_has_buff exists — was unreachable from a composed rule.
	var adv: Array = _advertised()
	for verb in ["has_buff", "not_has_buff"]:
		assert_true(adv.has(verb),
			"'%s' is implemented and used by the shipped rule templates; the composer must be able to emit it" % verb)
	assert_true(DP.AUTOBATTLE_GRAMMAR_DESCRIPTION.find("stat") != -1,
		"the grammar must document the 'stat' field, or the LLM will emit buff conditions with op/value and they will not match")
