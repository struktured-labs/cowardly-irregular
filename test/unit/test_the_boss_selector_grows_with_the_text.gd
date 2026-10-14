extends GutTest

## ⛔ THE BOSS SELECTOR IGNORED TEXT SIZE — 7 raw font sizes, zero `TextScale`.
##
## 🔑 IT IS A WINDOWED LIST: `VISIBLE_ROWS` rows with its own scroll indicators and NO
## ScrollContainer. So growth is space-bounded like ControlsMenu's -- but unlike ControlsMenu this
## screen can already SCROLL, so the honest answer is to show FEWER rows at a larger size rather
## than cap the font. Every boss stays reachable, just not all at once. Third correct answer in one
## census, and the discriminator each time was what the surface can already do:
##     TeleportMenu / FastTravelMenu  ScrollContainer   -> rows grow freely
##     ControlsMenu                   no scroll at all  -> the FONT must be capped
##     BossSelectorMenu               windowed + scroll -> the WINDOW shrinks
##
## ⛔ And a boss row's two labels are SIDE BY SIDE -- name left, world right-anchored at a fixed
## 110px -- the same closing-column risk as the other two lists. Their positions are written in TWO
## places (the build loop AND `_update_list`), so both writers had to be derived.

const BS := "res://src/ui/BossSelectorMenu.gd"
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
	var m: Control = load(BS).new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame
	return m


func _snapshot(m: Control) -> Dictionary:
	return {
		"row_h": int(m._row_h()),
		"visible": int(m._visible_rows()),
		"list_y": float(m._list_y()),
		"sub_y": float(m._sub_y()),
		"world_col": float(m._world_col_w()),
		"footer_gap": float(m._footer_gap()),
		"row_font": TextScale.scaled(13),
	}


func test_the_selector_builds_its_window() -> void:
	var m: Control = await _menu_at(1.0)
	assert_gt(m._row_highlights.size(), 5,
		"PRECONDITION: the window must build rows, got %d" % m._row_highlights.size())


## ARM 1 — the row font GREW.
func test_the_row_font_follows_the_setting() -> void:
	var small: Dictionary = _snapshot(await _menu_at(0.8))
	var big: Dictionary = _snapshot(await _menu_at(2.0))
	assert_gt(int(big["row_font"]), int(small["row_font"]),
		"row text must GROW: 80%% gave %d, 200%% gave %d" % [small["row_font"], big["row_font"]])


## ARM 2 — the WINDOW must fit between the list top and the footer at every preset. This is the arm
## the whole design turns on: a row below the footer is a boss the player cannot see.
func test_the_window_fits_above_the_footer_at_every_preset() -> void:
	var bad: Array = []
	for scale in PRESETS:
		var m: Control = await _menu_at(float(scale))
		var bottom: float = m._list_y() + float(int(m._visible_rows()) * int(m._row_h()))
		var limit: float = m._panel.size.y - m._footer_gap()
		if bottom > limit + 0.5:
			bad.append("%.2fx: %d rows end at %.0f, footer starts at %.0f"
				% [scale, int(m._visible_rows()), bottom, limit])
		if int(m._visible_rows()) < 1:
			bad.append("%.2fx: the window collapsed to %d rows" % [scale, int(m._visible_rows())])
	assert_eq(bad, [], "the window must fit above the footer: %s" % [bad])


## ARM 3 — EVERY boss stays reachable even as the window shrinks, PROVEN THROUGH `_clamp_scroll()`.
## Showing fewer rows is only acceptable because the list scrolls, so this is the arm the whole
## trade rests on.
##
## ⛔ ITS FIRST VERSION WAS A TAUTOLOGY: it recomputed `total - _visible_rows()` itself and never
## read the code's clamp, so pinning that clamp at the authored 14 while the window shrank passed
## 8/8 -- the exact divergence it exists to catch. It now selects the LAST entry, calls the real
## `_clamp_scroll()`, and asks whether that entry is inside the window.
func test_the_last_boss_is_reachable_at_every_preset() -> void:
	var bad: Array = []
	for scale in PRESETS:
		var m: Control = await _menu_at(float(scale))
		var total: int = (m._display_list as Array).size()
		if total <= 0:
			bad.append("%.2fx: the display list is empty" % scale)
			continue
		m.selected_index = (m._selectable_indices as Array).size() - 1
		m._clamp_scroll()
		await get_tree().process_frame
		var vis: int = int(m._visible_rows())
		var idx: int = int(m._get_display_index_for_selected())
		var off: int = int(m.scroll_offset)
		if idx < off or idx >= off + vis:
			bad.append("%.2fx: the last boss sits at display %d, window is [%d, %d)"
				% [scale, idx, off, off + vis])
	assert_eq(bad, [],
		"the last boss must be inside the window after the real clamp runs: %s" % [bad])


