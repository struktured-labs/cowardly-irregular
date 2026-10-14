extends GutTest

## A FORCE-APPLY THAT MOVED NOTHING WAS ANNOUNCED AS A SUCCESS.
##
## `force_apply` clamps each delta to the authored band and then returns APPLY_APPLIED whatever
## the clamp did, so a dial already at its ceiling records before == after and still reports
## "applied". RebalanceReviewPanel read only that status: it played `menu_select` and painted the
## toast SUCCESS_COLOR, while the toast's own TEXT -- derived from the same before/after rows --
## read "Auto-rebalance: no change - exp_multiplier already at its safe limit."
##
## Found in struktured's own saves: of 50 surviving `applied` rows in save_98, 46 read `1.15 ->
## 1.15`. The contradicting case is not the edge case, it is the MAJORITY case, on the screen
## where a player consents to the AI editing game constants.
##
## The fix is ONE derivation (`applied_moved_count`) that both the wording and the colour read,
## so they cannot disagree -- CLAUDE.md's rule for two sources feeding one surface.

const RD := preload("res://src/llm/RebalanceDaemon.gd")
const PanelScript := preload("res://src/ui/RebalanceReviewPanel.gd")
const SELF_PATH := "res://test/unit/test_the_apply_toast_matches_what_moved.gd"
const CONST_NAME := "exp_multiplier"

var _daemon
var _orig_daemon = null
var _orig_constants: Dictionary = {}
var _gs: Node = null
var _snapshot_ok: bool = false


func before_each() -> void:
	_snapshot_ok = false
	_gs = get_tree().root.get_node_or_null("GameState")
	assert_not_null(_gs, "FIXTURE: GameState is absent, so the panel can never resolve a daemon")
	_daemon = RD.new()
	if _gs != null:
		if "rebalance_daemon" in _gs:
			_orig_daemon = _gs.rebalance_daemon
			_gs.rebalance_daemon = _daemon
		if "game_constants" in _gs:
			_orig_constants = (_gs.game_constants as Dictionary).duplicate(true)
	SoundManager._sfx_cooldowns.clear()
	Toast._active_layers.clear()
	# LAST line: a teardown keyed to this flag cannot restore a snapshot that was never taken.
	_snapshot_ok = true


func after_each() -> void:
	if _snapshot_ok and _gs != null:
		if "rebalance_daemon" in _gs:
			_gs.rebalance_daemon = _orig_daemon
		if "game_constants" in _gs:
			_gs.game_constants = _orig_constants.duplicate(true)
	Toast._active_layers.clear()
	SoundManager._sfx_cooldowns.clear()


func _stamped(key: String) -> bool:
	return SoundManager._sfx_cooldowns.has(key)


## The band bites only at the ceiling, and the ceiling is baseline * CUMULATIVE_DELTA_MAX where the
## BASELINE is read from GameState.DEFAULT_GAME_CONSTANTS -- not from game_constants, and not 1.0,
## which it merely happens to be. Derived from the clamp's own two sources so a rebalance of either
## cannot quietly turn this fixture into the "it moved" case while still reading as a real failure.
func _ceiling() -> float:
	assert_true("DEFAULT_GAME_CONSTANTS" in _gs,
		"FIXTURE: without the authored defaults the band never bites and every arm here is vacuous")
	var defaults: Dictionary = _gs.DEFAULT_GAME_CONSTANTS
	assert_true(defaults.has(CONST_NAME),
		"FIXTURE: %s has no authored baseline, so _clamp_to_authored_band returns the current value and nothing can ever clamp" % CONST_NAME)
	return float(defaults.get(CONST_NAME, 1.0)) * RD.CUMULATIVE_DELTA_MAX


func _queue(start: float, multiplier: float) -> void:
	_gs.game_constants[CONST_NAME] = start
	_daemon.pending.append({
		"status": "needs_review",
		"verdict": "nudge_easier",
		"confidence": 0.9,
		"trigger": "party_wipe",
		"reason": "the party keeps wiping in the cave",
		"deltas": [{"constant": CONST_NAME, "multiplier": multiplier, "reason": "grind"}],
	})


func _settle() -> void:
	for _i in 3:
		await get_tree().process_frame


