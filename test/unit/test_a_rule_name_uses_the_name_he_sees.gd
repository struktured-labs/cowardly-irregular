extends GutTest

## cowir-main 21065/21067: player-facing names carry no Final Fantasy tier or summon name, and ids never reach a player.
## The Rule Composer broke the second half: its prompt listed bare ids (fira, firaga, summon_ifrit) and the MODEL writes
## the rule set's name and description, which the player reads, so "Fira on weak enemies" could come back through AI
## text where test_a_name_is_our_own (data files) cannot see it. The kit now shows each id's menu name beside it and
## tells the model to use that name in what it writes.

const FIRA := "fira"


func _shown(aid: String) -> String:
	return str(JobSystem.get_ability(aid).get("name", ""))


func test_a_renamed_spell_shows_its_menu_name_beside_its_id() -> void:
	var shown: String = _shown(FIRA)
	assert_ne(shown, "", "FIXTURE: fira has a menu name")
	assert_ne(shown.to_lower(), FIRA, "FIXTURE: and it differs from its id, which is the case this guards")
	var kit_block: String = DialoguePrompts._format_rule_kit(
		{"resolved": true, "job_id": "mage", "kit": [FIRA, "fire"], "max_mp": 40, "costs": {FIRA: 12, "fire": 4}})
	assert_string_contains(kit_block, "%s \"%s\" - 12 MP" % [FIRA, shown],
		"THE DEFECT: the model saw only the id, so it named the rule after the id")
	assert_string_contains(kit_block, DialoguePrompts.SHOWN_NAME_RULE, "and is told to write the name, not the id")


func test_an_id_that_is_its_own_name_is_not_repeated() -> void:
	var kit_block: String = DialoguePrompts._format_rule_kit(
		{"resolved": true, "job_id": "cleric", "kit": ["cure"], "max_mp": 30, "costs": {"cure": 6}})
	assert_string_contains(kit_block, "cure - 6 MP", "cure is shown as Cure, so the line stays as it was")


func test_the_party_kit_shows_the_names_too() -> void:
	var block: String = DialoguePrompts._format_party_kit({"resolved": true, "party": [
		{"member": "Mira", "job_id": "mage", "kit": [FIRA], "costs": {FIRA: 12}}]})
	assert_string_contains(block, "%s \"%s\" (12 MP)" % [FIRA, _shown(FIRA)], "the grind composer lists the same names")
	assert_string_contains(block, DialoguePrompts.SHOWN_NAME_RULE, "and states the same rule")


func test_the_grammar_example_names_no_summon_id() -> void:
	assert_false(DialoguePrompts.AUTOBATTLE_GRAMMAR_DESCRIPTION.contains("summon_ifrit"),
		"a worked example is copied by the model; it must not teach an FF-shaped id")
