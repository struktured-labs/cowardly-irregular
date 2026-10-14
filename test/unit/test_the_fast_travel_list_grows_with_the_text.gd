extends GutTest

## ⛔ A SIBLING MISS IN MY OWN CENSUS. `FastTravelMenu` renders the SAME destination list as the
## `TeleportMenu` I scaled one tick earlier -- 7 raw font sites, zero `TextScale` -- and I never
## looked at it, because my "census" was my own remembered list of four files rather than a measured
## population. `test_fast_travel_scrolls_to_its_selection:129` already carries a ratchet against
## these two diverging, so the codebase said they were twins and the miss happened anyway.
##
## 🔑 Reachable from a save point (`SavePoint.gd:208`), so a player meets it constantly.
##
## The fix is kept PARALLEL to TeleportMenu's deliberately, since that ratchet exists.

const FT := "res://src/ui/FastTravelMenu.gd"
## ⛔ DERIVED FROM THE CONSUMER'S OWN LIST, NOT A COPY. A hardcoded [0.8, 1.0, 1.25, 1.5, 2.0] goes
## quietly stale the day a preset is added, and the arms below then never visit the new step.
##
## 📌 NO FALLBACK TO A HARDCODED LADDER — the EMPTY default one line below is deliberate and is not
## the same thing. A fallback ladder would make these arms pass against a set the player cannot
## select; the empty default hands the floor something it can fail on, by name.
##
## ⚠️ AND THIS REACH IS RUNTIME, WHICH IS WHY "a rename reds" IS TRUE HERE and would be FALSE of a
## `class_name` const reach. `SettingsMenu.TEXT_SIZE_PRESETS` as a static reach resolves at PARSE
## time, so a rename stops the file RUNNING — `run_tests.sh` EC=3, whose first listed cause is a
## stale import cache, which cannot fix it. Keyed by string off `get_script_constant_map()`, a
## rename yields `[]` and the floor reds as an ordinary named failure (@cowir-music's finding;
## @cowir-overworld corrected the same sentence in their own file).
##
## ⛔ THE FLOOR LIVES IN HERE, NOT ONLY IN ITS OWN ARM. An empty or renamed ladder makes every
## `for scale in _presets()` iterate ZERO times and pass green; asserting inside the helper makes
## each sweeping arm red BY ITS OWN NAME, and it cannot be separated from the loops by a later edit
## the way a standalone floor arm can (@cowir-autogrind named the gap, @cowir-story the repair).
func _presets() -> Array:
	var consts: Dictionary = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map()
	var p: Array = consts.get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1,
		"FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must resolve and hold more than one step, or this "
		+ "arm's preset loop iterates nothing and passes. Got " + str(p))
	return p

var _saved = null
var _saved_gold: int = -1


func before_each() -> void:
	_saved = GameState.text_size_scale if "text_size_scale" in GameState else null
	## ⛔ A REAL GOLD VALUE, because gold is the one header number bounded by nothing. At the test
	## default it is 0, "0 G" fits the authored 120 at every preset, and `_gold_col_w()` would
	## return its floor forever -- an unexercised derivation that no mutation could red.
	## ⛔ VIA add_gold, BECAUSE `GameState.set_gold` DOES NOT EXIST. The first version called it, the
	## call errored, and a GDScript error ABORTS ITS ENCLOSING FUNCTION -- so before_each stopped
	## here, gold stayed 0, "0 G" fits the authored 120 at every preset, and ARM 8 passed VACUOUSLY
	## while its mutation stayed green. The arm looked like coverage and measured nothing.
	_saved_gold = int(GameState.get_gold())
	GameState.add_gold(9999999 - _saved_gold)


func after_each() -> void:
	if _saved != null:
		GameState.text_size_scale = _saved
	if _saved_gold >= 0:
		GameState.add_gold(_saved_gold - int(GameState.get_gold()))


