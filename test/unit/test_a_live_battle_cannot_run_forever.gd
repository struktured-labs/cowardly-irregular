extends GutTest

## HeadlessBattleResolver has had MAX_ROUNDS = 50 since it shipped. BattleManager — the engine a
## PLAYER fights in — had no cap and no stalemate detection at all, so a deadlocked fight never
## ended: measured 2026-10-25, the shipped build stalemates 1 in 20 on the W4 Masterite pair, and
## the goblin HP x4.0 balance cell ran 28.10 mean rounds, which is the same defect arriving as
## tedium instead of a hang. struktured ruled it a bug rather than balance.
##
## The resolution is the FLEE path, not the wipe path, and that is a claim about GameLoop rather
## than about this file: GameLoop:4057 discriminates escape from a party wipe by whether anyone
## survived, and a deadlock leaves both sides standing by definition, so end_battle(false) returns
## the player to the map with no game over and no progress lost. Arm 5 pins the survivor premise,
## because if it ever stopped holding this fix would start eating save files.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")
const RESOLVER_PATH := "res://src/autogrind/HeadlessBattleResolver.gd"
const THIS_FILE := "res://test/unit/test_a_live_battle_cannot_run_forever.gd"

var _bm = null
var _log_lines: Array[String] = []


func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)
	_log_lines.clear()
	_bm.battle_log_message.connect(func(s: String): _log_lines.append(s))


func _body(who: String, hp: int) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = who
	c.max_hp = hp
	c.current_hp = hp
	c.is_alive = true
	return c


## One party member and one enemy, both healthy, with the per-battle minima armed as start_battle
## leaves them. Returns [party, enemy] so an arm can move either side's HP.
func _two_sided_fight(party_hp: int = 1000, enemy_hp: int = 1000) -> Array:
	var pc := _body("Hero", party_hp)
	var foe := _body("Foe", enemy_hp)
	## TYPED LOCALS, NOT LITERALS. player_party is Array[Combatant]; assigning an untyped `[pc]`
	## through an untyped `_bm` is the roundtrip trap — it aborts this function and hands back [].
	var players: Array[Combatant] = [pc]
	var enemies: Array[Combatant] = [foe]
	var everyone: Array[Combatant] = [pc, foe]
	_bm.player_party = players
	_bm.enemy_party = enemies
	_bm.all_combatants = everyone
	_bm._win_condition = {}
	_bm.current_round = 0
	_bm._lowest_enemy_hp_total = -1
	_bm._lowest_player_hp_total = -1
	_bm._rounds_since_progress = 0
	_bm._stall_warning_sent = false
	return [pc, foe]


## Drives rounds the way _start_new_round does — increment, then poll — and returns the round the
## battle was resolved on, or -1 if it survived `rounds` of them. `per_round` mutates the board.
func _round_resolved_on(rounds: int, per_round: Callable) -> int:
	for _i in range(rounds):
		_bm.current_round += 1
		per_round.call(_bm.current_round)
		if _bm._resolve_if_going_nowhere():
			return _bm.current_round
	return -1


func test_the_floor_names_every_symbol_this_file_reaches() -> void:
	## DERIVED, not hand-listed: every `_bm.<name>` this file touches must exist on the real script,
	## so a rename reds here by name instead of leaving each arm to abort into a silent pass. These
	## are lane-local symbols with one consumer apiece — this file — so the floor IS the cover.
	var src: String = FileAccess.get_file_as_string(THIS_FILE)
	assert_gt(src.length(), 0, "the file must read its own source for the derivation to mean anything")
	var rx := RegEx.new()
	rx.compile("_bm\\.(\\w+)")
	var reached := {}
	for m in rx.search_all(src):
		reached[m.get_string(1)] = true
	assert_gt(reached.size(), 6, "the derivation must find the real reach set (found %s)" % str(reached.keys()))
	## Three call shapes reach three different namespaces, and `in` sees only the first — written
	## with `in` alone first, which reported every method and the signal as missing.
	var missing: Array = []
	for name in reached:
		if not ((name in _bm) or _bm.has_method(name) or _bm.has_signal(name)):
			missing.append(name)
	assert_eq(missing.size(), 0, "BattleManager no longer carries: " + str(missing))


## A function body, bounded at BOTH ends — from its own `func` line to the next one. An unbounded
## window reads the whole rest of the file and would find the call anywhere below.
func _func_body(src: String, fname: String) -> String:
	var start: int = src.find("func %s(" % fname)
	if start < 0:
		return ""
	var end: int = src.find("\nfunc ", start + 1)
	return src.substr(start, (end - start) if end > start else -1)


