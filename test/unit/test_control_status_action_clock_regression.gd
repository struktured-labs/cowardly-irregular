extends GutTest

## Control statuses must last for the number of actions their authored duration names.
##
## The round-start tick runs before anyone acts. Stun and charm already ignore it and
## spend one point on the action they stop. These were still on the round clock:
##   pacify (Peace Sign, 1) and silence (Void Pulse / Null Field, 1) fell off before the next action
##   sleep (Lullaby, 2), confuse (Hallucination Spores, 2) and fear (Phantom Wail / Howl, 2)
##     ticked at round start and were not spent by the action, so they controlled one fewer
##   cannot_act (jailbreak skip, default 1) was spent by the skip AND ticked at round start
## Silence and pacify do not skip the turn. They last through the next N actions, then drop.
## Sleep still wakes on a hit. The 30% / 40% / 25% break rolls still clear the status early.
## Battle start still strips them. Poison still ticks on the round clock.


const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")

var _bm: Node = null
var _bm_guard = null


func before_each() -> void:
	_bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	_bm_guard = BattleStateGuard.new()
	_bm_guard.snapshot()
	if _bm:
		_bm.turbo_mode = true
		_bm.is_autobattle_enabled = false


func after_each() -> void:
	if _bm_guard != null:
		_bm_guard.restore()


func _make(cname: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": cname,
		"max_hp": 500,
		"max_mp": 80,
		"attack": 40,
		"defense": 5,
		"magic": 30,
		"speed": 10,
	})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	c.current_mp = c.max_mp
	return c


func _resolver() -> HeadlessBattleResolver:
	return HeadlessBattleResolver.new()


func test_round_start_does_not_spend_action_clock_statuses() -> void:
	var c := _make("Held")
	for status in Combatant.ACTION_CLOCK_STATUSES:
		c.add_status(status, 1)
	c.end_turn()
	for status in Combatant.ACTION_CLOCK_STATUSES:
		assert_true(c.has_status(status),
			"round start runs before the next action — a 1-turn %s was gone before it could matter" % status)
		assert_eq(int(c.status_durations.get(status, 0)), 1,
			"the round-start tick must not spend %s" % status)


func test_poison_still_ticks_at_round_start() -> void:
	var c := _make("Poisoned")
	c.add_status("poison", 1)
	c.end_turn()
	assert_false(c.has_status("poison"), "poison is a per-round DoT — the action-clock change must not freeze it")


func test_battle_start_still_clears_transient_statuses() -> void:
	var c := _make("Between fights")
	for status in Combatant.ACTION_CLOCK_STATUSES:
		c.add_status(status, 2)
	c.add_status("permakilled", -1)
	c.clear_transient_statuses()
	for status in Combatant.ACTION_CLOCK_STATUSES:
		assert_false(c.has_status(status), "battle start must still clear %s" % status)
	assert_true(c.has_status("permakilled"), "permakilled is the one status a new battle keeps")


func test_damage_still_wakes_a_sleeper() -> void:
	var c := _make("Sleeper")
	c.add_status("sleep", 2)
	c.end_turn()
	assert_true(c.has_status("sleep"), "CONTROL: the round tick no longer wakes them")
	c.take_damage(30)
	assert_false(c.has_status("sleep"), "a hit must still wake a sleeper")


func test_cannot_act_one_turn_survives_the_round_and_the_skip_spends_it() -> void:
	var resolver := _resolver()
	var c := _make("Boss")
	c.add_status("cannot_act", 1)
	c.end_turn()
	assert_true(c.has_status("cannot_act"), "a 1-turn jailbreak hold must still be on when the action arrives")
	assert_eq(resolver._check_status_skip(c), "skip", "cannot_act skips the turn")
	assert_false(c.has_status("cannot_act"), "that skip spends the only point")


