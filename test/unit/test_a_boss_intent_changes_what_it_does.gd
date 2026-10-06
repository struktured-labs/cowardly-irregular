extends GutTest

## Regression 2026-09-29: every dragon announced its signature intent in a taunt and the intent changed nothing it did.
## The bias is data (boss_dialogue.json `bias`) over the boss's OWN abilities, capped at 1.5x, and only tilts the pick inside a pool.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")
const ROLLS := 12000
## A within-pool 1.5x on one of four lifts its share from 1/6 to 0.231; the threshold is the midpoint, about 3.4 sigma from either side at ROLLS.
const MIN_SHARE_GAIN := 0.032
const CAP := 1.5
## Pyrroth and Glacius read the tank ladder, Voltharion the assassin one. Umbraxis (caster) is armed by alias; the duels run elsewhere.
const DRAGONS := ["pyrroth", "glacius", "voltharion"]
## An ability alone in its pool cannot be favoured by a within-pool tilt; only a gate change could, and that is struktured's call.
## frost_turtle was here ("needs a gate change"); struktured 2026-10-06 approved it and the tank gate now
## scales with a utility bias, so the intent is armed. Kept as a named-gap slot for future authored intents.
const DESIGN_GAPS := {}

var _bm = null


func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)


func _json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(parsed is Dictionary, "CONTROL: %s parses" % path)
	return parsed if parsed is Dictionary else {}


func _monsters() -> Dictionary:
	var m := _json("res://data/monsters.json")
	return m.get("monsters", m)


## monster id per persona, the way BattleEnemySpawner resolves it (boss_llm_persona_id), else the id itself.
func _monster_for(persona: String) -> String:
	var mons := _monsters()
	for mid in mons:
		if mons[mid] is Dictionary and str(mons[mid].get("boss_llm_persona_id", "")) == persona:
			return str(mid)
	return persona if mons.has(persona) else ""


func _intents(persona: String) -> Array:
	return (_json("res://data/boss_dialogue.json").get(persona, {}) as Dictionary).get("scripted_intents", [])


## A boss built as the spawner builds it: stats and kit from monsters.json, persona meta from boss_llm_persona_id.
func _boss(persona: String) -> Combatant:
	var mid := _monster_for(persona)
	var v: Dictionary = _monsters()[mid]
	var st: Dictionary = v.get("stats", {})
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = persona
	c.max_hp = int(st.get("max_hp", 1000)); c.current_hp = c.max_hp
	c.max_mp = 99999; c.current_mp = c.max_mp
	c.attack = int(st.get("attack", 10)); c.defense = int(st.get("defense", 10))
	c.magic = int(st.get("magic", 10)); c.magic_defense = int(st.get("magic_defense", 10))
	c.speed = int(st.get("speed", 10))
	c.set_meta("monster_type", mid)
	c.set_meta("llm_persona_id", persona)
	c.set_meta("boss_dialogue_phase", 99)
	c.job = {"id": mid, "abilities": (v.get("abilities", []) as Array).duplicate()}
	return c


func _party() -> Array:
	var out: Array = []
	for j in ["fighter", "cleric", "mage", "rogue", "bard"]:
		var c := Combatant.new()
		autofree(c)
		c.combatant_name = j
		c.max_hp = 50000; c.current_hp = 50000
		c.job = {"id": j, "abilities": []}
		out.append(c)
	return out


## `ability`'s share of the boss's damage-pool picks (physical/magic, the pool the ladder tilts), over ROLLS real decisions with `intent` held.
func _pool_share(persona: String, intent: String, ability: String) -> float:
	var boss := _boss(persona)
	var pool: Array = []
	for id in boss.job["abilities"]:
		if str(JobSystem.get_ability(id).get("type", "")) in ["physical", "magic"]:
			pool.append(str(id))
	assert_true(pool.has(ability), "CONTROL: %s is not in %s's damage pool %s, so its share is not what the bias tilts" % [ability, persona, pool])
	if intent != "":
		boss.set_meta("llm_intent", intent)
	var foes := _party()
	var in_pool := 0
	var hits := 0
	for _i in ROLLS:
		boss.current_mp = boss.max_mp
		boss.set_meta("_utility_spent", {})
		var picked := str(_bm._make_ai_decision(boss, [boss], foes).get("ability_id", ""))
		if pool.has(picked):
			in_pool += 1
			if picked == ability:
				hits += 1
	assert_gt(in_pool, ROLLS / 5, "CONTROL: %s reached its damage pool only %d times, so the share is noise" % [persona, in_pool])
	assert_eq(str(boss.get_meta("llm_intent", "")), intent, "CONTROL: the intent under test changed mid-measurement")
	return float(hits) / float(maxi(in_pool, 1))


