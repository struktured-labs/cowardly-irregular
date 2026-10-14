extends GutTest

## ⛔ THE TELEPORT LIST IGNORED TEXT SIZE — 6 raw font sizes, zero `TextScale`, on a list of 30+
## destinations a player reads to pick one. Last file in this lane's census.
##
## ✅ It has a ScrollContainer, which is why rows here GROW FREELY where ControlsMenu's had to be
## capped by the space: a longer list is absorbed rather than made unreachable. Same census, two
## correct answers, and the discriminator is whether the surface can scroll.
##
## 🔑 Every cross-scale comparison reads a SNAPSHOT taken while its own scale is live. The derived
## getters read `TextScale` at CALL time, so holding two menus and asking each afterwards returns
## the current scale's answer for BOTH -- that error silently made three of my ControlsMenu arms
## compare a value with itself.

const TM := "res://src/ui/TeleportMenu.gd"
const PRESETS: Array = [0.8, 1.0, 1.25, 1.5, 2.0]

var _saved = null


func before_each() -> void:
	_saved = GameState.text_size_scale if "text_size_scale" in GameState else null


func after_each() -> void:
	if _saved != null:
		GameState.text_size_scale = _saved


func _menu_at(scale: float) -> Control:
	GameState.text_size_scale = scale
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	var layer := CanvasLayer.new()
	vp.add_child(layer)
	var m: Control = load(TM).new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame
	return m


func _snapshot(m: Control) -> Dictionary:
	return {
		"row_h": int(m._row_h()),
		"section_h": int(m._section_h()),
		"id_col": float(m._id_col_w()),
		"sub_y": float(m._sub_y()),
		"list_top": float(m._list_top()),
		"row_font": TextScale.scaled(m.ROW_FONT_SIZE),
	}


## Every built row, with its label and its right-hand id column.
func _rows(m: Control) -> Array:
	var out: Array = []
	for hl in m._highlight_refs:
		if not (hl and is_instance_valid(hl)):
			continue
		var item: Control = (hl as Control).get_parent() as Control
		if item == null:
			continue
		var labels: Array = []
		for c in item.get_children():
			if c is Label:
				labels.append(c as Label)
		if labels.size() >= 2:
			out.append({"item": item, "labels": labels})
	return out


## Drawn ink, not the line box: ascent + descent excludes the leading a Label reserves but never
## paints, and the authored header relies on that slack.
func _ink_h(l: Label) -> float:
	var fnt: Font = l.get_theme_font("font")
	if fnt == null:
		return l.size.y
	var px: int = l.get_theme_font_size("font_size")
	return fnt.get_ascent(px) + fnt.get_descent(px)


func test_the_list_builds_its_rows() -> void:
	var m: Control = await _menu_at(1.0)
	assert_gt(_rows(m).size(), 10,
		"PRECONDITION: the list must build rows, got %d" % _rows(m).size())


## ARM 1 — the row font GREW.
func test_the_row_font_follows_the_setting() -> void:
	var small: Dictionary = _snapshot(await _menu_at(0.8))
	var big: Dictionary = _snapshot(await _menu_at(2.0))
	assert_gt(int(big["row_font"]), int(small["row_font"]),
		"row text must GROW: 80%% gave %d, 200%% gave %d" % [small["row_font"], big["row_font"]])


## ARM 2 — the grown row text fits its row at every preset, measured as DRAWN text.
func test_no_row_text_overflows_its_row() -> void:
	var bad: Array = []
	for scale in PRESETS:
		var m: Control = await _menu_at(float(scale))
		var h: float = float(m._row_h())
		for row in _rows(m):
			for l in (row["labels"] as Array):
				var lab: Label = l as Label
				var drawn: float = float(lab.get_line_count()) * float(lab.get_line_height())
				if drawn > h:
					bad.append("%.2fx: '%s' draws %.0f in a %.0f row"
						% [scale, lab.text, drawn, h])
	assert_eq(bad, [], "row text must fit its row at every Text Size: %s" % [bad])


