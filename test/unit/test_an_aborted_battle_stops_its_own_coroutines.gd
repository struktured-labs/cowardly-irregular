extends GutTest

## cowir-autogrind, 4/4 SEGFAULT: stop a WATCHED autogrind mid-action, restart, crash. BattleManager is
## an autoload, so its execution coroutines survive the scene; an awaiting _execute_advance /
## _execute_next_action resumed after the stop and acted on freed combatants or on the NEXT battle.
## battle_serial existed (the LLM-line coroutines use it) but no execution await checked it, and
## nothing bumped it on a stop. abort_battle() now bumps it and every execution resume returns.

var _saved: Dictionary = {}


func before_each() -> void:
	var bm = BattleManager
	_saved = {"pp": bm.player_party.duplicate(), "ep": bm.enemy_party.duplicate(), "all": bm.all_combatants.duplicate(),
		"state": bm.current_state, "hold": bm.presentation_hold, "turbo": bm.turbo_mode}


func after_each() -> void:
	var bm = BattleManager
	bm.player_party.assign(_saved["pp"].filter(func(x): return is_instance_valid(x)))
	bm.enemy_party.assign(_saved["ep"].filter(func(x): return is_instance_valid(x)))
	bm.all_combatants.assign(_saved["all"].filter(func(x): return is_instance_valid(x)))
	bm.current_state = _saved["state"]
	bm.presentation_hold = _saved["hold"]
	bm.turbo_mode = _saved["turbo"]


func _c(n: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": n, "max_hp": 100000, "max_mp": 10, "attack": 50, "defense": 0, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


## Starts an Advance that awaits its presentation hold, optionally aborts during it, then reports
## whether the Advance's swing landed on the foe.
func _swing_landed(abort_during_hold: bool) -> bool:
	var bm = BattleManager
	var hero := _c("Hero")
	var foe := _c("Foe")
	bm.player_party.assign([hero] as Array[Combatant])
	bm.enemy_party.assign([foe] as Array[Combatant])
	bm.current_state = bm.BattleState.PROCESSING_ACTION
	bm.turbo_mode = false
	bm.presentation_hold = 0.3
	var before := foe.current_hp
	bm._execute_advance(hero, {"type": "advance", "actions": [{"type": "attack", "target": foe}, {"type": "attack", "target": foe}]})
	if abort_during_hold:
		bm.abort_battle()
		## The restart: a NEW battle is live before the old coroutine resumes. INACTIVE alone is not the
		## crash; downstream is_battle_active checks already stop that. A live successor is what it walks into.
		bm.battle_serial += 1
		bm.player_party.assign([hero] as Array[Combatant])
		bm.enemy_party.assign([foe] as Array[Combatant])
		bm.current_state = bm.BattleState.PROCESSING_ACTION
	await wait_seconds(0.2 / maxf(Engine.time_scale, 0.01) + 0.5)
	bm.abort_battle()  # stop the control run's continuation too, so it cannot leak into later files
	return foe.current_hp < before


func test_control_the_advance_swings_when_nothing_aborts_it() -> void:
	assert_true(await _swing_landed(false),
		"CONTROL: without an abort the Advance resumes after its hold and the swing lands; otherwise the arm below proves nothing")


func test_an_aborted_advance_does_not_resume_into_the_world() -> void:
	assert_false(await _swing_landed(true),
		"after abort_battle and a restart, the OLD Advance must return on resume; swinging into the next battle is the SEGFAULT's shape")


func test_abort_leaves_the_manager_inactive_and_silent() -> void:
	var bm = BattleManager
	var ended := [0]
	var cb := func(_v): ended[0] += 1
	bm.battle_ended.connect(cb)
	var serial_before: int = bm.battle_serial
	bm.current_state = bm.BattleState.PROCESSING_ACTION
	bm.abort_battle()
	bm.battle_ended.disconnect(cb)
	assert_eq(bm.current_state, bm.BattleState.INACTIVE, "an aborted battle is not in progress")
	assert_gt(bm.battle_serial, serial_before, "the abort must move battle_serial, or no coroutine can tell")
	assert_eq(ended[0], 0, "an abort is not an ending: no battle_ended, so no rewards or victory flow")
