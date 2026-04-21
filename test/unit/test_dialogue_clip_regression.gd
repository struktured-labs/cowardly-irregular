extends GutTest

## Regression tests for UI fixes:
##   - ec2295a: dialogue text bleeding out of box (clip_contents + BOX_HEIGHT bump)
##   - d3f28bf: QuestLog closes on A/B/X via _input (not _unhandled_input)
##
## These are source-level tests — we inspect the .gd files directly instead of
## preloading them, because preloading pulls in autoload-dependent scripts
## that only compile when the full project is loaded (not during standalone
## --check-only validation).

const CUTSCENE_DIALOGUE_PATH := "res://src/cutscene/CutsceneDialogue.gd"
const QUEST_LOG_PATH := "res://src/ui/QuestLog.gd"


func _read_source(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text = file.get_as_text()
	file.close()
	return text


## ---- Bug: long NPC dialogue text overflowed the box ----

func test_cutscene_dialogue_box_height_is_at_least_150() -> void:
	# BOX_HEIGHT was 120 (≈4 lines) pre-fix, bumped to 150 to fit ~6 lines.
	var src = _read_source(CUTSCENE_DIALOGUE_PATH)
	assert_false(src.is_empty(), "CutsceneDialogue.gd must exist")
	# Match the constant line — regex-free string scan.
	var found_150_or_higher = false
	for candidate in ["BOX_HEIGHT = 150", "BOX_HEIGHT = 160", "BOX_HEIGHT = 170", "BOX_HEIGHT = 180"]:
		if src.contains(candidate):
			found_150_or_higher = true
			break
	assert_true(found_150_or_higher,
		"CutsceneDialogue.BOX_HEIGHT must stay ≥150 to fit long dialogue (fix for ec2295a)")


func test_cutscene_dialogue_sets_clip_contents() -> void:
	# clip_contents on the dialogue box is the actual fix — without it, text
	# can render outside the box boundary even with height set correctly.
	var src = _read_source(CUTSCENE_DIALOGUE_PATH)
	assert_true(src.contains("_dialogue_box.clip_contents = true"),
		"Dialogue box must set clip_contents = true (fix for ec2295a)")
	assert_true(src.contains("_text_label.clip_contents = true"),
		"Text label must set clip_contents = true (fix for ec2295a)")


## ---- Bug: Quest log didn't close on A or B (used _unhandled_input) ----

func test_quest_log_handler_is_input_not_unhandled() -> void:
	# _unhandled_input misses events already handled by focused children or
	# the global ui system. _input is what actually fires for UI overlays.
	var src = _read_source(QUEST_LOG_PATH)
	assert_false(src.is_empty(), "QuestLog.gd must exist")
	assert_true(src.contains("func _input(event: InputEvent)"),
		"QuestLog must define _input (not _unhandled_input) for close-on-A/B to work")
	assert_false(src.contains("func _unhandled_input(event: InputEvent)"),
		"QuestLog should NOT use _unhandled_input (events may be consumed elsewhere)")


func test_quest_log_input_accepts_cancel_back_and_accept() -> void:
	# The close path must cover all three actions.
	var src = _read_source(QUEST_LOG_PATH)
	assert_true(src.contains("ui_cancel") and src.contains("ui_back") and src.contains("ui_accept"),
		"QuestLog._input must close on ui_cancel OR ui_back OR ui_accept (fix for d3f28bf)")