func test_cannot_act_two_turns_survive_a_round_boundary_between_skips() -> void:
	var resolver := _resolver()
	var c := _make("Boss")
	c.add_status("cannot_act", 2)
	c.end_turn()
	assert_eq(resolver._check_status_skip(c), "skip")
	assert_eq(int(c.status_durations.get("cannot_act", 0)), 1, "the first skip spends one point, not both")
	c.end_turn()
	assert_eq(int(c.status_durations.get("cannot_act", 0)), 1, "the round between skips must not spend the second point")
	assert_eq(resolver._check_status_skip(c), "skip")
	assert_false(c.has_status("cannot_act"), "the second skip spends a 2-turn hold")


func test_sleep_controls_two_actions_when_it_does_not_break() -> void:
	var resolver := _resolver()
	var c := _make("Sleeper")
	c.add_status("sleep", 2)
	var skips := 0
	var guard := 0
	while skips < 2 and guard < 80:
		guard += 1
		var before := int(c.status_durations.get("sleep", 0))
		if before <= 0:
			break
		c.end_turn()
		assert_eq(int(c.status_durations.get("sleep", 0)), before, "round start must not spend a sleep point")
		if resolver._check_status_skip(c) == "skip":
			skips += 1
			if skips < 2:
				assert_eq(int(c.status_durations.get("sleep", 0)), before - 1, "the skip spends one point")
		else:
			assert_false(c.has_status("sleep"), "waking is the break roll — it clears sleep instead of spending a point")
			c.add_status("sleep", before)
	assert_eq(skips, 2, "Lullaby is 2 turns — two skips when the 30% wake roll does not fire")
	assert_false(c.has_status("sleep"), "the second skip spends the last point")


func test_confuse_controls_two_actions_when_it_does_not_break() -> void:
	var resolver := _resolver()
	var c := _make("Dazed")
	c.add_status("confuse", 2)
	var controlled := 0
	var guard := 0
	while controlled < 2 and guard < 80:
		guard += 1
		var before := int(c.status_durations.get("confuse", 0))
		if before <= 0:
			break
		c.end_turn()
		assert_eq(int(c.status_durations.get("confuse", 0)), before, "round start must not spend a confuse point")
		var result: String = resolver._check_status_skip(c)
		if result == "confuse_attack":
			controlled += 1
			if controlled < 2:
				assert_eq(int(c.status_durations.get("confuse", 0)), before - 1, "the confused action spends one point")
		else:
			assert_eq(result, "", "confuse either forces an attack or snaps out")
			assert_false(c.has_status("confuse"), "snapping out clears confuse")
			c.add_status("confuse", before)
	assert_eq(controlled, 2, "Hallucination Spores is 2 turns — two confused actions when the snap-out roll does not fire")
	assert_false(c.has_status("confuse"), "the second confused action spends the last point")


func test_fear_controls_two_actions_across_skip_and_swing() -> void:
	var resolver := _resolver()
	var c := _make("Shaken")
	var target := _make("Target")
	c.add_status("fear", 2)
	var controlled := 0
	var saw_skip := false
	var saw_swing := false
	var guard := 0
	while controlled < 2 and guard < 80:
		guard += 1
		var before := int(c.status_durations.get("fear", 0))
		if before <= 0:
			break
		c.end_turn()
		assert_eq(int(c.status_durations.get("fear", 0)), before, "round start must not spend a fear point")
		var result: String = resolver._check_status_skip(c)
		if result == "skip":
			saw_skip = true
			controlled += 1
			if controlled < 2:
				assert_eq(int(c.status_durations.get("fear", 0)), before - 1, "a fear skip spends one point")
		elif not c.has_status("fear"):
			c.add_status("fear", before)
		else:
			assert_eq(result, "", "the swing path must not report a skip")
			var hp_before := target.current_hp
			resolver._execute_action({"type": "attack", "combatant": c, "target": target})
			saw_swing = true
			controlled += 1
			if controlled < 2:
				assert_eq(int(c.status_durations.get("fear", 0)), before - 1, "the swing fear did not skip still spends one point")
			target.current_hp = hp_before
	assert_eq(controlled, 2, "a 2-turn fear covers two actions, whether each one skips or still swings")
	assert_false(c.has_status("fear"), "the second controlled action spends the last point")
	assert_true(saw_skip or saw_swing, "CONTROL: the loop must have resolved a real fear action")


