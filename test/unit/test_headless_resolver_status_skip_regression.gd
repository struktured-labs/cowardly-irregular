extends GutTest

## _check_status_skip returns THREE values ("" / "skip" / "confuse_attack") and 24 resolver tests covered none of them.
## The regression this guards: collapsing `if skip != ""` to a bool makes confused combatants silently stop acting.


func _make_combatant(cname: String) -> Combatant:
	var c = Combatant.new()
	c.initialize({
		"name": cname,
		"max_hp": 100,
		"max_mp": 20,
		"attack": 15,
		"defense": 10,
		"magic": 5,
		"speed": 10
	})
	add_child_autofree(c)
	return c


func test_clean_combatant_is_not_skipped() -> void:
	var resolver = HeadlessBattleResolver.new()
	var c = _make_combatant("Clean")
	assert_eq(resolver._check_status_skip(c), "", "No status must not skip the turn")


func test_stun_skips_the_turn_and_is_consumed() -> void:
	var resolver = HeadlessBattleResolver.new()
	var c = _make_combatant("Stunned")
	c.add_status("stun")
	assert_eq(int(c.status_durations.get("stun", 0)), 3, "add_status default duration is 3")
	assert_eq(resolver._check_status_skip(c), "skip", "Stun must skip the turn")
	assert_true(c.has_status("stun"), "Default stun lasts 3 skips — one skip decrements, it does not clear")
	assert_eq(int(c.status_durations.get("stun", 0)), 2, "One skip spends one point of a 3-point stun")


func test_stun_duration_one_clears_on_the_first_skip() -> void:
	var resolver = HeadlessBattleResolver.new()
	var c = _make_combatant("Stunned")
	c.add_status("stun", 1)
	assert_eq(resolver._check_status_skip(c), "skip", "Duration 1 still skips the turn")
	assert_false(c.has_status("stun"), "Duration 1 is spent by the skip that uses it")
	assert_false(c.status_durations.has("stun"), "Removing stun clears its duration entry")


func test_stun_duration_two_survives_one_skip_then_clears() -> void:
	var resolver = HeadlessBattleResolver.new()
	var c = _make_combatant("Stunned")
	c.add_status("stun", 2)
	assert_eq(resolver._check_status_skip(c), "skip")
	assert_true(c.has_status("stun"), "Duration 2 survives the first skip")
	assert_eq(int(c.status_durations.get("stun", 0)), 1)
	assert_eq(resolver._check_status_skip(c), "skip", "Still stunned on the second action")
	assert_false(c.has_status("stun"), "The second skip spends the last point")


func test_round_start_end_turn_does_not_spend_a_stun_point() -> void:
	# Live rounds call end_turn before the skip. If that tick also spent stun,
	# duration 2 would collapse back to a single skip.
	var resolver = HeadlessBattleResolver.new()
	var c = _make_combatant("Stunned")
	c.add_status("stun", 2)
	c.end_turn()
	assert_eq(int(c.status_durations.get("stun", 0)), 2, "end_turn ticks other statuses; stun's clock is the skip")
	assert_eq(resolver._check_status_skip(c), "skip")
	assert_eq(int(c.status_durations.get("stun", 0)), 1)
	c.end_turn()
	assert_eq(resolver._check_status_skip(c), "skip")
	assert_false(c.has_status("stun"), "Duration 2 is two skips even with a round boundary between them")


func test_confusion_never_returns_a_silent_skip() -> void:
	var resolver = HeadlessBattleResolver.new()
	var saw_confuse_attack := false
	for i in range(60):
		var c = _make_combatant("Confused%d" % i)
		c.add_status("confuse")
		var r: String = resolver._check_status_skip(c)
		assert_ne(r, "skip", "Confusion routes to confuse_attack or clears — never a silent skip")
		if r == "confuse_attack":
			saw_confuse_attack = true
	assert_true(saw_confuse_attack, "60 draws at p=0.6 must yield at least one confuse_attack")


func test_sleep_either_wakes_or_skips_and_never_acts_normally() -> void:
	var resolver = HeadlessBattleResolver.new()
	var saw_skip := false
	for i in range(60):
		var c = _make_combatant("Sleeper%d" % i)
		c.add_status("sleep")
		var r: String = resolver._check_status_skip(c)
		assert_ne(r, "confuse_attack", "Sleep must never route to the confusion action")
		if r == "skip":
			saw_skip = true
		else:
			assert_false(c.has_status("sleep"), "A sleeper that acts must have woken — status cleared")
	assert_true(saw_skip, "60 draws at p=0.7 must yield at least one sleep skip")
