extends GutTest

## A boss face can change what WINNING means (2026-08-06).
##
## Party power is FLAT across W2-W6 — damage/round 1044 at L20 vs 1049 at L28, measured,
## because one equipment catalog covers the whole game. So more boss HP buys LENGTH, not
## difficulty; a 34,000 HP finale is a 33-round sponge. A fight gets harder by changing
## what the player must DO, which struktured already ruled once for Mordaine:
## "meta-aware mechanics fit her identity better than stat inflation" (BattleManager:1068).
##
## Four win-condition arms already exist. Two belong to the masterites the Calibrant wears
## (withhold_attack -> Warden, arbiter_ladder -> Arbiter), so the phases don't represent
## wearing their faces; they ARE their faces, procedurally.
##
## ⚠️ Authored-site counts differ by arm, and an earlier version of this comment said all
## four were authored exactly ONCE. Measured: withhold_attack and arbiter_ladder are, in
## monsters.json only — but survive_turns and status_threshold are DUAL-SOURCED, once in
## monsters.json and once as a cutscene `battle` step, where the step overrides. Editing
## the monster and expecting a duel to change is the trap; check both.
##
## ⚠️ SHIPPED OFF BY DEFAULT. A face with no `win_condition` key leaves _win_condition
## untouched, so every boss in the game behaves identically after this lands — including
## the Calibrant fight struktured played all night. Enabling a phase is one JSON field.
## That default is deliberate: changing the final boss's rules on my own design taste while
## he is away is not a routine call, and turning it on later costs thirty seconds.

func _bm() -> Node:
	var bm: Node = load("res://src/battle/BattleManager.gd").new()
	add_child_autofree(bm)
	return bm


func _enemy(name_in: String) -> Combatant:
	var c: Combatant = autofree(Combatant.new())
	c.combatant_name = name_in
	c.is_alive = true
	c.max_hp = 1000
	c.current_hp = 1000
	return c


## ── the default: nothing changes unless data says so ─────────────────

func test_a_face_without_a_win_condition_leaves_the_battle_untouched() -> void:
	# The property that makes this safe to land while he's playing. If this ever fails,
	# every shipped boss silently changed.
	var bm := _bm()
	bm._win_condition = {"type": "hp_zero"}
	bm._apply_face_win_condition({"name": "the Warden"}, "the Warden")
	assert_eq(bm._win_condition, {"type": "hp_zero"},
		"a face with no win_condition must not touch _win_condition — this is what keeps every existing boss byte-identical")


func test_an_empty_win_condition_dict_is_also_inert() -> void:
	var bm := _bm()
	bm._win_condition = {"type": "hp_zero"}
	bm._apply_face_win_condition({"name": "x", "win_condition": {}}, "x")
	assert_eq(bm._win_condition, {"type": "hp_zero"},
		"an empty dict must be treated as absent, not as a wipe")


## ── the switch ───────────────────────────────────────────────────────

func test_a_face_can_impose_its_own_win_condition() -> void:
	var bm := _bm()
	bm._win_condition = {"type": "hp_zero"}
	bm._apply_face_win_condition({"win_condition": {"type": "withhold_attack", "value": 3}}, "the Warden")
	assert_eq(str(bm._win_condition.get("type", "")), "withhold_attack",
		"the face's condition must replace the battle's")


## ── the arms LATCH, which is the actual work ─────────────────────────

func test_survive_turns_counts_from_the_phase_not_the_battle() -> void:
	# The defect a naive reassign ships: survive_turns compares ABSOLUTE current_round, so
	# a phase demanding "survive 3" that begins on round 12 is already won.
	var bm := _bm()
	bm.current_round = 12
	bm._apply_face_win_condition({"win_condition": {"type": "survive_turns", "value": 3}}, "Tempo")
	assert_false(bm._evaluate_custom_win_condition(),
		"a survive-3 phase beginning at round 12 must NOT be instantly satisfied")
	bm.current_round = 14
	assert_false(bm._evaluate_custom_win_condition(), "two turns in is still not three")
	bm.current_round = 15
	assert_true(bm._evaluate_custom_win_condition(), "three turns after the phase began, it is met")


func test_survive_turns_is_unchanged_when_no_phase_stamped_it() -> void:
	# The additive property. Every Spotlight Duel authors survive_turns with no _since_round,
	# so the baseline is 0 and behaviour is exactly what shipped.
	var bm := _bm()
	bm._win_condition = {"type": "survive_turns", "value": 5}
	bm.current_round = 4
	assert_false(bm._evaluate_custom_win_condition(), "round 4 of 5 is not yet a win")
	bm.current_round = 5
	assert_true(bm._evaluate_custom_win_condition(),
		"round 5 of 5 wins — a duel with no phase stamp must behave exactly as before")


func test_status_stacks_from_a_previous_phase_do_not_pre_satisfy_the_next() -> void:
	# The other latch: status_threshold reads a `_<status>_stacks` meta the PREVIOUS phase
	# filled. Carry it over and the new phase is won on arrival.
	var bm := _bm()
	var boss := _enemy("Calibrant")
	bm.enemy_party.append(boss)
	boss.set_meta("_swayed_stacks", 9)
	bm._apply_face_win_condition({"win_condition": {"type": "status_threshold", "status": "swayed", "value": 3}}, "the Curator")
	assert_eq(int(boss.get_meta("_swayed_stacks", -1)), 0,
		"the incoming phase must start from zero stacks, or nine carried stacks win it instantly")
	assert_false(bm._evaluate_custom_win_condition(),
		"and the condition must therefore evaluate as unmet")


func test_the_reset_only_clears_the_status_the_new_phase_names() -> void:
	# Precision: clearing every meta on the boss would be a bigger hammer than the defect,
	# and would erase state other systems own.
	var bm := _bm()
	var boss := _enemy("Calibrant")
	bm.enemy_party.append(boss)
	boss.set_meta("_swayed_stacks", 4)
	boss.set_meta("_boss_face_index", 2)
	bm._apply_face_win_condition({"win_condition": {"type": "status_threshold", "status": "swayed", "value": 3}}, "x")
	assert_eq(int(boss.get_meta("_boss_face_index", -1)), 2,
		"unrelated meta must survive — the face cursor especially, since the phase machinery reads it")


## ── the corpus this is built on ──────────────────────────────────────

func test_the_arms_this_relies_on_still_exist() -> void:
	# If an arm is renamed, a phase authoring it silently becomes unwinnable. Named members,
	# not a count — a count passes on a table that resolved nothing.
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_ne(src, "", "the file must be readable or this is vacuous")
	for arm in ["survive_turns", "status_threshold", "withhold_attack", "arbiter_ladder"]:
		assert_true(src.contains('"%s":' % arm),
			"win-condition arm `%s` must still exist — a phase authoring it would otherwise be unwinnable" % arm)