## The fixture the sibling guard uses: inject rows, then build. `_collect_rows` reads
## activated_crystals, which a fresh test state leaves EMPTY -- every row arm would be vacuous.
func _menu_at(scale: float, row_count: int = 24) -> Control:
	GameState.text_size_scale = scale
	var m: Control = load(FT).new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(m)
	m.size = Vector2(1280, 720)
	## ⛔ THE REAL DESTINATIONS, NOT INVENTED ONES. This first built "Whispering Cave Depths %d" --
	## 25 chars against a real worst of 31 ("Community Center (MapleHeights)"), so the arm that
	## checks the name clears the cost column was testing a string SHORTER than the game produces.
	## Same flaw as the grid's worst-by-length corpus of one, and @cowir-battle declared the
	## identical thing in their TurnInfo arm within the hour: a fit arm on a string the game never
	## shows. The FIX was always derived from `DESTINATIONS` itself, so it is sound by construction;
	## it is the VERIFICATION that was under-sized.
	var rows: Array = []
	var src: Array = TeleportMenu.DESTINATIONS
	for i in range(maxi(row_count, src.size())):
		var d: Dictionary = src[i % src.size()] as Dictionary
		rows.append({"id": str(d.get("id", "m%d" % i)), "label": str(d.get("label", "")),
			"spawn": str(d.get("spawn", "default")), "cost": 50 + (i % 6) * 100,
			"affordable": true})
	m.set("_rows", rows)
	m.set("_selected", 0)
	m._build_ui()
	await get_tree().process_frame
	await get_tree().process_frame
	return m


func _snapshot(m: Control) -> Dictionary:
	return {
		"row_h": int(m._row_h()),
		"row_font": TextScale.scaled(m.ROW_FONT_SIZE),
		"cost_col": float(m._cost_col_w()),
		"gold_col": float(m._gold_col_w()),
		"name_x": float(m._name_x()),
		"sub_y": float(m._sub_y()),
		"list_top": float(m._list_top()),
	}


func _rows_of(m: Control) -> Array:
	var out: Array = []
	for c in m._content.get_children():
		if not (c is Control):
			continue
		var labels: Array = []
		for l in (c as Control).get_children():
			if l is Label:
				labels.append(l as Label)
		if labels.size() >= 2:
			out.append({"item": c as Control, "labels": labels})
	return out


func test_the_menu_builds_its_rows() -> void:
	var m: Control = await _menu_at(1.0)
	assert_gt(_rows_of(m).size(), 10,
		"PRECONDITION: the fixture must build rows, got %d" % _rows_of(m).size())


## ARM 1 — the row font GREW, from snapshots taken at each scale.
func test_the_row_font_follows_the_setting() -> void:
	var small: Dictionary = _snapshot(await _menu_at(0.8))
	var big: Dictionary = _snapshot(await _menu_at(2.0))
	assert_gt(int(big["row_font"]), int(small["row_font"]),
		"row text must GROW: 80%% gave %d, 200%% gave %d" % [small["row_font"], big["row_font"]])


## ARM 2 — the drawn row text fits its row at every preset.
func test_no_row_text_overflows_its_row() -> void:
	var bad: Array = []
	for scale in _presets():
		var m: Control = await _menu_at(float(scale))
		var h: float = float(m._row_h())
		for row in _rows_of(m):
			for l in (row["labels"] as Array):
				var lab: Label = l as Label
				var drawn: float = float(lab.get_line_count()) * float(lab.get_line_height())
				if drawn > h:
					bad.append("%.2fx: '%s' draws %.0f in a %.0f row" % [scale, lab.text, drawn, h])
	assert_eq(bad, [], "row text must fit its row at every Text Size: %s" % [bad])


