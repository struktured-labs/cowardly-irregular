extends GutTest

## Group attacks are a design pillar — all-out attack, combo magic, six formation specials, limit
## breaks — and **nothing in automation had ever executed one.** @cowir-deploy measured it from the
## other side: **0 occurrences of "group" in the archived .660 render-smoke log.** So the smoke drove
## a scripted fight, a duel, a wipe and a roamer-triggered entry, and never the one command the game
## is partly about.
##
## It cost something concrete. `BattleManager._apply_vulnerability_window` applies two statuses after
## every group attack and has one caller, `_execute_group_action`; two authored, on-disk cues
## (`status_exposed`, `status_cannot_defer`) are reachable only from there and have never played
## (@cowir-music). A static audit credited them as wired on the strength of a `"status_" +`
## construction, so the gap was invisible from both directions at once.
##
## 🔑 THE LEG COVERS THE EXECUTION PATH, NOT THE MENU, AND THAT IS DELIBERATE. @cowir-controller
## measured `Win98Menu:937` deaf for 80ms after every spawn with `ignore_time_scale = true` — 80ms of
## WALL CLOCK at any speed, re-armed per character (~203 spawns in one session). A press landing in
## that window reads as "no group row", i.e. the feature looking broken when the press was mistimed.
## Their surface has its own guards for the menu; buying that coverage again here would cost a flake.
##
## ⚠️ AND IT IS 2 PARTICIPANTS, NOT 5. `group_participants()` returns the current combatant plus
## those LATER in the selection order, so by the time the smoke acts only two remain unselected.
## Measured: `2 of 2 participants struck together`. The leg therefore covers the execution path and
## NOT a full-party pool, which is a real limit and is why the arm below pins >= 2 rather than
## claiming the pillar is covered.

const SMOKE_FILE := "res://src/GameLoop.gd"


func _leg() -> String:
	var src := FileAccess.get_file_as_string(SMOKE_FILE)
	assert_ne(src, "", "CONTROL: GameLoop.gd must be readable or every arm here is vacuous")
	var at := src.find("func _smoke_group_action")
	assert_gt(at, -1, "the group-action leg must exist")
	var end := src.find("\nfunc ", at + 10)
	assert_gt(end, at, "CONTROL: the leg ends before the next function")
	return src.substr(at, end - at)


func test_the_leg_is_reached_while_the_party_can_still_act() -> void:
	var src := FileAccess.get_file_as_string(SMOKE_FILE)
	var call_at := src.find("await _smoke_group_action()")
	assert_gt(call_at, -1, "the leg is defined but never awaited, so it covers nothing")

	## ORDER IS THE PRECONDITION. The party sits in PLAYER_SELECTING only before autobattle takes
	## over; after `_enable_all_autobattle` the AI spends every turn and no group action can be
	## issued. A leg placed below that line would fail for a reason that has nothing to do with
	## group attacks.
	var autobattle_at := src.find("_enable_all_autobattle")
	assert_gt(autobattle_at, -1, "CONTROL: the smoke must still hand over to autobattle")
	assert_lt(call_at, autobattle_at,
		"the group-action leg must run BEFORE autobattle takes the wheel; after it the party never " +
		"reaches PLAYER_SELECTING again and the leg would report a broken feature")


## Every failure must say whether the SETUP or the FEATURE broke. This is the lesson from my own
## wipe leg, which called a correctly-wiped party a missing game-over screen.
func test_every_failure_names_setup_or_feature() -> void:
	var leg := _leg()
	var setup_msgs := leg.count("SETUP, not the feature")
	var feature_msgs := leg.count("THE FEATURE, not the setup")
	assert_gte(setup_msgs, 3,
		"each way the ARRANGEMENT can fail must say so — found %d; an unarranged attempt reported as " % setup_msgs +
		"a broken group attack is the exact failure this leg exists to avoid")
	assert_eq(feature_msgs, 1,
		"exactly one failure is about the FEATURE: the call was made with the preconditions met and " +
		"the execution path did not run")


func test_the_preconditions_are_asserted_before_the_attempt() -> void:
	var leg := _leg()
	assert_true(leg.contains("PLAYER_SELECTING"),
		"the leg must wait for a turn it can spend, not assume one")
	assert_true(leg.contains("group_participants()"),
		"it must check there is a party to pool before asking for a pooled strike")
	assert_true(leg.contains("participants.size() < 2"),
		"a group action needs at least two participants; one is not a group and would fail for the wrong reason")


## The proof is the SIGNAL, not the absence of an error.
func test_the_leg_observes_the_execution_signal() -> void:
	var leg := _leg()
	assert_true(leg.contains("group_attack_executing"),
		"the leg must observe BattleManager's own execution signal — that is what proves " +
		"_execute_group_action ran rather than the call being swallowed")
	assert_true(leg.contains("CONNECT_ONE_SHOT"),
		"one-shot, so the leg cannot be satisfied by a later unrelated group attack")
	assert_true(leg.contains("_smoke_shot(\"group_attack\")"),
		"and it must take a frame, so a blank render fails the smoke")


## It must NOT drive the command menu, for the 80ms reason in the header. If someone adds that
## later it should be a deliberate change against a measurement, not a drift.
func test_the_leg_does_not_drive_the_command_menu() -> void:
	var leg := _leg()
	for menu_shape in ["_smoke_key", "Win98Menu", "ui_accept"]:
		assert_false(leg.contains(menu_shape),
			"the leg reaches for '%s'; the command menu is deaf for 80ms after every spawn " % menu_shape +
			"(ignore_time_scale, so wall clock at any speed) and a press landing there reads as a " +
			"missing group row. Cover the menu on its own surface, not here")


## all_out_attack, specifically, because the other group types make the smoke ARRANGE a precondition.
func test_the_leg_picks_the_group_type_that_needs_no_arrangement() -> void:
	var leg := _leg()
	assert_true(leg.contains("all_out_attack"), "the leg must use the group type with no AP gate")
	for gated in ["limit_break", "combo_magic"]:
		assert_false(leg.contains("player_group_attack(\"%s\")" % gated),
			"'%s' gates on AP (4 each) or elements (2 distinct), so the leg would have to arrange " % gated +
			"its own precondition — and an unmet arrangement is indistinguishable from a broken gate")
