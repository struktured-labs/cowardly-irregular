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
	assert_string_contains(text, "2 rule(s) composed", "CONTROL: the count still renders")
	for rule in [HEAL, STRIKE]:
		var line: String = AutobattleSystem.describe_rule_for_llm(rule)
		assert_ne(line, "", "CONTROL: the rule has a description")
		assert_string_contains(text, line, "the preview lists what will be installed")


func test_rules_are_listed_in_priority_order() -> void:
	var text: String = _preview(OVERLAY.RC_DOMAIN_AUTOBATTLE, [HEAL, STRIKE])
	var first: int = text.find(AutobattleSystem.describe_rule_for_llm(HEAL))
	var second: int = text.find(AutobattleSystem.describe_rule_for_llm(STRIKE))
	assert_gt(first, -1, "CONTROL: the heal rule is shown")
	assert_gt(second, first, "first match wins, so the list reads top to bottom in that order")


func test_a_description_that_disagrees_cannot_hide_the_rules() -> void:
	var text: String = _preview(OVERLAY.RC_DOMAIN_AUTOBATTLE, [STRIKE], "Always heal the party.")
	assert_string_contains(text, "Always heal the party.", "CONTROL: the model's prose still renders")
	assert_string_contains(text, AutobattleSystem.describe_rule_for_llm(STRIKE), "and the attack the player would really get is beside it")


func test_control_an_autogrind_composition_is_not_listed_as_autobattle_rules() -> void:
	var text: String = _preview(OVERLAY.RC_DOMAIN_AUTOGRIND, [HEAL])
	assert_string_contains(text, "1 rule(s) composed", "CONTROL: the autogrind preview still renders")
	assert_false(text.contains("IF "), "autogrind rules have their own shape; the autobattle reader is not used on them")
