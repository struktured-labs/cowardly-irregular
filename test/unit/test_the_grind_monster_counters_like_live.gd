extends GutTest

## Live answers a landed swing on a monster with counter_abilities 40% of the time (BattleManager._trigger_monster_counter).
## The grind resolver never read the field, so optimization_itself (abstract_overworld pool) never countered in a grind.

const RESOLVER := preload("res://src/autogrind/HeadlessBattleResolver.gd")
const COUNTERER := "optimization_itself"

var _res = null


func before_each() -> void:
	seed(20261114)
	_res = RESOLVER.new()


func after_each() -> void:
	if _res != null:
		_res.free()
	_res = null


func _make(name_str: String, monster_type: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name_str, "max_hp": 9999999, "max_mp": 0,
		"attack": 60, "defense": 50, "magic": 10, "speed": 100})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	if monster_type != "":
		c.set_meta("monster_type", monster_type)
	return c


## Lines from n basic attacks by a hero on a monster of `monster_type`, through the resolver's own action executor.
func _swing(monster_type: String, n: int, hero: Combatant = null, foe: Combatant = null) -> Array:
	if hero == null:
		hero = _make("Hero", "")
	if foe == null:
		foe = _make("Foe", monster_type)
	_res._player_party = [hero]
	_res._enemy_party = [foe]
	_res._battle_log.clear()
	for i in n:
		_res._execute_action({"type": "attack", "combatant": hero, "target": foe})
	return _res._battle_log.duplicate()


func _count(lines: Array, needle: String) -> int:
	var n := 0
	for line in lines:
		if needle in str(line):
			n += 1
	return n


func test_floor_the_resolver_carries_the_counter_twin() -> void:
	assert_true(_res.has_method("_maybe_monster_counter"), "FLOOR: HeadlessBattleResolver._maybe_monster_counter is gone")
	assert_true(_res.has_method("_counter_targets"), "FLOOR: HeadlessBattleResolver._counter_targets is gone")


func test_control_the_pooled_monster_authors_counters() -> void:
	var row: Dictionary = EncounterSystem.monster_database.get(COUNTERER, {})
	assert_false(row.is_empty(), "CONTROL: %s must be in the monster database" % COUNTERER)
	assert_false((row.get("counter_abilities", []) as Array).is_empty(), "CONTROL: %s must author counter_abilities" % COUNTERER)


func test_a_struck_counterer_answers_about_two_hits_in_five() -> void:
	var lines := _swing(COUNTERER, 200)
	var hits := _count(lines, " attacks ")
	var counters := _count(lines, " counters with ")
	assert_gt(hits, 150, "CONTROL: most swings land: %d of 200" % hits)
	var rate := float(counters) / float(max(1, hits))
	assert_between(rate, 0.25, 0.55, "live counters 40%% of landed hits; the grind countered %d of %d" % [counters, hits])


func test_the_counter_strike_lands_on_the_attacker() -> void:
	var hero := _make("Hero", "")
	var lines := _swing(COUNTERER, 200, hero)
	assert_gt(_count(lines, "counters with Counter!"), 0, "CONTROL: the physical Counter fired at least once: %s" % str(lines.slice(0, 6)))
	assert_lt(hero.current_hp, hero.max_hp, "a Counter must hurt the hero who swung")


func test_a_silenced_monster_still_counters_like_live() -> void:
	var foe := _make("Foe", COUNTERER)
	foe.add_status("silence", 999)
	var lines := _swing(COUNTERER, 100, null, foe)
	assert_true(foe.has_status("silence"), "CONTROL: the foe stayed silenced")
	assert_gt(_count(lines, " counters with "), 0, "live's counter skips the silence check; the grind refused it")


func test_control_a_monster_without_counters_never_answers() -> void:
	var lines := _swing("slime", 100)
	assert_gt(_count(lines, " attacks "), 50, "CONTROL: the swings landed")
	assert_eq(_count(lines, " counters with "), 0, "a monster that authors no counter_abilities must never counter")
