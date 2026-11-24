extends GutTest

## The Rule Composer's confirm screen showed the model's own description and "N rule(s) composed", never the
## rules. The description is prose the model writes, so it can say "heal, then attack" over rules that do
## something else, and the player installed them blind. The preview now lists each rule as IF ... THEN ...

const OVERLAY := preload("res://src/ui/autobattle/RuleComposerOverlay.gd")

const HEAL := {"conditions": [{"type": "ally_hp_percent", "op": "<", "value": 50}],
	"actions": [{"type": "ability", "id": "cure", "target": "lowest_hp_ally"}], "enabled": true}
const STRIKE := {"conditions": [{"type": "always"}],
	"actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true}


func _preview(domain: String, rules: Array, description: String = "Heal, then attack.") -> String:
	var overlay = OVERLAY.new()
	add_child_autofree(overlay)
	overlay._domain = domain
	overlay._preview_panel = Panel.new()
	overlay.add_child(overlay._preview_panel)
	overlay._populate_preview({"description": description, "rules": rules, "notes": []})
	var label: Label = overlay._preview_panel.get_node_or_null("PreviewLabel") as Label
	return label.text if label != null else ""


func test_every_composed_rule_is_listed_before_confirm() -> void:
	var text: String = _preview(OVERLAY.RC_DOMAIN_AUTOBATTLE, [HEAL, STRIKE])
	for rule in [HEAL, STRIKE]:
		var line: String = AutobattleSystem.describe_rule_for_llm(rule, true)
		assert_ne(line, "", "CONTROL: the rule has a description")
		assert_string_contains(text, line, "the preview lists what will be installed")


func test_rules_are_listed_in_priority_order() -> void:
	var text: String = _preview(OVERLAY.RC_DOMAIN_AUTOBATTLE, [HEAL, STRIKE])
	var first: int = text.find(AutobattleSystem.describe_rule_for_llm(HEAL, true))
	var second: int = text.find(AutobattleSystem.describe_rule_for_llm(STRIKE, true))
	assert_gt(first, -1, "CONTROL: the heal rule is shown")
	assert_gt(second, first, "first match wins, so the list reads top to bottom in that order")


func test_a_description_that_disagrees_cannot_hide_the_rules() -> void:
	var text: String = _preview(OVERLAY.RC_DOMAIN_AUTOBATTLE, [STRIKE], "Always heal the party.")
	assert_string_contains(text, "Always heal the party.", "CONTROL: the model's prose still renders")
	assert_string_contains(text, AutobattleSystem.describe_rule_for_llm(STRIKE, true), "and the attack the player would really get is beside it")


func test_an_autogrind_composition_lists_its_rules_in_the_grinds_own_words() -> void:
	var stop := {"conditions": [{"type": "party_hp_avg", "op": "<", "value": 30}], "actions": [{"type": "stop_grinding"}]}
	var heal := {"conditions": [{"type": "party_hp_min", "op": "<", "value": 50}], "actions": [{"type": "heal_party"}]}
	var text: String = _preview(OVERLAY.RC_DOMAIN_AUTOGRIND, [stop, heal])
	for rule in [stop, heal]:
		var line: String = AutogrindSystem.describe_rule(rule)
		assert_true(line != "" and not line.contains("party_hp"), "CONTROL: the grind's reader gives words (%s)" % line)
		assert_string_contains(text, line, "a grind rule is shown before it is installed")
	assert_lt(text.find(AutogrindSystem.describe_rule(stop)), text.find(AutogrindSystem.describe_rule(heal)), "in the order they are checked")
	assert_false(text.contains("IF "), "CONTROL: the autobattle reader is not used on grind rules")
	assert_false(text.contains("rule(s) composed"), "the list is the count; it is not said twice")


func test_an_ability_reads_by_its_display_name_not_its_id() -> void:
	var shown: String = str(JobSystem.get_ability("cure").get("name", ""))
	assert_true(shown != "" and shown != "cure", "CONTROL: cure has a display name distinct from its id (%s)" % shown)
	var text: String = _preview(OVERLAY.RC_DOMAIN_AUTOBATTLE, [HEAL])
	assert_string_contains(text, "ability %s" % shown, "the player reads the spell's name")
	assert_false(text.contains("ability cure"), "and never its internal id")


func test_the_count_is_not_said_twice() -> void:
	var text: String = _preview(OVERLAY.RC_DOMAIN_AUTOBATTLE, [HEAL, STRIKE])
	assert_string_contains(text, "2. ", "CONTROL: the numbered list is the count")
	assert_false(text.contains("rule(s) composed"), "the status line above already says how many; the preview does not repeat it")


func test_the_model_facing_reading_still_uses_ids() -> void:
	assert_string_contains(AutobattleSystem.describe_rule_for_llm(HEAL), "ability cure", "CONTROL: the LLM prompt keeps the ids it must write back")
