extends GutTest

## Royal Spite (struktured 2026-11-14): the Rat King's counter speaks first, lands on its own heavy beat, and hits no harder than Counter.

const MONSTERS := "res://data/monsters.json"
const ABILITIES := "res://data/abilities.json"
const SCENE := "res://src/battle/BattleScene.gd"

var _monster: Combatant = null
var _scene: Node = null
var _taunts: Array = []
var _logs: Array = []
var _started: Array = []


func after_each() -> void:
	if _monster != null and is_instance_valid(_monster) and BattleManager.enemy_party.has(_monster):
		BattleManager.enemy_party.erase(_monster)
	_monster = null
	for pair in [[BattleManager.boss_taunt, _on_taunt], [BattleManager.battle_log_message, _on_log], [BattleManager.monster_counter_started, _on_started]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	if _scene != null and is_instance_valid(_scene):
		_scene.free()
	_scene = null


func _json(path: String) -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


func _make(name_str: String, hp: int, atk: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name_str, "max_hp": hp, "max_mp": 50, "attack": atk, "defense": 40, "magic": 10, "magic_defense": 20, "speed": 10})
	add_child_autofree(c)
	return c


func _on_taunt(_boss: Combatant, line: String) -> void:
	_taunts.append(line)
	_logs.append("TAUNT")


func _on_log(msg: String) -> void:
	_logs.append(msg)


func _on_started(_m: Combatant, _t: Combatant, ability_id: String) -> void:
	_started.append(ability_id)
	_logs.append("STARTED")


func test_the_rat_king_counters_with_royal_spite_and_nobody_else_does() -> void:
	var monsters := _json(MONSTERS)
	assert_eq(monsters.get("cave_rat_king", {}).get("counter_abilities", []), ["royal_spite"], "the Rat King's only counter is Royal Spite")
	var others: Array = []
	var generic: int = 0
	for id in monsters:
		var row = monsters[id]
		if id == "cave_rat_king" or not (row is Dictionary):
			continue
		var counters = row.get("counter_abilities", [])
		if counters is Array and counters.has("royal_spite"):
			others.append(id)
		if counters is Array and counters.has("counter"):
			generic += 1
	assert_eq(others, [], "Royal Spite is the Rat King's own; the other bosses keep the generic counter")
	assert_gt(generic, 0, "CONTROL: the generic counter is still authored on the other bosses")


func test_royal_spite_hits_exactly_as_hard_as_counter() -> void:
	var abilities := _json(ABILITIES)
	var spite: Dictionary = abilities.get("royal_spite", {})
	var counter: Dictionary = abilities.get("counter", {})
	assert_eq(str(spite.get("name", "")), "Royal Spite")
	assert_false(counter.is_empty(), "CONTROL: the generic counter still exists to compare against")
	for key in ["type", "damage_multiplier", "target_type", "mp_cost"]:
		assert_eq(spite.get(key), counter.get(key), "struktured: no extra damage; Royal Spite matches Counter's %s" % key)
	assert_false(spite.has("element") or spite.has("crit_bonus") or spite.has("effect"), "nothing on Royal Spite may add to the hit")


