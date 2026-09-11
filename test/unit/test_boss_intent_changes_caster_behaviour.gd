extends GutTest

## Does the LLM's chosen INTENT actually change what a boss does?
##
## Every existing intent test calls `_bias_by_intent(tag)` by hand and asserts the
## returned dictionary's values. Per cowir-battle 2026-09-09 that is EXECUTION, not
## SELECTION: it proves the table is right and says nothing about whether any
## decision path reads it. So the intent layer has never been measured end to end.
##
## 🔴 IT DOES, and the file said otherwise. BattleManager's own scope comment states
## that attack_weight "is read ONLY inside _make_masterite_decision", and concludes
## the intent layer is "DIALOGUE-FIRST for non-masterites by construction" — it
## selects a taunt, not how abilities are weighted. `_ai_caster` has read
## attack_weight unconditionally since c2ae4e1b (2026-06-14); the comment was
## written 4a1e5ff5 (2026-07-29), six weeks LATER, to "stop this being re-filed".
## FALSE when written, in @cowir-sfx's taxonomy — not expired, so no rot check
## could ever have caught it: there is no transition to detect.
##
## Consequence, measured below: Mordaine is the ONE boss authoring the three
## attack_weight-armed intents (aggress 1.4 / turtle 0.6 / exploit_pattern 0.9),
## and he classifies as a caster. His spell rate swings with the LLM's choice.
## The four dragons author none of the three, so for them the comment's conclusion
## happens to hold — which is exactly why it read as true.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")
const ROLLS := 400

var _bm = null


func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)


func _monsters() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	assert_not_null(parsed, "CONTROL: monsters.json parses")
	return (parsed as Dictionary).get("monsters", parsed)


func _from_data(mid: String) -> Combatant:
	var v: Dictionary = _monsters()[mid]
	var st: Dictionary = v.get("stats", {})
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = mid
	c.max_hp = int(st.get("max_hp", 100)); c.current_hp = c.max_hp
	c.max_mp = int(st.get("max_mp", 9999)); c.current_mp = c.max_mp
	c.attack = int(st.get("attack", 10)); c.defense = int(st.get("defense", 10))
	c.magic = int(st.get("magic", 10)); c.magic_defense = int(st.get("magic_defense", 10))
	c.speed = int(st.get("speed", 10))
	c.set_meta("monster_type", mid)
	c.job = {"id": mid, "abilities": (v.get("abilities", []) as Array).duplicate()}
	return c


func _victim() -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Party"
	c.max_hp = 5000; c.current_hp = 5000
	return c


func _resolved_kit(boss: Combatant) -> Array:
	var avail: Array = []
	for aid in (boss.job["abilities"] as Array):
		var a: Dictionary = JobSystem.get_ability(str(aid))
		if not a.is_empty():
			avail.append(a)
	return avail


## Fraction of decisions that were a MAGIC ability, driving the real path.
func _magic_rate(mid: String, intent_id: String) -> float:
	var boss := _from_data(mid)
	if intent_id != "":
		boss.set_meta("llm_intent", intent_id)
	var target := _victim()
	var avail: Array = _resolved_kit(boss)
	assert_gt(avail.size(), 0, "CONTROL: %s's kit resolves against abilities.json" % mid)
	var arch: String = _bm._get_ai_archetype(boss, avail)
	assert_eq(arch, "caster",
		"CONTROL: %s must classify as a caster, or this measures the wrong AI arm" % mid)
	var magic: int = 0
	for _i in ROLLS:
		boss.current_mp = boss.max_mp  # isolate the intent from MP exhaustion
		var action: Dictionary = _bm._execute_archetype_ai(boss, arch, avail, [boss], [target])
		if str(action.get("type", "")) == "ability":
			var a: Dictionary = JobSystem.get_ability(str(action.get("ability_id", "")))
			if str(a.get("type", "")) == "magic":
				magic += 1
	return float(magic) / float(ROLLS)


# ── the finding ───────────────────────────────────────────────────────────────

func test_the_llm_intent_actually_changes_mordaines_spell_rate() -> void:
	var aggressive: float = _magic_rate("chancellor_mordaine", "aggress")
	var defensive: float = _magic_rate("chancellor_mordaine", "turtle")
	gut.p("  mordaine magic rate — aggress %.3f · turtle %.3f" % [aggressive, defensive])
	assert_gt(aggressive, defensive,
		"the W1 final boss must cast MORE under 'aggress' than 'turtle' — the file claims the intent layer is dialogue-only for him, and it is not")
	assert_gt(aggressive - defensive, 0.15,
		"and the gap must be a real mechanical swing, not sampling noise (1.4x vs 0.6x on a 0.75 base)")


func test_an_unarmed_intent_leaves_the_spell_rate_at_baseline() -> void:
	## The discriminator. If ANY intent string moved the rate, the test above would
	## be measuring randomness rather than the bias table.
	var baseline: float = _magic_rate("chancellor_mordaine", "")
	var unarmed: float = _magic_rate("chancellor_mordaine", "fire_resist")
	gut.p("  mordaine magic rate — no intent %.3f · fire_resist (counter-only) %.3f" % [baseline, unarmed])
	assert_lt(absf(baseline - unarmed), 0.15,
		"'fire_resist' carries counter_action_chance only and no attack_weight, so it must NOT move the spell rate")


func test_an_unknown_intent_is_inert_rather_than_disruptive() -> void:
	var baseline: float = _magic_rate("chancellor_mordaine", "")
	var nonsense: float = _magic_rate("chancellor_mordaine", "hokum_pokum")
	assert_lt(absf(baseline - nonsense), 0.15,
		"an intent the table does not know must fall through to no bias — the LLM must never be able to disable a boss by naming garbage")


# ── the data half: which bosses can this reach at all ─────────────────────────

func _intent_ids(bid: String) -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/boss_dialogue.json"))
	assert_not_null(parsed, "CONTROL: boss_dialogue.json parses")
	var root: Dictionary = (parsed as Dictionary).get("bosses", parsed)
	var out: Array = []
	for spec in (root.get(bid, {}) as Dictionary).get("scripted_intents", []):
		if spec is Dictionary:
			out.append(str((spec as Dictionary).get("id", "")))
	return out


func test_mordaine_is_the_only_w1_boss_authoring_an_armed_intent() -> void:
	## Pins WHY the false comment read as true: it is correct for four of the five.
	## The field is "id", not "intent_id" — reading the wrong key returns a plausible,
	## internally consistent "no boss is armed" for all ten entries.
	var armed := {"aggress": true, "turtle": true, "exploit_pattern": true}
	var mordaine: Array = _intent_ids("chancellor_mordaine")
	assert_gt(mordaine.size(), 0,
		"CONTROL: Mordaine's intents must parse by the 'id' key, or this test proves nothing")
	var mordaine_armed: int = 0
	for i in mordaine:
		if armed.has(i):
			mordaine_armed += 1
	assert_eq(mordaine_armed, 3, "Mordaine authors all three attack_weight-armed intents")
	for dragon in ["pyrroth", "glacius", "voltharion", "umbraxis"]:
		var ids: Array = _intent_ids(dragon)
		assert_gt(ids.size(), 0, "CONTROL: %s's intents must parse" % dragon)
		for i in ids:
			assert_false(armed.has(i),
				"%s authors '%s' — a dragon gaining an armed intent makes its fight mechanically intent-driven, which is a design change, not a data tweak" % [dragon, i])