## ARM 3 — the destination name must not run under the right-hand map-id column. The id column is
## right-anchored and the name is left-anchored, so they close on each other from both sides as the
## text grows, and nothing in the file bounds either.
func test_the_name_never_runs_under_the_id_column() -> void:
	var bad: Array = []
	for scale in PRESETS:
		var m: Control = await _menu_at(float(scale))
		var asked_col: float = float(m._id_col_w())
		for row in _rows(m):
			var labels: Array = row["labels"] as Array
			var name_lab: Label = null
			var id_lab: Label = null
			for l in labels:
				var lab: Label = l as Label
				if lab.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
					id_lab = lab
				elif lab.text.strip_edges() != "" and lab.text.strip_edges() != "▶":
					name_lab = lab
			if name_lab == null or id_lab == null:
				continue
			var fnt: Font = name_lab.get_theme_font("font")
			if fnt == null:
				continue
			var ends: float = name_lab.position.x + fnt.get_string_size(name_lab.text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, name_lab.get_theme_font_size("font_size")).x
			## ⛔ A MARGIN, NOT MERE NON-OVERLAP. Measured without the panel widening: at 2.0x the
			## longest name ended at 481 and the id column started at 481 -- touching exactly, which
			## a `>` test passes while the next longer destination name overlaps silently.
			if ends > id_lab.position.x - 4.0:
				bad.append("%.2fx: '%s' ends %.0f, id column starts %.0f (margin %+.0f)"
					% [scale, name_lab.text, ends, id_lab.position.x,
						id_lab.position.x - ends])
			## And the id must fit the column the layout ASKED for, which is what makes a pinned 216
			## detectable: the widest id needs 286 at 2.0x.
			## ⛔ COMPARED AGAINST `_id_col_w()`, NOT `id_lab.size.x`. A Label clamps its size UP to
			## its content, so the pinned-216 version reports 278 and the assert compared 278 with
			## 278 and passed. The rect is the content; the COLUMN is the claim.
			var id_fnt: Font = id_lab.get_theme_font("font")
			if id_fnt != null:
				var id_w: float = id_fnt.get_string_size(id_lab.text, HORIZONTAL_ALIGNMENT_LEFT,
					-1, id_lab.get_theme_font_size("font_size")).x
				if id_w > asked_col + 1.0:
					bad.append("%.2fx: id '%s' needs %.0f in a %.0f column"
						% [scale, id_lab.text, id_w, asked_col])
	assert_eq(bad, [], "a destination name must clear the id column: %s" % [bad])


## ARM 4 — the state the fix did NOT set out to change, both directions. Derived values replace
## literals, so the DEFAULT moves unless every floor holds; 0.8x must not shrink a box either.
func test_the_small_and_default_sizes_render_the_shipped_layout() -> void:
	var consts: Dictionary = (load(TM) as GDScript).get_script_constant_map()
	for key in ["ROW_HEIGHT", "SECTION_HEADER_HEIGHT"]:
		assert_true(consts.has(key), "FLOOR: %s must still exist, or this arm is vacuous" % key)
	for scale in [0.8, 1.0]:
		var snap: Dictionary = _snapshot(await _menu_at(scale))
		assert_eq(int(snap["row_h"]), int(consts["ROW_HEIGHT"]),
			"at %.0f%% the row height must be the authored %d" % [scale * 100.0, consts["ROW_HEIGHT"]])
		assert_eq(int(snap["section_h"]), int(consts["SECTION_HEADER_HEIGHT"]),
			"at %.0f%% the section header must be the authored %d"
				% [scale * 100.0, consts["SECTION_HEADER_HEIGHT"]])
		assert_eq(int(snap["id_col"]), 216,
			"at %.0f%% the id column must be the authored 216" % [scale * 100.0])
		assert_eq(int(snap["sub_y"]), 32,
			"at %.0f%% the subtitle must sit at the authored 32" % [scale * 100.0])
		assert_eq(int(snap["list_top"]), 56,
			"at %.0f%% the list must start at the authored 56" % [scale * 100.0])


## ARM 5 — the mouse HIT REGION and the drawn row must be ONE height. `make_clickable` adds an
## invisible Button child, so that is the click target rather than the row Control.
func test_the_click_target_matches_the_drawn_row() -> void:
	var bad: Array = []
	for scale in PRESETS:
		var m: Control = await _menu_at(float(scale))
		for row in _rows(m):
			var item: Control = row["item"] as Control
			var hit: Button = null
			for c in item.get_children():
				if c is Button:
					hit = c as Button
					break
			if hit == null:
				bad.append("%.2fx: a row has no click target" % scale)
				break
			if absf(hit.size.y - item.size.y) > 0.5:
				bad.append("%.2fx: click target %.0f tall, row draws %.0f"
					% [scale, hit.size.y, item.size.y])
			break
	assert_eq(bad, [], "a click must land on the row under the pointer: %s" % [bad])


