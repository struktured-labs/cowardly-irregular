extends GutTest

## struktured via main 23352: "the base battle engine being sophisticated enough to let monsters [defer and advance]
## strategically or tactically". EnemyTactics replaces the 15% advance roll and the "never defer" rule with a scored
## choice from state, tilted by a short plan (data/enemy_plans.json). These arms pin the state-first contract, the
## stall bounds that keep the old frozen-battle bug dead, the re-pick events, the plan data, and termination by fuzz.


func _rng(s: int = 7) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func _state(over: Dictionary = {}) -> Dictionary:
	var st := {"hp_pct": 1.0, "ap": 0, "consecutive_defers": 0, "allies_alive": 1, "queued_defers": 0,
		"foes": [{"hp": 100, "max_hp": 100, "ap": 0, "deferring": false, "est_hit": 10}], "party_ap_total": 0, "party_ap_max": 0}
	st.merge(over, true)
	return st


func test_a_reachable_kill_beats_every_plan() -> void:
	var low := _state({"foes": [{"hp": 6, "max_hp": 100, "ap": 0, "deferring": false, "est_hit": 10}]})
	for tag in EnemyTactics.plans()["plans"]:
		var c: Dictionary = EnemyTactics.choose(low, EnemyTactics.plan(tag), {}, _rng())
		assert_eq([c["shape"], c["why"]], ["attack", "kill"], "plan %s must still take a one-swing kill" % tag)
	var reach := _state({"ap": 2, "foes": [{"hp": 25, "max_hp": 100, "ap": 0, "deferring": false, "est_hit": 10}]})
	var c2: Dictionary = EnemyTactics.choose(reach, EnemyTactics.plan("hold_the_line"), {"advance_weight": 0.5}, _rng())
	assert_eq([c2["shape"], c2["count"], c2["why"]], ["advance", 3, "finish"],
		"a kill three swings away is an Advance ×3 even under a cautious plan and a damped posture")


func test_the_plan_tilts_a_neutral_state_and_the_state_still_rules() -> void:
	var neutral := _state({"ap": 0})
	var steady: Dictionary = EnemyTactics.choose(neutral, EnemyTactics.plan("steady"), {}, _rng())
	var banking: Dictionary = EnemyTactics.choose(neutral, EnemyTactics.plan("bank_then_burst"), {}, _rng())
	assert_eq(steady["shape"], "attack", "CONTROL: with no tilt a monster on 0 AP just attacks")
	assert_eq(banking["shape"], "defer", "bank_then_burst banks on 0 AP: the plan does shift the choice")
	var banked := _state({"ap": 3})
	assert_eq(EnemyTactics.choose(banked, EnemyTactics.plan("bank_then_burst"), {}, _rng())["shape"], "advance",
		"and once banked, the same plan spends it")
	var burst := _state({"party_ap_max": 4, "party_ap_total": 6})
	assert_eq(EnemyTactics.choose(burst, EnemyTactics.plan("steady"), {}, _rng())["why"], "brace",
		"a party that banked a burst is braced for, with no plan at all")


func test_each_stall_rule_bites() -> void:
	var tilted := EnemyTactics.plan("hold_the_line")
	assert_eq(EnemyTactics.choose(_state({"party_ap_max": 4}), tilted, {"defer_weight": 2.0}, _rng())["shape"], "defer",
		"CONTROL: braced, cautious and pushed to defer, it defers")
	for case in [{"consecutive_defers": 2}, {"ap": 4}, {"allies_alive": 3, "queued_defers": 2}]:
		var st := _state({"party_ap_max": 4})
		st.merge(case, true)
		assert_ne(EnemyTactics.choose(st, tilted, {"defer_weight": 2.0}, _rng())["shape"], "defer",
			"no defer when %s, whatever the plan and posture" % str(case))


func test_no_advance_into_debt_it_cannot_survive() -> void:
	var healthy := _state({"ap": 2, "hp_pct": 0.9})
	var hurt := _state({"ap": 2, "hp_pct": 0.2})
	var p := EnemyTactics.plan("punish_defer")
	assert_eq(EnemyTactics.choose(healthy, p, {"advance_weight": 2.0}, _rng())["shape"], "advance", "CONTROL: healthy on 2 AP, it bursts ×3")
	assert_ne(EnemyTactics.choose(hurt, p, {"advance_weight": 2.0}, _rng())["shape"], "advance", "at 20% HP it will not go into debt")


func test_each_repick_event_fires_and_a_quiet_turn_does_not() -> void:
	var base := _state({"allies_alive": 2})
	assert_eq(EnemyTactics.repick_event({}, base), "encounter", "the first turn picks a plan")
	assert_eq(EnemyTactics.repick_event(base, base.duplicate(true)), "", "CONTROL: a quiet turn re-picks nothing")
	var cases := {"hp_band_crossed": {"hp_pct": 0.4}, "ally_fell": {"allies_alive": 1}, "foe_fell": {"foes": []},
		"party_banked": {"party_ap_max": 3},
		"target_killable": {"foes": [{"hp": 5, "max_hp": 100, "ap": 0, "deferring": false, "est_hit": 10}]}}
	for ev in cases:
		var now := base.duplicate(true)
		now.merge(cases[ev], true)
		assert_eq(EnemyTactics.repick_event(base, now), ev, "%s re-picks" % ev)


