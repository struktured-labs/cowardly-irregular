extends GutTest

## Regression: BossIntentContext.to_dict() must emit the persona STRING so
## DialoguePrompts.build_boss_intent can render it into the LLM prompt.
##
## Pre-fix the dict carried only `persona_len: int`, and build_boss_intent
## (DialoguePrompts.gd) looked up `ctx.get("persona", "")` — falling through
## to a generic "A formidable JRPG boss." default on EVERY authored boss.


func test_to_dict_includes_persona_string() -> void:
	var ctx = BossIntentContext.new()
	ctx.boss_id = "chancellor_mordaine"
	ctx.persona = "Coldly composed usurper, weaponizes politeness."
	var d := ctx.to_dict()
	assert_true(d.has("persona"), "to_dict must include 'persona' key")
	assert_eq(d["persona"], "Coldly composed usurper, weaponizes politeness.",
		"persona must round-trip as the full string, not just its length")
	assert_false(d.has("persona_len"),
		"persona_len was the buggy key — should no longer appear")


func test_boss_intent_prompt_contains_persona() -> void:
	var ctx = BossIntentContext.new()
	ctx.boss_id = "chancellor_mordaine"
	ctx.persona = "MORDAINE_PERSONA_MARKER"
	ctx.available_intents = ["aggress", "turtle"]
	var DP = load("res://src/llm/DialoguePrompts.gd")
	if DP == null or not DP.has_method("build_boss_intent"):
		pending("DialoguePrompts.build_boss_intent unavailable in test env")
		return
	var prompt: String = DP.build_boss_intent("Chancellor Mordaine", ctx.to_dict())
	assert_true(prompt.find("MORDAINE_PERSONA_MARKER") > -1,
		"persona text must reach the boss-intent prompt; pre-fix the marker was dropped")
