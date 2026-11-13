extends GutTest

## battle 24696: two cadence conditions reached the evaluator; the Rule Composer's grammar teaches them (the parity guard covers that they are listed).
## This file pins what the paragraph CLAIMS: the abilities it calls an interrupt really land a status that breaks a charge.

const DP := preload("res://src/llm/DialoguePrompts.gd")
const ABILITIES := "res://data/abilities.json"


func _paragraph() -> String:
	var g: String = DP.AUTOBATTLE_GRAMMAR_DESCRIPTION
	var from: int = g.find("enemy_charging is NULLARY")
	var to: int = g.find("is the interrupt", from)
	return g.substr(from, to - from) if from >= 0 and to > from else ""


func _effect_of(ability_id: String) -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ABILITIES))
	var table: Variant = (parsed as Dictionary).get("abilities", parsed) if parsed is Dictionary else {}
	var a: Variant = (table as Dictionary).get(ability_id, {}) if table is Dictionary else {}
	return str((a as Dictionary).get("effect", "")) if a is Dictionary else ""


func test_every_named_interrupt_lands_a_breaking_status() -> void:
	var text: String = _paragraph()
	assert_ne(text, "", "CONTROL: the grammar carries the enemy_charging paragraph")
	var rx := RegEx.create_from_string("'([a-z_]+)'")
	var named: Array = []
	for m in rx.search_all(text):
		named.append(m.get_string(1))
	assert_gt(named.size(), 0, "CONTROL: the paragraph names at least one ability")
	var wrong: Array = []
	for id in named:
		if not BossCadence.DEFAULT_INTERRUPTS.has(_effect_of(id)):
			wrong.append("%s (effect '%s')" % [id, _effect_of(id)])
	assert_eq(wrong, [], "an ability the composer calls an interrupt must land a status in BossCadence.DEFAULT_INTERRUPTS")


func test_the_two_conditions_are_taught_with_their_shape() -> void:
	var g: String = DP.AUTOBATTLE_GRAMMAR_DESCRIPTION
	assert_string_contains(g, "{\"type\":\"enemy_charging\"}", "enemy_charging is shown nullary, with no op or value")
	assert_string_contains(g, "{\"type\":\"enemy_signature_in\",\"op\":\"<=\",\"value\":1}", "enemy_signature_in is shown with op and value")
	assert_true(AutobattleSystem.NULLARY_CONDITIONS.has("enemy_charging"), "CONTROL: the evaluator agrees enemy_charging is nullary")
	assert_false(AutobattleSystem.NULLARY_CONDITIONS.has("enemy_signature_in"), "CONTROL: and that enemy_signature_in is not")