## ARM 4 — a boss NAME must keep margin from the right-anchored world column, OVER THE WHOLE
## ROSTER. Measured on the twin lists: a fixed right column left exactly ZERO margin at 2.0x, which
## a `>` test passes while the next longer name overlaps.
##
## ⛔ ITS FIRST VERSION ITERATED `_row_highlights` -- THE VISIBLE WINDOW -- WHICH IS ~10 OF 53.
## The display list interleaves group headers, so one screenful never reaches the long names:
## `Glacius, the Frozen Sovereign` (29), `Voltharion, the Storm's Edge` (28),
## `Warden of the Assembly Line` (27). @cowir-adhoc's line is the one that applies -- "drives real
## data" is not the same claim as "drives the WORST real data" -- and it is the third instance of
## this in my own work within the hour, after the grid's corpus of one and the fast travel
## fixture's invented labels. The FIX always iterated every boss (`_world_col_w` does); it was the
## VERIFICATION that saw a tenth of them.
func test_every_boss_name_keeps_margin_from_the_world_column() -> void:
	var bad: Array = []
	for scale in PRESETS:
		var m: Control = await _menu_at(float(scale))
		var asked: float = float(m._world_col_w())
		var roster: Array = m.BOSSES
		assert_gt(roster.size(), 20,
			"PRECONDITION: the roster must be loaded, got %d" % roster.size())
		var probe := Label.new()
		probe.add_theme_font_size_override("font_size", TextScale.scaled(13))
		m.add_child(probe)
		var wprobe := Label.new()
		wprobe.add_theme_font_size_override("font_size", TextScale.scaled(10))
		m.add_child(wprobe)
		await get_tree().process_frame
		var fnt: Font = probe.get_theme_font("font")
		var wfnt: Font = wprobe.get_theme_font("font")
		if fnt == null or wfnt == null:
			continue
		## the geometry a boss row is built with: name at x=10, world right-anchored
		var row_w: float = m._panel.size.x - 16.0
		var world_x: float = row_w - asked
		for b in roster:
			var nm: String = str((b as Dictionary).get("name", ""))
			var wd: String = str((b as Dictionary).get("world", ""))
			var ends: float = 10.0 + fnt.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1,
				TextScale.scaled(13)).x
			if ends > world_x - 4.0:
				bad.append("%.2fx: '%s' ends %.0f, world column starts %.0f"
					% [scale, nm, ends, world_x])
			var ww: float = wfnt.get_string_size(wd, HORIZONTAL_ALIGNMENT_LEFT, -1,
				TextScale.scaled(10)).x
			if ww > asked + 1.0:
				bad.append("%.2fx: world '%s' needs %.0f in a %.0f column" % [scale, wd, ww, asked])
		probe.queue_free()
		wprobe.queue_free()
	assert_eq(bad, [],
		"every boss name in the roster must clear the world column: %s" % [bad.slice(0, 6)])


