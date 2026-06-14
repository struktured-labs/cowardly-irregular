extends GutTest

## Regression: plain CutsceneDialogue (NPC chat, no CutsceneDirector) must
## offer a ui_cancel (B / Esc) fast-exit that finishes the dialogue queue.
##
## Pre-fix (2026-06-04): CutsceneDialogue._input handled only ui_accept and
## left-click. CutsceneDirector renders a hold-B-to-skip pill for story
## cutscenes, but plain NPC dialogue (e.g. Elder Theron) had no gamepad /
## keyboard fast-exit — mouse-only players could click past, controller
## users were stuck. User reported: "can't skip Elder Theron dialogue."
##
## Fix: CutsceneDialogue._input now handles ui_cancel by calling
## _finish_dialogue() — finishes the queue immediately and closes the panel.
## Echo-guarded so holding B doesn't double-fire.
##
## The LLM "thinking" guard (Wave C) must still win: while the thinking
## indicator is visible, ui_cancel is swallowed so the player can't skip the
## queue out from under an in-flight LLM response. This test pins both
## branches so neither regresses the other.
##
## Source-pin test (cheap, fast). Doesn't drive the full autoload+UI input
## graph; instead reads the source and asserts both branches are in place,
## matching the test_cutscene_completion_story_flag_mirror_regression style.
##
## Ported from commit 03983fe (CutsceneDialogue part).


const CUTSCENE_DIALOGUE_PATH := "res://src/cutscene/CutsceneDialogue.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_input_has_ui_cancel_fast_exit() -> void:
	# Pin: the fast-exit branch finishes the dialogue queue on ui_cancel and
	# is echo-guarded so holding B doesn't double-fire.
	var text = _read(CUTSCENE_DIALOGUE_PATH)
	assert_true(text.find("event.is_action_pressed(\"ui_cancel\") and not event.is_echo()") > -1,
		"_input must handle ui_cancel (B / Esc), echo-guarded, for fast-exit")
	assert_true(text.find("_finish_dialogue()") > -1,
		"the ui_cancel branch must call _finish_dialogue() to skip the queue")


func test_thinking_guard_swallows_ui_cancel() -> void:
	# Pin: while the LLM "thinking" indicator is visible, ui_cancel must be
	# swallowed (no fast-exit) so the player can't skip the queue out from
	# under an in-flight LLM response. Locks the Wave C guard interaction.
	var text = _read(CUTSCENE_DIALOGUE_PATH)
	var guard_idx = text.find("if _thinking_label != null and _thinking_label.visible:")
	assert_true(guard_idx > -1,
		"the Wave C thinking guard block must still exist")
	# The first ui_cancel branch (the swallow) lives inside the guard; the
	# fast-exit branch lives below. There must be at least two ui_cancel
	# branches: one swallowed under the guard, one that fast-exits.
	var first = text.find("event.is_action_pressed(\"ui_cancel\")")
	assert_true(first > guard_idx,
		"the first ui_cancel branch must be inside the thinking guard (swallow)")
	var second = text.find("event.is_action_pressed(\"ui_cancel\")", first + 1)
	assert_true(second > first,
		"there must be a second ui_cancel branch below the guard (fast-exit)")