func test_the_first_royal_spite_speaks_before_it_lands_and_the_next_does_not() -> void:
	if EncounterSystem == null or not EncounterSystem.monster_database.has("cave_rat_king"):
		pending("cave_rat_king must be in EncounterSystem.monster_database")
		return
	var line: String = BossDialogue.get_counter_first_line("cave_rat_king")
	assert_ne(line, "", "boss_dialogue.json authors the Rat King's first-counter line")
	_monster = _make("Cave Rat King", 4000, 60)
	_monster.set_meta("monster_type", "cave_rat_king")
	BattleManager.enemy_party.append(_monster)
	var hero := _make("Hero", 99999, 10)
	BattleManager.boss_taunt.connect(_on_taunt)
	BattleManager.battle_log_message.connect(_on_log)
	BattleManager.monster_counter_started.connect(_on_started)
	for _i in range(200):
		BattleManager._trigger_monster_counter(_monster, hero)
		if _started.size() >= 3:
			break
	assert_gte(_started.size(), 3, "the 40% counter must fire three times in 200 hits")
	assert_eq(_started, ["royal_spite", "royal_spite", "royal_spite"], "every counter was Royal Spite")
	assert_eq(_taunts, [line], "the Rat King speaks on his FIRST Royal Spite only")
	var first_taunt: int = _logs.find("TAUNT")
	var first_started: int = _logs.find("STARTED")
	assert_true(first_taunt >= 0 and first_taunt < first_started, "the line comes BEFORE the hit resolves: %s" % str(_logs.slice(0, 6)))
	var named: int = 0
	for m in _logs:
		if str(m).contains("answers with Royal Spite!"):
			named += 1
	assert_eq(named, 3, "every Royal Spite is named in the log, in its own verb")


func test_the_beat_lands_at_full_weight_and_the_generic_counter_does_not() -> void:
	var spite: Dictionary = JobSystem.get_ability("royal_spite")
	var counter: Dictionary = JobSystem.get_ability("counter")
	var hero := _make("Hero", 1000, 10)
	var chip: Array = [[hero, 20, false, "", 1.0]]
	var scene_script: GDScript = load(SCENE)
	var heavy: Dictionary = scene_script.counter_impact(spite, chip, hero)
	assert_eq(float(heavy["w"]), 1.0, "Royal Spite's beat lands at the heaviest weight however small its number")
	assert_eq(scene_script.hitstop_for(heavy), scene_script.HIT_HITSTOP.y, "so its freeze is the longest a non-kill hit has")
	var plain: Dictionary = scene_script.counter_impact(counter, chip, hero)
	assert_almost_eq(float(plain["w"]), 0.02, 0.001, "CONTROL: the generic counter's chip stays a chip")
	assert_eq(float(scene_script.counter_impact(spite, [], hero)["w"]), 0.0, "a miss lands no weight")
	assert_almost_eq(scene_script.counter_lead(true, 0.4), 0.4 + scene_script.COUNTER_GAP, 0.0001, "the beat waits for the hero's own contact")
	assert_almost_eq(scene_script.counter_lead(false, 0.4), scene_script.COUNTER_GAP, 0.0001, "and only the gap when no swing is in flight")


func test_the_counter_number_leaves_the_heros_swing() -> void:
	_scene = load(SCENE).new()
	if _scene._tier() == BattleJuice.Tier.OFF:
		pending("the beat is off at this juice tier; the lift is untestable here")
		return
	var hero := _make("Hero", 1000, 10)
	var rat := _make("Rat", 1000, 10)
	_scene._full_render_dmg_buffer = [[rat, 50, false, "", 1.0]]
	_scene._on_monster_counter_started(rat, hero, "royal_spite")
	(_scene._full_render_dmg_buffer as Array).append([hero, 77, false, "", 1.0])
	var lifted: Array = _scene._lift_counter_entries()
	assert_eq(lifted.size(), 1, "the counter's number is lifted out")
	assert_eq(int(lifted[0][1]), 77)
	assert_eq((_scene._full_render_dmg_buffer as Array).size(), 1, "the hero's own hit stays held for the hero's contact")
	assert_eq(int(_scene._full_render_dmg_buffer[0][1]), 50)
	_scene._full_render_dmg_buffer = null
	_scene._on_monster_counter_started(rat, hero, "royal_spite")
	assert_not_null(_scene._full_render_dmg_buffer, "with nothing held, the counter opens its own hold")
	(_scene._full_render_dmg_buffer as Array).append([hero, 9, false, "", 1.0])
	assert_eq(_scene._lift_counter_entries().size(), 1)
	assert_null(_scene._full_render_dmg_buffer, "and closes it again, so later numbers are not swallowed")
