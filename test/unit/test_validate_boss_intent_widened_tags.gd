extends GutTest

## Task 5 fix: validate_boss_intent's gate is available_intents, not a hardcoded const.

const DialoguePrompts := preload("res://src/llm/DialoguePrompts.gd")

const _WIDENED_TAGS := ["fire_resist", "ice_resist", "lightning_resist",
						"focus_healer", "defense_boost", "rotate_aggro"]


func test_validate_boss_intent_accepts_widened_tags_when_available() -> void:
	for tag in _WIDENED_TAGS:
		var raw: Dictionary = {"intent_id": tag, "reason": "test", "taunt": "test"}
		var got: Dictionary = DialoguePrompts.validate_boss_intent(raw, [tag])
		assert_eq(got.get("intent_id", ""), tag,
			"validate_boss_intent must accept widened tag '%s' via available_intents" % tag)


func test_validate_boss_intent_rejects_widened_tag_when_not_available() -> void:
	# Same tag, absent from available_intents — proves the gate is the array arg.
	var raw: Dictionary = {"intent_id": "fire_resist", "reason": "test", "taunt": "test"}
	var got: Dictionary = DialoguePrompts.validate_boss_intent(raw, ["aggress", "turtle"])
	assert_eq(got.get("intent_id", ""), "",
		"validate_boss_intent must reject a widened tag absent from available_intents")
