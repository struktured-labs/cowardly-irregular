extends GutTest

const DialoguePrompts := preload("res://src/llm/DialoguePrompts.gd")

const _ALL_ALLOWED := ["aggress", "turtle", "exploit_pattern",
                       "fire_resist", "ice_resist", "lightning_resist",
                       "focus_healer", "defense_boost", "rotate_aggro"]

func test_all_allowed_tags_pass_validation() -> void:
	for tag in _ALL_ALLOWED:
		var reply := {"intent_id": tag, "reason": "test", "taunt": "test"}
		var validated: Dictionary = DialoguePrompts.validate_boss_intent_reply(reply)
		assert_eq(validated.get("intent_id", ""), tag,
				  "intent '%s' should be preserved by validator" % tag)

func test_unknown_intent_falls_back() -> void:
	var reply := {"intent_id": "make_soup", "reason": "test", "taunt": "test"}
	var validated: Dictionary = DialoguePrompts.validate_boss_intent_reply(reply)
	assert_ne(validated.get("intent_id", ""), "make_soup",
			  "unknown intent must NOT be accepted verbatim")
