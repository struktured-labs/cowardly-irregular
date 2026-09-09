extends GutTest

## "Voltharion's kit is 4/5 magic — without this the telegraph never lands." It never landed.
##
## That comment sits above the code that CONSUMES storm_gathering's next_attack_multiplier, and the
## consumption is correct. Selection was the gate: Voltharion classifies as an assassin, and
## _ai_assassin could pick only `physical` and `magic`. storm_gathering is `support`. So the
## telegraph the comment was written to make land has never been cast, and the ability that reads it
## has never had anything to read.
##
## _ai_tank had a utility slot; assassin, brute and caster did not. Measured across the roster, 25
## monsters carried support abilities no archetype they reach could select — Voltharion's overcharge
## and storm_gathering, two of the five Spotlight Duel minibosses' defensive moves, and the common
## W1 kit: goblin's steal, wolf's howl, spider's web_shot, skeleton's rattle, ogre's enrage.
##
## ⚠️ The 24 masterite_* monsters looked stranded too and are NOT: they route through
## _make_masterite_decision before the archetype ladder is reached. Probing the archetype path for
## monsters that never take it inflated my first count from 25 to 37 — the corpus error, in the
## instrument built to find corpus errors.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")
const ROLLS := 500

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
	hero.max_hp = 900000; hero.current_hp = 900000
	var seen: Dictionary = {"_archetype": arch, "_kit": avail.size()}
	for _i in ROLLS:
		var action: Dictionary = _bm._execute_archetype_ai(c, arch, avail, [c], [hero])
		if str(action.get("type", "")) == "ability":
			seen[str(action.get("ability_id", ""))] = true
	return seen

func test_voltharion_can_gather_the_storm() -> void:
	var seen := _selectable("lightning_dragon")
	assert_eq(seen["_archetype"], "assassin", "CONTROL: the Storm's Edge still classifies as an assassin")
	assert_true(seen.has("storm_gathering"),
		"the telegraph must be castable — the code that consumes it has never had anything to consume")

func test_the_two_spotlight_minibosses_reach_their_defensive_moves() -> void:
	## rogue_lockward and mage_prismatic_construct are duel opponents built to showcase a PC's kit.
	assert_true(_selectable("rogue_lockward").has("masterite_counter_stance"),
		"the Rogue's duel opponent must be able to take its counter stance")
	assert_true(_selectable("mage_prismatic_construct").has("masterite_iron_guard"),
		"the Mage's duel opponent must be able to guard")

func test_a_self_buff_is_not_aimed_at_the_party() -> void:
	## The bug I wrote and caught in the same hour: I passed alive_enemies into a parameter named
	## alive_allies, which would have handed the party a monster's self-buff. Target selection now
	## reads target_type, so only enemy-facing utility goes to an enemy.
	var boss := Combatant.new()
	autofree(boss)
	boss.combatant_name = "Boss"
	boss.max_hp = 100; boss.current_hp = 100
	var hero := Combatant.new()
	autofree(hero)
	hero.combatant_name = "Hero"
	hero.max_hp = 100; hero.current_hp = 100
	var self_buff: Dictionary = {"id": "brace", "type": "support", "target_type": "self"}
	var enemy_debuff: Dictionary = {"id": "jeer", "type": "support", "target_type": "single_enemy"}
	var buff_targets: Array = []
	var debuff_targets: Array = []
	for _i in 200:
		var a: Dictionary = _bm._ai_utility_action(boss, [self_buff], [hero], 1.0)
		if not a.is_empty():
			buff_targets.append(a["targets"][0])
		var b: Dictionary = _bm._ai_utility_action(boss, [enemy_debuff], [hero], 1.0)
		if not b.is_empty():
			debuff_targets.append(b["targets"][0])
	assert_gt(buff_targets.size(), 0, "CONTROL: a chance of 1.0 always returns an action")
	for t in buff_targets:
		assert_eq(t, boss, "a self-targeted buff must land on the caster")
	for t in debuff_targets:
		assert_eq(t, hero, "an enemy-targeted utility must land on the enemy")

func test_the_utility_slot_declines_often_enough_to_fall_through() -> void:
	## The discriminator. If it always fired, an assassin would stop being an assassin.
	var boss := Combatant.new()
	autofree(boss)
	boss.combatant_name = "Boss"
	var buff: Dictionary = {"id": "brace", "type": "support", "target_type": "self"}
	var taken: int = 0
	for _i in 1000:
		if not _bm._ai_utility_action(boss, [buff], [], 0.25).is_empty():
			taken += 1
	assert_gt(taken, 150, "CONTROL: it fires — %d of 1000 at a 0.25 chance" % taken)
	assert_lt(taken, 400, "and it declines most of the time, or the archetype's own behaviour is drowned")

func test_an_empty_utility_pool_returns_nothing() -> void:
	var boss := Combatant.new()
	autofree(boss)
	assert_eq(_bm._ai_utility_action(boss, [], [], 1.0), {},
		"no utility abilities means no action, not a crash and not an empty ability id")

func test_the_roster_reach_ratchet() -> void:
	## Measured this hour: 98 of 106 monsters can reach their whole kit. It was 24 this morning.
	## A ratchet, not a target — a new monster whose archetype cannot reach its kit reds this.
	var full: int = 0
	var total: int = 0
	for mid in _monsters():
		var v: Dictionary = _monsters()[mid]
		if (v.get("abilities", []) as Array).is_empty():
			continue
		total += 1
		var seen := _selectable(mid)
		if seen.size() - 2 >= int(seen["_kit"]):
			full += 1
	assert_gt(total, 100, "CONTROL: the whole roster was walked (%d)" % total)
	assert_gte(full, 98, "reach regressed: %d of %d, was 98 of 106 when this landed" % [full, total])
