extends GutTest

## The composer's kit block says "Ability ids you may use, and NOTHING else", and it
## already warns that the worked examples carry ids to demonstrate shape. It sits about
## 1.1k characters before the output spec, with the whole grammar in between — and the
## model kept spending a rule on `esuna`, an id that appears in the examples.
##
## Restating the ids immediately before the answer, measured on live llama3 with the
## mage's real prompt, 24 samples per arm:
##
##   as shipped          8 off-kit ability rules (every one `esuna`)
##   kit restated here   1
##
## Unparsed replies ran 0-8% in BOTH arms — the single failure was a malformed nested
## quote inside rules_json, not truncation — so this claims nothing about that.
##
## The reminder is DERIVED from the same kit_context the earlier block reads. A second
## copy of the ids is the drift shape this codebase fixed three times today.

const DP := preload("res://src/llm/DialoguePrompts.gd")


func _kit(job_id: String, ids: Array, costs: Dictionary = {}) -> Dictionary:
	return {"resolved": true, "job_id": job_id, "kit": ids, "full_kit": ids,
			"max_mp": 70, "costs": costs}


func test_the_ids_are_restated_after_the_players_intent() -> void:
	var p: String = DP.build_rule_composition(
		"autobattle", "hit weaknesses with magic", [], _kit("mage", ["fire", "blizzard", "channel"]))
	var at: int = p.find("Before you answer: this character knows ONLY these ability ids")
	assert_gt(at, -1, "the reminder must be present for an autobattle composition")
	for id in ["fire", "blizzard", "channel"]:
		assert_true(p.substr(at).find(id) != -1, "it must name %s" % id)


func test_it_sits_between_the_intent_and_the_output_spec() -> void:
	## Position IS the mechanism — the earlier block already says the same thing in
	## stronger words. If a later edit moves this above the grammar it stops being
	## this change, so the ordering is pinned rather than the presence.
	var p: String = DP.build_rule_composition(
		"autobattle", "burn things", [], _kit("mage", ["fire"]))
	var kit_block: int = p.find("Ability ids you may use, and NOTHING else")
	var intent: int = p.find("Player intent:")
	var reminder: int = p.find("Before you answer: this character knows ONLY")
	var spec: int = p.find("Emit a JSON object with fields:")
	assert_gt(kit_block, -1, "CONTROL: the original kit block must still be there")
	assert_gt(intent, kit_block, "CONTROL: intent follows the kit block")
	assert_gt(reminder, intent, "the reminder must come after the player's intent")
	assert_gt(spec, reminder, "and immediately before the output spec")


func test_the_ids_come_from_the_kit_not_from_a_list_here() -> void:
	## A different kit must produce a different reminder. A hardcoded set would pass
	## the first arm and fail this one.
	var p: String = DP.build_rule_composition(
		"autobattle", "keep everyone alive", [], _kit("cleric", ["cure", "protect", "pray"]))
	var at: int = p.find("Before you answer: this character knows ONLY")
	assert_gt(at, -1, "the reminder must be present")
	var tail: String = p.substr(at)
	for id in ["cure", "protect", "pray"]:
		assert_true(tail.find(id) != -1, "a cleric's reminder must name %s" % id)
	assert_eq(tail.find("blizzard"), -1, "and must not name another job's ability")


func test_autogrind_gets_no_reminder() -> void:
	## Autogrind is party-level: it has no kit, and there is nothing to restate.
	var p: String = DP.build_rule_composition("autogrind", "stop if the party is hurt", [], {})
	assert_eq(p.find("Before you answer: this character knows ONLY"), -1,
		"the autogrind prompt must not carry a per-character kit reminder")


func test_an_unresolved_kit_adds_nothing() -> void:
	## Headless, or a character the kit cannot resolve for: the prompt must degrade to
	## exactly what it was, not to a reminder listing nothing.
	var p: String = DP.build_rule_composition("autobattle", "attack", [], {"resolved": false, "kit": []})
	assert_eq(p.find("Before you answer: this character knows ONLY"), -1,
		"an unresolved kit must add no reminder at all")
	var p2: String = DP.build_rule_composition("autobattle", "attack", [], _kit("mage", []))
	assert_eq(p2.find("Before you answer: this character knows ONLY"), -1,
		"and neither must an empty one")


func test_the_original_kit_block_is_untouched() -> void:
	## This is an addition, not a replacement. The earlier block carries the MP costs
	## and the example-id warning, and both are load-bearing for other measured fixes.
	var p: String = DP.build_rule_composition(
		"autobattle", "heal", [], _kit("cleric", ["cure"], {"cure": 6}))
	assert_true(p.find("Ability ids you may use, and NOTHING else") != -1,
		"the original allowlist block must survive")
	assert_true(p.find("cure - 6 MP") != -1, "with its MP costs, which the guard supplier depends on")
