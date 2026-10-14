extends GutTest

## ⛔ THE AUTOBATTLE RULE GRID IGNORED TEXT SIZE — 38 raw font sites, zero `TextScale`, on the
## screen whose mastery the project calls the game itself ("Mastering autobattle scripting IS the
## game"). Every condition and action a player writes was rendered at a fixed 11px.
##
## ⛔ AND THE CELLS ARE A FIXED 110x44 GRID, so scaling the fonts alone overflows them. The height
## is now DERIVED and the width deliberately is NOT: this grid scrolls vertically only, so a wider
## grid would put cells permanently out of reach, while a taller one is already absorbed.
##
## 🔑 The budget is MEASURED through the same break rule the labels draw with. Scaling the authored
## 44 by the font factor under-reserved by 5px at 2.0x -- a bigger font at a FIXED width spends its
## growth on line count, which outruns the factor.

const GE := "res://src/ui/autobattle/AutobattleGridEditor.gd"
## ⛔ DERIVED FROM THE CONSUMER'S OWN LIST, NOT A COPY. A hardcoded [0.8, 1.0, 1.25, 1.5, 2.0] goes
## quietly stale the day a preset is added, and the arms below then never visit the new step. NO
## FALLBACK DEFAULT: a rename must red, and a fallback would make these pass against a ladder the
## player cannot select.
static func _presets() -> Array:
	var consts: Dictionary = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map()
	return consts.get("TEXT_SIZE_PRESETS", [])

## Two rules whose cells carry real wrapped text, including the hard newline an action row builds.
const RULES: Array = [
	{"enabled": true,
	 "conditions": [{"type": "hp_percent", "op": "<", "value": 50}],
	 "actions": [{"type": "ability", "id": "cure", "target": "lowest_hp_ally"},
		{"type": "attack", "target": "enemy"}]},
	{"enabled": true,
	 "conditions": [{"type": "mp_percent", "op": ">", "value": 25}],
	 "actions": [{"type": "ability", "id": "fire", "target": "enemy"}]},
	## ⛔ A SINGLE UNBREAKABLE TOKEN, and the guard is toothless without it. With only ordinary
	## multi-word text, AUTOWRAP_WORD and AUTOWRAP_WORD_SMART produce the SAME lines, so reverting
	## the wrap mode changed nothing and that mutation passed. One long word is the whole
	## difference between the two rules.
	{"enabled": true,
	 "conditions": [{"type": "hp_percent", "op": "<", "value": 10}],
	 "actions": [{"type": "ability", "id": "unbreakablethaumaturgy", "target": "enemy"}]},
]

## ⛔ SHORT TEXT ON PURPOSE, for the floor arm only. `_cell_h` takes the MAX across cells, so the
## long token in RULES dominates and the measured requirement never dips under 44 -- which leaves
## the floor carrying nothing and its mutation inert. Here every cell is one short line, so 44 is
## held by the floor and by nothing else.
const SHORT_RULES: Array = [
	{"enabled": true,
	 "conditions": [{"type": "always"}],
	 "actions": [{"type": "attack", "target": "enemy"}]},
]

var _saved = null


func before_each() -> void:
	AutobattleSystem._test_disable_persistence = true
	_saved = GameState.text_size_scale if "text_size_scale" in GameState else null


func after_each() -> void:
	AutobattleSystem._test_disable_persistence = false
	if _saved != null:
		GameState.text_size_scale = _saved


func _editor_at(scale: float, rules_in: Array = []) -> Control:
	GameState.text_size_scale = scale
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	var layer := CanvasLayer.new()
	vp.add_child(layer)
	var ed: Control = load(GE).new()
	ed.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(ed)
	await get_tree().process_frame
	ed.setup("fighter", "Fighter")
	ed.rules = (rules_in if not rules_in.is_empty() else RULES).duplicate(true)
	ed._refresh_grid()
	await get_tree().process_frame
	await get_tree().process_frame
	return ed


## Every Label inside a grid cell, with the cell that must contain it.
func _cell_labels(ed: Control) -> Array:
	var out: Array = []
	for cell in ed._grid_container.get_children():
		if not (cell is Control) or not (cell as Control).has_meta("cell_type"):
			continue
		for c in (cell as Control).get_children():
			if c is Label:
				out.append({"cell": cell as Control, "label": c as Label})
	return out


