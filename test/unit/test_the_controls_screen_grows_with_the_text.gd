extends GutTest

## ⛔ THE CONTROLS SCREEN IGNORED TEXT SIZE — 28 raw font sizes, zero `TextScale`, on the screen a
## player opens BECAUSE a control is wrong. Its sibling, the F1 reference, was the same defect.
##
## ⛔ AND SCALING THE FONTS ALONE IS A SILENT NO-OP FOR THE THREE BINDING COLUMNS.
## `_fit_column_label` steps a binding label's font DOWN to a floor of 10 until it fits its column,
## then clips with an ellipsis -- so a raised override is taken straight back off and the player
## sees NOTHING change. Two writers, one surface, the later one wins. The columns must widen with
## the text or the text does not grow at all, and ARM 6 is the arm that defends it.
##
## 🔑 The geometry is derived on BOTH axes and the authored layout is the f==1 case of the SAME
## arithmetic: 12 + name, 320 + 160 + 10 == 490, 490 + 110 + 10 == 610 are the literals it replaces.
## Measured, every preset, vertical and horizontal overflow zero:
##     0.80x panel 768  rh 32    1.00x panel 768  rh 32  <- authored exactly
##     1.25x panel 848  rh 32    1.50x panel 951  rh 32
##     2.00x panel 1156 rh 30  font 15 of a wanted 28
##
## ⚠️ THE HONEST LIMIT, pinned by ARM 7 rather than buried here: at 2.0x the rows reach font 15,
## not 28. 14 rows do not scroll, and 14 full-size rows plus the three bands need ~782px of a 720px
## viewport. Reachability outranks size on a screen with no scrollbar, so the text grows as far as
## it fits and stops. True 2.0x here needs scrolling, which is a separate item.

const CM := "res://src/ui/ControlsMenu.gd"
## ⛔ DERIVED FROM THE CONSUMER'S OWN LIST, NOT A COPY. A hardcoded [0.8, 1.0, 1.25, 1.5, 2.0] goes
## quietly stale the day a preset is added, and the arms below then never visit the new step. NO
## FALLBACK DEFAULT: a rename must red, and a fallback would make these pass against a ladder the
## player cannot select.
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
	var m: Control = load(CM).new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame
	return m


## ⛔ SNAPSHOT, because every derived value here reads `TextScale` AT CALL TIME. Holding two menus
## and asking each for `_col_w()` afterwards returns the CURRENT scale's answer for both -- my first
## version of arms 1/6/7 compared 0.8x against 2.0x and read the same numbers twice, which showed
## up only because the column assert demanded strict growth and got 320 vs 320. Values compared
## across scales must be taken while their own scale is still live.
func _snapshot(m: Control) -> Dictionary:
	var fonts: Array = []
	for pair in _binding_labels(m):
		fonts.append(int((pair["label"] as Label).get_theme_font_size("font_size")))
	return {
		"row_font": int(m._row_font()),
		"want_font": TextScale.scaled(14),
		"row_h": int(m._row_h()),
		"col_w": (m._col_w() as Array).duplicate(),
		"binding_fonts": fonts,
	}


## The binding-column labels, which are the ones `_fit_column_label` rewrites.
func _binding_labels(m: Control) -> Array:
	var out: Array = []
	var xs: Array = m._col_x()
	for h in m._highlight_refs:
		if not (h and is_instance_valid(h)):
			continue
		for l in (h as Control).get_children():
			if not (l is Label):
				continue
			var lab := l as Label
			for i in range(1, xs.size()):
				if absf(lab.position.x - float(xs[i])) < 2.0 and lab.text != "":
					out.append({"label": lab, "col": i - 1})
	return out


func test_the_screen_builds_its_rows() -> void:
	var m: Control = await _menu_at(1.0)
	assert_gt(m._highlight_refs.size(), 10,
		"PRECONDITION: the menu must build its rows, got %d" % m._highlight_refs.size())


## ARM 1 — the row font GREW, read from snapshots taken at each scale rather than from two live
## nodes, which would both answer with whatever scale is set last.
func test_the_row_font_follows_the_setting() -> void:
	var small: Dictionary = _snapshot(await _menu_at(0.8))
	var big: Dictionary = _snapshot(await _menu_at(2.0))
	assert_gt(int(big["row_font"]), int(small["row_font"]),
		"row text must GROW: 80%% gave %d, 200%% gave %d" % [small["row_font"], big["row_font"]])


