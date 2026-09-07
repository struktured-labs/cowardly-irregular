extends GutTest

## A victory check on a finished battle declared DEFEAT after a win (2026-07-30).
##
## end_battle() -> _cleanup_battle() clears player_party and enemy_party. The
## check opens with:
##
##     var players_alive = player_party.any(func(p): return p.is_alive)
##     if not players_alive: end_battle(false)
##
## `[].any()` is false, so "nobody is alive" and "nobody exists" are the same
## answer. Any SECOND call — from an await resuming after the battle ended —
## read the emptied party as a party wipe and emitted battle_ended(false).
## Measured before the fix: returns true, state INACTIVE, battle_ended=[false],
## immediately after a victory.
##
## Reachable because the execution chain awaits: _execute_next_action and
## _execute_group_action both call this after `await`, and the battle can end
## underneath them.
##
## The fix returns TRUE (stop) rather than false. Callers are all
## `if _check_victory_conditions(): return`, so false would let them fall
## through to _start_new_round(), which sets SELECTION_PHASE with no
## battle-over guard — trading a spurious defeat for a resurrected selection
## state after victory.

var _bm: Node


func before_each() -> void:
	_bm = load("res://src/battle/BattleManager.gd").new()
	add_child_autofree(_bm)


func _pc(n: String) -> Combatant:
	var c: Combatant = autofree(Combatant.new())
	c.combatant_name = n
	c.is_alive = true
	c.max_hp = 100
	c.current_hp = 100
	return c


## ── the regression ───────────────────────────────────────────────────

func test_a_finished_battle_does_not_re_fire_an_outcome() -> void:
	var seen: Array = []
	_bm.battle_ended.connect(func(v): seen.append(v))
	_bm.current_state = _bm.BattleState.VICTORY
	# Parties cleared, as _cleanup_battle leaves them — that emptiness IS the bug.
	var stop: bool = _bm._check_victory_conditions()
	assert_eq(seen, [],
		"a check on an already-ended battle must emit NOTHING — it emitted battle_ended(false), a defeat after a win")
	assert_true(stop,
		"and must still report STOP, or the caller runs on into _start_new_round() and resurrects a selection state")


func test_defeat_state_is_equally_terminal() -> void:
	# The other terminal state. A wipe followed by a resumed await had the
	# mirror problem: enemies_alive false on an emptied roster reads as a win.
	var seen: Array = []
	_bm.battle_ended.connect(func(v): seen.append(v))
	_bm.current_state = _bm.BattleState.DEFEAT
	assert_true(_bm._check_victory_conditions(), "a lost battle is still over")
	assert_eq(seen, [], "and must not now announce a VICTORY over an empty enemy roster")


func test_inactive_with_POPULATED_parties_is_still_evaluated() -> void:
	# The guard must key on the ARRAYS, not on is_battle_active(). INACTIVE also
	# covers a battle that has not started yet, whose parties are populated —
	# gating on state made the win-condition harness read a victory it never
	# fired. Caught by the full gate, not by this file.
	_bm.current_state = _bm.BattleState.INACTIVE
	_bm.player_party.append(_pc("Fighter"))
	_bm.enemy_party.append(_pc("Bat"))
	var seen: Array = []
	_bm.battle_ended.connect(func(v): seen.append(v))
	assert_false(_bm._check_victory_conditions(),
		"populated parties must still be evaluated — a state-keyed guard reported STOP here and broke two harness tests")
	assert_eq(seen, [], "and emits nothing")


## ── the live paths must still work ───────────────────────────────────

func test_a_real_party_wipe_still_reports_defeat() -> void:
	# NEGATIVE CONTROL. A guard that returned true unconditionally would also
	# silence the spurious defeat — and every real one with it, so no battle
	# could ever be lost. This is the assertion that separates the fix from
	# that mistake.
	var hero: Combatant = _pc("Fighter")
	hero.is_alive = false
	var foe: Combatant = _pc("Bat")
	_bm.player_party.append(hero)
	_bm.enemy_party.append(foe)
	_bm.current_state = _bm.BattleState.EXECUTION_PHASE
	var seen: Array = []
	_bm.battle_ended.connect(func(v): seen.append(v))
	assert_true(_bm._check_victory_conditions(), "a real wipe must resolve the battle")
	assert_eq(seen, [false], "and must emit DEFEAT exactly once")


func test_a_real_victory_still_reports_victory() -> void:
	var hero: Combatant = _pc("Fighter")
	var foe: Combatant = _pc("Bat")
	foe.is_alive = false
	_bm.player_party.append(hero)
	_bm.enemy_party.append(foe)
	_bm.current_state = _bm.BattleState.EXECUTION_PHASE
	var seen: Array = []
	_bm.battle_ended.connect(func(v): seen.append(v))
	assert_true(_bm._check_victory_conditions(), "all enemies down must resolve the battle")
	assert_eq(seen, [true], "and must emit VICTORY exactly once")


func test_an_ongoing_battle_resolves_nothing() -> void:
	# Both sides standing: the check must report "carry on" and stay silent.
	_bm.player_party.append(_pc("Fighter"))
	_bm.enemy_party.append(_pc("Bat"))
	_bm.current_state = _bm.BattleState.EXECUTION_PHASE
	var seen: Array = []
	_bm.battle_ended.connect(func(v): seen.append(v))
	assert_false(_bm._check_victory_conditions(),
		"a battle with both sides alive must not resolve — returning true here would end every fight on its first check")
	assert_eq(seen, [], "and must emit nothing")