func test_the_detector_is_actually_wired_into_the_round_advance() -> void:
	## ⛔ EVERY OTHER ARM CALLS _resolve_if_going_nowhere DIRECTLY, so all of them stay green if the
	## CALL SITE is deleted and the function becomes dead code — battles would run forever again with
	## a fully passing guard. This is a reachability question, which is a fact about the source, so a
	## bounded source pin is the honest instrument rather than a weaker one dressed up as behaviour.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var body: String = _func_body(src, "_start_new_round")
	assert_gt(body.length(), 0, "BattleManager must still declare _start_new_round for this to mean anything")
	assert_true(body.contains("_resolve_if_going_nowhere()"),
		"_start_new_round must call the detector, or nothing in the live engine ever bounds a battle")
	## Precedence, pinned where it is decided: a kill landing on the last legal round still wins.
	var vic: int = body.find("_check_victory_conditions()")
	var stale: int = body.find("_resolve_if_going_nowhere()")
	assert_true(vic >= 0 and vic < stale,
		"victory must be tested BEFORE the timeout, or a fight won on the final round reports as a disengage")


func test_the_live_cap_is_the_resolvers_twin() -> void:
	## The comment on BattleManager.MAX_ROUNDS claims it is HeadlessBattleResolver's twin. Twins by
	## construction must agree in VALUE, and nothing but this makes them.
	var resolver_src: String = FileAccess.get_file_as_string(RESOLVER_PATH)
	var rx := RegEx.new()
	rx.compile("(?m)^const MAX_ROUNDS\\s*(?::\\s*int\\s*)?=\\s*(\\d+)")
	var m := rx.search(resolver_src)
	assert_not_null(m, "HeadlessBattleResolver must still declare MAX_ROUNDS for the twin to mean anything")
	if m == null:
		return
	assert_eq(BattleManagerScript.MAX_ROUNDS, int(m.get_string(1)),
		"the live cap and the headless cap must be the same number — a player and the grind must agree on when a fight is over")


func test_a_fight_making_progress_is_never_cut_short() -> void:
	## CONTROL, and the arm that must red if the detector is too eager. Every other arm asserts that
	## something DOES end; without this one, "return true always" passes the whole file.
	var sides := _two_sided_fight(1000, 100000)
	var foe: Combatant = sides[1]
	var resolved := _round_resolved_on(BattleManagerScript.MAX_ROUNDS, func(_r):
		foe.current_hp -= 100
	)
	assert_eq(resolved, -1, "a fight whose enemy loses HP every round was resolved on round %d" % resolved)
	assert_eq(_bm._rounds_since_progress, 0, "a new low every round must keep the no-progress counter pinned at zero")


func test_a_deadlock_ends_itself() -> void:
	## Neither side can touch the other — the heal-loop and wrong-element case. Nothing mutates HP.
	_two_sided_fight()
	var resolved := _round_resolved_on(BattleManagerScript.MAX_ROUNDS, func(_r): pass)
	assert_gt(resolved, 0, "a fight in which no HP ever changes must end itself, and did not")
	assert_eq(resolved, BattleManagerScript.STALEMATE_ROUNDS + 1,
		"the deadlock must be called one round after STALEMATE_ROUNDS of no progress, not at the hard cap")


func test_the_hard_cap_catches_a_fight_that_progresses_forever() -> void:
	## A fight that keeps making progress never trips the deadlock test, so the cap is the only
	## thing bounding it. One HP a round off a huge pool is progress by the letter and a hang in
	## practice — this is the 28-round goblin cell taken to its limit.
	var sides := _two_sided_fight(1000, 100000)
	var foe: Combatant = sides[1]
	var resolved := _round_resolved_on(BattleManagerScript.MAX_ROUNDS + 5, func(_r):
		foe.current_hp -= 1
	)
	assert_eq(resolved, BattleManagerScript.MAX_ROUNDS + 1,
		"a forever-progressing fight must end on the round after MAX_ROUNDS; ended on %d" % resolved)


