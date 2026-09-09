extends GutTest

## ACTING ON A WARNING BEFORE THE REPORT, which was the fleet's cheapest find today.
##
## My .242 healing fix was a DEAD-LOOKUP REPAIR: the resolver read `power` (authored by 0 of 7
## healing abilities) and healed magic*1, so every heal in every headless battle was ~65x weak.
## Fixing it turned healing ON — and it turned it on for BOTH SIDES, because _select_enemy_action
## uses the same _resolve_ability path.
##
## Two lanes today had a dead-lookup repair detonate downstream authoring that had never once
## executed (AFRAID tuning, then Sandrift's doorway). This is the same risk in my lane: enemy
## healing was authored years ago and has never actually run in a grind.
##
##   monster                lv   hp     mp   heal  heal/hp  casts
##   new_age_retro_hippie   4    1200   60   600   50%      7      <- worst case
##   crystal_golem          9    4500   50   1500  33%      2
##   rogue_automaton        10   4000   80   1200  30%      5
##   memory_leak            11   3500   60   800   23%      6
##
## Enemies heal only below 30% HP and only while MP lasts, so the total is bounded — but the
## resolver has MAX_ROUNDS=50 that live combat does not, and a fight that live resolves can time
## out here. Its own comment names this exact case: "a player rule facing an unkillable enemy
## (healing boss...) would grind to a halt reporting defeats forever."
##
## Reasoning says 50 rounds is plenty. Reasoning has been wrong all day, so this drives it.

const HEALER := "new_age_retro_hippie"


func _party(n: int, atk: int) -> Array:
	var out: Array = []
	for i in range(n):
		var c := Combatant.new()
		c.initialize({
			"name": "PC%d" % i, "max_hp": 400, "max_mp": 30,
			"attack": atk, "defense": 12, "magic": atk, "speed": 12
		})
		add_child_autofree(c)
		out.append(c)
	return out


func _healer_enemy() -> Combatant:
	var f := FileAccess.open("res://data/monsters.json", FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	var table: Dictionary = parsed.get("monsters", parsed)
	var mon: Dictionary = table[HEALER]
	var st: Dictionary = mon.get("stats", {})
	var c := Combatant.new()
	c.initialize({
		"name": str(mon.get("name", HEALER)),
		"max_hp": int(st.get("hp", 1200)), "max_mp": int(st.get("mp", 60)),
		"attack": int(st.get("attack", 20)), "defense": int(st.get("defense", 10)),
		"magic": int(st.get("magic", 20)), "speed": int(st.get("speed", 10))
	})
	for a in mon.get("abilities", []):
		c.learned_abilities.append(str(a))
	add_child_autofree(c)
	return c


func test_the_fixture_really_is_a_healer_that_can_outheal_itself() -> void:
	## ARM+ for the whole file. If the monster lost its heal, or heal_amount went to 0, every
	## termination assertion below would pass for the wrong reason.
	var e := _healer_enemy()
	assert_gt(e.max_hp, 0, "the fixture must load real stats from monsters.json")
	var js = get_tree().root.get_node_or_null("JobSystem")
	assert_not_null(js, "precondition: JobSystem autoload")
	var healed := 0
	for a in e.learned_abilities:
		var ab: Dictionary = js.get_ability(str(a))
		if str(ab.get("type", "")) == "healing":
			healed = maxi(healed, int(ab.get("heal_amount", 0)))
	assert_gt(healed, 0, "control: the fixture must know a heal with a real authored amount")
	assert_gt(float(healed) / float(e.max_hp), 0.25,
		"control: the heal must be large relative to its HP, or this file tests nothing")




func test_a_battle_that_cannot_resolve_reports_stalemate() -> void:
	## DETERMINISTIC by construction: a party that cannot die and cannot kill must exhaust
	## MAX_ROUNDS. Forcing it beats sampling it — my first version asserted bands measured from
	## ONE run each and they failed on re-run, because the resolver is stochastic. A single sample
	## of a random process is not a measurement.
	var r := HeadlessBattleResolver.new()
	var tank: Array = []
	for i in range(2):
		var c := Combatant.new()
		c.initialize({"name": "Tank%d" % i, "max_hp": 99999, "max_mp": 0,
			"attack": 1, "defense": 9999, "magic": 1, "speed": 1})
		add_child_autofree(c)
		tank.append(c)
	var res: Dictionary = r.resolve_battle(tank, [_healer_enemy()])
	assert_eq(str(res.get("termination_reason", "")), "stalemate",
		"an unresolvable battle must be REPORTED as a stalemate, not as an ordinary defeat")
	assert_false(bool(res.get("victory", true)), "and it is not a win")


func test_the_stalemate_rate_against_an_underpowered_party_is_reported() -> void:
	## Context, not an assertion — a rate cannot be pinned without making the suite flaky.
	## Measured over 20 runs each on 2026-09-09, after the .242 healing fix turned enemy healing on:
	##   atk 100  stalemate 35%  win   0%   <- grinds a fight it NEVER wins, a third timing out
	##   atk 150  stalemate 15%  win  50%
	##   atk 200  stalemate  0%  win 100%
	## The 0%-win/35%-stalemate band is the one that matters: before a consumer existed, that party
	## ground forever and every timeout looked like an ordinary defeat.
	gut.p("stalemate rates (2026-09-09, n=20): atk100 35%% | atk150 15%% | atk200 0%%")
	assert_true(true, "documentation arm")


func test_the_grind_actually_STOPS_on_a_stalemate() -> void:
	## The defect this file exists for: termination_reason had 3 writes in the resolver and ZERO
	## consumers, so a stalemating matchup ground forever losing every battle. Cadence #19 built
	## the signal; nothing ever listened.
	var sys = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(sys)
	sys._test_disable_persistence = true
	sys.is_grinding = true
	sys.on_battle_stalemate()
	assert_false(sys.is_grinding, "a stalemate must stop the grind rather than repeat it forever")


func test_a_stalemate_signal_is_inert_when_not_grinding() -> void:
	# ARM+: the consumer must not fire stop machinery outside a session.
	var sys = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(sys)
	sys._test_disable_persistence = true
	sys.is_grinding = false
	sys.on_battle_stalemate()
	assert_false(sys.is_grinding, "no-op outside a grind")


func test_the_CONSUMER_IS_WIRED_not_just_present() -> void:
	## My mutation removed stop_autogrind from on_battle_stalemate and watched this file go red —
	## which proves the HELPER works and says nothing about whether anything CALLS it. That is the
	## unit-versus-wiring gap I hit two hours ago on the action picker and shipped again here.
	##
	## The call lives in GameLoop, at the only place a headless result is consumed, and GameLoop is
	## not instantiable in a unit test. A source pin is the RIGHT instrument for this particular
	## claim rather than a substitute for a behavioural one: the question is literally "does a call
	## site exist", which is a property of the text. It cannot tell you the call fires — the arms
	## above cover that half — but it does catch the failure that actually happened to cadence #19,
	## where a signal had three writers and no reader for months.
	## ⚠️ MY FIRST PIN WAS ITSELF HOLLOW: it asserted contains("on_battle_stalemate"), which also
	## matches the has_method("on_battle_stalemate") GUARD on the line above — so deleting the CALL
	## left it green. A mention is not a call. Pin the invocation syntax, receiver and parens.
	var src: String = load("res://src/GameLoop.gd").source_code
	assert_true(src.contains("AutogrindSystem.on_battle_stalemate()"),
		"GameLoop must CALL it — a has_method mention is not a call site, and this signal already went unread once")
	assert_true(src.contains('result.get("termination_reason"'),
		"and it must read the field off the battle result, not merely name the method")
