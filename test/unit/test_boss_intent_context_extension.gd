extends GutTest

const BossIntentContext := preload("res://src/battle/BossIntentContext.gd")

func test_default_fields_present_and_empty() -> void:
	var ctx: BossIntentContext = BossIntentContext.new()
	assert_true("player_lead_pc_rules" in ctx,
				"BossIntentContext must expose player_lead_pc_rules")
	assert_true("learned_patterns_counter" in ctx,
				"BossIntentContext must expose learned_patterns_counter")
	assert_true("learned_patterns_sample" in ctx,
				"BossIntentContext must expose learned_patterns_sample")
	assert_eq(ctx.player_lead_pc_rules.size(), 0)
	assert_eq(ctx.learned_patterns_counter, "")
	assert_eq(ctx.learned_patterns_sample.size(), 0)

func test_fields_accept_assignment() -> void:
	var ctx: BossIntentContext = BossIntentContext.new()
	ctx.player_lead_pc_rules = [{"conditions": [], "actions": []}]
	ctx.learned_patterns_counter = "fire_resist"
	ctx.learned_patterns_sample = {"ability_frequencies": {"fire": 42}}
	assert_eq(ctx.player_lead_pc_rules.size(), 1)
	assert_eq(ctx.learned_patterns_counter, "fire_resist")
	assert_eq(ctx.learned_patterns_sample.get("ability_frequencies", {}).get("fire", 0), 42)
