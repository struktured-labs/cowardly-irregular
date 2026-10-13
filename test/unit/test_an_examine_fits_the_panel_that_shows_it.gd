extends GutTest

## ⛔ AN EXAMINE THAT OVERFLOWS ITS PANEL IS PROSE THE PLAYER CANNOT REACH, SILENTLY. The readable's
## body box is `PANEL_W - 28` x `PANEL_H - 74` with word-smart autowrap, and the examine loader hands
## the provider ONE entry — so `_entries.size() == 1`, `_render_page` shows no page arrows, and
## anything past the box height is simply not drawn and not reachable.
##
## 🔑 NOBODY CAN SELF-CHECK THIS BY LENGTH, WHICH IS THE WHOLE REASON IT NEEDS A GUARD. Measured over
## the 45 authored rows: `scriptura_guild_edicts` is 255 characters and renders SHORTER than
## `node_prime_terminal` at 190, because word lengths and explicit breaks dominate. I started to
## publish a "~231 character ceiling" derived from the tallest row and threw it away — the
## extrapolation is unsound on its own data. So an author has no rule of thumb, and a new entry can
## overflow without looking longer than the ones that fit.
##
## ✅ HEADROOM TODAY IS ~30 px, two lines. Tallest rendered 136 px against a 166 px box. That is why
## the arm reports the OVERFLOW IN PIXELS and the row id: @cowir-main asked for a failure an author
## can act on without running a render, and "trim about 14 px from node_prime_terminal" is that.
##
## ⛔ AND THE GEOMETRY IS READ, NOT COPIED — caught by re-reading this file before running it. The
## first draft configured its label with a literal `font_size 12` and `PANEL_W - 28`, copied out of
## `_build_panel`. That is a second copy of the subject: change the panel's font or insets and this
## arm keeps measuring the old box and passes prose that no longer fits. `ReadableProp.body_box()`
## and `ReadableProp.BODY_FONT` now name both once, and this file reads them.
##
## ⚠️ THE TOLERANCE QUESTION, ASKED BEFORE WRITING IT (@cowir-sfx's lens, @cowir-controller's
## sharper form — "does this window have a neighbour inside it?"): none, by construction. This
## compares a rendered height against a BOX BOUNDARY, not one sibling against another, so the
## neighbourhood is empty and no window is needed. The assert is `need <= box`, with no slack.

const PACK := "res://data/examine_texts.json"

## The real consumer's geometry, read from the class rather than copied — a second copy of 420/240
## here would go stale the moment the panel is resized and the guard would pass on a box that no
## longer exists.
var _box: Vector2 = Vector2.ZERO
var _host: Control = null


func before_all() -> void:
	_box = ReadableProp.body_box()


func _rows() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PACK))
	assert_true(parsed is Dictionary, "CONTROL: %s must parse" % PACK)
	if not (parsed is Dictionary):
		return {}
	return (parsed as Dictionary).get("examines", {})


## A label configured exactly as `_build_panel` configures the body label.
func _rendered_height(txt: String) -> float:
	var lab := Label.new()
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.text = txt
	lab.add_theme_font_size_override("font_size", ReadableProp.BODY_FONT)
	lab.size = _box
	_host.add_child(lab)
	await get_tree().process_frame
	await get_tree().process_frame
	var h: float = lab.get_minimum_size().y
	lab.queue_free()
	await get_tree().process_frame
	return h


func test_the_geometry_came_from_the_class() -> void:
	assert_gt(_box.x, 300.0, "CONTROL: body width %.0f looks wrong — read from ReadableProp" % _box.x)
	assert_gt(_box.y, 100.0, "CONTROL: body height %.0f looks wrong" % _box.y)


func test_every_authored_examine_fits_its_panel() -> void:
	_host = Control.new()
	_host.size = Vector2(640, 480)
	add_child_autofree(_host)
	var rows := _rows()
	assert_gt(rows.size(), 40, "CONTROL: only %d authored rows found" % rows.size())
	var over: Array = []
	var tallest := 0.0
	var tallest_id := ""
	var measured := 0
	for k in rows.keys():
		var e = rows[k]
		if not (e is Dictionary):
			continue
		var txt: String = str((e as Dictionary).get("text", ""))
		if txt == "":
			continue
		measured += 1
		var need: float = await _rendered_height(txt)
		if need > tallest:
			tallest = need
			tallest_id = str(k)
		if need > _box.y:
			over.append("'%s' needs %.0f px of %.0f — %.0f px of prose is drawn nowhere and the reader has no page arrow to reach it; trim about %.0f px" % [
				str(k), need, _box.y, need - _box.y, need - _box.y])
	assert_gt(measured, 40, "CONTROL: only %d rows had text to measure" % measured)
	## The corpus must still contain something CLOSE to the limit, or the arm is asserting about
	## short prose and would stay green through a panel that had shrunk under the real content.
	assert_gt(tallest, _box.y * 0.6,
		"CONTROL: tallest row '%s' is %.0f px of a %.0f px box (%.0f%%) — nothing here approaches the limit, so a green says little" % [
			tallest_id, tallest, _box.y, tallest / _box.y * 100.0])
	over.sort()
	for o in over:
		gut.p("OVERFLOW %s" % str(o))
	assert_eq(over, [], "an authored examine does not fit the panel that shows it: %s" % "; ".join(over))
	gut.p("  %d examines fit; tallest '%s' at %.0f px of %.0f (%.0f px spare)" % [
		measured, tallest_id, tallest, _box.y, _box.y - tallest])
