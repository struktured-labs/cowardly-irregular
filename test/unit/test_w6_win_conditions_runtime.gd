extends GutTest

## Runtime companion to test_w6_win_conditions_regression (msg 3225).
##
## That file pins the SHAPE via source text. This one drives the real
## objects, because a source ratchet cannot catch a logic error — it
## would happily confirm that a correctly-spelled comparison runs
## backwards. Both arms are counter-driven, and a counter is exactly the
## thing worth executing rather than reading.

var _bm: Node


func before_each() -> void:
	# Fresh instance rather than the autoload, so a half-argued ladder
	# cannot leak into unrelated tests. In-tree via add_child_autofree
	# (the pattern test_free_move_mp_restore_target_regression uses):
	# end_battle resolves absolute node paths, and a detached node makes
	# those fail loudly enough to bury a real error in the suite log.
	_bm = load("res://src/battle/BattleManager.gd").new()
	add_child_autofree(_bm)


func _pc(job_id: String) -> Combatant:
	var c: Combatant = autofree(Combatant.new())
	c.combatant_name = job_id.capitalize()
	c.job = {"id": job_id}
	c.is_alive = true
	_bm.player_party.append(c)
	return c


## ── withhold_attack ──────────────────────────────────────────────────

func test_restraint_accumulates_and_wins() -> void:
	_bm._win_condition = {"type": "withhold_attack", "value": 3}
	assert_false(_bm._evaluate_custom_win_condition(), "must not win before any round")
	for i in 3:
		_bm._advance_withhold_round()
	assert_eq(_bm._wc_withhold_rounds, 3, "three quiet rounds must credit three")
	assert_true(_bm._evaluate_custom_win_condition(), "restraint must win at the authored count")


func test_victory_lands_on_the_round_it_is_earned() -> void:
	# The behaviour the source ratchet used to defend with a character-count
	# window. Off-by-one here is invisible in review and reads in play as a
	# boss that ignores the round you actually won on.
	_bm._win_condition = {"type": "withhold_attack", "value": 2}
	_bm._advance_withhold_round()
	assert_false(_bm._evaluate_custom_win_condition(), "one quiet round of two must not win")
	_bm._advance_withhold_round()
	assert_true(_bm._evaluate_custom_win_condition(),
		"the SECOND quiet round must win on that round — crediting after the victory check lands it a round late")


func test_a_strike_zeroes_the_count() -> void:
	var hero: Combatant = _pc("fighter")
	_bm._win_condition = {"type": "withhold_attack", "value": 3}
	_bm._advance_withhold_round()
	_bm._advance_withhold_round()
	assert_eq(_bm._wc_withhold_rounds, 2, "precondition: two rounds banked")
	_bm._observe_action_for_win_condition(hero, {"type": "attack"})
	assert_eq(_bm._wc_withhold_rounds, 0, "a strike must zero banked restraint")
	assert_false(_bm._evaluate_custom_win_condition())


func test_striking_round_earns_no_credit() -> void:
	var hero: Combatant = _pc("fighter")
	_bm._win_condition = {"type": "withhold_attack", "value": 2}
	_bm._observe_action_for_win_condition(hero, {"type": "attack"})
	_bm._advance_withhold_round()
	assert_eq(_bm._wc_withhold_rounds, 0,
		"the round in which you struck must not itself be credited at round end")


func test_enemy_action_does_not_break_restraint() -> void:
	var boss: Combatant = autofree(Combatant.new())
	boss.combatant_name = "Warden of Form"
	boss.is_alive = true
	_bm.enemy_party.append(boss)
	_bm._win_condition = {"type": "withhold_attack", "value": 2}
	_bm._advance_withhold_round()
	_bm._observe_action_for_win_condition(boss, {"type": "attack"})
	assert_eq(_bm._wc_withhold_rounds, 1,
		"the Warden attacking YOU must not break your restraint")


func test_unauthored_value_is_not_an_instant_win() -> void:
	_bm._win_condition = {"type": "withhold_attack"}
	assert_false(_bm._evaluate_custom_win_condition(),
		"a missing value must not hand over a victory before the fight starts")


func test_progress_signal_fires_with_real_numbers() -> void:
	_bm._win_condition = {"type": "withhold_attack", "value": 4}
	var seen: Array = []
	_bm.win_condition_progress.connect(func(k, c, n): seen.append([k, c, n]))
	_bm._advance_withhold_round()
	assert_eq(seen.size(), 1, "one quiet round must emit exactly one progress event")
	assert_eq(seen[0], ["withhold_attack", 1, 4], "progress must carry live current/needed")
	var hero: Combatant = _pc("mage")
	_bm._observe_action_for_win_condition(hero, {"type": "attack"})
	assert_eq(seen[1], ["withhold_attack", 0, 4],
		"the reset must emit too — it is the beat both audio lanes are scoring")


## ── arbiter_ladder ───────────────────────────────────────────────────

const LADDER: Array = [
	{"key": "faith", "job": "cleric"},
	{"key": "logic", "job": "mage"},
	{"key": "edge", "job": "rogue"},
	{"key": "voice", "job": "bard"},
]