## ARM 3 — the destination name must keep MARGIN from the cost column, and the cost must fit the
## column the layout ASKED for. Both halves measured on TeleportMenu's twin: a fixed column left
## exactly ZERO margin at 2.0x (touching, which `>` passes), and comparing against the label's rect
## instead of the asked width compared a clamped value with itself.
func test_the_name_keeps_margin_from_the_cost_column() -> void:
	var bad: Array = []
	for scale in _presets():
		var m: Control = await _menu_at(float(scale))
		var asked: float = float(m._cost_col_w())
		for row in _rows_of(m):
			var name_lab: Label = null
			var cost_lab: Label = null
			for l in (row["labels"] as Array):
				var lab: Label = l as Label
				if lab.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
					cost_lab = lab
				elif lab.text.strip_edges() != "" and not lab.text.strip_edges().begins_with("▶"):
					name_lab = lab
			if name_lab == null or cost_lab == null:
				continue
			var fnt: Font = name_lab.get_theme_font("font")
			if fnt == null:
				continue
			var ends: float = name_lab.position.x + fnt.get_string_size(name_lab.text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, name_lab.get_theme_font_size("font_size")).x
			if ends > cost_lab.position.x - 4.0:
				bad.append("%.2fx: '%s' ends %.0f, cost starts %.0f (margin %+.0f)"
					% [scale, name_lab.text, ends, cost_lab.position.x,
						cost_lab.position.x - ends])
			var cf: Font = cost_lab.get_theme_font("font")
			if cf != null:
				var cw: float = cf.get_string_size(cost_lab.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
					cost_lab.get_theme_font_size("font_size")).x
				if cw > asked + 1.0:
					bad.append("%.2fx: cost '%s' needs %.0f in a %.0f column"
						% [scale, cost_lab.text, cw, asked])
	assert_eq(bad, [], "a name must clear the cost column with margin: %s" % [bad])


## ARM 4 — the state the fix did NOT set out to change, both directions.
func test_the_small_and_default_sizes_render_the_shipped_layout() -> void:
	var consts: Dictionary = (load(FT) as GDScript).get_script_constant_map()
	assert_true(consts.has("ROW_HEIGHT"),
		"FLOOR: ROW_HEIGHT must still exist, or this arm is vacuous")
	## ⛔ DERIVED, NOT `[0.8, 1.0]`. Converting the ladder const left this SECOND literal behind,
	## and it carries no 1.25 so every ladder-keyed census is blind to it — yet this is the arm
	## that decides whether a new SUB-UNITY preset is ever checked (@cowir-music, 2026-10-14).
	var at_or_below: Array = _presets().filter(func(p): return float(p) <= 1.0)
	assert_gt(at_or_below.size(), 1,
		"CONTROL: the sub-unity set must derive more than one step from the shipped ladder, or this loop iterates nothing and passes: " + str(at_or_below))
	for scale in at_or_below:
		var snap: Dictionary = _snapshot(await _menu_at(scale))
		assert_eq(int(snap["row_h"]), int(consts["ROW_HEIGHT"]),
			"at %.0f%% the row height must be the authored %d"
				% [scale * 100.0, consts["ROW_HEIGHT"]])
		assert_eq(int(snap["name_x"]), 26, "at %.0f%% the name column must be at 26" % [scale * 100.0])
		assert_eq(int(snap["sub_y"]), 32, "at %.0f%% the subtitle must sit at 32" % [scale * 100.0])
		assert_eq(int(snap["list_top"]), 60, "at %.0f%% the list must start at 60" % [scale * 100.0])
		assert_eq(int(snap["cost_col"]), 100,
			"at %.0f%% the cost column must be the authored 100" % [scale * 100.0])
		assert_eq(int(snap["gold_col"]), 120,
			"at %.0f%% the gold readout must be the authored 120" % [scale * 100.0])


## ARM 5 — the click target and the drawn row are ONE height.
func test_the_click_target_matches_the_drawn_row() -> void:
	var bad: Array = []
	for scale in _presets():
		var m: Control = await _menu_at(float(scale))
		for row in _rows_of(m):
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


## ARM 6 — the SCROLL path must use the same row height the rows were laid out with. It carried its
## own copy of ROW_HEIGHT, and the row positions come from the copy that was already correct.
func test_the_last_row_scrolls_into_view_at_every_preset() -> void:
	var bad: Array = []
	for scale in _presets():
		var m: Control = await _menu_at(float(scale))
		m.set("_selected", (m.get("_rows") as Array).size() - 1)
		m._update_selection()
		await get_tree().process_frame
		var row_y: float = float((m.get("_row_y") as Array)[int(m.get("_selected"))])
		var top: float = float(m._scroll.scroll_vertical)
		var view: float = float(m.get("_viewport_height"))
		var drawn: float = float(m._row_h()) - 2.0
		if row_y < top - 0.5:
			bad.append("%.2fx: the selected row is %.0f ABOVE the view" % [scale, top - row_y])
		elif row_y + drawn > top + view + 0.5:
			bad.append("%.2fx: the selected row ends %.0f, past the view at %.0f"
				% [scale, row_y + drawn, top + view])
	assert_eq(bad, [], "the selected row must be on screen after scrolling: %s" % [bad])