## ⛔ THE BREAK RULE IS READ OFF THE LABEL, NEVER OFF THE SUBJECT'S OWN CONSTANT. The first version
## of arm 3 measured with `CELL_TEXT_BREAK` -- the very value the fix chose -- so reverting the
## labels to AUTOWRAP_WORD changed nothing it looked at and the mutation PASSED. A guard fed by the
## thing it is judging only ever agrees with it.
func _break_flags_of(l: Label) -> int:
	match l.autowrap_mode:
		TextServer.AUTOWRAP_ARBITRARY:
			return TextServer.BREAK_MANDATORY | TextServer.BREAK_GRAPHEME_BOUND
		TextServer.AUTOWRAP_WORD:
			return TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
		TextServer.AUTOWRAP_WORD_SMART:
			return TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND \
				| TextServer.BREAK_GRAPHEME_BOUND
		_:
			return TextServer.BREAK_MANDATORY


func test_the_grid_builds_with_cells() -> void:
	var ed: Control = await _editor_at(1.0)
	var pairs: Array = _cell_labels(ed)
	assert_gt(pairs.size(), 4,
		"PRECONDITION: the fixture must build real cells, got %d" % pairs.size())


## ARM 1 — the font GREW. A fit-only arm passes on the raw-literal defect by construction, because
## 11px fits a 44px cell at every setting.
func test_the_cell_font_follows_the_setting() -> void:
	var small: Control = await _editor_at(0.8)
	var s_px: int = int((_cell_labels(small)[0]["label"] as Label).get_theme_font_size("font_size"))
	var big: Control = await _editor_at(2.0)
	var b_px: int = int((_cell_labels(big)[0]["label"] as Label).get_theme_font_size("font_size"))
	assert_gt(b_px, s_px,
		"cell text must GROW with Text Size: 80%% gave %d, 200%% gave %d" % [s_px, b_px])


## ARM 2 — the DRAWN text fits its cell vertically, at every preset rather than the endpoints.
## Drawn height is line_count * line_height: a wrapping Label's `size` is a MINIMUM and over-reports
## (@cowir-autogrind measured 252px of rect drawing one line), so asserting on the rect reds correct
## layout.
func test_no_cell_text_overflows_its_cell_at_any_preset() -> void:
	var bad: Array = []
	for scale in _presets():
		var ed: Control = await _editor_at(float(scale))
		var h: float = float(ed._cell_h())
		for pair in _cell_labels(ed):
			var l: Label = pair["label"] as Label
			var drawn: float = float(l.get_line_count()) * float(l.get_line_height())
			if drawn > h:
				bad.append("%.2fx: '%s' draws %.0f in a %.0f cell"
					% [scale, l.text.replace("\n", "/"), drawn, h])
	assert_eq(bad, [], "cell text must fit its cell at every Text Size step: %s" % [bad])


## ARM 3 — and horizontally, measured THROUGH THE WRAP. The width is fixed by design, so the wrap
## rule is the only thing keeping text inside it; `get_string_size` on the raw text answers about
## UNWRAPPED glyphs and reports a false overflow (it told me +13 where the label draws none).
func test_no_cell_text_spills_sideways_at_any_preset() -> void:
	var bad: Array = []
	for scale in _presets():
		var ed: Control = await _editor_at(float(scale))
		for pair in _cell_labels(ed):
			var l: Label = pair["label"] as Label
			var fnt: Font = l.get_theme_font("font")
			if fnt == null:
				continue
			var px: int = l.get_theme_font_size("font_size")
			var wrapped: float = fnt.get_multiline_string_size(l.text,
				HORIZONTAL_ALIGNMENT_CENTER, l.size.x, px, -1, _break_flags_of(l)).x
			if wrapped > l.size.x + 1.0:
				bad.append("%.2fx: '%s' wraps to %.0f in a %.0f box"
					% [scale, l.text.replace("\n", "/"), wrapped, l.size.x])
	assert_eq(bad, [], "wrapped cell text must stay inside its box: %s" % [bad])


