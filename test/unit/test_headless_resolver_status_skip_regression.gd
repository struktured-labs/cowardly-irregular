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
	assert_eq(resolver._check_status_skip(c), "skip", "Stun must skip the turn")
	assert_false(c.has_status("stun"), "Stun is consumed by the check, not left to re-fire next round")


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