## ARM 6 — the SCROLL path must use the same row height the rows were laid out with. Two copies of
## that number scroll the selected row to the wrong place, and the row positions come from the copy
## that is already correct, so asserting on positions alone cannot see it.
func test_the_last_row_scrolls_into_view_at_every_preset() -> void:
	var bad: Array = []
	for scale in PRESETS:
		var m: Control = await _menu_at(float(scale))
		m._selected = m.DESTINATIONS.size() - 1
		m._update_selection()
		await get_tree().process_frame
		var row_y: float = float(m._row_global_y[m._selected])
		var top: float = float(m._scroll.scroll_vertical)
		var view: float = float(m._viewport_height)
		var rh: float = float(m._row_h())
		if row_y < top - 0.5:
			bad.append("%.2fx: the selected row is %.0f ABOVE the view" % [scale, top - row_y])
		elif row_y + rh > top + view + 0.5:
			bad.append("%.2fx: the selected row ends %.0f, past the view at %.0f"
				% [scale, row_y + rh, top + view])
	assert_eq(bad, [], "the selected row must be on screen after scrolling: %s" % [bad])


## ARM 7 — the header BAND SCALES. The subtitle's y was a bare 32 while the title above it scales,
## so at 2.0x a 36px title drew straight through it; this is the arm for that repair.
##
## ⛔ IT IS NOT WRITTEN AS A COLLISION CHECK, AND THE REASON IS MEASURED RATHER THAN CHOSEN. Both
## forms RED ON THE AUTHORED LAYOUT AT 1.00x:
##     title.position.y + size.y          -> ink ends 34, subtitle starts 32
##     title.position.y + ascent+descent  -> 34 as well; for this font the line box IS the ink
## The shipped design overlaps the title's metric by 2px and looks right because "TELEPORT" has no
## descenders. So a metric threshold cannot be satisfied by correct layout, and an arm that reds on
## the shipped screen is not a guard -- it is a demand to change the design. What the fix actually
## claims is that the band GROWS with the text, which is structural and provable, so that is what
## this asserts. @cowir-story @cowir-overworld: relevant to any plate-vs-text arm.
func test_the_header_band_scales_with_the_text() -> void:
	var small: Dictionary = _snapshot(await _menu_at(0.8))
	var big: Dictionary = _snapshot(await _menu_at(2.0))
	assert_gt(float(big["sub_y"]), float(small["sub_y"]),
		"the subtitle must move DOWN as the title grows, or the title draws through it: "
		+ "80%% %.0f, 200%% %.0f" % [float(small["sub_y"]), float(big["sub_y"])])
	assert_gt(float(big["list_top"]), float(small["list_top"]),
		"the list must start below the grown header: 80%% %.0f, 200%% %.0f"
			% [float(small["list_top"]), float(big["list_top"])])
	## And the band must not merely move -- it must stay PROPORTIONAL to the text.
	## ⛔ MEASURED FROM 1.0x, NOT 0.8x, AND THAT IS NOT A CONVENIENCE. The first version asked for
	## 2.5x (0.8 -> 2.0) and got 2.0, because the geometry factor is FLOORED at 1.0 on purpose: a
	## text size may not shrink a shipped box, so 0.8x and 1.0x have the same band by design. The
	## arm had encoded an expectation the floor exists to forbid.
	var base: Dictionary = _snapshot(await _menu_at(1.0))
	var grew: float = float(big["sub_y"]) / float(base["sub_y"])
	assert_gte(grew, 1.99,
		"the header band must scale WITH the text: 1.0x -> 2.0x is 2x of text and the band "
		+ "moved %.2fx" % grew)
	assert_eq(float(small["sub_y"]), float(base["sub_y"]),
		"and 80%% must share 100%%'s band, because a box only ever grows: %.0f vs %.0f"
			% [float(small["sub_y"]), float(base["sub_y"])])
