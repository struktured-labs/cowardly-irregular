extends GutTest

## elder_mushroom never released a spore. Four abilities, three offensive, none reachable.
##
## _ai_healer's own docstring says "attack only when no one needs healing" — and the attack it fell
## back to was a BASIC one. The archetype could select `healing` and `["buff","support"]` and nothing
## else, so a healer monster's entire offensive kit was decoration. Measured with the real classifier
## before the fix, at full HP the mushroom selected NO ability at all in 400 rolls; wounded, it
## selected exactly one, its heal.
##
## Same permission-vs-preference shape as _ai_tank, which is what sent me looking: the filter was
## written to express what the archetype PREFERS and enforced as what it is ALLOWED. The intent was
## already in the docstring; only the fallback never reached the kit.
##
## Blast radius, stated because it is a behaviour change to shipped fights: 5 monsters classify as
## healer and 4 of them gain abilities — crystal_golem, rogue_automaton, elder_mushroom, memory_leak.
## new_age_retro_hippie authors no offensive ability and is unaffected, which is the natural control.

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

func _from_data(mid: String, hp_fraction: float) -> Combatant:
	var v: Dictionary = _monsters()[mid]
	var st: Dictionary = v.get("stats", {})
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = mid
	c.max_hp = int(st.get("max_hp", 100)); c.current_hp = int(float(c.max_hp) * hp_fraction)
	c.max_mp = int(st.get("max_mp", 50)); c.current_mp = c.max_mp
	c.attack = int(st.get("attack", 10)); c.defense = int(st.get("defense", 10))
	c.magic = int(st.get("magic", 10)); c.speed = int(st.get("speed", 10))
	c.set_meta("monster_type", mid)
	c.job = {"id": mid, "abilities": (v.get("abilities", []) as Array).duplicate()}
	return c

## Every ability id the monster's own archetype AI returns, at the given HP fraction.
func _selectable(mid: String, hp_fraction: float = 1.0) -> Dictionary:
	var mob := _from_data(mid, hp_fraction)
	var victim := Combatant.new()
	autofree(victim)
	victim.combatant_name = "Party"
	victim.max_hp = 9000; victim.current_hp = 9000
	var avail: Array = []
	for aid in (mob.job["abilities"] as Array):
		var a: Dictionary = JobSystem.get_ability(str(aid))
		if not a.is_empty():
			avail.append(a)
	assert_gt(avail.size(), 0, "CONTROL: %s's kit resolves against abilities.json" % mid)
	var arch: String = _bm._get_ai_archetype(mob, avail)
	var seen: Dictionary = {"_archetype": arch}
	for _i in ROLLS:
		var action: Dictionary = _bm._execute_archetype_ai(mob, arch, avail, [mob], [victim])
		if str(action.get("type", "")) == "ability":
			seen[str(action.get("ability_id", ""))] = true
	return seen

func test_the_mushroom_can_release_its_spores() -> void:
	var seen := _selectable("elder_mushroom")
	assert_eq(seen["_archetype"], "healer", "CONTROL: the classifier still calls it a healer")
	assert_true(seen.has("toxic_cloud") or seen.has("hallucination_spores") or seen.has("root_bind"),
		"a healer at full HP must be able to reach its own offensive kit — it had none of it")

func test_the_automaton_can_use_its_three_attacks() -> void:
	var seen := _selectable("rogue_automaton")
	assert_true(seen.has("voltage_surge") or seen.has("segfault_slash") or seen.has("buffer_overflow"),
		"three authored attacks must be reachable")

func test_healing_still_comes_first_when_someone_is_hurt() -> void:
	## The discriminator. If the offensive branch were placed above the heal, a wounded healer would
	## start trading blows instead of healing, which is the opposite of the archetype.
	var seen := _selectable("elder_mushroom", 0.3)
	assert_true(seen.has("regenerate"),
		"a wounded healer must still heal — this adds a fallback, it does not reorder the priorities")

func test_a_healer_with_no_offensive_kit_is_unaffected() -> void:
	## The natural control: new_age_retro_hippie authors no physical or magic ability, so the new
	## branch cannot fire for it and its behaviour must be identical.
	var kit: Array = _monsters()["new_age_retro_hippie"].get("abilities", [])
	var offensive: Array = []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var ab: Dictionary = (parsed as Dictionary).get("abilities", parsed)
	for aid in kit:
		if str((ab.get(str(aid), {}) as Dictionary).get("type", "")) in ["physical", "magic"]:
			offensive.append(aid)
	assert_eq(offensive.size(), 0,
		"CONTROL: this monster has no offensive ability, so it is the untouched case — if that changes, the control moved")

func test_every_healer_reaches_something_at_full_health() -> void:
	## The general property. A monster that can select nothing while healthy is a basic-attack loop.
	var checked: int = 0
	for mid in ["crystal_golem", "rogue_automaton", "elder_mushroom", "memory_leak"]:
		var seen := _selectable(mid)
		assert_gt(seen.size() - 1, 0, "%s selected NO ability in %d rolls at full HP" % [mid, ROLLS])
		checked += 1
	assert_eq(checked, 4, "CONTROL: the four healers with offensive kits were exercised")