func _ladder_battle() -> Dictionary:
	_bm._win_condition = {"type": "arbiter_ladder", "phases": LADDER.duplicate(true)}
	# Fighter FIRST, deliberately. The real party is the locked five and
	# Fighter leads it, so party index never equals phase index — cleric is
	# party[1] arguing phase[0]. Without him the two orders coincide and the
	# fixture cannot tell "match the phase's job" from "the Nth party member
	# argues the Nth phase", which is a plausible misreading of the design.
	# Verified: that mutation passes 15/15 against a fixture without Fighter.
	_pc("fighter")
	return {
		"cleric": _pc("cleric"), "mage": _pc("mage"),
		"rogue": _pc("rogue"), "bard": _pc("bard"),
	}


func test_ladder_in_order_wins() -> void:
	var pcs: Dictionary = _ladder_battle()
	for job in ["cleric", "mage", "rogue", "bard"]:
		assert_false(_bm._evaluate_custom_win_condition(), "must not win mid-ladder at %s" % job)
		_bm._observe_action_for_win_condition(pcs[job], {"type": "ability", "ability_id": "cure"})
	assert_eq(_bm._wc_phase_index, 4, "all four phases must register")
	assert_true(_bm._evaluate_custom_win_condition(), "a completed case wins")


func test_out_of_order_does_not_advance() -> void:
	var pcs: Dictionary = _ladder_battle()
	# Voice is authored LAST; opening with it must not count.
	_bm._observe_action_for_win_condition(pcs["bard"], {"type": "ability", "ability_id": "lullaby"})
	assert_eq(_bm._wc_phase_index, 0, "Voice cannot open the case — the ladder is ordered")
	_bm._observe_action_for_win_condition(pcs["cleric"], {"type": "ability", "ability_id": "cure"})
	assert_eq(_bm._wc_phase_index, 1, "Faith opens it")


func test_plain_attack_does_not_argue() -> void:
	var pcs: Dictionary = _ladder_battle()
	_bm._observe_action_for_win_condition(pcs["cleric"], {"type": "attack"})
	assert_eq(_bm._wc_phase_index, 0, "a swing is not an argument")


func test_empty_ladder_never_wins() -> void:
	_bm._win_condition = {"type": "arbiter_ladder", "phases": []}
	assert_false(_bm._evaluate_custom_win_condition(),
		"an unauthored phases array must not read as a completed case")


func test_ladder_emits_ordered_progress() -> void:
	var pcs: Dictionary = _ladder_battle()
	var seen: Array = []
	_bm.win_condition_progress.connect(func(k, c, n): seen.append([k, c, n]))
	for job in ["cleric", "mage", "rogue", "bard"]:
		_bm._observe_action_for_win_condition(pcs[job], {"type": "ability", "ability_id": "cure"})
	assert_eq(seen, [
		["arbiter_ladder", 1, 4], ["arbiter_ladder", 2, 4],
		["arbiter_ladder", 3, 4], ["arbiter_ladder", 4, 4],
	], "each phase must report once, in order, with the true denominator")


## ── strike classification against REAL ability data ──────────────────

func test_damage_abilities_are_strikes_and_support_is_not() -> void:
	# Reads live abilities.json through JobSystem rather than a fixture —
	# the classifier's whole job is to agree with the shipped data.
	if get_tree().root.get_node_or_null("JobSystem") == null:
		pending("JobSystem autoload unavailable")
		return
	assert_true(_bm._action_is_strike({"type": "ability", "ability_id": "fire"}),
		"fire deals damage — a strike")
	assert_false(_bm._action_is_strike({"type": "ability", "ability_id": "cure"}),
		"cure heals — restraint survives it, which is what makes the fight playable")
	assert_true(_bm._action_is_strike({"type": "attack"}), "a plain swing is a strike")
	assert_false(_bm._action_is_strike({"type": "defer"}), "deferring is the intended play")


func test_advance_queue_hiding_a_strike_is_caught() -> void:
	# The partial-enumeration trap: an Advance is typed "advance", so a
	# shallow check would let the player swing freely inside one.
	if get_tree().root.get_node_or_null("JobSystem") == null:
		pending("JobSystem autoload unavailable")
		return
	assert_true(_bm._action_is_strike({
		"type": "advance",
		"actions": [{"type": "defer"}, {"type": "attack"}],
	}), "a strike queued inside an Advance still counts as striking")
	assert_false(_bm._action_is_strike({
		"type": "advance",
		"actions": [{"type": "defer"}, {"type": "ability", "ability_id": "cure"}],
	}), "a peaceful Advance queue must not break restraint")


## ── cross-battle leak ────────────────────────────────────────────────

func test_end_battle_clears_progress() -> void:
	var pcs: Dictionary = _ladder_battle()
	_bm._observe_action_for_win_condition(pcs["cleric"], {"type": "ability", "ability_id": "cure"})
	_bm._wc_withhold_rounds = 2
	assert_eq(_bm._wc_phase_index, 1, "precondition: mid-ladder")
	_bm.end_battle(true)
	assert_eq(_bm._wc_phase_index, 0, "a half-argued case must not survive into the next battle")
	assert_eq(_bm._wc_withhold_rounds, 0, "banked restraint must not survive either")
	assert_true(_bm._win_condition.is_empty(), "and the condition itself clears")
