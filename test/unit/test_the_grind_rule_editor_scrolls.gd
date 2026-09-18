extends GutTest

## ⛔ THE AUTOGRIND RULE EDITOR NEVER SCROLLED. `_grid_container.position` was set once at build
## and never moved, `clip_contents` was false, and there is NO CAP on the number of rules. So past
## the ninth rule the rows were still DRAWN — over the footer and off the bottom of the screen —
## and the cursor walked off with them.
##
## 🔑 ITS AUTOBATTLE TWIN HAS SOLVED THIS SINCE IT GREW PAST NINE ROWS. Same hand-positioned,
## non-ScrollContainer grid; AutobattleGridEditor._update_scroll_offset shifts the container and the
## cursor follows for free because _update_cursor derives its position from that same container.
## This is that function ported, not a new idea.
##
## ⚠️ AND THE EDITOR IS LIVE ON THE PATH I JUST ADDED A PAD BINDING TO: AutogrindUI:2943 opens it
## mid-grind, which is what Start (and R) now reach.
##
## The invariant is POSITIONAL, not an offset value: the selected row must lie inside the drawn
## viewport. Asserting a particular _scroll_offset would pin a coincidental number and red on a
## correct resize.

const GridScript := preload("res://src/ui/autogrind/AutogrindGridEditor.gd")
const ROW_STRIDE := 44 + 24   # CELL_HEIGHT + ROW_SPACING

## This instantiates a live AutogrindGridEditor, which reaches AutogrindSystem's persisting path.
## ⛔ RESTORE THE PRIOR VALUE, not `false`: a gate that leaves the flag set closes its own leak and
## silences every later test in the same process — @cowir-autogrind measured that today.
var _saved_persist: bool = false


func before_all() -> void:
	_saved_persist = AutogrindSystem._test_disable_persistence
	AutogrindSystem._test_disable_persistence = true


func after_all() -> void:
	AutogrindSystem._test_disable_persistence = _saved_persist


func _editor(rule_count: int, row: int) -> Node:
	var ed: Node = GridScript.new()
	ed.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(ed)
	ed.size = Vector2(1280, 720)
	var rules: Array = ed.get("rules")
	rules.clear()
	for i in range(rule_count):
		rules.append({"conditions": [], "actions": []})
	ed.set("cursor_row", row)
	ed.set("cursor_col", 0)
	return ed


func _row_top(ed: Node) -> float:
	return int(ed.get("cursor_row")) * ROW_STRIDE - float(ed.get("_scroll_offset"))


func test_the_container_clips_its_overflow() -> void:
	var ed := _editor(3, 0)
	var c = ed.get("_grid_container")
	assert_ne(c, null, "CONTROL: the grid container must exist, or the arms below measure nothing")
	assert_true(c.clip_contents,
		"rows past the viewport are drawn over the rest of the screen unless the container clips")


func test_a_deep_row_is_scrolled_into_view() -> void:
	var ed := _editor(30, 25)
	ed._update_cursor()
	var view_h: float = ed.get("_grid_container").size.y
	assert_gt(view_h, 0.0, "CONTROL: the container must have a height to scroll within")
	var top := _row_top(ed)
	assert_true(top >= 0.0 and top + 44 <= view_h,
		"rule 25 sits at y=%.0f in a viewport of %.0f — the cursor is off screen and the player is "
		% [top, view_h] + "editing a row they cannot see")


func test_the_first_row_does_not_scroll() -> void:
	var ed := _editor(30, 0)
	ed._update_cursor()
	assert_eq(float(ed.get("_scroll_offset")), 0.0,
		"row 0 must sit at the anchor — a negative offset pushes the grid down off its own top")


## Walking back UP must bring the window with it, or the cursor leaves the other end.
func test_scrolling_back_up_follows_the_cursor() -> void:
	var ed := _editor(30, 25)
	ed._update_cursor()
	assert_gt(float(ed.get("_scroll_offset")), 0.0, "CONTROL: the window must have moved first")
	ed.set("cursor_row", 1)
	ed._update_cursor()
	var view_h: float = ed.get("_grid_container").size.y
	var top := _row_top(ed)
	assert_true(top >= 0.0 and top + 44 <= view_h,
		"after walking back to rule 1 the row sits at y=%.0f in a viewport of %.0f" % [top, view_h])


## ⛔ THE ARM THAT MAKES THE OTHERS REAL. Every arm above used to call _update_scroll_offset()
## DIRECTLY, so removing its call from _update_cursor left them all GREEN — they proved the
## function computes, never that anything invokes it. They drive _update_cursor now, and this pins
## the wiring itself so a future refactor cannot quietly unhook it.
func test_the_cursor_path_drives_the_scroll() -> void:
	var GdSource = load("res://test/unit/helpers/gd_source.gd")
	var code: String = GdSource.code_of("res://src/ui/autogrind/AutogrindGridEditor.gd")
	assert_ne(code, "", "CONTROL: source must survive the comment strip")
	var i: int = code.find("func _update_cursor")
	assert_gt(i, -1, "CONTROL: _update_cursor must exist")
	# substr(i) BEGINS with "func _update_cursor", so splitting on "func " returns an empty first
	# element — measured, and it failed this arm on a correctly wired tree. Skip the header first.
	var rest: String = code.substr(i + 5)
	var nxt: int = rest.find("\nfunc ")
	var body: String = rest.substr(0, nxt) if nxt > -1 else rest
	assert_true(body.contains("_update_scroll_offset()"),
		"_update_cursor no longer drives the scroll — the rows stop following the cursor and every "
		+ "positional arm in this file keeps passing, because they call the scroll themselves")


## ⚠️ NO ARM FOR THE `maxf(0.0, …)` FLOOR, AND THAT IS DELIBERATE: it is UNREACHABLE. Both branches
## assign a non-negative value — `cursor_y` is row * stride, and the elif only fires when
## `cursor_y + CELL_HEIGHT > view_h + offset`, so its result exceeds zero too. Deleting the floor
## leaves this suite green and I checked that before writing an arm around it. It is kept because
## the twin has it and a future branch could assign something else; it is defensive, not defended.


## ⛔ RATCHET: the two rule editors are twins and diverged silently for as long as one of them had
## no cap on rows. Neither may lose its scroll.
func test_both_rule_editors_scroll() -> void:
	var GdSource = load("res://test/unit/helpers/gd_source.gd")
	for path in ["res://src/ui/autogrind/AutogrindGridEditor.gd",
			"res://src/ui/autobattle/AutobattleGridEditor.gd"]:
		var code: String = GdSource.code_of(path)
		assert_ne(code, "", "CONTROL: %s must survive the comment strip" % path)
		assert_true(code.contains("func _update_scroll_offset"),
			"%s has no scroll owner — its cursor leaves the viewport once the rules outgrow it" % path)
		assert_true(code.contains("clip_contents = true"),
			"%s does not clip, so overflow rows draw over the rest of the screen" % path)