## ARM 5 — the state the fix did NOT set out to change, both directions.
func test_the_small_and_default_sizes_render_the_shipped_layout() -> void:
	var consts: Dictionary = (load(BS) as GDScript).get_script_constant_map()
	for key in ["ROW_HEIGHT", "VISIBLE_ROWS"]:
		assert_true(consts.has(key), "FLOOR: %s must still exist, or this arm is vacuous" % key)
	for scale in [0.8, 1.0]:
		var snap: Dictionary = _snapshot(await _menu_at(scale))
		assert_eq(int(snap["row_h"]), int(consts["ROW_HEIGHT"]),
			"at %.0f%% the row height must be the authored %d"
				% [scale * 100.0, consts["ROW_HEIGHT"]])
		assert_eq(int(snap["visible"]), int(consts["VISIBLE_ROWS"]),
			"at %.0f%% the window must be the authored %d rows"
				% [scale * 100.0, consts["VISIBLE_ROWS"]])
		assert_eq(int(snap["list_y"]), 52, "at %.0f%% the list must start at 52" % [scale * 100.0])
		assert_eq(int(snap["sub_y"]), 30, "at %.0f%% the subtitle must sit at 30" % [scale * 100.0])
		assert_eq(int(snap["world_col"]), 110,
			"at %.0f%% the world column must be the authored 110" % [scale * 100.0])


## ARM 6 — the click target and the drawn row are ONE height.
func test_the_click_target_matches_the_drawn_row() -> void:
	var bad: Array = []
	for scale in PRESETS:
		var m: Control = await _menu_at(float(scale))
		for hl in m._row_highlights:
			if not (hl and is_instance_valid(hl)):
				continue
			var hit: Button = null
			for c in (hl as Control).get_children():
				if c is Button:
					hit = c as Button
					break
			if hit == null:
				continue
			if absf(hit.size.y - (hl as Control).size.y) > 0.5:
				bad.append("%.2fx: click target %.0f tall, row draws %.0f"
					% [scale, hit.size.y, (hl as Control).size.y])
			break
	assert_eq(bad, [], "a click must land on the row under the pointer: %s" % [bad])


## ARM 7 — the header band SCALES. Not a metric collision check: on the twin lists BOTH metric forms
## red on the AUTHORED layout, because a header's offset sits inside the title's line box and looks
## right (leading is not ink). Measured from 1.0x, since the factor is floored there by design.
func test_the_header_band_scales_with_the_text() -> void:
	var small: Dictionary = _snapshot(await _menu_at(0.8))
	var base: Dictionary = _snapshot(await _menu_at(1.0))
	var big: Dictionary = _snapshot(await _menu_at(2.0))
	assert_gt(float(big["sub_y"]), float(base["sub_y"]),
		"the subtitle must move down as the title grows: 100%% %.0f, 200%% %.0f"
			% [float(base["sub_y"]), float(big["sub_y"])])
	assert_gt(float(big["list_y"]), float(base["list_y"]),
		"the list must start below the grown header: 100%% %.0f, 200%% %.0f"
			% [float(base["list_y"]), float(big["list_y"])])
	assert_eq(float(small["sub_y"]), float(base["sub_y"]),
		"and 80%% shares 100%%'s band, because a box only ever grows: %.0f vs %.0f"
			% [float(small["sub_y"]), float(base["sub_y"])])


## ARM 8 — THE DRAWN ROW TEXT MUST FIT ITS ROW, the arm this guard was missing. Pinning `_row_h()`
## back to the authored 32 passed every other arm, because `_visible_rows()` simply shows MORE short
## rows and the window still fits the footer -- the window absorbs the defect, and the only visible
## symptom is 2.0x text drawn outside a 32px band. A space-bounded design can hide a row-height
## regression from every arm that measures the WINDOW.
func test_no_row_text_overflows_its_row() -> void:
	var bad: Array = []
	for scale in PRESETS:
		var m: Control = await _menu_at(float(scale))
		var h: float = float(m._row_h())
		for i in range(m._row_highlights.size()):
			for lbl in [m._row_labels[i] as Label, m._row_world_labels[i] as Label]:
				if lbl == null or lbl.text == "":
					continue
				var drawn: float = float(lbl.get_line_count()) * float(lbl.get_line_height())
				if lbl.position.y + drawn > h + 0.5:
					bad.append("%.2fx: '%s' ends %.0f in a %.0f row"
						% [scale, lbl.text, lbl.position.y + drawn, h])
	assert_eq(bad, [], "row text must stay inside its row at every Text Size: %s" % [bad])
