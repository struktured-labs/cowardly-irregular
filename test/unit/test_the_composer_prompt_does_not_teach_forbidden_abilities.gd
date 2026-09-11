extends GutTest

## The prompt told the model "NOTHING else", then handed it a rule to copy.
##
## The rule-composition prompt carries worked JSON examples that spend real
## ability ids, and the kit block below them forbids everything outside the
## character's kit. The model copies the examples. Measured against live llama3
## on current main, 10 samples per job, scored by compose_async's OWN verdict
## (source == "llm"), not by a re-implementation:
##
##     fighter   2/10 reached the player      8/10 fell back
##     cleric    6/10                         4/10
##
## 'esuna' occurs EXACTLY ONCE in the whole fighter prompt — inside a complete,
## copy-pasteable rule — and appeared in 5 of those 8 failures. 'fire' and 'raise'
## account for two more. The kit block already said "Anything not on that list is
## rejected and DISCARDS THE WHOLE RULE SET"; examples teach harder than
## prohibitions, which is the same mechanism that had party lines reciting their
## authored phrases 10 of 12 times until they were relabelled.
##
## After naming the example ids as shape-only, same model, same procedure:
##
##     fighter   2/10 -> 6/10               'esuna' failures 5 -> 2
##     cleric    6/10 -> 8/10
##
## ⚠️ n=10 per arm per condition, one model, one intent. Large and one-directional
## with an identified mechanism, but a demonstration rather than a benchmark —
## re-measure with tools/rule_composition_compose.gd before quoting it as one.
##
## THE IDS ARE PARSED OUT OF THE GRAMMAR, NOT LISTED. A hand-written warning goes
## stale the moment someone rewords an example: it would name ids that are no
## longer present — an inert warning — while the new ones get copied freely.

const DP := preload("res://src/llm/DialoguePrompts.gd")


func _prompt_with_kit(job: String, kit: Array, costs: Dictionary, max_mp: int) -> String:
	return DP.build_rule_composition("autobattle", "keep everyone alive", [], {
		"resolved": true, "job_id": job, "kit": kit, "costs": costs, "max_mp": max_mp,
	})


# ── the defect ────────────────────────────────────────────────────────────────

func test_the_prompt_names_its_own_example_ids_as_invalid() -> void:
	var p: String = _prompt_with_kit("fighter", ["power_strike", "provoke", "cleave"],
		{"power_strike": 8, "provoke": 5, "cleave": 12}, 30)
	var at: int = p.find("demonstrate SHAPE ONLY")
	assert_true(at != -1,
		"the kit block must name the examples as shape-only — the model copies them otherwise")
	if at == -1:
		return
	## Scoped to the WARNING LINE, not the whole prompt: 'fire' occurs 8 times in the
	## grammar regardless, so searching the full text would pass without the warning
	## naming it at all.
	var warn: String = p.substr(at - 90, 120)
	for stray in DP._example_ability_ids():
		assert_true(warn.find(stray) != -1,
			"the warning must NAME '%s' (the grammar spends it); warning reads: %s" % [stray, warn])


func test_the_warned_ids_are_really_in_the_grammar() -> void:
	## ANTI-INERT. A warning naming ids the examples no longer use suppresses
	## nothing and reads as coverage from both sides.
	var ids: Array[String] = DP._example_ability_ids()
	assert_gt(ids.size(), 0,
		"CONTROL: the parser found no example ids — it is broken, and the warning would be empty")
	for aid in ids:
		assert_true(DP.AUTOBATTLE_GRAMMAR_DESCRIPTION.find('"id":"%s"' % aid) != -1,
			"'%s' must actually appear as an example id, or the warning is about nothing" % aid)


func test_a_kit_ability_is_never_warned_against() -> void:
	## THE DISCRIMINATOR. A mage really does have 'fire'. Telling that character its
	## own ability is invalid would break the feature in the other direction.
	var p: String = _prompt_with_kit("mage", ["fire", "blizzard", "thunder"],
		{"fire": 8, "blizzard": 8, "thunder": 8}, 80)
	var warn_at: int = p.find("demonstrate SHAPE ONLY")
	assert_true(warn_at != -1, "PREMISE: the warning is present for a resolved kit")
	var warn_line: String = p.substr(warn_at - 90, 130)
	assert_eq(warn_line.find("fire"), -1,
		"'fire' is in THIS character's kit and must not be listed as invalid: %s" % warn_line)


func test_the_kit_list_still_offers_the_real_abilities() -> void:
	## CONTROL: the warning must not crowd out the thing it protects.
	var p: String = _prompt_with_kit("fighter", ["power_strike", "provoke", "cleave"],
		{"power_strike": 8, "provoke": 5, "cleave": 12}, 30)
	for aid in ["power_strike", "provoke", "cleave"]:
		assert_true(p.find(aid + " - ") != -1, "the kit must still list '%s' with its cost" % aid)
	assert_true(p.find("30 MP pool") != -1, "and the real pool")


func test_no_kit_means_no_warning() -> void:
	## CONTROL: autogrind and unresolved characters get no kit block at all, so a
	## warning about example ids would be talking about a list that isn't there.
	var p: String = DP.build_rule_composition("autogrind", "grind safely", [], {})
	assert_eq(p.find("demonstrate SHAPE ONLY"), -1,
		"no kit block means no warning — there is no 'list above' to refer to")
	var unresolved: String = DP.build_rule_composition("autobattle", "x", [], {"resolved": false})
	assert_eq(unresolved.find("demonstrate SHAPE ONLY"), -1,
		"an unresolved character must not be warned about a kit it was never shown")
