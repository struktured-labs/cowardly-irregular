extends GutTest

## Two of the five Spotlight Duels are won by something other than killing the boss, and nothing
## verified either end-to-end.
##
## The duels are a headline feature — every W1 starter unlock is a solo showcase of that PC's kit —
## and two carry bespoke win conditions: the Cleric survives 8 rounds, the Bard sways the courtier
## three times. A bespoke condition is exactly the shape that ships unreachable: it has one consumer,
## one producer, and no other content exercises the path. If the Bard's songs stopped incrementing
## the stack counter, the duel would simply never end and it would read as the boss being unkillable.
##
## Both are winnable today — but the two tests are NOT the same strength, and the docstring above
## originally implied they were. Stating the difference rather than letting "end-to-end" cover both:
##
##   BARD    end-to-end. Drives _execute_ability with a real lullaby, so the song arm, the sway
##           hook and the meta counter all have to work for it to pass.
##   CLERIC  evaluator-level ONLY. It sets current_round by hand and asks the evaluator. It does
##           NOT run eight rounds of a real battle, so it cannot see anything that would stop the
##           round counter advancing — which is precisely the defect shape that would make the
##           duel unwinnable. Running it for real needs a live battle loop and a survivable party;
##           that is a bigger fixture than this file, and naming the gap is more honest than
##           implying it is covered.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")

var _bm = null

func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)

func _monsters() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	assert_not_null(parsed, "CONTROL: monsters.json parses")
	return (parsed as Dictionary).get("monsters", parsed)

func _duel_foe(mid: String) -> Combatant:
	var v: Dictionary = _monsters()[mid]
	var st: Dictionary = v.get("stats", {})
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = mid
	c.max_hp = int(st.get("max_hp", 3000)); c.current_hp = c.max_hp
	c.max_mp = 999; c.current_mp = 999
	c.set_meta("monster_type", mid)
	c.job = {"id": mid, "abilities": (v.get("abilities", []) as Array).duplicate()}
	return c

func _bard() -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Lyra"
	c.max_hp = 600; c.current_hp = 600
	c.max_mp = 200; c.current_mp = 200
	c.magic = 90
	c.job = {"id": "bard", "abilities": ["battle_hymn", "lullaby"]}
	return c

func test_the_bard_can_actually_sway_the_courtier() -> void:
	## Three songs, one stack each, and the evaluator flips exactly on the third. Anything that broke
	## the increment — the song arm, the sway hook, the meta key — leaves an unwinnable duel that
	## looks like an unkillable boss.
	var foe := _duel_foe("bard_hostile_courtier")
	var bard := _bard()
	_bm.player_party.append(bard)
	_bm.enemy_party.append(foe)
	_bm._win_condition = _monsters()["bard_hostile_courtier"].get("win_condition", {})
	assert_eq(str(_bm._win_condition.get("status", "")), "swayed", "CONTROL: the duel still wins on sway")
	assert_false(_bm._evaluate_custom_win_condition(), "CONTROL: not already won before a single song")
	for i in 3:
		_bm._execute_ability(bard, "lullaby", [foe])
	assert_eq(int(foe.get_meta("_swayed_stacks", 0)), 3, "each song must land one stack")
	assert_true(_bm._evaluate_custom_win_condition(), "three stacks must win the duel")

func test_two_songs_are_not_enough() -> void:
	## The discriminator. An evaluator that returned true on any stack at all would pass the test
	## above and end the showcase on the first note.
	var foe := _duel_foe("bard_hostile_courtier")
	var bard := _bard()
	_bm.player_party.append(bard)
	_bm.enemy_party.append(foe)
	_bm._win_condition = _monsters()["bard_hostile_courtier"].get("win_condition", {})
	for i in 2:
		_bm._execute_ability(bard, "lullaby", [foe])
	assert_eq(int(foe.get_meta("_swayed_stacks", 0)), 2, "CONTROL: two songs, two stacks")
	assert_false(_bm._evaluate_custom_win_condition(), "two is short of the threshold of three")

func test_the_cleric_duel_turns_on_the_round_count() -> void:
	var wc: Dictionary = _monsters()["cleric_survive_target"].get("win_condition", {})
	assert_eq(str(wc.get("type", "")), "survive_turns", "CONTROL: the Cleric duel still wins by surviving")
	var need: int = int(wc.get("value", 0))
	assert_gt(need, 0, "CONTROL: it demands a positive number of rounds (%d)" % need)
	_bm._win_condition = wc
	_bm.current_round = need - 1
	assert_false(_bm._evaluate_custom_win_condition(), "one round short must not win")
	_bm.current_round = need
	assert_true(_bm._evaluate_custom_win_condition(), "reaching the round count must win")

func test_the_other_three_duels_are_ordinary_kills() -> void:
	## Records which duels are bespoke, so a new custom condition arrives with a test rather than
	## inheriting silence. hp_zero needs no evaluator and must NOT acquire one by accident.
	var bespoke: Array = []
	var mons := _monsters()
	for mid in mons:
		var v: Dictionary = mons[mid]
		if not bool(v.get("spotlight_duel", false)):
			continue
		var wc = v.get("win_condition", null)
		if wc != null and str((wc as Dictionary).get("type", "")) != "hp_zero":
			bespoke.append(mid)
	bespoke.sort()
	assert_eq(bespoke, ["bard_hostile_courtier", "cleric_survive_target"],
		"a duel gained or lost a bespoke win condition — it needs its own reachability test: " + str(bespoke))

func test_a_bespoke_condition_never_defaults_to_won() -> void:
	## The failure that would be invisible in play: an evaluator returning true for an unknown or
	## empty condition ends every duel the instant it starts, which reads as a cutscene bug.
	_bm._win_condition = {}
	assert_false(_bm._evaluate_custom_win_condition(), "an empty condition must not read as won")
	_bm._win_condition = {"type": "not_a_real_condition", "value": 3}
	assert_false(_bm._evaluate_custom_win_condition(), "nor must an unknown one")