func test_an_authored_win_condition_is_exempt_from_the_deadlock_test_but_not_the_cap() -> void:
	## withhold_attack WANTS zero progress — the player wins masterite_warden_abstract by NOT
	## attacking for four rounds — and survive_turns and arbiter_ladder have their own odd damage
	## flows. Both directions are asserted: the exemption must hold, and it must not become a way
	## to opt out of being bounded at all.
	_two_sided_fight()
	_bm._win_condition = {"type": "withhold_attack", "value": 4}
	var past_deadlock := _round_resolved_on(BattleManagerScript.STALEMATE_ROUNDS + 5, func(_r): pass)
	assert_eq(past_deadlock, -1,
		"an authored win condition must survive its own deliberate lack of progress; was cut on round %d" % past_deadlock)
	var capped := _round_resolved_on(BattleManagerScript.MAX_ROUNDS, func(_r): pass)
	assert_eq(capped, BattleManagerScript.MAX_ROUNDS + 1,
		"the exemption covers the deadlock test only — the hard cap must still fire, and did not")


func test_a_resolved_deadlock_leaves_survivors_so_it_is_a_flee_and_not_a_wipe() -> void:
	## THE LOAD-BEARING PREMISE. GameLoop:4057 routes end_battle(false) to the overworld when any
	## party member lives and to the game-over screen when none does. If a deadlock could resolve
	## with the party wiped, this fix would hand out game overs for the engine's own failure.
	var sides := _two_sided_fight()
	var pc: Combatant = sides[0]
	## SNAPSHOT PER ROUND, because end_battle -> _cleanup_battle:1314 CLEARS player_party. Reading
	## the manager's array after the fact measures the teardown, and would have passed only on the
	## runs where end_battle happened to abort before reaching the clear — a coincidence, not a
	## mechanism. What is being pinned is the state at the INSTANT of resolution.
	var survivors_at_resolution := -1
	var resolved := -1
	for _i in range(BattleManagerScript.MAX_ROUNDS):
		_bm.current_round += 1
		var standing := 0
		for m in _bm.player_party:
			if m is Combatant and m.is_alive:
				standing += 1
		if _bm._resolve_if_going_nowhere():
			survivors_at_resolution = standing
			resolved = _bm.current_round
			break
	assert_gt(resolved, 0, "the deadlock must have resolved for this arm to be about anything")
	assert_gt(survivors_at_resolution, 0,
		"GameLoop:4057 reads survivors to tell a flee from a wipe; zero at resolution is a game over handed out for the engine's own failure")
	assert_true(pc.is_alive, "and the party member really is alive, not merely counted — a deadlock ends with everyone standing")


func test_the_player_is_warned_before_the_fight_is_taken_away_from_them() -> void:
	## An ending the player could not see coming is the surprising behaviour struktured ruled
	## against. The warning must arrive inside the lead window, exactly once, and before the end.
	var sides := _two_sided_fight(1000, 100000)
	var foe: Combatant = sides[1]
	var warned_on := -1
	var warn_count := 0
	for _i in range(BattleManagerScript.MAX_ROUNDS + 2):
		_bm.current_round += 1
		foe.current_hp -= 1
		var before := _log_lines.size()
		if _bm._resolve_if_going_nowhere():
			break
		for j in range(before, _log_lines.size()):
			if _log_lines[j].contains("going nowhere"):
				warn_count += 1
				if warned_on < 0:
					warned_on = _bm.current_round
	assert_eq(warn_count, 1, "the stall warning must fire exactly once per battle, not every round (fired %d times)" % warn_count)
	assert_eq(warned_on, BattleManagerScript.MAX_ROUNDS - BattleManagerScript.STALL_WARNING_LEAD,
		"the warning must arrive STALL_WARNING_LEAD rounds before the cap, while fleeing is still possible")


func test_the_disengage_says_what_happened_in_the_players_own_log() -> void:
	## push_warning goes to a console no player reads. The battle log is the surface they have.
	_two_sided_fight()
	var resolved := _round_resolved_on(BattleManagerScript.MAX_ROUNDS, func(_r): pass)
	assert_gt(resolved, 0, "the deadlock must have resolved for there to be a message")
	var said := false
	for line in _log_lines:
		if line.contains("disengages"):
			said = true
	assert_true(said, "the player must be told the party disengaged, not just dropped on the map: " + str(_log_lines))


func test_a_dead_side_contributes_nothing_to_its_total() -> void:
	## _side_hp_total drives both minima, so a corpse still counted would make a party wipe read as
	## a steady total and a deadlock. Pinned because the whole detector is written against it.
	var alive := _body("Alive", 500)
	var dead := _body("Dead", 500)
	dead.current_hp = 0
	dead.is_alive = false
	assert_eq(_bm._side_hp_total([alive, dead]), 500, "only living combatants count toward a side's HP total")
	assert_eq(_bm._side_hp_total([]), 0, "an empty side totals zero rather than aborting")