func test_every_plan_tag_and_weight_is_real() -> void:
	var p := EnemyTactics.plans()
	var tags: Dictionary = p["plans"]
	assert_true(tags.has("steady"), "CONTROL: the no-tilt plan exists")
	var reached := {"steady": true}
	for k in p["personality"]:
		assert_true(tags.has(p["personality"][k]), "personality %s names a real plan" % k)
		reached[p["personality"][k]] = true
	for k in p["events"]:
		assert_true(tags.has(p["events"][k]), "event %s names a real plan" % k)
		reached[p["events"][k]] = true
	for t in tags:
		assert_true(reached.has(t), "plan %s is reachable from a personality or an event" % t)
		assert_gt(int(tags[t].get("turns", 0)), 0, "plan %s lasts at least a turn" % t)
		for w in tags[t].get("weights", {}):
			assert_true(w in ["attack", "defer", "advance"], "plan %s weights '%s', which the scorer never reads" % [t, w])
	for arch in ["brute", "assassin", "tank", "caster", "debuffer", "healer"]:
		assert_true(p["personality"].has(arch), "the existing AI archetype %s has a personality" % arch)


## Termination: seeded battles, every monster on EnemyTactics, a party that defers as much as the worst player can.
## A stall is rounds where NOBODY lands a blow; the bounds cap that at 2 in a row, so 3 is the old frozen-battle bug.
func test_every_fuzzed_battle_ends() -> void:
	var stuck: Array = []
	var defers := 0
	var advances := 0
	for seed_i in 300:
		var r := _rng(seed_i + 1)
		var party: Array = []
		var foes: Array = []
		for i in r.randi_range(1, 4):
			party.append(_fighter("P%d" % i, r))
		for i in r.randi_range(1, 4):
			foes.append(_fighter("E%d" % i, r))
		var always_defer: bool = seed_i % 3 == 0
		var rounds := 0
		var quiet := 0
		var worst_quiet := 0
		while _alive(party).size() > 0 and _alive(foes).size() > 0 and rounds < 2000:
			rounds += 1
			var landed := 0
			for c in party + foes:
				c.is_defending = false
			for p in _alive(party):
				if always_defer or r.randf() < 0.4:
					p.is_defending = true
					p.current_ap = mini(p.current_ap + 1, 4)
				else:
					landed += _swing(p, _alive(foes), r, 1)
			var queued := 0
			for e in _alive(foes):
				var c: Dictionary = EnemyTactics.decide(e, _alive(foes), _alive(party), "caster", {}, r, queued, Callable(self, "_est"))
				match str(c["shape"]):
					"defer":
						e.is_defending = true
						e.current_ap = mini(e.current_ap + 1, 4)
						queued += 1
						defers += 1
					"advance":
						advances += 1
						landed += _swing(e, _alive(party), r, int(c["count"]))
						e.current_ap -= int(c["count"]) - 1
					_:
						landed += _swing(e, _alive(party), r, 1)
			quiet = quiet + 1 if landed == 0 else 0
			worst_quiet = maxi(worst_quiet, quiet)
		if rounds >= 2000 or worst_quiet >= 3:
			stuck.append("seed %d: %d rounds, %d quiet in a row" % [seed_i, rounds, worst_quiet])
	assert_gt(defers, 0, "CONTROL: monsters really do defer in the fuzz")
	assert_gt(advances, 0, "CONTROL: and really do advance")
	assert_eq(stuck, [], "every battle must end and never sit 3 rounds with no blow landed")


static func _est(a: Combatant, t: Combatant) -> int:
	return maxi(1, int(float(a.attack * a.attack) / float(maxi(1, a.attack + t.defense))))


func _fighter(nm: String, r: RandomNumberGenerator) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": nm, "max_hp": r.randi_range(40, 160), "max_mp": 0, "attack": r.randi_range(8, 30),
		"defense": r.randi_range(4, 20), "magic": 1, "speed": 10})
	add_child_autofree(c)
	c.current_ap = 0
	return c


func _alive(side: Array) -> Array:
	return side.filter(func(c): return c.is_alive)


func _swing(a: Combatant, targets: Array, r: RandomNumberGenerator, times: int) -> int:
	var hits := 0
	for i in times:
		var live := _alive(targets)
		if live.is_empty():
			return hits
		hits += 1
		var t: Combatant = live[r.randi() % live.size()]
		var d: int = _est(a, t) / (2 if t.is_defending else 1)
		t.current_hp = maxi(0, t.current_hp - maxi(1, d))
		if t.current_hp == 0:
			t.is_alive = false
	return hits
