extends GutTest

## W6 win-condition arms + win_condition_progress signal (msg 3225).
##
## The two Calibrant finales are won by NOT fighting:
##   withhold_attack  — Warden of Form. Survive N consecutive rounds
##                      without a single player strike. Any strike zeroes
##                      the count, so the counter teaches the rule.
##   arbiter_ladder   — Arbiter of Essence. Argue a case IN ORDER;
##                      each phase satisfied by its job using a real
##                      ability. Voice last, per cowir-story's canon.
##
## Both report through `win_condition_progress(kind, current, needed)`,
## which cowir-sfx and cowir-music are scoring against — they had split
## the audio between them and were blocked on a live signal rather than a
## described one, so the emit shape is pinned here.

const BM_SRC: String = "res://src/battle/BattleManager.gd"


func _src() -> String:
	return FileAccess.get_file_as_string(BM_SRC)


func _fn_body(name: String) -> String:
	var s: String = _src()
	var i: int = s.find("func %s(" % name)
	assert_gt(i, -1, "function %s must exist" % name)
	var n: int = s.find("\nfunc ", i + 1)
	return s.substr(i, (n - i) if n > -1 else 4000)


## ── (1) The signal exists with the agreed shape ──────────────────────

func test_progress_signal_declared() -> void:
	# Two lanes are building against this exact signature. A rename or an
	# arg-order change is a cross-lane break, not a local refactor.
	assert_string_contains(_src(),
		"signal win_condition_progress(kind: String, current: int, needed: int)",
		"the agreed signal shape is a cross-lane contract with cowir-sfx and cowir-music")


func test_both_arms_emit_progress() -> void:
	assert_string_contains(_fn_body("_advance_withhold_round"),
		'win_condition_progress.emit("withhold_attack"',
		"restraint must report progress or the audio lane has nothing to score")
	assert_string_contains(_fn_body("_observe_action_for_win_condition"),
		'win_condition_progress.emit("arbiter_ladder"',
		"the ladder must report progress per phase")


func test_reset_emits_progress_too() -> void:
	# A reset to zero is a CHANGE, and the most audible moment in a
	# withhold fight. Emitting only on increases would make the failure
	# silent — exactly the beat both audio lanes asked to score.
	var body: String = _fn_body("_observe_action_for_win_condition")
	var reset_at: int = body.find("_wc_withhold_rounds = 0")
	assert_gt(reset_at, -1, "a strike must zero the counter")
	assert_gt(body.find('win_condition_progress.emit("withhold_attack", 0', reset_at), -1,
		"the reset must emit progress 0 — a regression is a change, and it is the loudest one")


## ── (2) withhold_attack ──────────────────────────────────────────────

func test_withhold_never_wins_on_unauthored_value() -> void:
	# The silent-failure shape: `value` missing → 0, and `rounds >= 0` is
	# true before the fight starts. That reads as a victory the player
	# never earned, on a boss that never acted.
	var body: String = _fn_body("_evaluate_custom_win_condition")
	var arm: int = body.find('"withhold_attack"')
	assert_gt(arm, -1, "withhold_attack arm must exist")
	var next_arm: int = body.find('"arbiter_ladder"', arm)
	var seg: String = body.substr(arm, next_arm - arm)
	assert_string_contains(seg, "need_rounds > 0",
		"an unauthored value must not read as an instant win")


func test_strike_classification_uses_damage_multiplier_not_type() -> void:
	# `type` and `damage_multiplier` DISAGREE in abilities.json: 'support'
	# and 'meta' entries carry multipliers while some 'magic' does not.
	# Classifying on type would be a proxy for the thing.
	var body: String = _fn_body("_action_is_strike")
	assert_string_contains(body, "damage_multiplier",
		"strike classification must read the damage multiplier directly")
	assert_false(body.find('== "physical"') > -1,
		"must not classify by ability type — it disagrees with the multiplier")
	assert_false(body.find('== "magic"') > -1,
		"must not classify by ability type — it disagrees with the multiplier")


func test_strike_classification_covers_group_and_advance() -> void:
	# A group attack and an Advance queue are both ways to strike without
	# an action typed "attack". Missing either is the partial-enumeration
	# shape — the player would win a restraint fight while swinging.
	var body: String = _fn_body("_action_is_strike")
	assert_string_contains(body, '"attack", "group"',
		"group attacks are strikes")
	assert_string_contains(body, '"advance"',
		"an Advance queue must be inspected for strikes inside it")
	assert_string_contains(body, "_action_is_strike(sub)",
		"Advance must recurse into its sub-actions rather than trust its own type")


