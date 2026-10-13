extends GutTest

## MAX_FIELD_ENEMIES is checked at SELECTION (_can_monster_summon, via _process_ai_selection) and
## never again. CTB separates selection from execution, so every enemy that decided to summon this
## round measured the SAME field snapshot: at 4 alive, two summoners both pass 4 < 5, both queue,
## and both execute through the dispatcher arm at _execute_next_action -> _execute_summon, which has
## no ceiling check. The field reaches 6, past a ceiling whose own comment says it exists to
## "prevent overwhelming battles". test_a_full_field_refuses_rather_than_floods passes throughout:
## it fills to 5 and drives the ABILITY path, which is guarded separately in _execute_ally_summon.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")

var _bm = null
var _spawned: Array = []


func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)
	_spawned = []
	## Mirrors production: BattleScene._on_monster_summoned appends the new enemy to
	## BattleManager.enemy_party (:6626). Godot signals are synchronous, so the field has already
	## grown by the time the next queued action executes — without that, nothing can grow and the
	## ceiling re-check below could never fire, which is a fixture that cannot see its own subject.
	_bm.monster_summoned.connect(func(mtype, _summoner):
		_spawned.append(str(mtype))
		var born := Combatant.new()
		autofree(born)
		born.combatant_name = "Summoned %d" % _spawned.size()
		born.max_hp = 10
		born.current_hp = 10
		born.set_meta("monster_type", str(mtype))
		_bm.enemy_party.append(born))


func _enemy(nm: String, mtype: String) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = nm
	c.max_hp = 20
	c.current_hp = 20
	c.set_meta("monster_type", mtype)
	_bm.enemy_party.append(c)
	return c


func test_two_summoners_at_four_alive_cannot_push_the_field_past_the_ceiling() -> void:
	var g1 := _enemy("Goblin A", "goblin")
	var g2 := _enemy("Goblin B", "goblin")
	_enemy("Mook A", "slime")
	_enemy("Mook B", "slime")

	## CONTROL: the selection snapshot both summoners measured. 4 < 5, so BOTH were allowed to
	## queue — this is the premise, and if it ever fails the scenario below is not the real one.
	assert_eq(_bm._alive_enemy_count(), 4, "CONTROL: four alive, one slot under the ceiling")
	assert_true(_bm._can_monster_summon(g1), "CONTROL: the first summoner was allowed to queue")
	assert_true(_bm._can_monster_summon(g2), "CONTROL: so was the second, off the same snapshot")

	## Execution phase: both queued actions resolve through the dispatcher.
	_bm._execute_summon(g1, "goblin")
	_bm._execute_summon(g2, "goblin")

	assert_eq(_spawned.size(), 1,
		"the second queued summon must be refused at EXECUTION — the ceiling is measured at " +
		"selection, so two summoners at 4 alive otherwise put 6 enemies on a 5-enemy field")


func test_a_single_summon_at_four_alive_is_still_allowed() -> void:
	## The regression this fix could cause: refusing the FIRST summon too would silently remove
	## reinforcements from every ordinary fight.
	var g := _enemy("Goblin A", "goblin")
	_enemy("Mook A", "slime")
	_enemy("Mook B", "slime")
	_enemy("Mook C", "slime")
	assert_eq(_bm._alive_enemy_count(), 4, "CONTROL: one slot free")
	_bm._execute_summon(g, "goblin")
	assert_eq(_spawned.size(), 1, "a lone summon into the last slot must still land")
