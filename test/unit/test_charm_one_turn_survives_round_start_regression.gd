extends GutTest

## Puppy Eyes (Unassuming Local Dog) authors charm for 1 turn. The dog casts it as an
## ability, so it lands after the party has already acted. The next round starts by
## calling end_turn on everyone, and that tick used to spend the charm BEFORE the
## victim's action — a 1-turn charm hit 0 and fell off, the command menu opened, and
## they acted. The skip never got a chance to stop them.


func _make(cname: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": cname,
		"max_hp": 100,
		"max_mp": 20,
		"attack": 15,
		"defense": 10,
		"magic": 5,
		"speed": 10,
	})
	add_child_autofree(c)
	return c


func test_a_one_turn_charm_survives_the_round_start_tick() -> void:
	var c := _make("Charmed")
	c.add_status("charm", 1)
	c.end_turn()
	assert_true(c.has_status("charm"),
		"round start ticks every status before anyone acts — a 1-turn charm was gone before it could stop the turn")
	assert_eq(int(c.status_durations.get("charm", 0)), 1,
		"the round-start tick must not spend the point the next action still has to pay")


func test_the_skipped_turn_spends_a_one_turn_charm() -> void:
	var resolver := HeadlessBattleResolver.new()
	var c := _make("Charmed")
	c.add_status("charm", 1)
	c.end_turn()
	assert_true(c.has_status("charm"), "CONTROL: the charm is still on when the action arrives")
	var saw_skip := false
	for _i in 40:
		if not c.has_status("charm"):
			c.add_status("charm", 1)
		else:
			c.status_durations["charm"] = 1
		if resolver._check_status_skip(c) == "skip":
			saw_skip = true
			assert_false(c.has_status("charm"),
				"Puppy Eyes is 1 turn — the skip it paid for spends that point, and the turn after is free")
			break
	assert_true(saw_skip, "40 draws at p=0.65 must skip at least once")


func test_a_two_turn_charm_survives_one_skip_and_ends_on_the_second() -> void:
	# The skip itself must not wipe a longer charm (break-free is the only early clear).
	var resolver := HeadlessBattleResolver.new()
	var c := _make("Charmed")
	c.add_status("charm", 2)
	var skips := 0
	var guard := 0
	while skips < 2 and guard < 80:
		guard += 1
		var before := int(c.status_durations.get("charm", 0))
		if before <= 0:
			break
		var r: String = resolver._check_status_skip(c)
		if r == "skip":
			skips += 1
			if skips == 1:
				assert_true(c.has_status("charm"), "one skip of a 2-turn charm leaves it on")
				assert_eq(int(c.status_durations.get("charm", 0)), before - 1,
					"the skip spends one point, it does not clear the rest")
		else:
			# Broke free — put the same point count back so the skip clock is what we measure.
			c.add_status("charm", before)
	assert_eq(skips, 2, "a 2-turn charm stops two actions")
	assert_false(c.has_status("charm"), "the second skip spends the last point")


func test_live_charm_skip_spends_the_same_clock() -> void:
	var live := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var head := FileAccess.get_file_as_string("res://src/autogrind/HeadlessBattleResolver.gd")
	assert_true(live.contains("spend_action_clock(\"charm\")"),
		"live battle must spend charm on the skip — the grind is not the fight the player is in")
	assert_true(head.contains("spend_action_clock(\"charm\")"),
		"the grind must spend charm on the same skip")