func test_withhold_credited_before_victory_recheck() -> void:
	# The round-end path already ran _check_victory_conditions BEFORE the
	# counter advanced. Without a re-check the win lands a full round late,
	# which reads as an unresponsive boss.
	var s: String = _src()
	var adv: int = s.find("_advance_withhold_round()")
	assert_gt(adv, -1, "round-end must credit the withheld round")
	var recheck: int = s.find("_check_victory_conditions()", adv)
	assert_gt(recheck, -1, "victory must be re-checked after crediting")
	# Assert the ORDER (credit precedes re-check), not the distance. A
	# character-count window is a coincidental magnitude: it goes red on a
	# correct refactor that adds a line between them, and green on a wrong
	# one that keeps them adjacent while reordering. The behaviour this
	# exists to defend is pinned in the runtime file, where it can fail
	# for the real reason.
	assert_gt(recheck, adv,
		"the credit must precede the re-check — reversed, the win lands a full round late")


## ── (3) arbiter_ladder ───────────────────────────────────────────────

func test_ladder_requires_ability_not_plain_attack() -> void:
	var body: String = _fn_body("_observe_action_for_win_condition")
	assert_string_contains(body, 'str(action.get("type", "")) != "ability"',
		"only a real ability argues a case — a plain swing says nothing")


func test_ladder_is_ordered_not_a_set() -> void:
	# The whole design is ORDER (Faith→Logic→Edge→Voice, Voice last). A
	# set-membership check would accept any sequence and quietly discard
	# the mechanic while still passing a "did all four act" test.
	var body: String = _fn_body("_observe_action_for_win_condition")
	assert_string_contains(body, "phases[_wc_phase_index]",
		"the ladder must consult only the CURRENT phase — indexing is what makes it ordered")
	assert_string_contains(body, "_wc_phase_index += 1",
		"a satisfied phase advances the index by one")


func test_empty_ladder_never_wins() -> void:
	var body: String = _fn_body("_evaluate_custom_win_condition")
	assert_string_contains(body, "not _arbiter_phases().is_empty()",
		"an unauthored phases array must not read as a completed ladder")


func test_arbiter_phases_returns_empty_for_other_types() -> void:
	# Lets callers treat an empty ladder as "not an Arbiter fight" without
	# a second type check, so the two guards cannot drift apart.
	assert_string_contains(_fn_body("_arbiter_phases"),
		'!= "arbiter_ladder"',
		"the accessor must type-guard so callers need only check emptiness")


## ── (4) Only the party is judged, and only in these fights ───────────

func test_observer_ignores_enemies() -> void:
	# The Warden attacking YOU must not break your restraint.
	assert_string_contains(_fn_body("_observe_action_for_win_condition"),
		"combatant in player_party",
		"only player actions count — the boss striking must not zero the player's count")


func test_observer_is_inert_without_a_win_condition() -> void:
	# This runs on every action in every normal battle in the game.
	var body: String = _fn_body("_observe_action_for_win_condition")
	assert_string_contains(body, "_win_condition.is_empty()",
		"must early-out in normal battles")
	assert_string_contains(_fn_body("_advance_withhold_round"),
		'!= "withhold_attack"',
		"round-end helper must early-out for every other condition")


## ── (5) The arms have real consumers, reachable on the real path ─────

func test_w6_masterites_author_the_new_conditions() -> void:
	# An arm with no consumer is the shipped-unwired shape this session
	# has spent its length hunting. These two are the consumers.
	var m: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/monsters.json"))
	var expected: Dictionary = {
		"masterite_warden_abstract": "withhold_attack",
		"masterite_arbiter_abstract": "arbiter_ladder",
	}
	for mid in expected:
		assert_true(m.has(mid), "%s must exist" % mid)
		var wc: Variant = (m[mid] as Dictionary).get("win_condition", {})
		assert_true(wc is Dictionary and not (wc as Dictionary).is_empty(),
			"%s must author a win_condition — otherwise the arm has no consumer" % mid)
		assert_eq(str((wc as Dictionary).get("type", "")), expected[mid],
			"%s must use its designed condition" % mid)


