extends GutTest

## Madame Orrery authors an in-voice refusal for arriving out of sequence, once per world —
## "Packet received out of order. Buffering. That's a joke." run_giver_dialogue HAS the branch
## (state == "" and dlg.has("locked")), but _giver_quest_for returns a quest only when it is
## offerable or active, and the offerable case returns before the branch. So the branch cannot
## be reached and all four lines are dead prose. Two of the four givers are placed today
## (madame_orrery_w2 in MapleStripMall, _w3 in BrasstonVillage) and both prereqs are emitted
## by cutscenes, so the locked state is reachable in play — only the dialogue isn't.

const LOCKED_QUEST := "world2_fine_print"
const LOCKED_GIVER := "madame_orrery_w2"
const PREREQ := "world1_orrery_complete"

## ⚠️ WAS `world4_form_exception_alpha` / `dorrit_w4`, AND THAT QUEST IS NOW WITHHELD
## (`"wiring_pending": true`, 2026-10-14 — its custom steps have no emitter, so it could be
## accepted and never finished). Both assertions below would still have PASSED, which is the
## problem: `is_offerable` would be false and `_giver_quest_for` would return "" for a SECOND
## reason, and the arm could then no longer tell you prereq-locking works at all. A control that
## is clear for two reasons cannot attribute its own pass.
##
## Prereq-locked, giver-owned, authors NO locked block, and NOT withheld — asserted below rather
## than assumed, so this control cannot drift into the same state silently.
const SILENT_QUEST := "world2_wrong_blue"
const SILENT_GIVER := "casper_kid"

var _saved_quests: Dictionary
var _saved_flags: Dictionary
var _saved_consts: Dictionary


func before_each() -> void:
	_saved_quests = GameState.quests.duplicate(true)
	_saved_flags = GameState.story_flags.duplicate(true)
	_saved_consts = GameState.game_constants.duplicate(true)
	GameState.quests.erase(LOCKED_QUEST)
	_clear_flag(PREREQ)


func after_each() -> void:
	GameState.quests = _saved_quests
	GameState.story_flags = _saved_flags
	GameState.game_constants = _saved_consts


## is_story_flag_set reads FOUR namespaces; clearing one leaves the quest offerable and the
## whole file green against the shipped defect.
func _clear_flag(flag: String) -> void:
	GameState.story_flags.erase(flag)
	GameState.game_constants.erase("cutscene_flag_" + flag)
	GameState.game_constants.erase(flag)
	var d: Variant = GameState.game_constants.get("dungeon_flags", {})
	if d is Dictionary:
		(d as Dictionary).erase(flag)


## FLOOR. If the quest is not actually locked, every assertion below is about nothing.
func test_control_the_quest_is_genuinely_locked() -> void:
	assert_eq(QuestSystem.get_state(LOCKED_QUEST), "", "quest must be unstarted")
	assert_false(QuestSystem.is_offerable(LOCKED_QUEST),
		"quest must be prereq-locked — if it is offerable the fixture failed to clear all four "
		+ "flag namespaces and this file tests the offer path instead")


## ...and the lock must be the PREREQ, not some other absence.
func test_control_it_unlocks_when_the_prereq_lands() -> void:
	GameState.set_story_flag(PREREQ)
	assert_true(QuestSystem.is_offerable(LOCKED_QUEST),
		"setting the prereq must make it offerable; if not, the lock is something else and the "
		+ "regression below would pass for the wrong reason")
	assert_eq(QuestSystem._giver_quest_for(LOCKED_GIVER), LOCKED_QUEST,
		"the offerable path must still resolve — the fix must not disturb live business")


## THE REGRESSION. A locked giver with authored lines must resolve to her quest.
func test_a_locked_giver_with_authored_lines_resolves_to_its_quest() -> void:
	assert_eq(QuestSystem._giver_quest_for(LOCKED_GIVER), LOCKED_QUEST,
		"Madame Orrery authors a refusal for exactly this state and the player can reach it. "
		+ "_giver_quest_for returns only offerable-or-active quests, so run_giver_dialogue's "
		+ "locked branch is unreachable and she says her generic villager line instead")


## The other 29 must NOT start talking. No authored lines means the old silence is correct.
func test_a_locked_giver_without_authored_lines_stays_silent() -> void:
	var q: Dictionary = QuestSystem.get_quest(SILENT_QUEST)
	assert_false(q.is_empty(), "control quest must load")
	assert_false((q.get("dialogue", {}) as Dictionary).has("locked"),
		"control must genuinely lack a locked block, else it proves nothing")
	assert_false(bool(q.get("wiring_pending", false)),
		"control must NOT be wiring_pending — a withheld quest is unofferable for a second reason "
		+ "and this arm could then pass with prereq-locking entirely broken")
	## ⛔ CLEAR THE PREREQ HERE, don't inherit it. Its flag is settable by any earlier file in a
	## sweep, and if it arrives set the quest is OFFERABLE and both assertions below red — an
	## order-dependent flake that reads as a real defect. The original control carried the same
	## exposure; making the claim true by construction is cheaper than hoping.
	var prereq: String = str(q.get("prereq_flag", ""))
	assert_ne(prereq, "", "control must be prereq-gated, or it tests a different shape")
	_clear_flag(prereq)
	assert_false(GameState.is_story_flag_set(prereq), "the control's prereq must actually be clear")
	assert_false(QuestSystem.is_offerable(SILENT_QUEST), "control must be prereq-locked")
	assert_eq(QuestSystem._giver_quest_for(SILENT_GIVER), "",
		"a prereq-locked quest with no authored refusal must still resolve to nothing — the NPC "
		+ "falls through to their own dialogue, which is the correct behaviour for 29 of 33")


## The prose must still be there, and be prose. A block of empty strings would play as silence.
func test_the_four_authored_refusals_are_real_lines() -> void:
	var found: Array = []
	var dir := DirAccess.open("res://data/quests/")
	assert_true(dir != null, "quest dir must open")
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".json"):
			var q = JSON.parse_string(FileAccess.get_file_as_string("res://data/quests/" + f))
			if q is Dictionary:
				var lines: Variant = (q.get("dialogue", {}) as Dictionary).get("locked", [])
				if lines is Array and not (lines as Array).is_empty():
					found.append(q.get("id", f))
					for line in lines:
						assert_true(str((line as Dictionary).get("text", "")).length() > 20,
							"%s's locked line must carry real prose, not a placeholder" % [q.get("id")])
		f = dir.get_next()
	dir.list_dir_end()
	assert_eq(found.size(), 4, "the Orrery arc authors one refusal per world (w2/w3/w4/w5). "
		+ "If this count moves, re-point the guard rather than deleting it: %s" % [found])
