extends GutTest

## Mordaine cast firaga 2268 times in 3000 turns and nothing else. void_pulse: never.
##
## _ai_caster kept the single highest-scoring spell, the same single-slot rule the tank and assassin
## had. Measured on the live decision path, the two casters on the W1 spine each used exactly ONE
## ability all fight — shadow_dragon void_breath, chancellor_mordaine firaga.
##
## ⛔ AND THAT GATED TWO OF MY OWN FIXES FROM EARLIER TODAY. Silence blocked nothing until this
## morning; its only two sources are void_pulse (mordaine, the_calibrant, castle_warden…) and
## null_field (shadow_dragon). Both belong to casters. So the repair landed, was folded, was tagged
## — and neither boss could reach the ability that delivers it. Third time today that a correct fix
## sat behind a selection gate, which is why the reachability question now comes before the fix.
##
## Scoring still orders the list and weakness exploitation is still the primary sort; the bias only
## stops the top entry being the only one that can ever win.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")
const ROLLS := 600

var _bm = null

func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)

func _monsters() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	assert_not_null(parsed, "CONTROL: monsters.json parses")
	return (parsed as Dictionary).get("monsters", parsed)

func _selectable(mid: String) -> Dictionary:
	var v: Dictionary = _monsters()[mid]
	var st: Dictionary = v.get("stats", {})
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = mid
	c.max_hp = int(st.get("max_hp", 100)); c.current_hp = c.max_hp
	c.max_mp = 99999; c.current_mp = 99999
	c.attack = int(st.get("attack", 10)); c.defense = int(st.get("defense", 10))
	c.magic = int(st.get("magic", 10)); c.speed = int(st.get("speed", 10))
	c.set_meta("monster_type", mid)
	var avail: Array = []
	for aid in (v.get("abilities", []) as Array):
		var a: Dictionary = JobSystem.get_ability(str(aid))
		if not a.is_empty():
			avail.append(a)
	assert_gt(avail.size(), 0, "CONTROL: %s's kit resolves" % mid)
	var arch: String = _bm._get_ai_archetype(c, avail)
	var hero := Combatant.new()
	autofree(hero)
	hero.combatant_name = "Hero"
	hero.max_hp = 900000; hero.current_hp = 900000
	var seen: Dictionary = {"_archetype": arch}
	for _i in ROLLS:
		var action: Dictionary = _bm._execute_archetype_ai(c, arch, avail, [c], [hero])
		if str(action.get("type", "")) == "ability":
			seen[str(action.get("ability_id", ""))] = true
	return seen

func test_mordaine_can_cast_void_pulse() -> void:
	## The W1 FINAL BOSS's silence. This is the ability that makes this morning's silence gate real;
	## without it that fix is correct and unreachable.
	var seen := _selectable("chancellor_mordaine")
	assert_eq(seen["_archetype"], "caster", "CONTROL: the classifier still calls Mordaine a caster")
	assert_true(seen.has("void_pulse"),
		"Mordaine must be able to reach void_pulse — the silence fix has nothing to ride on otherwise")

func test_umbraxis_can_cast_null_field() -> void:
	var seen := _selectable("shadow_dragon")
	assert_true(seen.has("null_field"),
		"the Void Render's ability-suppression field must be reachable — the other half of silence")

func test_a_caster_reaches_most_of_its_book() -> void:
	## The variety property. One spell on repeat is what this replaces.
	for mid in ["chancellor_mordaine", "shadow_dragon"]:
		var seen := _selectable(mid)
		assert_gte(seen.size() - 1, 3, "%s selected only %d distinct spells" % [mid, seen.size() - 1])

func test_weakness_exploitation_still_orders_the_book() -> void:
	## The discriminator: the bias must not have flattened the heuristic into a coin flip. A spell
	## whose element the target is weak to must score above a stronger spell it resists.
	var weak_target := Combatant.new()
	autofree(weak_target)
	weak_target.combatant_name = "Strawman"
	weak_target.elemental_weaknesses.append("fire")
	var small_fire: Dictionary = {"id": "ember", "element": "fire", "damage_multiplier": 1.0}
	var big_plain: Dictionary = {"id": "smash", "element": "", "damage_multiplier": 1.8}
	assert_gt(_bm._caster_spell_score(small_fire, [weak_target]), _bm._caster_spell_score(big_plain, [weak_target]),
		"a weakness-matching spell must outrank a stronger neutral one — that is the whole heuristic")
	assert_eq(_bm._caster_spell_score(big_plain, [weak_target]), 1.8,
		"CONTROL: an element-less spell scores its raw power, undoubled")

func test_the_scorer_does_not_double_for_a_resistant_target() -> void:
	var tough := Combatant.new()
	autofree(tough)
	tough.combatant_name = "Tough"
	var fire: Dictionary = {"id": "ember", "element": "fire", "damage_multiplier": 1.0}
	assert_eq(_bm._caster_spell_score(fire, [tough]), 1.0,
		"no weakness, no bonus — otherwise every spell doubles and the ordering is noise")
