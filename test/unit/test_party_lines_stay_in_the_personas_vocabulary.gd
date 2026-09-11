extends GutTest

## The cleric of the Eternal Loop kept praying to "the Lord".
##
## Party combat dialogue exists to make each character sound like themselves —
## flavour IS the whole feature, since the line changes nothing mechanical. The
## cleric's persona establishes a specific theology (the Liturgical Order of the
## Eternal Loop, which holds that the game itself is scripture), and the model
## drifted to generic fantasy, invoking a deity that does not exist in this world.
##
## MEASURED against local llama3 with the REAL persona and phrases, 14 samples
## per arm, same prompt otherwise:
##
##     lines invoking a generic "Lord"   BEFORE 4/14    AFTER 0/14
##     lines using the persona's "Loop"  BEFORE 3/14    AFTER 5/14
##
## The rule is deliberately GENERAL rather than "never say Lord". Five starter
## jobs have personas full of proper nouns, and a cleric-specific blocklist would
## do nothing for the other four while reading like it had solved the class. What
## is pinned here is the general instruction, not the cleric's vocabulary.
##
## ⚠️ One model, one persona, one scenario. The effect is large and
## one-directional, but it is a demonstration.

const DP := preload("res://src/llm/DialoguePrompts.gd")

const PERSONA := "a Watchful Cleric of the Liturgical Order of the Eternal Loop"
const PHRASES := ["The Loop provides. Hold still.", "Mercy is a stat. Mine is capped."]


func _prompt() -> String:
	return DP.build_party_line(PERSONA, PHRASES, {
		"event_kind": "big_hit_taken", "speaker_name": "Rilla", "speaker_job_id": "cleric",
		"speaker_hp_pct": 22.0, "speaker_mp_pct": 40.0,
	})


# ── the instruction is present and general ────────────────────────────────────

func test_the_prompt_confines_the_line_to_the_personas_vocabulary() -> void:
	assert_true(_prompt().find("Stay inside the persona's OWN vocabulary") != -1,
		"the model must be told to stay inside the persona's own terms")


func test_it_names_the_categories_that_drifted() -> void:
	## "Stay in character" is too vague to act on — the observed drift was a
	## specific class of proper noun, so the rule names that class.
	var p: String = _prompt()
	assert_true(p.find("deity") != -1, "a deity is what the cleric invented")
	assert_true(p.find("never names") != -1,
		"the test is whether the persona names it, not whether it sounds plausible")


func test_it_says_what_to_do_instead() -> void:
	## Forbidding without redirecting is what made an earlier prompt line
	## underperform: the model needs the alternative, not only the prohibition.
	assert_true(_prompt().find("use that, not a generic") != -1,
		"the rule must point at the persona's own term as the replacement")


func test_the_rule_is_general_not_a_blocklist() -> void:
	## THE DISCRIMINATOR. A cleric-specific fix would read as solved and leave the
	## other four jobs drifting. Nothing in the instruction may name this persona's
	## particular vocabulary.
	var p: String = _prompt()
	var rule_at: int = p.find("Stay inside the persona's OWN vocabulary")
	assert_gt(rule_at, -1, "CONTROL: the rule must be found")
	var rule: String = p.substr(rule_at, 220)
	for word in ["Loop", "Lord", "cleric", "Liturgical"]:
		assert_eq(rule.find(word), -1,
			"the instruction must not hardcode '%s' — it has to work for every persona" % word)


# ── it must not disturb what already worked ───────────────────────────────────

func test_the_persona_and_phrases_still_reach_the_model() -> void:
	## CONTROL: a rule about the persona is worthless if the persona stops being
	## shown, and the phrases are how the register is taught.
	var p: String = _prompt()
	assert_true(p.find("Eternal Loop") != -1, "the persona must still be present")
	assert_true(p.find("Mercy is a stat. Mine is capped.") != -1,
		"the authored phrases must still be shown as register cues")


func test_the_do_not_copy_instruction_survives() -> void:
	## CONTROL: the hour-22 fix that stopped the model reciting authored phrases
	## verbatim (10 of 12 before it) must not be displaced by this addition.
	var p: String = _prompt()
	assert_true(p.find("EXAMPLES OF VOICE, not lines to say") != -1,
		"the phrases must still be framed as examples")
	assert_true(p.find("Write a NEW line") != -1, "and the instruction to write fresh must remain")


func test_the_output_contract_survives() -> void:
	## CONTROL: adding a rule mid-block must not disturb the ones around it.
	var p: String = _prompt()
	assert_true(p.find("mood: ONE of") != -1, "the mood enum must still be stated")
	assert_true(p.find('{"line": "...", "mood": "..."}') != -1,
		"the JSON contract must still be stated")


func test_a_persona_with_no_phrases_still_gets_the_rule() -> void:
	## The rule is about the persona, not the phrase list — a job with no authored
	## phrases drifts just as easily.
	var p: String = DP.build_party_line(PERSONA, [], {"speaker_name": "Rilla"})
	assert_true(p.find("Stay inside the persona's OWN vocabulary") != -1,
		"the vocabulary rule must not depend on there being signature phrases")