## Drives the REAL panel row the player presses, not force_apply directly: the colour and the cue
## are decided in _apply_current, so that is what has to be observed.
func _press_apply(start: float, multiplier: float) -> Dictionary:
	_queue(start, multiplier)
	var p = PanelScript.new()
	add_child_autofree(p)
	await _settle()
	SoundManager._sfx_cooldowns.clear()
	Toast._active_layers.clear()
	p._apply_current()
	await _settle()
	var colour: Variant = null
	if Toast._active_layers.size() > 0:
		var layer: Node = Toast._active_layers[-1]
		var labels: Array = []
		if is_instance_valid(layer):
			for ch in layer.get_children():
				if ch is Label:
					labels.append(ch)
		if labels.size() > 0:
			colour = (labels[-1] as Label).get_theme_color("font_color")
	# FIXTURE, not a subject assert: an un-populated row list makes _apply_current return at its
	# guard, and every arm below would then compare against an entry no press produced.
	assert_eq(_daemon.applied.size(), 1,
		"FIXTURE: the Apply press must have moved exactly one proposal into applied")
	assert_eq(_daemon.pending.size(), 0, "FIXTURE: and must have taken it out of pending")
	var entry: Dictionary = _daemon.applied[-1] if _daemon.applied.size() > 0 else {}
	return {
		"colour": colour,
		"line": str(_daemon.summarize_applied(entry)),
		"moved": int(_daemon.applied_moved_count(entry)),
		"after": float(_gs.game_constants.get(CONST_NAME, 0.0)),
	}


# -- the oracles' own controls -------------------------------------------------

## Every arm below reads a cooldown stamp as "this cue played". If play_ui leaves no stamp in this
## harness they all pass measuring nothing, so prove the instrument sees a cue first.
func test_the_cue_oracle_can_see_a_cue() -> void:
	SoundManager._sfx_cooldowns.clear()
	assert_false(_stamped("menu_select"), "FLOOR: the stamp table must start clean")
	SoundManager.play_ui("menu_select")
	assert_true(_stamped("menu_select"),
		"CONTROL: play_ui must leave an observable stamp, or every cue arm here measures nothing")


## Same for the colour: a toast whose font_color cannot be read back makes every colour arm below
## a comparison against null that would have to be written as a pass.
func test_the_colour_oracle_can_see_a_toast_colour() -> void:
	var host := Control.new()
	add_child_autofree(host)
	Toast._active_layers.clear()
	Toast.show(host, "control", Toast.WARNING_COLOR)
	await _settle()
	assert_eq(Toast._active_layers.size(), 1, "CONTROL: Toast.show must register exactly one layer")
	var layer: Node = Toast._active_layers[-1]
	var labels: Array = []
	for ch in layer.get_children():
		if ch is Label:
			labels.append(ch)
	assert_gt(labels.size(), 0, "CONTROL: the toast layer must carry a Label to read a colour from")
	assert_eq((labels[-1] as Label).get_theme_color("font_color"), Toast.WARNING_COLOR,
		"CONTROL: the colour this file reads back must be the colour Toast was given")


# -- the defect ----------------------------------------------------------------

func test_a_clamped_apply_is_not_announced_as_a_success() -> void:
	var ceiling: float = _ceiling()
	var got: Dictionary = await _press_apply(ceiling, 1.10)
	assert_eq(float(got["after"]), ceiling,
		"CONTROL: the band must actually have refused the change, or this is not the clamped case")
	assert_eq(int(got["moved"]), 0, "CONTROL: and nothing may have moved")
	assert_true(str(got["line"]).contains("no change"),
		"CONTROL: the wording must already say nothing moved: %s" % str(got["line"]))
	assert_ne(got["colour"], Toast.SUCCESS_COLOR,
		("the toast says %s and paints it SUCCESS green" % str(got["line"])))
	assert_eq(got["colour"], Toast.DEFAULT_COLOR,
		"a no-op apply is informational, not a failure: %s" % str(got["colour"]))
	assert_false(_stamped("menu_select"),
		"and the success chime must not play for an apply that moved nothing")
	assert_true(_stamped("menu_move"),
		"the press must still be audible -- a silent button reads as a dropped input")


func test_a_real_move_is_still_announced_as_a_success() -> void:
	var got: Dictionary = await _press_apply(1.0, 1.05)
	assert_gt(float(got["after"]), 1.0, "CONTROL: this fixture must actually have moved the dial")
	assert_eq(int(got["moved"]), 1, "CONTROL: and must record exactly one mover")
	assert_eq(got["colour"], Toast.SUCCESS_COLOR,
		"a real change must still read as a success: %s" % str(got["line"]))
	assert_true(_stamped("menu_select"), "and must still play the success chime")
	assert_false(_stamped("menu_move"),
		"CONTROL: the neutral cue must NOT also fire, or the arm above proves nothing")


