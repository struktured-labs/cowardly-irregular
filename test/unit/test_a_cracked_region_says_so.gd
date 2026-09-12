extends GutTest

## A region cracks every 20 consecutive wins and applies min(level * 0.15, 0.75) to every reward
## after it — up to -75%, live, through on_battle_victory's `reward_scale = yield * (1 - penalty)`.
##
## With Auto-Advance ON the player gets GameLoop's full-screen "REGION CRACKED / Warping to World N"
## overlay. With it OFF — the W toggle in the console, and one shipped preset — AutogrindController
## printed a line to stdout and returned. **The player stayed in the region taking the penalty with
## no announcement at all**, while nine authored lines about it (carrying BBCode, so written for a
## rich-text surface) went to the terminal.
##
## Same shape as system_collapse in .338: the event was real, the consequence was real, and the only
## listener was somewhere the player cannot see.

const CTRL := "res://src/autogrind/AutogrindController.gd"
const GL := "res://src/GameLoop.gd"
const SYS := "res://src/autogrind/AutogrindSystem.gd"


## Body EXCLUDING the signature line — a parameter name in the signature must not satisfy a
## "does the body use it" assert. That trap cost this lane a green mutation earlier today.
func _fn_body(src: String, name_: String) -> String:
	var at := src.find("func %s(" % name_)
	if at < 0:
		return ""
	var after_sig := src.find("\n", at)
	if after_sig < 0:
		return ""
	var end := src.find("\nfunc ", after_sig)
	return src.substr(after_sig, (end - after_sig) if end > after_sig else 700)


## PREMISE: the penalty must really apply, or announcing it guards nothing.
func test_the_crack_penalty_is_really_applied() -> void:
	var sys := _code_only(FileAccess.get_file_as_string(SYS), "func on_battle_victory(")
	assert_gt(sys.length(), 1000, "CONTROL: the system source must have been read")
	assert_true(sys.contains("func _get_region_crack_penalty"),
		"PRECONDITION: the penalty function must still exist")
	var win := _fn_body(sys, "on_battle_victory")
	assert_true(win.contains("_get_region_crack_penalty()"),
		("on_battle_victory no longer applies the crack penalty. If cracks stopped costing rewards, " +
		"this file should be re-justified rather than kept — the announcement exists because the " +
		"cost is real"))


## The staying branch must announce. The defect was a print and a return.
func test_staying_in_a_cracked_region_emits() -> void:
	var ctrl := _code_only(FileAccess.get_file_as_string(CTRL), "func _on_region_cracked(")
	assert_true(ctrl.contains("signal region_cracked_in_place("),
		"the controller must declare a signal for a crack it is staying in")
	var body := _fn_body(ctrl, "_on_region_cracked")
	assert_gt(body.length(), 60, "CONTROL: the crack handler body must have been found")
	var at := body.find("if not _auto_advance_regions:")
	assert_gt(at, -1, "PRECONDITION: the staying branch must still exist")
	## ⛔ Comments stripped above, and the window widened: the FIRST version read the raw source with
	## a 400-char window, and the four explanatory comment lines I had just added to that branch
	## pushed the emit past the end. The arm redded on code that was correct. Prose must not consume
	## the window a code assertion measures.
	var branch := body.substr(at, 600)
	assert_true(branch.contains("region_cracked_in_place.emit("),
		("the staying branch still only prints. The player keeps grinding in a region whose rewards " +
		"are cut 15% per crack level and nothing tells them — emit here, as the advance branch " +
		"reaches GameLoop's warp overlay"))


## GameLoop must connect it and reach the surfaces the player watches.
func test_the_crack_reaches_the_live_surface() -> void:
	var gl := _code_only(FileAccess.get_file_as_string(GL), "func _on_grind_complete(")
	assert_true(gl.contains("region_cracked_in_place.connect("),
		"GameLoop does not listen — the signal would be emitted to nobody, as system_collapse was")
	var body := _fn_body(gl, "_on_autogrind_region_cracked_in_place")
	assert_gt(body.length(), 60, "GameLoop must own a handler for it")
	assert_true(body.contains("_show_autogrind_toast("),
		"it must toast: the console that would log it is hidden for the whole grind")
	assert_true(body.contains("_autogrind_battle_summaries.append("),
		"and write the battle summary the player reads back")


## The PENALTY must survive into the message — a handler that drops it still toasts.
func test_the_announcement_carries_the_penalty() -> void:
	var body := _fn_body(_code_only(FileAccess.get_file_as_string(GL), "func _on_grind_complete("), "_on_autogrind_region_cracked_in_place")
	assert_true(body.contains("reward_penalty"),
		("the handler ignores its reward_penalty argument. 'REGION CRACKED' without the number is " +
		"the half the player already infers; the percentage is the half they cannot"))
	assert_true(body.contains("crack_level"),
		"and the level, because the penalty compounds per level up to -75%")


## The auto-advance path must keep its own overlay — this change must not have replaced it.
func test_the_advance_path_still_warps() -> void:
	var gl := _code_only(FileAccess.get_file_as_string(GL), "func _on_grind_complete(")
	assert_true(gl.contains("REGION CRACKED"),
		"the full-screen warp overlay must survive: it is the auto-advance path's announcement")
	assert_true(gl.contains("func _show_region_warp_transition"),
		"and its builder must still exist — this change adds a second surface, it replaces nothing")


## BOTH halves, because they need different mechanisms (@cowir-overworld):
##   `#` comments   line-addressable, stateless — drop the line
##   `"""` regions  NOT line-addressable; a docstring carries no `#`, so the line pass cannot see
##                  it. Parity split on the delimiter, keep even chunks — also stateless, so there
##                  is no toggle to desync the way a state machine can (@cowir-adhoc's precedence
##                  bug swallowed five files that way).
## `must_survive` is REQUIRED, not conventional, so no call site can omit the positive control
## (@cowir-controller's shape): over-stripping and correct stripping are otherwise the same green.
func _code_only(src: String, must_survive: String) -> String:
	var out: PackedStringArray = []
	for line in src.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	var no_hash := "\n".join(out)
	var parts := no_hash.split("\"\"\"")
	var kept: PackedStringArray = []
	for i in parts.size():
		if i % 2 == 0:
			kept.append(parts[i])
	var stripped := "".join(kept)
	assert_true(stripped.contains(must_survive),
		("CONTROL: the stripper removed a known CODE site (%s). An over-aggressive strip and a " +
		"correct one are the same green, so every assert below would be measuring nothing") % must_survive)
	return stripped