## ARM 7 — the header band SCALES. Not written as a metric collision check: on the twin, BOTH metric
## forms red on the AUTHORED layout at 1.00x, because a header's authored offset sits inside the
## title's line box and looks right (leading is not ink). Measured from 1.0x, because the geometry
## factor is floored at 1.0 and 0.8x shares 100%'s band by design.
func test_the_header_band_scales_with_the_text() -> void:
	var small: Dictionary = _snapshot(await _menu_at(0.8))
	var base: Dictionary = _snapshot(await _menu_at(1.0))
	var big: Dictionary = _snapshot(await _menu_at(2.0))
	assert_gt(float(big["sub_y"]), float(base["sub_y"]),
		"the subtitle must move DOWN as the title grows: 100%% %.0f, 200%% %.0f"
			% [float(base["sub_y"]), float(big["sub_y"])])
	assert_gt(float(big["list_top"]), float(base["list_top"]),
		"the list must start below the grown header: 100%% %.0f, 200%% %.0f"
			% [float(base["list_top"]), float(big["list_top"])])
	assert_gte(float(big["sub_y"]) / float(base["sub_y"]), 1.99,
		"the band must scale WITH the text: 1.0x -> 2.0x moved %.2fx"
			% (float(big["sub_y"]) / float(base["sub_y"])))
	assert_eq(float(small["sub_y"]), float(base["sub_y"]),
		"and 80%% shares 100%%'s band, because a box only ever grows: %.0f vs %.0f"
			% [float(small["sub_y"]), float(base["sub_y"])])


## ARM 8 — the GOLD readout, the one header value bounded by nothing. A player decides whether they
## can afford a jump from this number, so a clipped one is worse than a cramped one.
func test_the_gold_readout_fits_its_band() -> void:
	var bad: Array = []
	for scale in _presets():
		var m: Control = await _menu_at(float(scale))
		var asked: float = float(m._gold_col_w())
		var gold: Label = null
		for c in m.get_children():
			for l in (c as Node).get_children():
				if l is Label and (l as Label).horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT \
						and (l as Label).text.ends_with(" G"):
					gold = l as Label
					break
			if gold != null:
				break
		if gold == null:
			bad.append("%.2fx: the gold readout was not found" % scale)
			continue
		## FLOOR: the fixture's gold must actually be in the label. A "0 G" here means before_each
		## aborted, and every assertion below it would pass on a value the game never shows.
		if gold.text == "0 G":
			bad.append("%.2fx: the fixture's gold never reached the label ('%s') -- this arm "
				% [scale, gold.text] + "would pass vacuously")
		var fnt: Font = gold.get_theme_font("font")
		if fnt == null:
			continue
		var drawn: float = fnt.get_string_size(gold.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			gold.get_theme_font_size("font_size")).x
		if drawn > asked + 1.0:
			bad.append("%.2fx: gold '%s' needs %.0f in a %.0f band"
				% [scale, gold.text, drawn, asked])
	assert_eq(bad, [], "the gold readout must fit the band the layout asked for: %s" % [bad])


## FLOOR for the preset derivation — without it an empty list makes every preset loop above iterate
## ZERO times and pass, which is the shrinking-corpus shape a derived guard fails into silently.
func test_the_preset_list_derives_from_settings() -> void:
	var p: Array = _presets()
	assert_gt(p.size(), 1,
		"FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must still resolve and hold more than one step — a "
		+ "rename leaves every preset loop here iterating nothing and passing. Got " + str(p))
	assert_true(p.has(1.0), "the derived presets must include the 1.0 default: " + str(p))
