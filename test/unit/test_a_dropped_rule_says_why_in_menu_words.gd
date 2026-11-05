extends GutTest

## The Rule Composer drops a rule the character cannot run and tells the player: "Dropped a rule this character cannot
## run — <why>". The why was the deep check's own text ("ability 'cure' not in fighter's level-1 kit … NOT a fizzle"),
## which is the MODEL's repair hint, so the player read ids and lint vocabulary. It now goes through the share path's
## translator (ScriptShareManager.player_text_for_finding, cowir-controller), and the model's hint is untouched.

const RC := preload("res://src/llm/RuleComposer.gd")

const KEPT := {"conditions": [{"type": "mp_percent", "op": ">=", "value": 10}], "actions": [{"type": "attack"}], "enabled": true}
const UNLEARNED := {"conditions": [{"type": "mp_percent", "op": ">=", "value": 50}],
	"actions": [{"type": "ability", "id": "cure", "target": "lowest_hp_ally"}], "enabled": true}


func before_each() -> void:
	AutobattleSystem._test_disable_persistence = true


func _rc():
	var c = RC.new()
	add_child_autofree(c)
	return c


func test_the_note_names_the_ability_and_job_as_the_player_sees_them() -> void:
	var lint: Array = AutobattleSystem.validate_rule(UNLEARNED.duplicate(true), "hero")
	assert_false(lint.is_empty(), "CONTROL: the deep check refuses cure for the hero's job")
	var rules: Array = [KEPT.duplicate(true), UNLEARNED.duplicate(true)]
	var notes: Array[String] = _rc()._drop_unusable_rules(rules, "hero", AutobattleSystem)
	assert_eq(notes.size(), 1, "FIXTURE: the unlearned rule was dropped and reported")
	if notes.size() != 1:
		return
	var job_id: String = str(AutobattleSystem.get_deep_check_kit("hero").get("job_id", ""))
	assert_string_contains(notes[0], AbilityIcons.name_of("cure"), "THE DEFECT: the note named the id")
	assert_string_contains(notes[0], Combatant.job_display_name_for_id(job_id), "and the job as this world names it")
	assert_false(notes[0].contains("level-1 kit") or notes[0].contains("fizzle"), "and none of the lint's words: %s" % notes[0])


func test_the_model_still_gets_the_lint_text() -> void:
	## The same refusal, read by the model as a repair hint, keeps the deep check's own words and ids.
	var lint: Array = AutobattleSystem.validate_rule(UNLEARNED.duplicate(true), "hero")
	assert_true(", ".join(lint).contains("'cure'"), "the deep check's text is unchanged: %s" % [lint])


func test_a_finding_the_translator_does_not_know_passes_through() -> void:
	var rule: Dictionary = {"conditions": [{"type": "always"}], "actions": [{"type": "attack"}], "enabled": true}
	assert_eq(ScriptShareManager.player_text_for_finding("some other refusal", rule, "hero"), "some other refusal",
		"an unrecognised finding keeps its text rather than going blank")