## The invariant the shared derivation buys. Not an equality between two copies of the rule -- one
## computation, read twice -- so this reds if anyone gives the colour its own idea of "changed".
func test_the_colour_never_contradicts_the_toast_text() -> void:
	var ceiling: float = _ceiling()
	var cases: Array = [
		[ceiling, 1.10],
		[ceiling, 1.00],
		[1.10, 1.10],
		[1.00, 1.05],
	]
	var saw_both: Dictionary = {}
	for case in cases:
		_daemon = RD.new()
		_gs.rebalance_daemon = _daemon
		SoundManager._sfx_cooldowns.clear()
		var got: Dictionary = await _press_apply(float(case[0]), float(case[1]))
		var says_no_change: bool = str(got["line"]).contains("no change")
		var moved: int = int(got["moved"])
		assert_eq(says_no_change, moved == 0,
			"text and derivation disagree for %s: moved=%d line=%s" % [str(case), moved, str(got["line"])])
		assert_eq(got["colour"] == Toast.SUCCESS_COLOR, moved > 0,
			"colour and derivation disagree for %s: moved=%d colour=%s" % [str(case), moved, str(got["colour"])])
		saw_both[moved > 0] = true
	assert_eq(saw_both.size(), 2,
		"CONTROL: the ladder must contain BOTH a mover and a no-op, or this arm checks one direction")


func test_applied_moved_count_counts_only_what_actually_moved() -> void:
	assert_eq(int(_daemon.applied_moved_count({})), 0, "an empty entry moved nothing")
	assert_eq(int(_daemon.applied_moved_count({"applied_changes": []})), 0, "no rows moved nothing")
	assert_eq(int(_daemon.applied_moved_count({"applied_changes": [
		{"constant": "a", "before": 1.15, "after": 1.15},
	]})), 0, "a row whose before equals its after did not move")
	assert_eq(int(_daemon.applied_moved_count({"applied_changes": [
		{"constant": "a", "before": 0.0, "after": 0.0},
	]})), 0, "a zero baseline has no percentage to report and must not count as a move")
	assert_eq(int(_daemon.applied_moved_count({"applied_changes": [
		{"constant": "a", "before": 1.0, "after": 1.05},
	]})), 1, "a row that moved counts once")
	assert_eq(int(_daemon.applied_moved_count({"applied_changes": [
		{"constant": "a", "before": 1.15, "after": 1.15},
		{"constant": "b", "before": 1.0, "after": 1.10},
	]})), 1, "a mixed entry counts only the mover")


## DERIVED from this file's own source rather than hand-listed: a snapshot can be stale, and can be
## wrong on the day it is written. Reached on an INSTANCE, so a rename aborts an arm into a vacuous
## pass; this names the symbol instead.
func test_the_daemon_still_has_what_this_file_drives() -> void:
	var src: String = FileAccess.get_file_as_string(SELF_PATH)
	assert_false(src.is_empty(), "FIXTURE: this file could not read its own source")
	var code: String = ""
	for raw in src.split("\n"):
		var line: String = str(raw)
		var hash_at: int = line.find("#")
		if hash_at >= 0:
			line = line.substr(0, hash_at)
		code += line + "\n"
	var strip := RegEx.new()
	strip.compile("\"[^\"]*\"")
	code = strip.sub(code, "\"\"", true)
	var re := RegEx.new()
	re.compile("_daemon\\.([a-zA-Z_][a-zA-Z0-9_]*)\\s*\\(")
	var reached: Array[String] = []
	for m in re.search_all(code):
		var name: String = m.get_string(1)
		if not reached.has(name):
			reached.append(name)
	assert_true(reached.has("applied_moved_count"),
		"FIXTURE: the derivation under test must be among the reached names: %s" % str(reached))
	assert_gt(reached.size(), 1, "FIXTURE: the derivation found no call sites, so it checks nothing")
	for name in reached:
		assert_true(_daemon.has_method(name),
			"RebalanceDaemon has no method %s, which this file calls" % name)


func test_the_panel_still_has_the_press_this_file_drives() -> void:
	var p = PanelScript.new()
	add_child_autofree(p)
	assert_true(p.has_method("_apply_current"),
		"RebalanceReviewPanel._apply_current is what the Apply row calls; this file drives it directly")
