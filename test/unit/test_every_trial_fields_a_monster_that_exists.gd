extends GutTest

## THE THREE SUB-FINAL TRIALS (struktured, 2026-10-26: "three sub final bosses, one for automated
## gamers, one for classic gmaes, one for one shottesr"). `TrialRouting` shipped in v3.33.728 with
## its routing guarded and NO OCCUPANTS — every playstyle reached exactly one trial and each trial
## fielded nothing. This pins that the data behind it exists and still carries the mechanic its
## trial is named for.
##
## ⛔ IT CHECKS THE MECHANIC, NOT THE PROSE. cowir-story owns every display name, description,
## dialogue line and intro cutscene on these entries and can rewrite all of it without touching this
## file. What must not change silently is WHAT EACH TRIAL TESTS: the automation trial has to punish
## repetition, the classic trial has to rotate its weakness, the burst trial has to be deletable in
## one phase. A guard keyed to names would red on an author doing their job and stay green on the
## three mechanics being quietly dropped.
##
## 🔑 THE POPULATION IS DERIVED FROM `TrialRouting.TRIAL_MONSTERS`, not listed here — a fourth trial
## or a renamed occupant is covered without editing this file, and a trial pointing at a missing id
## reds by name.

const ROUTING := preload("res://src/battle/TrialRouting.gd")


func _monsters() -> Dictionary:
	var f := FileAccess.open("res://data/monsters.json", FileAccess.READ)
	assert_not_null(f, "monsters.json must open")
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


func test_the_routing_still_exposes_what_these_arms_read() -> void:
	assert_true(ROUTING.TRIAL_MONSTERS is Dictionary, "TRIAL_MONSTERS is the derived population")
	assert_eq((ROUTING.TRIAL_MONSTERS as Dictionary).size(), 3,
		"struktured asked for THREE; a fourth is fine but is a design change, not a silent one")
	for trial in [ROUTING.TRIAL_AUTOMATION, ROUTING.TRIAL_CLASSIC, ROUTING.TRIAL_BURST]:
		assert_true((ROUTING.TRIAL_MONSTERS as Dictionary).has(trial),
			"trial '%s' has no occupant in TRIAL_MONSTERS" % trial)
	assert_eq(ROUTING.monster_for("a_trial_that_does_not_exist"),
		str((ROUTING.TRIAL_MONSTERS as Dictionary)[ROUTING.TRIAL_CLASSIC]),
		"an unrecognised trial must fall back to the classic occupant, not to an empty arena")


func test_every_trial_fields_a_monster_that_exists() -> void:
	var ms: Dictionary = _monsters()
	assert_gt(ms.size(), 0, "CONTROL: monsters.json parsed, else every arm below is vacuous")
	for trial in ROUTING.TRIAL_MONSTERS:
		var id: String = str(ROUTING.TRIAL_MONSTERS[trial])
		assert_true(ms.has(id), "trial '%s' fields '%s', which is not in monsters.json" % [trial, id])
		if not ms.has(id):
			continue
		var e: Dictionary = ms[id]
		assert_true(bool(e.get("boss", false)), "%s is a sub-final boss and must be flagged boss" % id)
		assert_true(e.has("one_shot"), "%s needs a one_shot block — every boss carries one" % id)
		assert_eq(int((e["one_shot"] as Dictionary).get("hp_threshold", -1)),
			int((e.get("stats", {}) as Dictionary).get("max_hp", -2)),
			"%s's one_shot threshold must EQUAL its max_hp — the honest form .727 established" % id)


## The three trials must be interchangeable in everything except mechanic, or the routing decides
## difficulty and payout rather than flavour. Derived relationship, not pinned values.
func test_the_three_trials_are_the_same_rung_of_the_ladder() -> void:
	var ms: Dictionary = _monsters()
	var levels: Array = []
	var exps: Array = []
	var golds: Array = []
	for trial in ROUTING.TRIAL_MONSTERS:
		var e: Dictionary = ms.get(str(ROUTING.TRIAL_MONSTERS[trial]), {})
		if e.is_empty():
			continue
		levels.append(int(e.get("level", -1)))
		exps.append(int(e.get("exp_reward", -1)))
		golds.append(int(e.get("gold_reward", -1)))
	assert_eq(levels.size(), 3, "CONTROL: all three entries were found")
	for arr in [[levels, "level"], [exps, "exp_reward"], [golds, "gold_reward"]]:
		var values: Array = arr[0]
		for v in values:
			assert_eq(v, values[0],
				"the three trials must share their %s (%s) — routing picks a MECHANIC, and a player does not choose which trial they get" % [arr[1], str(values)])


func test_each_trial_still_carries_the_mechanic_it_is_named_for() -> void:
	var ms: Dictionary = _monsters()

	var op: Dictionary = ms.get(ROUTING.monster_for(ROUTING.TRIAL_AUTOMATION), {})
	assert_false(op.is_empty(), "the automation trial's occupant must exist")
	var sb: Dictionary = op.get("special_behavior", {}) as Dictionary
	assert_true(bool(sb.get("counter_repeated_actions", false)),
		"the AUTOMATION trial must punish repetition — counter_repeated_actions is the engine hook that does it")
	assert_false((op.get("learns_from", []) as Array).is_empty(),
		"the AUTOMATION trial must adapt — learns_from is what BattleManager's elemental adaptation reads")

	var ex: Dictionary = ms.get(ROUTING.monster_for(ROUTING.TRIAL_CLASSIC), {})
	assert_gt((ex.get("weakness_cycle", []) as Array).size(), 1,
		"the CLASSIC trial must rotate its weakness — a cycle of one element is not a reading test")
	assert_gt(int(ex.get("weakness_cycle_turns", 0)), 0,
		"a weakness_cycle with no turn count never rotates (BattleManager._apply_weakness_cycles)")

	var mg: Dictionary = ms.get(ROUTING.monster_for(ROUTING.TRIAL_BURST), {})
	assert_false(mg.is_empty(), "the burst trial's occupant must exist")
	## The burst trial is the one a one-shot build is SUPPOSED to delete, so it must be the softest
	## target of the three. A relationship, not a number, so retuning all three keeps this true.
	var others: Array = []
	for trial in ROUTING.TRIAL_MONSTERS:
		var id: String = str(ROUTING.TRIAL_MONSTERS[trial])
		if id == ROUTING.monster_for(ROUTING.TRIAL_BURST):
			continue
		others.append(int((ms.get(id, {}).get("stats", {}) as Dictionary).get("max_hp", 0)))
	var burst_hp: int = int((mg.get("stats", {}) as Dictionary).get("max_hp", 0))
	assert_gt(others.size(), 0, "CONTROL: there are other trials to compare against")
	for hp in others:
		assert_lt(burst_hp, hp,
			"the BURST trial must have the lowest max_hp of the three — it is the fight a one-shot build is meant to end in one phase")
