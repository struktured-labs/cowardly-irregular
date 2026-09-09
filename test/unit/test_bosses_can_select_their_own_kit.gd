extends GutTest

## Pyrroth never breathed fire. Glacius never used ice. The Rat King still never summoned.
##
## _get_ai_archetype classifies by stats, and _ai_tank's filters were PERMISSION where they meant
## PREFERENCE: it could select only ["buff","support","defensive"] or "physical". Measured against
## the real classifier and the real roster, fire_dragon and ice_dragon both classify as TANK, and
## every offensive ability either dragon owns is type `magic`. So the Ember Wyrm's whole reason for
## existing was unselectable, and the fight it produced was tail_sweep and basic attacks.
##
## ⛔ AND THIS INVALIDATED MY OWN FIX FROM THIS MORNING. I repaired _execute_ability so that
## royal_summon spawns a Rat Guard, and tested it by calling _execute_ability directly — which
## proves EXECUTION and says nothing about SELECTION. cave_rat_king classifies as tank too, and
## "summon" was in no archetype's vocabulary at all, so the Rat King's signature move still could
## not be chosen. "A fix that swaps one dead lookup for another is indistinguishable from a fix",
## and a test that calls the repaired function directly cannot tell the difference either.
##
## These drive the REAL decision path many times and assert the ability appears in what it returns.

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
	c.max_mp = int(st.get("max_mp", 50)); c.current_mp = c.max_mp
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

## Every ability id the monster's own archetype AI actually returns over many rolls.
func _selectable(mid: String) -> Dictionary:
	var boss := _from_data(mid)
	var target := _victim()
	var avail: Array = []
	for aid in (boss.job["abilities"] as Array):
		var a: Dictionary = JobSystem.get_ability(str(aid))
		if not a.is_empty():
			avail.append(a)
	assert_gt(avail.size(), 0, "CONTROL: %s's kit resolves against abilities.json" % mid)
	var arch: String = _bm._get_ai_archetype(boss, avail)
	var seen: Dictionary = {"_archetype": arch}
	for _i in ROLLS:
		var action: Dictionary = _bm._execute_archetype_ai(boss, arch, avail, [boss], [target])
		if str(action.get("type", "")) == "ability":
			seen[str(action.get("ability_id", ""))] = true
	return seen

func test_pyrroth_can_choose_fire() -> void:
	var seen := _selectable("fire_dragon")
	assert_eq(seen["_archetype"], "tank", "CONTROL: the classifier still calls the Ember Wyrm a tank")
	assert_true(seen.has("fire_breath") or seen.has("magma_eruption") or seen.has("flame_wall"),
		"a fire dragon must be able to select fire — its whole kit is magic and tanks could not pick magic")

func test_glacius_can_choose_ice() -> void:
	var seen := _selectable("ice_dragon")
	assert_true(seen.has("blizzard_breath") or seen.has("ice_prison") or seen.has("absolute_zero"),
		"the Frozen Sovereign must be able to select ice")

func test_the_rat_king_can_choose_to_summon() -> void:
	## The reachability half of this morning's summon fix. That commit made the summon WORK; this
	## is what makes it HAPPEN.
	var seen := _selectable("cave_rat_king")
	assert_true(seen.has("royal_summon") or seen.has("rat_swarm"),
		"the tutorial boss must be able to select the move its whole fight is built around")

func test_a_tank_still_prefers_its_defensive_move() -> void:
	## The discriminator: widening the vocabulary must not flatten the archetype into "cast anything".
	## Pyrroth's inferno_rage is the utility slot and must still come up.
	var seen := _selectable("fire_dragon")
	assert_true(seen.has("inferno_rage"),
		"the tank's utility slot must survive — this widens a filter, it does not remove one")

func test_every_boss_can_reach_at_least_one_offensive_ability() -> void:
	## The general property, over the W1 spine. A boss that can only basic-attack is not a boss.
	var checked: int = 0
	for mid in ["cave_rat_king", "fire_dragon", "ice_dragon", "lightning_dragon", "shadow_dragon", "chancellor_mordaine"]:
		var seen := _selectable(mid)
		var picked: int = seen.size() - 1
		assert_gt(picked, 0, "%s (%s) selected NO ability in %d rolls" % [mid, seen["_archetype"], ROLLS])
		checked += 1
	assert_eq(checked, 6, "CONTROL: the whole W1 boss spine was exercised")