func test_every_authored_bias_names_only_its_bosses_own_abilities_within_the_cap() -> void:
	var dialogue := _json("res://data/boss_dialogue.json")
	var checked := 0
	var bad: Array[String] = []
	for persona in dialogue:
		if not (dialogue[persona] is Dictionary):
			continue
		for it in (dialogue[persona] as Dictionary).get("scripted_intents", []):
			if not (it is Dictionary) or not (it.get("bias") is Dictionary):
				continue
			var mid := _monster_for(str(persona))
			var kit: Array = (_monsters().get(mid, {}) as Dictionary).get("abilities", [])
			for ability in it["bias"]:
				checked += 1
				var w: float = float(it["bias"][ability])
				if not kit.has(ability):
					bad.append("%s/%s favours %s, which %s does not own" % [persona, it["id"], ability, mid])
				if w <= 1.0 or w > CAP:
					bad.append("%s/%s weights %s at %.2f — favoured abilities sit in (1.0, %.1f]" % [persona, it["id"], ability, w, CAP])
	assert_gt(checked, 0, "CONTROL: no intent authors a bias, so this checked nothing")
	assert_eq(bad, [] as Array[String], "an authored intent bias is wrong: %s" % "; ".join(bad))


func test_every_dragon_signature_intent_is_armed_or_named_a_gap() -> void:
	var unarmed: Array[String] = []
	for persona in DRAGONS:
		var ladder: String = _bm._get_ai_archetype(_boss(persona), [])
		for it in _intents(persona):
			var id := str(it.get("id", ""))
			if id in _bm._COUNTER_INTENT_TAGS or not _bm._bias_by_intent(id).is_empty():
				continue
			if it.get("bias") is Dictionary or DESIGN_GAPS.has(id):
				continue
			unarmed.append("%s/%s (%s ladder)" % [persona, id, ladder])
	assert_eq(unarmed, [] as Array[String],
		"a dragon announces an intent that changes nothing it does — author a bias over its own kit, or name the gap: %s" % ", ".join(unarmed))


func test_a_tank_dragons_intent_tilts_it_toward_what_it_names() -> void:
	var boss := _boss("pyrroth")
	assert_eq(_bm._get_ai_archetype(boss, []), "tank", "CONTROL: Pyrroth must reach the tank ladder, or this measures another")
	var without := _pool_share("pyrroth", "", "flame_wall")
	var with_intent := _pool_share("pyrroth", "guard_scales", "flame_wall")
	assert_gt(with_intent, without + MIN_SHARE_GAIN,
		"Guard Scales left Flame Wall's share of the damage picks where it was (%.3f vs %.3f without) — the announced posture still changes nothing" % [with_intent, without])


func test_an_assassin_dragons_intent_tilts_it_toward_what_it_names() -> void:
	var boss := _boss("voltharion")
	assert_eq(_bm._get_ai_archetype(boss, []), "assassin", "CONTROL: Voltharion must reach the assassin ladder, or this measures another")
	var without := _pool_share("voltharion", "", "static_field")
	var with_intent := _pool_share("voltharion", "static_taunt", "static_field")
	assert_gt(with_intent, without + MIN_SHARE_GAIN,
		"Static Taunt left Static Field's share of the damage picks where it was (%.3f vs %.3f without) — the announced posture still changes nothing" % [with_intent, without])


func test_control_no_bias_keeps_the_ladders_own_odds() -> void:
	var pool: Array = [{"id": "a"}, {"id": "b"}, {"id": "c"}]
	var counts := {"a": 0, "b": 0, "c": 0}
	for _i in ROLLS:
		counts[str(_bm._pick_biased_by_power(pool, {}).get("id"))] += 1
	assert_almost_eq(float(counts["a"]) / ROLLS, 0.5, 0.04, "CONTROL: without a bias the strongest still takes half the picks")
	var tilted := {"a": 0, "b": 0, "c": 0}
	for _i in ROLLS:
		tilted[str(_bm._pick_biased_by_power(pool, {"c": 1.5}).get("id"))] += 1
	assert_almost_eq(float(tilted["c"]) / ROLLS, 0.375 / 1.125, 0.04,
		"a 1.5x bias on the weakest must lift it from 1/4 to 1/3 of the picks, no more")



## Frost Turtle names frost_armor, alone in Glacius's utility pool behind the tank's 40% gate. The gate now
## scales with that bias, so the posture shows: more of his turns are Frost Armor.
func _share_of_all(persona: String, intent: String, ability: String) -> float:
	var boss := _boss(persona)
	if intent != "":
		boss.set_meta("llm_intent", intent)
	var foes := _party()
	var hits := 0
	for _i in ROLLS:
		boss.current_mp = boss.max_mp
		boss.set_meta("_utility_spent", {})
		if str(_bm._make_ai_decision(boss, [boss], foes).get("ability_id", "")) == ability:
			hits += 1
	return float(hits) / float(ROLLS)


func test_frost_turtle_makes_glacius_reach_for_frost_armor() -> void:
	var boss := _boss("glacius")
	assert_true((boss.job["abilities"] as Array).has("frost_armor"), "CONTROL: Glacius must own frost_armor")
	var without := _share_of_all("glacius", "", "frost_armor")
	var with_intent := _share_of_all("glacius", "frost_turtle", "frost_armor")
	assert_gt(without, 0.0, "CONTROL: Glacius casts Frost Armor at all without the intent")
	assert_gt(with_intent, without + MIN_SHARE_GAIN,
		"Frost Turtle must raise Frost Armor's share of Glacius's turns (%.3f vs %.3f without)" % [with_intent, without])
	assert_lt(with_intent, without * 1.6, "and by no more than the 1.5x cap allows (%.3f vs %.3f)" % [with_intent, without])