func test_one_turn_pacify_blocks_exactly_one_action() -> void:
	var resolver := _resolver()
	var attacker := _make("Dove")
	var target := _make("Target")
	attacker.add_status("pacify", 1)
	attacker.end_turn()
	assert_true(attacker.has_status("pacify"), "Peace Sign is 1 turn and must still be on after the round starts")
	var hp_before := target.current_hp
	resolver._execute_action({"type": "attack", "combatant": attacker, "target": target})
	assert_eq(target.current_hp, hp_before, "the one action Peace Sign covers must not land")
	assert_false(attacker.has_status("pacify"), "that action spends the only point")
	var landed := false
	for _i in 12:
		resolver._execute_action({"type": "attack", "combatant": attacker, "target": target})
		if target.current_hp < hp_before:
			landed = true
			break
	assert_true(landed, "once pacify is spent the next swings are real — 12 misses is ~1e-12")


func test_pacify_on_a_defer_still_spends_the_action() -> void:
	var resolver := _resolver()
	var c := _make("Dove")
	c.add_status("pacify", 1)
	c.end_turn()
	assert_true(c.has_status("pacify"), "CONTROL: the round tick left the 1-turn pacify in place")
	resolver._execute_action({"type": "defer", "combatant": c})
	assert_false(c.has_status("pacify"), "defer is an action — a 1-turn pacify covers it and then ends")


func test_one_turn_silence_blocks_exactly_one_action() -> void:
	var aid := _damaging_ability()
	if aid == "":
		pass_test("JobSystem autoload unavailable")
		return
	var resolver := _resolver()
	var caster := _make("Mage")
	var target := _make("Victim")
	resolver._player_party = [caster]
	resolver._enemy_party = [target]
	caster.add_status("silence", 1)
	caster.end_turn()
	assert_true(caster.has_status("silence"), "Void Pulse / Null Field are 1 turn and must survive the round start")
	var hp_before := target.current_hp
	resolver._execute_action({"type": "ability", "combatant": caster, "ability_id": aid, "targets": [target]})
	assert_eq(target.current_hp, hp_before, "the silenced action must not cast")
	assert_false(caster.has_status("silence"), "that action spends the only point")
	resolver._execute_action({"type": "ability", "combatant": caster, "ability_id": aid, "targets": [target]})
	assert_lt(target.current_hp, hp_before, "the next action is free to cast")


func test_silence_spent_by_a_basic_attack_lasts_one_action() -> void:
	## Silence blocks spells. The written duration is still one action, including a swing.
	var aid := _damaging_ability()
	if aid == "":
		pass_test("JobSystem autoload unavailable")
		return
	var resolver := _resolver()
	var caster := _make("Mage")
	var target := _make("Victim")
	resolver._player_party = [caster]
	resolver._enemy_party = [target]
	caster.add_status("silence", 1)
	caster.end_turn()
	resolver._execute_action({"type": "attack", "combatant": caster, "target": target})
	assert_false(caster.has_status("silence"), "a basic attack is an action, so a 1-turn silence ends on it")
	var hp_before := target.current_hp
	resolver._execute_action({"type": "ability", "combatant": caster, "ability_id": aid, "targets": [target]})
	assert_lt(target.current_hp, hp_before, "the following cast is no longer silenced")


func test_two_turn_silence_blocks_two_casts_across_a_round_boundary() -> void:
	var aid := _damaging_ability()
	if aid == "":
		pass_test("JobSystem autoload unavailable")
		return
	var resolver := _resolver()
	var caster := _make("Mage")
	var target := _make("Victim")
	resolver._player_party = [caster]
	resolver._enemy_party = [target]
	caster.add_status("silence", 2)
	caster.end_turn()
	assert_eq(int(caster.status_durations.get("silence", 0)), 2)
	var hp_before := target.current_hp
	resolver._execute_action({"type": "ability", "combatant": caster, "ability_id": aid, "targets": [target]})
	assert_eq(target.current_hp, hp_before, "first cast is silenced")
	assert_eq(int(caster.status_durations.get("silence", 0)), 1)
	caster.end_turn()
	assert_eq(int(caster.status_durations.get("silence", 0)), 1, "the round between actions must not spend the second point")
	resolver._execute_action({"type": "ability", "combatant": caster, "ability_id": aid, "targets": [target]})
	assert_eq(target.current_hp, hp_before, "second cast is silenced")
	assert_false(caster.has_status("silence"))
	resolver._execute_action({"type": "ability", "combatant": caster, "ability_id": aid, "targets": [target]})
	assert_lt(target.current_hp, hp_before, "the third cast lands")


