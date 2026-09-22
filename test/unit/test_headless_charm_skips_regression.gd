extends GutTest

## puppy_eyes (Unassuming Local Dog) applies "charm". Live's _execute_next_action skips that
## combatant's turn unless a 0.35 roll breaks the charm. The grind's _check_status_skip handled
## stun, sleep, confuse and fear and then returned "", so a charmed fighter kept swinging.
## The status was on the "grind ignores what abilities inflict" list for that reason.

const RESOLVER := "res://src/autogrind/HeadlessBattleResolver.gd"
const LIVE := "res://src/battle/BattleManager.gd"
const TRIALS := 80


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


func test_charm_either_breaks_or_skips_and_never_acts_while_charmed() -> void:
	var resolver := HeadlessBattleResolver.new()
	var saw_skip := false
	var saw_break := false
	for i in TRIALS:
		var c := _make("Charmed%d" % i)
		c.add_status("charm", 2)
		var r: String = resolver._check_status_skip(c)
		assert_ne(r, "confuse_attack", "charm must never route to a confused swing")
		if r == "skip":
			saw_skip = true
			assert_true(c.has_status("charm"), "a skipped turn must leave charm on — it is not consumed like stun")
		else:
			assert_eq(r, "", "charm's only acting result is a broken charm")
			assert_false(c.has_status("charm"), "a charmed combatant that acts must have broken free")
			saw_break = true
	assert_true(saw_skip, "%d draws at p=0.65 must skip at least once" % TRIALS)
	assert_true(saw_break, "%d draws at p=0.35 must break free at least once" % TRIALS)


func test_an_uncharmed_combatant_is_not_skipped() -> void:
	var resolver := HeadlessBattleResolver.new()
	var c := _make("Clear")
	assert_eq(resolver._check_status_skip(c), "", "no charm must not skip")
	c.add_status("charm", 2)
	c.remove_status("charm")
	assert_eq(resolver._check_status_skip(c), "", "a cleared charm must not skip the next check")


func test_break_chance_matches_live() -> void:
	var re := RegEx.new()
	assert_eq(re.compile("has_status\\(\"charm\"\\)[\\s\\S]{0,240}?randf\\(\\) < (0\\.[0-9]+)"), OK)
	var live := FileAccess.get_file_as_string(LIVE)
	var head := FileAccess.get_file_as_string(RESOLVER)
	assert_gt(live.length(), 1000, "CONTROL: live battle source was read")
	assert_gt(head.length(), 1000, "CONTROL: headless resolver source was read")
	var lm := re.search(live)
	var hm := re.search(head)
	assert_not_null(lm, "CONTROL: live's charm break roll is readable")
	assert_not_null(hm, "CONTROL: the grind's charm break roll is readable")
	if lm == null or hm == null:
		return
	assert_eq(hm.get_string(1), lm.get_string(1),
		"the two engines disagree on the charm break chance: live %s vs headless %s" % [lm.get_string(1), hm.get_string(1)])