## ARM 4 — the floor, in the ONE direction it is actually a claim. This arm first asserted that
## 100% renders the authored 44 exactly, and the fixture's long token red it at 56. The measurement
## settled which was wrong, and it was the ARM: across all 289 real abilities the tallest action
## text needs 56px in a 44px cell AT THE SHIPPED 11px DEFAULT -- "Create Autobattle Script" wraps
## to three lines and overflows today, with Text Size never touched. Pinning 44 at 100% would have
## pinned that overflow in place. What IS a claim is that the floor never yields DOWNWARD: a text
## size may only ever grow a box (@cowir-autogrind's 0.8x regression), so no preset may render a
## cell shorter than the authored 44, and the height must never shrink as the setting rises.
func test_the_cell_height_only_ever_grows() -> void:
	var consts: Dictionary = (load(GE) as GDScript).get_script_constant_map()
	assert_true(consts.has("CELL_HEIGHT"),
		"FLOOR: the authored CELL_HEIGHT must still exist, or this arm is vacuous")
	var authored: int = int(consts.get("CELL_HEIGHT", -1))
	var seen: Array = []
	for scale in _presets():
		var ed: Control = await _editor_at(float(scale), SHORT_RULES)
		var h: int = int(ed._cell_h())
		assert_gte(h, authored,
			"at %.2fx the cell height %d must not fall below the authored %d" % [scale, h, authored])
		seen.append(h)
	for i in range(1, seen.size()):
		assert_gte(int(seen[i]), int(seen[i - 1]),
			"the cell height must never SHRINK as Text Size rises: %s across %s" % [seen, _presets()])


## ARM 6 — THE REAL DOMAIN, EXHAUSTIVELY. Every ability in the table, not the longest one.
##
## ⛔ ITS FIRST VERSION DROVE ONLY THE LONGEST-BY-CHARACTER-COUNT ABILITY, AND THAT MISSED A REAL
## SHIPPED DEFECT. The grid went out in `.690` with `CELL_TEXT_BREAK` set to GRAPHEME_BOUND while
## the cells wrap WORD_SMART (whose rule is ADAPTIVE). Measured exhaustively afterwards:
##     150%   5 abilities derived a cell SHORTER than the Label draws  (54 vs 69)
##     200%  15 abilities                                             (101 vs 124)
## `Create Autobattle Script`, `Masterite Proclamation`, `Crown Authority` -- NONE of them the
## longest string, which is why a worst-by-length corpus of one could not see it. The two flag sets
## only diverge where a token exceeds the cell, and 74 abilities do at 200%; the arm checked one.
## @cowir-autogrind named both the hazard and this cure: drive EVERY id, it costs seconds.
func test_every_real_ability_fits_the_cell_it_derives() -> void:
	var ab: Dictionary = JobSystem.abilities if "abilities" in JobSystem else {}
	assert_gt(ab.size(), 50, "PRECONDITION: the ability table must be loaded, got %d" % ab.size())
	var bad: Array = []
	for scale in _presets():
		var ed: Control = await _editor_at(float(scale))
		var fnt: Font = ed.get_theme_font("font", "Label")
		if fnt == null:
			continue
		var px: int = TextScale.scaled(11)
		var inner: float = float(ed.CELL_WIDTH - 12)
		var brk: int = (load(GE) as GDScript).get_script_constant_map()["CELL_TEXT_BREAK"]
		var probe := Label.new()
		probe.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		probe.add_theme_font_size_override("font_size", px)
		ed.add_child(probe)
		probe.size = Vector2(inner, 20.0)
		for aid in ab.keys():
			var text: String = ed._format_action({"type": "ability", "id": str(aid),
				"target": "enemy"})
			probe.text = text
			await get_tree().process_frame
			var drawn: float = float(probe.get_line_count()) * float(probe.get_line_height())
			var budget: float = fnt.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER,
				inner, px, -1, brk).y + 8.0
			if budget < drawn:
				bad.append("%.2fx: '%s' derives %.0f, draws %.0f"
					% [scale, str(aid), budget, drawn])
		probe.queue_free()
	assert_eq(bad, [],
		"every ability's cell budget must cover what its Label draws -- a budget measured under "
		+ "different break flags than the node wraps with comes out SHORT: %s" % [bad.slice(0, 6)])


## FLOOR for the preset derivation — without it an empty list makes every preset loop above iterate
## ZERO times and pass, which is the shrinking-corpus shape a derived guard fails into silently.
func test_the_preset_list_derives_from_settings() -> void:
	var p: Array = _presets()
	assert_gt(p.size(), 1,
		"FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must still resolve and hold more than one step — a "
		+ "rename leaves every preset loop here iterating nothing and passing. Got " + str(p))
	assert_true(p.has(1.0), "the derived presets must include the 1.0 default: " + str(p))
