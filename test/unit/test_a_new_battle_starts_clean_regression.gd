extends GutTest

## Regression (render smoke, .549): a battle started over one that never reached end_battle logged
## "Signal 'died' is already connected" and left the old battle's combatants wired to BattleManager;
## and every New Game logged "'weapon_mastery' already equipped on Fighter — equip failed" because
## JobSystem.assign_job already equips a job's roster passives before _create_party equipped them again.

const BattleState := preload("res://test/unit/helpers/battle_state.gd")

var _bm_guard: RefCounted = null


func before_all() -> void:
	_bm_guard = BattleState.new()
	_bm_guard.snapshot()


func after_all() -> void:
	if _bm_guard != null:
		_bm_guard.restore()


func _combatant(n: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": n, "max_hp": 100, "max_mp": 10, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func _died_links(c: Combatant) -> int:
	var n := 0
	for conn in c.died.get_connections():
		var cb: Callable = conn["callable"]
		if cb.get_object() == BattleManager and cb.get_method() == "_on_combatant_died":
			n += 1
	return n


func test_a_battle_started_over_an_abandoned_one_unwires_the_old_combatants() -> void:
	var hero := _combatant("Hero")
	var slime := _combatant("Slime")
	var bat := _combatant("Bat")
	var p: Array[Combatant] = [hero]
	var e1: Array[Combatant] = [slime]
	BattleManager.start_battle(p, e1)
	assert_eq(_died_links(slime), 1, "CONTROL: start_battle wires each combatant's died signal once")
	var e2: Array[Combatant] = [bat]
	BattleManager.start_battle(p, e2)
	assert_eq(_died_links(slime), 0,
		"the abandoned battle's enemy is still wired to BattleManager: start_battle cleared its callback map without disconnecting it")
	assert_eq(_died_links(hero), 1, "the party member carried into the new battle is wired exactly once")
	assert_eq(_died_links(bat), 1, "the new enemy is wired")
	BattleManager._cleanup_battle()
	assert_eq(_died_links(hero) + _died_links(bat), 0, "cleanup still unwires everything it connected")


func test_a_roster_passive_is_equipped_once_and_quietly() -> void:
	## First, so a missing helper reds here instead of aborting this arm after its controls passed.
	assert_true(PassiveSystem.has_method("ensure_equipped"), "PassiveSystem.ensure_equipped is gone")
	var f := _combatant("Fighter")
	JobSystem.assign_job(f, "fighter")
	var roster: Array = (f.job as Dictionary).get("passive_abilities", [])
	assert_false(roster.is_empty(), "SCOPE: the fighter's roster grants a passive, so there is something to equip twice")
	var pid: String = str(roster[0])
	assert_true(pid in f.equipped_passives, "CONTROL: assign_job already equipped %s" % pid)
	assert_false(PassiveSystem.equip_passive(f, pid), "CONTROL: the raw equip refuses a second copy, which is what logged 'equip failed'")
	assert_true(PassiveSystem.ensure_equipped(f, pid), "wanting it ON when it is already ON is a success, not a failed equip")
	assert_eq(f.equipped_passives.count(pid), 1, "still exactly one copy")


func test_the_starting_party_never_raw_equips_a_passive() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var at: int = src.find("func _create_party(")
	assert_gt(at, 0, "SCOPE: _create_party exists")
	var end: int = src.find("\nfunc ", at + 1)
	var body: String = src.substr(at, end - at)
	assert_true(body.contains("PassiveSystem.ensure_equipped("), "SCOPE: the starting party does equip passives")
	assert_false(body.contains("PassiveSystem.equip_passive("),
		"_create_party raw-equips a passive; assign_job may already have equipped it, and New Game logs 'equip failed'")