## ARM 2 — no binding label spills past its own column, at any preset. Measured as DRAWN text, and
## `_fit_column_label` sets `clip_text`, so an overflow here is text the player loses to an ellipsis.
func test_no_binding_label_spills_its_column_at_any_preset() -> void:
	var bad: Array = []
	for scale in _presets():
		var m: Control = await _menu_at(float(scale))
		var w: Array = m._col_w()
		for pair in _binding_labels(m):
			var lab: Label = pair["label"] as Label
			var fnt: Font = lab.get_theme_font("font")
			if fnt == null:
				continue
			var drawn: float = fnt.get_string_size(lab.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				lab.get_theme_font_size("font_size")).x
			if drawn > float(w[int(pair["col"])]) + 1.0:
				bad.append("%.2fx: '%s' draws %.0f in a %.0f column"
					% [scale, lab.text, drawn, float(w[int(pair["col"])])])
	assert_eq(bad, [], "a binding label must fit its column at every Text Size: %s" % [bad])


## ARM 3 — the rows must not reach the bottom labels, at any preset. This is the arm that the first
## four versions of the fix failed, each for a different missing term.
func test_the_rows_never_reach_the_bottom_labels() -> void:
	var bad: Array = []
	for scale in _presets():
		var m: Control = await _menu_at(float(scale))
		var lowest: float = 0.0
		for h in m._highlight_refs:
			if h and is_instance_valid(h):
				lowest = maxf(lowest, (h as Control).position.y + (h as Control).size.y)
		var limit: float = m._flash_y(m._panel.size.y)
		if lowest > limit:
			bad.append("%.2fx: rows end at %.0f, past the bottom band at %.0f"
				% [scale, lowest, limit])
	assert_eq(bad, [], "no row may reach the conflict/flash/footer band: %s" % [bad])


## ARM 4 — the state the fix did NOT set out to change, in both directions. A derived layout
## replaces literals, so the DEFAULT moves unless the floors hold; 0.8x must not shrink a box
## either. An earlier version of this fix stacked measured heights and shifted 100% by 3px.
func test_the_small_and_default_sizes_render_the_shipped_layout() -> void:
	var consts: Dictionary = (load(CM) as GDScript).get_script_constant_map()
	for key in ["ROW_HEIGHT", "ROW_START_Y"]:
		assert_true(consts.has(key),
			"FLOOR: %s must still exist, or this arm is vacuous" % key)
	## ⛔ DERIVED, NOT `[0.8, 1.0]`. Converting the ladder const left this SECOND literal behind,
	## and it carries no 1.25 so every ladder-keyed census is blind to it — yet this is the arm
	## that decides whether a new SUB-UNITY preset is ever checked (@cowir-music, 2026-10-14).
	var at_or_below: Array = _presets().filter(func(p): return float(p) <= 1.0)
	assert_gt(at_or_below.size(), 1,
		"CONTROL: the sub-unity set must derive more than one step from the shipped ladder, or this loop iterates nothing and passes: " + str(at_or_below))
	for scale in at_or_below:
		var m: Control = await _menu_at(scale)
		assert_eq(int(m._row_h()), int(consts["ROW_HEIGHT"]),
			"at %.0f%% the row height must be the authored %d" % [scale * 100.0, consts["ROW_HEIGHT"]])
		assert_eq(int(m._rows_top()), int(consts["ROW_START_Y"]),
			"at %.0f%% the rows must start at the authored %d" % [scale * 100.0, consts["ROW_START_Y"]])
		assert_eq(int(m._device_y()), 30,
			"at %.0f%% the subtitle must sit at the authored 30" % [scale * 100.0])
		var x: Array = m._col_x()
		assert_eq([int(x[0]), int(x[1]), int(x[2]), int(x[3])], [12, 320, 490, 610],
			"at %.0f%% the columns must be the authored 12/320/490/610" % [scale * 100.0])


