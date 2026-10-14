extends GutTest

## ALL THREE OUTCOMES OF "TEST CONNECTION" WERE AUDIBLY IDENTICAL.
##
## `_on_test_pressed` played `menu_select` on the PRESS and nothing at all when the probe
## finished. So a probe that timed out after PROBE_TIMEOUT_SEC, one that answered with an error,
## and one that replied all sounded exactly the same -- on an ASYNC operation with a wall-clock
## ceiling, which is the shape a player has every reason to look away from while it runs.
## The status label did distinguish them (STATUS_FAIL_COLOR vs STATUS_OK_COLOR), so this is the
## audience half of the same defect: the eye was told and the ear was not.
##
## The cue is a VALUE (`probe_result_cue`) because the three outcomes are only reachable through a
## live HTTP probe -- a cue nobody can assert is a cue nobody checks. @cowir-battle's split.

const PanelScript := preload("res://src/ui/BYOKConfigPanel.gd")
const SELF_PATH := "res://test/unit/test_a_byok_test_result_is_audible.gd"
const PANEL_SRC := "res://src/ui/BYOKConfigPanel.gd"

# the three shapes _await_probe returns, named so a reader knows which is which
const TIMED_OUT: Array = []
const ANSWERED_FAIL: Array = [false, "", "connection refused"]
const ANSWERED_OK: Array = [true, "pong", ""]


func after_each() -> void:
	if SoundManager:
		SoundManager._sfx_cooldowns.clear()


func _stamped(key: String) -> bool:
	return SoundManager._sfx_cooldowns.has(key)


func _panel_source() -> String:
	var src: String = GdSource.code_of(PANEL_SRC)
	assert_false(src.is_empty(), "FIXTURE: BYOKConfigPanel source did not load, so the source arms judge nothing")
	return src


# -- the oracle's own control ---------------------------------------------------

## Two arms below read a cooldown stamp as "this cue played". If play_ui leaves no stamp in this
## harness they pass measuring nothing, so prove the instrument sees a cue first.
func test_the_cue_oracle_can_see_a_cue() -> void:
	SoundManager._sfx_cooldowns.clear()
	assert_false(_stamped("menu_error"), "FLOOR: the stamp table must start clean")
	SoundManager.play_ui("menu_error")
	assert_true(_stamped("menu_error"),
		"CONTROL: play_ui must leave an observable stamp, or the cue arms here measure nothing")


# -- the defect ----------------------------------------------------------------

## THE ARM. Before the fix every outcome produced the same sound (none), so the SET of distinct
## cues had exactly one member. A reader can check this without knowing which cue is which.
func test_the_three_outcomes_do_not_share_one_cue() -> void:
	var cues: Dictionary = {}
	for res in [TIMED_OUT, ANSWERED_FAIL, ANSWERED_OK]:
		cues[PanelScript.probe_result_cue(res)] = true
	assert_gt(cues.size(), 1,
		"all three probe outcomes map to the same cue %s — a failure is audibly a success" % str(cues.keys()))
	assert_eq(cues.size(), 2,
		"two outcomes are failures and one is not, so exactly 2 distinct cues: %s" % str(cues.keys()))


func test_a_probe_that_never_answered_is_audible() -> void:
	assert_eq(PanelScript.probe_result_cue(TIMED_OUT), "menu_error",
		"a probe that timed out must not sound like one that replied")


func test_a_probe_that_answered_with_a_failure_is_audible() -> void:
	assert_eq(PanelScript.probe_result_cue(ANSWERED_FAIL), "menu_error",
		"an answered-but-failed probe must not sound like a success")


func test_a_probe_that_replied_says_so() -> void:
	assert_eq(PanelScript.probe_result_cue(ANSWERED_OK), "menu_select",
		"a working backend must be audibly distinguishable from a broken one")


## Both cues must be keys the game ACTUALLY plays: play_ui returns silently for an unknown key, so
## a typo here would reinstate the defect while every arm above still passed. Derived from src/.
func test_both_cues_are_keys_the_game_plays() -> void:
	var seen: Dictionary = {}
	var dir := DirAccess.open("res://src")
	assert_not_null(dir, "FIXTURE: res://src did not open, so this arm derives nothing")
	_collect_ui_keys("res://src", seen, 0)
	assert_gt(seen.size(), 10, "FIXTURE: only %d play_ui keys found in src/ — the scan is broken" % seen.size())
	for res in [TIMED_OUT, ANSWERED_FAIL, ANSWERED_OK]:
		var cue: String = PanelScript.probe_result_cue(res)
		assert_true(seen.has(cue), "%s is not a key any src/ caller plays, so play_ui would return silently" % cue)


func _collect_ui_keys(path: String, seen: Dictionary, depth: int) -> void:
	if depth > 6:
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var full: String = path + "/" + name
		if dir.current_is_dir():
			if not name.begins_with("."):
				_collect_ui_keys(full, seen, depth + 1)
		elif name.ends_with(".gd"):
			var re := RegEx.new()
			re.compile('play_ui\\("([a-z_]+)"')
			for m in re.search_all(GdSource.code_of(full)):
				seen[m.get_string(1)] = true
		name = dir.get_next()
	dir.list_dir_end()


# -- the press must stay audible, and the call site must CONSUME the helper -----

## @cowir-sfx's ruling, kept: the press DID register and silence cannot say so. A fix that moved the
## cue from the press to the result would trade one silence for another.
func test_the_press_itself_is_still_audible() -> void:
	var src: String = _panel_source()
	var i: int = src.find("func _on_test_pressed(")
	assert_gt(i, 0, "FIXTURE: _on_test_pressed not found, so this arm judges nothing")
	var body: String = src.substr(i, src.find("\nfunc ", i + 10) - i)
	assert_true(body.contains("play_ui("), "the Test press must stay audible — a silent button reads as a dropped input")


## A helper nothing calls is not a fix. Spelling only, deliberately: the VALUE arms above carry the
## behaviour, and this names the one thing they cannot see — whether the panel uses the answer.
func test_the_result_path_consumes_the_helper() -> void:
	var src: String = _panel_source()
	assert_true(src.contains("play_ui(probe_result_cue(res))"),
		"the result path must play the cue the helper derives, or probe_result_cue is dead code")


# NO DERIVED FLOOR HERE, DELIBERATELY. Every reach of this file is ONE static on a PRELOADED
# script, which resolves at PARSE time: a rename gives EC=3 with nothing run, which run_tests.sh
# names outright and which no reader can mistake for a pass. A floor would be dead code, and
# `has_method` on a GDScript resource answers about GDScript's own methods rather than the ones
# this script declares -- so it would also be the wrong instrument. The value arms above are the
# cover; the parse is the floor.
