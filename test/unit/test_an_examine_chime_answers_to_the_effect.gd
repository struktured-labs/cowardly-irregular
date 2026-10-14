extends GutTest

## 🐛 A DISCOVERY CHIME FOR A PRESS THAT FOUND NOTHING. `QuestExaminePoint._examine` played
## `secret_found` — the cue `AnnexLiberation`, `CivicBackDoor` and `CivicFrontDesk` use for a
## genuine discovery — BEFORE doing any work. Two facts make that reachable rather than theoretical:
##
##   `_is_live()` keys on the QUEST OBJECTIVE's `required_flag`, not on this member's own flag, so
##   every member of a group stays pressable until the whole set completes.
##   `_group_complete_after_marking()` sets `<flag>_<n>`, which is IDEMPOTENT.
##
## So re-pressing a lamp you had already read played the discovery chime and reprinted the same
## "(1 of 5 documented)". The status said "found something"; the effect was nothing, and the player
## cannot tell whether the press registered. Shipped default, Brasston's five-lamp route.
##
## Found by @cowir-story, who declined it; verified independently before it was taken. The remedy
## follows @cowir-ai's `applied_moved_count` precedent — paint the success from the EFFECT — and
## @cowir-sfx's ruling that the audio answer is a SOFTER CUE, not silence, because the press did
## register and silence cannot say so.
##
## ⚠️ WHY THE SEAM IS STATIC: judging the cue through `_examine` needs a live QuestSystem with an
## active quest whose current objective names this flag. `cue_for` lets the DECISION be driven
## directly, and the idempotency arm below drives the real `_group_done` /
## `_group_complete_after_marking` on a real instance — so the two halves of the defect are each
## tested against real code rather than a restatement.

const FLAG := "zz_examine_chime_probe"
const MANIFEST := "res://data/sfx_manifest.json"

var _saved: Dictionary = {}


## ⛔ SAVE AND RESTORE THE WHOLE FLAG STORE. This file WRITES `GameState.story_flags` through
## `set_story_flag`, and a leaked flag changes what a later file's quest gates see — the same class
## `test_zz_text_size_scale_not_leaked_by_tests` polices for the text scale. A unique flag name is
## not enough: the store itself must come back.
func before_each() -> void:
	_saved = (GameState.story_flags as Dictionary).duplicate(true) if "story_flags" in GameState else {}


func after_each() -> void:
	if "story_flags" in GameState:
		GameState.story_flags.clear()
		for k in _saved:
			GameState.story_flags[k] = _saved[k]


## ⛔ THE DECISION: a press that advanced nothing must not sound like a discovery.
func test_the_cue_is_chosen_by_whether_anything_advanced() -> void:
	var moved: String = QuestExaminePoint.cue_for(true)
	var still: String = QuestExaminePoint.cue_for(false)
	assert_ne(moved, still,
		"both outcomes play '%s' — the cue cannot be answering to the effect if one literal serves a press that advanced the set and one that did nothing" % moved)
	assert_eq(moved, "secret_found",
		"a press that advanced the set must keep the discovery cue its three sibling props use")
	## ⛔ NOT SILENCE. The press DID register, and an absent cue cannot say so — the complaint this
	## fixes is that the player cannot tell, and silence is the other way of not telling them.
	assert_ne(still, "",
		"a press that advanced nothing must still make a sound: silence cannot distinguish 'already done' from 'the press did not register'")
	gut.p("  advanced -> %s · nothing advanced -> %s" % [moved, still])


## ⛔ BOTH CUES MUST EXIST, or the fix is a silent no-op the moment one is renamed.
func test_both_cues_are_real() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(parsed is Dictionary, "CONTROL: the sfx manifest must parse")
	if not (parsed is Dictionary):
		return
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {})
	assert_gt(sfx.size(), 500, "CONTROL: the manifest must be readable, found %d keys" % sfx.size())
	for cue in [QuestExaminePoint.cue_for(true), QuestExaminePoint.cue_for(false)]:
		assert_true(sfx.has(cue),
			"'%s' is not a manifest key, so this cue plays nothing — the fix would be inaudible rather than wrong" % cue)
	gut.p("  both cues resolve in a %d-key manifest" % sfx.size())


## ⛔ THE OTHER HALF, DRIVEN ON A REAL INSTANCE: marking a member twice advances the count once.
## This is the fact that makes the defect reachable, and it is the one a cue-only guard would miss.
func test_marking_a_member_twice_advances_nothing() -> void:
	var p := QuestExaminePoint.new()
	add_child_autofree(p)
	p.flag = FLAG
	p.group_size = 5
	p.member_index = 1
	assert_eq(p._group_done(), 0, "CONTROL: the probe flag must start unset, or this arm proves nothing")
	var before: int = p._group_done()
	var complete_first: bool = p._group_complete_after_marking()
	var after_first: int = p._group_done()
	var complete_again: bool = p._group_complete_after_marking()
	var after_second: int = p._group_done()
	assert_eq(after_first, before + 1, "the FIRST mark must advance the set: %d -> %d" % [before, after_first])
	assert_eq(after_second, after_first,
		"the SECOND mark advanced the set %d -> %d; if marking were not idempotent this defect could not occur and this arm is about the wrong thing" % [after_first, after_second])
	assert_false(complete_first, "CONTROL: 1 of 5 must not report the group complete")
	assert_false(complete_again, "CONTROL: a repeat mark must not report the group complete either")
	gut.p("  marks: %d -> %d -> %d (second advanced nothing, as the defect requires)" % [
		before, after_first, after_second])


## ⛔ AND THE SOURCE MUST NOT PLAY A DISCOVERY CUE UNCONDITIONALLY AGAIN. Read as the one expression
## that decides, not as a token census: the file NAMES `secret_found` in prose above the fix.
func test_examine_does_not_play_a_literal_discovery_cue() -> void:
	var raw := FileAccess.get_file_as_string("res://src/exploration/QuestExaminePoint.gd")
	assert_ne(raw, "", "CONTROL: the source must be readable")
	var code: String = str(GdSource.split(raw)["code"])
	assert_false(code.contains("##"), "CONTROL: the comment strip kept no doc comment")
	assert_true(code.contains("play_ui(cue_for("),
		"the cue must be chosen through `cue_for`, so one expression decides it")
	assert_false(code.contains('play_ui("secret_found")'),
		"_examine plays the discovery cue as a LITERAL again — that is the defect, and it fires before the work is done")
	gut.p("  the cue reaches play_ui only through cue_for")
