extends GutTest

## cowir-sfx msg 2160 (2026-07-04) — three underclaimed one-line hooks
## wired in engine files without new SFX authoring. Pins each so the
## wiring can't silently rot back:
## 1. QuestTracker branches on the state arg — 'complete' → quest_complete jingle,
##    everything else keeps soft_chime (so objective_advanced doesn't sound identical to done)
## 2. QuestLog nav/cancel play menu_move/menu_cancel like every other menu
## 3. FastTravelMenu warp confirm fires portal_enter alongside menu_select
##
## 2026-09-16: all three read RAW source, so any assert here was satisfiable by a COMMENT naming
## the cue — this lane's own .325 defect, in the lane's own file. Now on GdSource.code_of.
## The page branch was also pinned by a 420-char window and an exact `count == 3`: the window can
## spill into whatever follows, and the count was right only while the branch total happened to
## match it (it moved 2→3 the same day). Each branch is now bounded by the NEXT branch.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")


## A function's body: from its signature to the next top-level `func`.
func _func_body(code: String, signature: String) -> String:
	var start: int = code.find(signature)
	if start < 0:
		return ""
	var nxt: int = code.find("\nfunc ", start + 1)
	return code.substr(start, nxt - start) if nxt > start else code.substr(start)


## The slice between two markers — a branch bounded by the branch that follows it.
func _between(body: String, from_marker: String, to_marker: String) -> String:
	var a: int = body.find(from_marker)
	if a < 0:
		return ""
	var b: int = body.find(to_marker, a + 1) if to_marker != "" else -1
	return body.substr(a, b - a) if b > a else body.substr(a)


func test_quest_tracker_branches_completion_from_progress() -> void:
	var src: String = GdSource.code_of("res://src/exploration/QuestTracker.gd")
	assert_ne(src, "", "CONTROL: QuestTracker code must survive the comment strip")
	assert_true(src.contains("SoundManager.play_ui(\"quest_complete\" if str(_b) == \"complete\" else \"soft_chime\")"),
		"QuestTracker must branch on str(_b) == 'complete' — bare _b == \"complete\" throws int-vs-string at runtime because objective_advanced sends an int index")


func test_quest_log_cancel_is_chirped() -> void:
	var src: String = GdSource.code_of("res://src/ui/QuestLog.gd")
	assert_ne(src, "", "CONTROL: QuestLog code must survive the comment strip")
	assert_true(src.contains("SoundManager.play_ui(\"menu_cancel\")"),
		"QuestLog close must play menu_cancel like every other overworld menu")


func test_every_moving_scroll_branch_chirps() -> void:
	# Each branch is bounded by the one after it, so a chirp cannot be borrowed from a neighbour
	# and a fourth branch cannot pass by inheriting a count.
	var src: String = GdSource.code_of("res://src/ui/QuestLog.gd")
	var body: String = _func_body(src, "func _input(event: InputEvent) -> void:")
	assert_ne(body, "", "CONTROL: QuestLog._input must be found, or every arm below is vacuous")
	# Source order: page jump, then ui_up, then ui_down.
	# The cursor branches read MenuNav.step's result since 2026-09-17; the page jump still reads the
	# helper directly. Delimiters follow source order, so a chirp cannot be borrowed from a neighbour.
	var branches := [
		["MenuPaging.page_delta(event)", "nav == \"ui_up\"", "the page jump"],
		["nav == \"ui_up\"", "nav == \"ui_down\"", "ui_up"],
		["nav == \"ui_down\"", "", "ui_down"],
	]
	for b in branches:
		var seg: String = _between(body, b[0], b[1])
		assert_ne(seg, "", "CONTROL: the %s branch is gone — this arm no longer describes _input" % b[2])
		assert_true(seg.contains("SoundManager.play_ui(\"menu_move\")"),
			"%s moves the scroll and does not chirp — a silent move reads as a dead button" % b[2])


func test_fast_travel_menu_portal_whoosh_wired() -> void:
	var src: String = GdSource.code_of("res://src/ui/FastTravelMenu.gd")
	var body: String = _func_body(src, "func _pick() -> void:")
	assert_ne(body, "", "CONTROL: FastTravelMenu._pick must be found")
	var cue: int = body.find("SoundManager.play_ui(\"portal_enter\")")
	var emit: int = body.find("teleport_requested.emit")
	assert_gt(cue, -1, "crystal-to-crystal warp must fire the portal_enter dimensional whoosh")
	assert_gt(emit, -1, "CONTROL: the teleport signal must still be emitted from _pick")
	assert_lt(cue, emit, "portal_enter fires AFTER the teleport signal — the scene is already leaving")
