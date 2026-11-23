extends GutTest

## The cadence (cowir-battle) puts a boss's signature on a clock; the LLM that picks the boss's posture was never told.
## Now the intent context carries the clock and the prompt names it, so a boss can plan around its own big blow.
## A boss with no clock gets exactly the prompt it had before.

const DP := preload("res://src/llm/DialoguePrompts.gd")
const CTX := preload("res://src/battle/BossIntentContext.gd")
const CADENCED := "ice_dragon"
const PLAIN := "slime"


func _ctx(sig: String, turns: int, charging: bool) -> Dictionary:
	var c = CTX.new()
	c.boss_id = "glacius"
	c.phase = 1
	c.persona = "Cold."
	c.available_intents = ["aggress", "turtle"]
	c.signature_id = sig
	c.signature_in = turns
	c.charging = charging
	return c.to_dict()


func _built(monster_type: String, clock: Dictionary) -> BossIntentContext:
	var boss := Combatant.new()
	boss.initialize({"name": "Boss", "max_hp": 500, "max_mp": 50, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(boss)
	boss.set_meta("monster_type", monster_type)
	if not clock.is_empty():
		boss.set_meta("_cadence", clock)
	return BattleManager._build_boss_intent_context(boss, "glacius", 1, null)


func test_the_prompt_names_the_clock_both_ways() -> void:
	var move: String = DP._ability_named("absolute_zero")
	var charging: String = DP.build_boss_intent("Glacius", _ctx("absolute_zero", 1, true))
	assert_string_contains(charging, "You are gathering power for %s. It releases on your next turn" % move, "charging: the release is next turn")
	var building: String = DP.build_boss_intent("Glacius", _ctx("absolute_zero", 4, false))
	assert_string_contains(building, "Your signature move, %s, comes in 4 of your turns" % move, "building: the count is named")
	assert_false(building.contains("You are gathering power"), "a boss still building is not told it is charging")


func test_a_boss_with_no_clock_gets_the_prompt_it_had() -> void:
	var none: String = DP.build_boss_intent("Glacius", _ctx("", -1, false))
	var bare = CTX.new()
	bare.boss_id = "glacius"
	bare.phase = 1
	bare.persona = "Cold."
	bare.available_intents = ["aggress", "turtle"]
	assert_eq(none, DP.build_boss_intent("Glacius", bare.to_dict()), "no clock: byte-identical to a context that never set the fields")
	assert_false(none.contains("signature move") or none.contains("gathering power"), "and no clock line")


func test_the_battle_hands_the_llm_the_live_clock() -> void:
	var cfg: Dictionary = BossCadence.config(EncounterSystem.monster_database.get(CADENCED, {}))
	assert_false(cfg.is_empty(), "CONTROL: %s carries a cadence row" % CADENCED)
	if cfg.is_empty():
		return
	var fresh := _built(CADENCED, {})
	assert_eq(fresh.signature_id, str(cfg["signature"]), "the signature is the row's")
	assert_eq(fresh.signature_in, BossCadence.turns_to_release(BossCadence.fresh_state(), cfg), "a fresh clock reads the scheduler's own count")
	assert_false(fresh.charging, "a fresh clock is not charging")
	var mid: Dictionary = BossCadence.fresh_state()
	for i in int(cfg["every"]) + 1:
		mid = BossCadence.next(mid, cfg)["state"]
	assert_true(BossCadence.is_charging(mid), "CONTROL: every+1 turns put the clock into its charge")
	var charging := _built(CADENCED, mid)
	assert_true(charging.charging, "a charging boss's context says so")
	assert_eq(charging.signature_in, BossCadence.turns_to_release(mid, cfg), "and counts its release from the live state")
	var plain := _built(PLAIN, {})
	assert_eq([plain.signature_id, plain.signature_in, plain.charging], ["", -1, false], "a monster with no cadence row hands over no clock")