## ARM 5 — the mouse HIT REGION and the drawn row must be ONE height. `make_clickable` adds an
## invisible Button child sized (width, height), so THAT is the click target; the first version of
## this arm compared the highlight's height to `_row_h()`, which is the drawn row measured against
## itself -- a tautology, and reverting the hit area to the raw ROW_HEIGHT passed it 8/8. The
## Button's own minimum is 8px, so nothing clamps and the comparison is exact.
func test_the_click_target_matches_the_drawn_row() -> void:
	var bad: Array = []
	for scale in _presets():
		var m: Control = await _menu_at(float(scale))
		for h in m._highlight_refs:
			if not (h and is_instance_valid(h)):
				continue
			var hit: Button = null
			for c in (h as Control).get_children():
				if c is Button:
					hit = c as Button
					break
			if hit == null:
				bad.append("%.2fx: a row has no click target at all" % scale)
				break
			if absf(hit.size.y - (h as Control).size.y) > 0.5:
				bad.append("%.2fx: the click target is %.0f tall where the row draws %.0f"
					% [scale, hit.size.y, (h as Control).size.y])
			break
	assert_eq(bad, [],
		"a click must land on the row under the pointer at every Text Size: %s" % [bad])


## ARM 6 — THE DEFENCE OF THE ACTUAL FINDING, in two halves because the first is not sensitive
## enough alone. Reading the override where it is SET would pass on the broken version, since
## `_fit_column_label` lowers it afterwards; this reads what the label ends up with.
func test_a_binding_labels_effective_font_actually_grows() -> void:
	var small: Dictionary = _snapshot(await _menu_at(0.8))
	var big: Dictionary = _snapshot(await _menu_at(2.0))
	assert_gt((small["binding_fonts"] as Array).size(), 2,
		"PRECONDITION: binding labels must be found (%d)" % (small["binding_fonts"] as Array).size())
	var s_max: int = 0
	for f in (small["binding_fonts"] as Array):
		s_max = maxi(s_max, int(f))
	var b_max: int = 0
	for f in (big["binding_fonts"] as Array):
		b_max = maxi(b_max, int(f))
	assert_gt(b_max, s_max,
		"a binding label's EFFECTIVE font must grow: 80%% ended at %d, 200%% at %d" % [s_max, b_max])
	## ⛔ AND THE MECHANISM, because the check above passed 8/8 against the very defect it names:
	## with the columns pinned at 160/110/120 the fit helper still lands on a larger font at 200%
	## than at 80%. The column WIDTH growing is what the fix actually does, and it is structural
	## rather than a threshold, so it cannot be satisfied by a coincidence.
	var s_w: Array = small["col_w"] as Array
	var b_w: Array = big["col_w"] as Array
	for i in range(s_w.size()):
		assert_gt(float(b_w[i]), float(s_w[i]),
			"binding column %d must WIDEN with the text, or the fit helper claws the font back: "
				% i + "80%% %.0f, 200%% %.0f" % [float(s_w[i]), float(b_w[i])])


## ARM 7 — the documented limit, pinned so it cannot drift into a silent regression. At 2.0x the
## rows deliberately do NOT reach the requested size; what must hold is that they grow at all.
func test_the_capped_size_is_still_an_increase() -> void:
	var base: Dictionary = _snapshot(await _menu_at(1.0))
	var big: Dictionary = _snapshot(await _menu_at(2.0))
	assert_gt(int(big["row_font"]), int(base["row_font"]),
		"200%% must still be bigger than 100%% even though it cannot reach the full request: "
		+ "100%% gave %d, 200%% gave %d" % [base["row_font"], big["row_font"]])
	assert_lt(int(big["row_font"]), int(big["want_font"]),
		"this arm documents a CAP; if 200%% now reaches the full %d the cap is gone and this "
			% int(big["want_font"]) + "file's header is stale")


## FLOOR for the preset derivation — without it an empty list makes every preset loop above iterate
## ZERO times and pass, which is the shrinking-corpus shape a derived guard fails into silently.
func test_the_preset_list_derives_from_settings() -> void:
	var p: Array = _presets()
	assert_gt(p.size(), 1,
		"FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must still resolve and hold more than one step — a "
		+ "rename leaves every preset loop here iterating nothing and passing. Got " + str(p))
	assert_true(p.has(1.0), "the derived presets must include the 1.0 default: " + str(p))