func test_arbiter_ladder_data_is_ordered_voice_last() -> void:
	# cowir-story's canon: Voice closes the case. Pinning the authored
	# order, because the mechanic is the order — a shuffled phases array
	# still passes every structural check while destroying the design.
	var m: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/monsters.json"))
	var phases: Array = ((m["masterite_arbiter_abstract"] as Dictionary)["win_condition"] as Dictionary)["phases"]
	var keys: Array = []
	var jobs: Array = []
	for p in phases:
		keys.append(str((p as Dictionary).get("key", "")))
		jobs.append(str((p as Dictionary).get("job", "")))
	assert_eq(keys, ["faith", "logic", "edge", "voice"], "authored order is the mechanic")
	assert_eq(jobs, ["cleric", "mage", "rogue", "bard"],
		"each phase must name a real starter job or its phase is unsatisfiable")


func test_ladder_jobs_are_all_in_the_locked_party() -> void:
	# The party is the locked five. A phase naming a job nobody has would
	# make the fight literally unwinnable — and it would present as a boss
	# that simply never loses, not as a data error.
	var m: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/monsters.json"))
	var jobs_json: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/jobs.json"))
	var phases: Array = ((m["masterite_arbiter_abstract"] as Dictionary)["win_condition"] as Dictionary)["phases"]
	for p in phases:
		var jid: String = str((p as Dictionary).get("job", ""))
		assert_true(jobs_json.has(jid), "phase job '%s' must be a real job" % jid)
		assert_eq(int((jobs_json[jid] as Dictionary).get("type", -1)), 0,
			"phase job '%s' must be a STARTER job — the locked five are the only guaranteed party" % jid)


func test_normal_battles_adopt_monster_win_conditions() -> void:
	# The wiring that makes all of the above real. Before this,
	# _win_condition was set ONLY inside start_solo_battle, so a
	# win_condition on a monster fought as a normal encounter was data
	# with no reader — the arms would have been unreachable in play.
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var helper: int = src.find("func _adopt_monster_win_condition")
	assert_gt(helper, -1, "the general adoption helper must exist")
	var call_at: int = src.find("_adopt_monster_win_condition(specific_enemies)")
	assert_gt(call_at, -1,
		"_start_battle_async must adopt — it is the funnel every battle-entry path goes through")


func test_adoption_never_outranks_an_explicit_condition() -> void:
	# start_solo_battle sets _win_condition BEFORE calling
	# _start_battle_async, so the helper must fill only an empty one or it
	# would silently override every Spotlight Duel's step-authored victory.
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var i: int = src.find("func _adopt_monster_win_condition")
	var n: int = src.find("\nfunc ", i + 1)
	var body: String = src.substr(i, n - i)
	assert_string_contains(body, "not BattleManager._win_condition.is_empty()",
		"must return early when a condition is already set — the duels depend on it")


## ── (6) Latent readers the widened field now reaches ─────────────────

func test_sway_progress_denominator_is_type_guarded() -> void:
	# Generalizing _win_condition to normal battles widened who can see it
	# set. The Bard's sway log read `value` with NO type check — fine while
	# the field only ever held status_threshold during a solo duel, wrong
	# the moment withhold_attack (whose `value` is a ROUND count) can be
	# live in an ordinary encounter. Unreachable today because no monster
	# sets tracks_sway_stacks; pinned because *I* moved it closer to
	# reachable, and an unreachable misread is still a misread waiting.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var at: int = src.find("_swayed_stacks\", current + 1")
	assert_gt(at, -1, "the sway counter must exist")
	var seg: String = src.substr(at, 700)
	var need_at: int = seg.find("var need: int")
	assert_gt(need_at, -1, "the sway log must compute a denominator")
	assert_true(seg.substr(need_at, 220).contains('"status_threshold"'),
		"the sway denominator must only accept `value` from status_threshold — every other condition means something different by it")


## ── (7) Cross-battle leak ────────────────────────────────────────────

func test_counters_reset_with_the_condition() -> void:
	# The nastiest available bug here: a half-argued ladder or banked
	# restraint surviving into an unrelated battle. It would not show in
	# the fight that caused it — only in the NEXT one.
	var body: String = _fn_body("end_battle")
	var clear: int = body.find("_win_condition = {}")
	assert_gt(clear, -1, "end_battle must clear the win condition")
	for field in ["_wc_withhold_rounds = 0", "_wc_struck_this_round = false", "_wc_phase_index = 0"]:
		var at: int = body.find(field, clear)
		assert_gt(at, -1, "end_battle must also clear %s" % field)
		assert_lt(at - clear, 400,
			"%s must be cleared beside the condition it belongs to, not somewhere it can drift from" % field)
