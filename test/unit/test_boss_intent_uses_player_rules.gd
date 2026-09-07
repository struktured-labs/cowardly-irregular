extends GutTest

const DialoguePrompts := preload("res://src/llm/DialoguePrompts.gd")
const BossIntentContext := preload("res://src/battle/BossIntentContext.gd")

func test_prompt_includes_player_rules_summary() -> void:
	var ctx: BossIntentContext = BossIntentContext.new()
	ctx.player_lead_pc_rules = [
		{"conditions": [{"type": "hp_percent", "op": "<", "value": 30}],
		"actions": [{"type": "ability", "id": "fire", "target": "lowest_hp_enemy"}]},
	]
	ctx.learned_patterns_counter = "fire_resist"
	ctx.learned_patterns_sample = {"ability_frequencies": {"fire": 42, "attack": 12}}
	var prompt: String = DialoguePrompts.build_boss_intent("Test Boss", ctx.to_dict())
	assert_true("fire_resist" in prompt,
				"prompt must include the learned_patterns_counter string")
	assert_true("fire" in prompt,
				"prompt must surface the player's fire-frequency signal")

func test_prompt_lists_widened_allowlist() -> void:
	var ctx: BossIntentContext = BossIntentContext.new()
	var prompt: String = DialoguePrompts.build_boss_intent("Test Boss", ctx.to_dict())
	for tag in ["fire_resist", "ice_resist", "lightning_resist",
			"focus_healer", "defense_boost", "rotate_aggro"]:
		assert_true(tag in prompt,
					"prompt must list widened intent '%s' as a choice" % tag)
