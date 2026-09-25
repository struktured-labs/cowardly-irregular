extends GutTest

## Burrow applies "evasion" for one turn. Live's _target_dodges_physical misses a physical
## swing 60% of the time and leaves the status on (duration, not a charge, wears it off).
## The grind's twin of that function honoured invisible and shadow_step and skipped evasion,
## so the burrow was a badge. The status was on the grind-ignores census for that reason.

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


func test_evasion_sometimes_dodges_and_is_not_consumed() -> void:
	var resolver := HeadlessBattleResolver.new()
	var attacker := _make("Swinger")
	var target := _make("Burrowed")
	target.add_status("evasion", 2)
	var dodges := 0
	for _i in TRIALS:
		if resolver._target_dodges_physical(attacker, target):
			dodges += 1
	assert_true(target.has_status("evasion"), "a dodge must not strip evasion — live leaves it until the duration ticks off")
	assert_eq(int(target.status_durations.get("evasion", -1)), 2, "the dodge roll must not spend a turn of duration")
	assert_gt(dodges, 0, "%d swings at 60%% must dodge at least once" % TRIALS)
	assert_lt(dodges, TRIALS, "%d swings at 60%% must also land at least once — a guaranteed miss would be a different status" % TRIALS)


func test_no_evasion_means_the_swing_lands() -> void:
	var resolver := HeadlessBattleResolver.new()
	var attacker := _make("Swinger")
	var target := _make("Open")
	for _i in 20:
		assert_false(resolver._target_dodges_physical(attacker, target),
			"a combatant with no evasion status and no gear must not dodge")


func test_dodge_chance_matches_live() -> void:
	var re := RegEx.new()
	assert_eq(re.compile("has_status\\(\"evasion\"\\) and randf\\(\\) < (0\\.[0-9]+)"), OK)
	var live := FileAccess.get_file_as_string(LIVE)
	var head := FileAccess.get_file_as_string(RESOLVER)
	assert_gt(live.length(), 1000, "CONTROL: live battle source was read")
	assert_gt(head.length(), 1000, "CONTROL: headless resolver source was read")
	var lm := re.search(live)
	var hm := re.search(head)
	assert_not_null(lm, "CONTROL: live's evasion dodge roll is readable")
	assert_not_null(hm, "CONTROL: the grind's evasion dodge roll is readable")
	if lm == null or hm == null:
		return
	assert_eq(hm.get_string(1), lm.get_string(1),
		"the two engines disagree on the evasion dodge chance: live %s vs headless %s" % [lm.get_string(1), hm.get_string(1)])
