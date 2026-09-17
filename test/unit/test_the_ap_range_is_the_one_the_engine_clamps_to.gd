extends GutTest

## `ap` is the one autobattle numeric whose NAME does not carry its scale. Every other one
## does — hp_percent, mp_percent, turn, enemy_count — and the model gets those right; measured
## across every corpus this branch captured, party_hp_* values ran 10-90 throughout.
##
## The grammar named `ap` in the condition list and showed one example at `>= 4`, which
## anchors most answers to 4 and says nothing about the bounds.
##
## MEASURED on live llama3, three intents that invite a number, same intents both arms:
##
##     before   3 of 31 ap conditions outside -4..4   values 8, 16, 20
##     after    0 of 45
##
## Combatant clamps to [-4, 4], so `ap >= 20` validates and never fires.
##
## ✅ AND AN UNPLANNED GAIN, which is why the line names the negative side too: the intent
## "it is fine to go deep into AP debt" produced 4 ap conditions before (values 4, 2, 0) and
## 14 after, spanning -4 to 0. The model could not express debt because nothing told it
## negatives were legal — the feature was unreachable through the composer, not just
## mis-valued.

const DP := preload("res://src/llm/DialoguePrompts.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")


func _autobattle() -> String:
	return DP.build_rule_composition("autobattle", "bank points", [],
		{"resolved": true, "job_id": "mage", "kit": ["fire"], "full_kit": ["fire"],
		"max_mp": 70, "costs": {"fire": 8}, "items": ["potion"]})


func test_the_prompt_states_the_ap_range() -> void:
	var p: String = _autobattle()
	assert_true(p.find("runs -4 to +4") != -1, "the bounds must be named")
	assert_true(p.find("negative is debt") != -1,
		"and the negative side, which is what made debt expressible at all")


func test_it_says_an_out_of_range_value_never_fires() -> void:
	## Naming the bounds without the consequence leaves `ap >= 20` looking like a strong
	## guard rather than a dead rule.
	## ⚠️ Anchored on the AP clause, not on "never fires": the elements paragraph already
	## says "An element nothing is weak to simply never fires", so the loose form matched a
	## sentence that was never the subject and survived the mutation that deletes this one.
	var p: String = _autobattle()
	assert_true(p.find("that range validates and then never fires") != -1,
		"the consequence must be stated ON THE AP LINE")


func test_the_stated_range_is_the_one_the_engine_clamps_to() -> void:
	## THE RATCHET. The prompt now makes a claim ABOUT THE ENGINE. If Combatant's clamp
	## moves, the prompt is confidently teaching bounds that no longer hold and nothing
	## else in the tree would say so. Comments stripped — the file discusses AP in prose.
	var code: String = GdSource.code_of("res://src/battle/Combatant.gd")
	assert_false(code.is_empty(), "CONTROL: Combatant's source must be readable")
	var clamps: int = code.count("clampi(current_ap")
	assert_gt(clamps, 0, "CONTROL: the AP clamp must still be findable")
	assert_true(code.find("-4, 4)") != -1,
		"the prompt says -4..+4 because Combatant clamps there: %d clamp sites found" % clamps)


func test_the_grind_prompt_does_not_get_it() -> void:
	## CONTROL: the autogrind grammar has no `ap` condition — its conditions are party-level.
	## A range for a condition the domain does not offer is noise.
	var p: String = DP.build_rule_composition("autogrind", "grind", [],
		{"resolved": true, "party": [{"member": "cleric", "job_id": "cleric", "kit": ["cure"],
		"costs": {"cure": 6}, "profiles": ["Default"], "between_battle": ["cure"]}]})
	assert_true(p.find("runs -4 to +4") == -1, "the grind grammar has no ap condition")