func test_both_engines_spend_the_same_clocks() -> void:
	var live := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var head := FileAccess.get_file_as_string("res://src/autogrind/HeadlessBattleResolver.gd")
	assert_gt(live.length(), 1000, "CONTROL: live battle source was read")
	assert_gt(head.length(), 1000, "CONTROL: headless resolver source was read")
	for status in ["sleep", "confuse", "fear", "cannot_act"]:
		var needle := "spend_action_clock(\"%s\")" % status
		assert_true(live.contains(needle), "live battle must spend %s on the action it controls" % status)
		assert_true(head.contains(needle), "the grind must spend %s on the same action" % status)
	assert_true(live.contains("spend_restriction_clocks()"),
		"live must spend silence, pacify and a fear swing after the action has read them")
	assert_true(head.contains("spend_restriction_clocks()"),
		"the grind must spend those same clocks after the action")


func test_live_cannot_act_survives_the_round_the_skip_starts() -> void:
	## _execute_next_action's skip falls into a new round, which calls end_turn.
	## A 2-turn hold used to lose the second point to that tick.
	assert_not_null(_bm, "BattleManager autoload required")
	if _bm == null:
		return
	var attacker := _make("Boss")
	var victim := _make("Hero")
	attacker.attack = 80
	_stage(attacker, victim)
	attacker.add_status("cannot_act", 1)
	attacker.end_turn()
	assert_true(attacker.has_status("cannot_act"), "live round start must leave a 1-turn cannot_act for the skip")
	var hp := victim.current_hp
	_skip_once(attacker, victim)
	assert_eq(victim.current_hp, hp, "the skip must consume the attack")
	assert_false(attacker.has_status("cannot_act"), "the skip spends a 1-turn hold")

	attacker.add_status("cannot_act", 2)
	_skip_once(attacker, victim)
	assert_true(attacker.has_status("cannot_act"), "a 2-turn hold survives the skip and the round that skip starts")
	assert_eq(int(attacker.status_durations.get("cannot_act", 0)), 1)
	_skip_once(attacker, victim)
	assert_eq(victim.current_hp, hp, "the second skip must also consume the attack")
	assert_false(attacker.has_status("cannot_act"), "the second skip spends the last point")


func _stage(attacker: Combatant, victim: Combatant) -> void:
	_bm.enemy_party.clear()
	_bm.player_party.clear()
	_bm.all_combatants.clear()
	_bm.enemy_party.append(attacker)
	_bm.player_party.append(victim)
	_bm.all_combatants.append(victim)
	_bm.all_combatants.append(attacker)
	_bm.volatility = VolatilitySystem.new()
	_bm.volatility.reset_battle()
	_bm.current_state = _bm.BattleState.PROCESSING_ACTION
	if AutobattleSystem:
		AutobattleSystem.set_autobattle_enabled(_bm._get_character_id(victim), false)
		AutobattleSystem.set_autobattle_enabled(_bm._get_character_id(attacker), false)


func _skip_once(attacker: Combatant, victim: Combatant) -> void:
	_bm.execution_order.clear()
	_bm.execution_order.append({
		"type": "attack",
		"combatant": attacker,
		"target": victim,
		"speed": 1.0,
	})
	_bm._execute_next_action()


func _damaging_ability() -> String:
	var js: Node = get_node_or_null("/root/JobSystem")
	if js == null or not js.has_method("get_ability"):
		return ""
	for candidate in ["fire", "blizzard", "thunder"]:
		var ab: Dictionary = js.get_ability(candidate)
		if not ab.is_empty() and int(ab.get("mp_cost", 0)) > 0:
			return candidate
	return ""
