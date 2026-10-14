extends GutTest
## The autogrind console had 32 hardcoded font sizes and ZERO routed through TextScale, so the whole
## screen ignored the player's Text Size setting while ItemsMenu and its siblings honour it.
##
## ⛔ AND SCALING A FONT WITHOUT GROWING ITS BOX IS THE DEFECT, not the fix (cowir-main's rule, after
## story hit it twice in one day). So every arm below measures the BUILT nodes at every step of
## SettingsMenu.TEXT_SIZE_PRESETS, never the source:
##
##   fonts grew          per label, in the default screen and in the modal
##   nothing collides    no two labels on one parent overlap, each stays in its own box, and
##                       nothing is drawn outside the console
##   every row reachable the grid clips, so the claim is that the cursor can scroll each row in
##
## ⛔ MODE COVERAGE IS PART OF THE CLAIM. 4 of the 32 sites live in _show_permadeath_confirmation, a
## modal the default build never enters, and the rule cells need an authored rule. @cowir-adhoc
## shipped a contrast guard that reported JobMenu clean having built one of its two screens; a
## behavioural guard inherits the blind spots of the STATE you put the scene in.
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const UI := "res://src/ui/autogrind/AutogrindUI.gd"
const SettingsMenuScript = preload("res://src/ui/SettingsMenu.gd")

var _ag: Dictionary
var _scale_was: float = 1.0


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	_scale_was = float(GameState.text_size_scale) if "text_size_scale" in GameState else 1.0


func after_each() -> void:
	if "text_size_scale" in GameState:
		GameState.text_size_scale = _scale_was
	AutogrindState.restore(_ag)


func _party() -> Array[Combatant]:
	var out: Array[Combatant] = []
	for nm in ["Fighter", "Cleric"]:
		var c := Combatant.new()
		autofree(c)
		c.initialize({"name": nm, "max_hp": 100, "max_mp": 50})
		out.append(c)
	return out


## Authored rules, so the cell builders run -- without one the row/cell sizes are never reached.
## ⛔ THE SECOND RULE IS THE ONE THAT EXERCISES THE DERIVED ROW HEIGHT. A cell's text is authored
## multi-line ("Use\nPotions") and a real member_ability adds the ability's own name, so the longest
## name the game ships wraps to four lines at 2.0x in a 112px cell -- past any scaled constant. A
## fixture of short rules leaves that derivation unexercised and the arm green either way.
## ⛔ AND THE RETURN IS CHECKED, which `set_autogrind_rules`' own docstring requires: it validates the
## WHOLE set and refuses it entirely on one bad entry, leaving the console to lay out whatever
## defaults the process loaded. My first version named a condition type that does not exist, so five
## arms measured the default grid and passed -- including the mutation that drops the row-height
## derivation, which has nothing to bite on without this rule's long ability name.
func _author_a_rule() -> void:
	var ok: bool = AutogrindSystem.set_autogrind_rules([
		{"enabled": true, "conditions": [{"type": "party_hp_avg", "op": "<", "value": 50}],
		 "actions": [{"type": "heal_party"}]},
		{"enabled": true, "conditions": [{"type": "corruption", "op": ">", "value": 3}],
		 "actions": [{"type": "member_ability", "member": "cleric", "ability": "hallucination_spores"}]},
	])
	assert_true(ok, "FLOOR: the fixture's rules must be ACCEPTED, or every arm measures the default grid")


## ⛔ `modal` IS PART OF THE CLAIM, FOR BOTH ARMS. 4 of the 33 font sites and 6 boxes exist only
## inside _show_permadeath_confirmation, which the default build never enters. @cowir-adhoc shipped a
## contrast guard that reported JobMenu clean having built one of its two screens; a behavioural
## guard inherits the blind spots of the STATE you put the scene in.
func _console(scale: float, modal: bool = false, box: Vector2 = Vector2(1280, 720)) -> Node:
	if "text_size_scale" in GameState:
		GameState.text_size_scale = scale
	_author_a_rule()
	var ui: Node = load(UI).new()
	ui.size = box
	add_child_autofree(ui)
	if ui.has_method("setup"):
		ui.setup(_party())
	await wait_frames(3)
	if modal:
		assert_true(ui.has_method("_show_permadeath_confirmation"), "FLOOR: the modal builder must exist")
		if ui.has_method("_show_permadeath_confirmation"):
			ui._show_permadeath_confirmation()
			await wait_frames(2)
	return ui


## Every text node, for the font-GREW arm: the setting must reach all of them.
func _labels(n: Node, acc: Array) -> Array:
	if n is Label or n is RichTextLabel:
		acc.append(n)
	for c in n.get_children():
		_labels(c, acc)
	return acc


func _font_of(l: Control) -> int:
	return int(l.get_theme_font_size("font_size" if l is Label else "normal_font_size"))


## BEHAVIOURAL, not a source scan: a guard that greps for TextScale certifies spelling. This builds
## the screen twice and requires the rendered font sizes to actually differ.
## ⛔ PER LABEL, NEVER A SUM. The modal's four sites disappear into a total the other twenty-eight
## carry upward -- the arm would pass on the exact regression it exists to catch.
func test_the_console_text_grows_with_the_setting() -> void:
	await _fonts_grow(false)


func test_the_modal_text_grows_with_the_setting() -> void:
	await _fonts_grow(true)


func _fonts_grow(modal: bool) -> void:
	var ladder: Array = SettingsMenuScript.TEXT_SIZE_PRESETS
	var small: Node = await _console(float(ladder[0]), modal)
	var a: Array = _labels(small, [])
	assert_gt(a.size(), 0, "FLOOR: the console must render labels at all (modal=%s)" % modal)
	var was: Array = []
	for l in a:
		was.append(_font_of(l))
	var big: Node = await _console(float(ladder[ladder.size() - 1]), modal)
	var b: Array = _labels(big, [])
	assert_eq(b.size(), a.size(), "FLOOR: both builds must render the same labels to pair them")
	if b.size() != a.size():
		return
	for i in range(b.size()):
		assert_gt(_font_of(b[i]), int(was[i]),
			"'%s' kept font %d at %sx and %sx -- a hardcoded size ignores Text Size" % [
				_short(b[i]), int(was[i]), ladder[0], ladder[ladder.size() - 1]])


## BOTH AXES AT ONCE, AND AGAINST THE OBJECT THAT CAN ACTUALLY COLLIDE.
##
## ⛔ "INSIDE ITS SIZED ANCESTOR" IS HOLLOW ON THIS SCREEN, which is why it is not the only check
## here. The console is absolutely positioned: 28 of the 32 sites are `add_child(self)` on the root,
## so the first sized ancestor is the 1280x720 viewport and a containment walk passes whatever the
## text does. The header's three stats labels are spaced by the literals 80 and 160 (:421-:435); at
## 2.0x "Eff: 1.0x" is wider than an 80px gap and lands ON TOP of "Corr:". Text over text is what a
## player sees, and an intersection test is both axes in one predicate.
##
## ⛔ NEVER `box >= font.get_height()`: a Label clamps its own height up to its content, so authored
## boxes sit under get_height while looking correct and that predicate reds shipped layout
## (cowir-story, measured three times in one file). An explicit `.size =` is a FLOOR, not a cap, and
## is NOT what makes a rect arm hollow -- a Label's rect tracks its glyphs even where a size was
## assigned. What makes one hollow is a node whose minimum does not derive from text: a RichTextLabel
## without fit_content (`_battle_log` scrolls instead) keeps the box it was handed, so it is out of
## the fit population and the font-GREW arm covers it instead. ⚠️ A `clip_text` Label would belong
## here too, but only in the HORIZONTAL axis: it collapses the WIDTH minimum while the height
## minimum stays line-height driven (@cowir-controller measured four configurations; @cowir-adhoc
## retracted the "takes the text out of the minimum entirely" version I had copied here). This
## screen sets `clip_text` nowhere, so nothing here turns on it.
## THE DRAWN RECT, NOT THE NODE'S. A wrapping Label's size is a MINIMUM wrapped at its longest word,
## so it barely moves with the font: the hint strip reported 252px of rect at 1.0x and 504 at 2.0x
## while drawing ONE line and three. `get_line_count() * get_line_height()` is the height a player
## sees, and for single-line non-wrapping text the two agree (@cowir-story measured size.y ==
## get_height there), so one expression covers both populations.
func _rect(l: Label) -> Rect2:
	return Rect2(l.global_position, Vector2(l.size.x, float(l.get_line_count() * l.get_line_height())))


## Visible, non-empty plain Labels: the nodes whose drawn text can land on another's.
func _fit_labels(n: Node, acc: Array) -> Array:
	if n is Label and n.visible and str(n.text).strip_edges() != "":
		acc.append(n)
	for c in n.get_children():
		_fit_labels(c, acc)
	return acc


## The first sized ancestor that is NOT the screen root. A root bound is no bound, and counting one
## as coverage is how a containment arm reports a screen it never judged.
func _real_box(l: Control, root: Node) -> Control:
	var anc: Node = l.get_parent()
	while anc != null and anc != root:
		if anc is Control and (anc as Control).size.x > 0.0 and (anc as Control).size.y > 0.0:
			return anc as Control
		anc = anc.get_parent()
	return null


func _short(l: Control) -> String:
	return str(l.text).replace("\n", " ").substr(0, 28)


## ⛔ SWEEPS EVERY PRESET, DERIVED FROM SettingsMenu.TEXT_SIZE_PRESETS -- not 200% alone.
## @cowir-adhoc assumed 200% from reading the constants and their mutation showed the field menu
## already broken at 125%; a guard that only tests the extreme reports the wrong threshold, and a new
## preset added to that const is covered here the day it lands.
func test_nothing_collides_at_any_text_size() -> void:
	var presets: Array = SettingsMenuScript.TEXT_SIZE_PRESETS
	assert_gt(presets.size(), 2, "FLOOR: the preset ladder must have been read, not assumed")
	for scale in presets:
		await _check_fit_at(float(scale), false)


## MODE COVERAGE for the fit half too: the modal is four more labels in a box of its own.
func test_the_modal_does_not_collide_at_any_text_size() -> void:
	for scale in SettingsMenuScript.TEXT_SIZE_PRESETS:
		await _check_fit_at(float(scale), true)


func _check_fit_at(scale: float, modal: bool) -> void:
	var ui: Node = await _console(scale, modal)
	var all: Array = _fit_labels(ui, [])
	assert_gt(all.size(), 0, "FLOOR: nothing to measure at %sx means nothing was proved" % scale)
	var texts: String = ""
	for l in all:
		texts += str(l.text) + "\n"
	assert_true(modal or texts.contains("casts"),
		"FLOOR: at %sx the long member_ability cell is missing, so the tallest row never rendered" % scale)

	# Sibling overlap: the arm that works on an absolutely-positioned screen.
	var by_parent: Dictionary = {}
	for l in all:
		var k: int = l.get_parent().get_instance_id()
		if not by_parent.has(k):
			by_parent[k] = []
		by_parent[k].append(l)
	var pairs: int = 0
	for k in by_parent:
		var group: Array = by_parent[k]
		for i in range(group.size()):
			for j in range(i + 1, group.size()):
				pairs += 1
				var ra: Rect2 = _rect(group[i])
				var rb: Rect2 = _rect(group[j])
				assert_false(ra.intersects(rb),
					"at %sx Text Size '%s' is drawn ON TOP of '%s' -- grown text in a gap that did not grow (%s vs %s)" % [
						scale, _short(group[i]), _short(group[j]), str(ra), str(rb)])
	assert_gt(pairs, 0, "FLOOR: at %sx no two labels shared a parent, so nothing was compared" % scale)

	# Containment, for the labels that do have a box of their own (the rule cells, the party rows).
	# ⛔ A CLIPPING box is skipped, not asserted: the engine cannot draw outside it, so "runs past its
	# box" is not a thing a player can see there. What matters inside the grid is that the cursor can
	# BRING a row into view, which is test_every_rule_row_can_be_brought_into_view.
	var boxed: int = 0
	var clipped: int = 0
	for l in all:
		var box: Control = _real_box(l, ui)
		if box == null:
			continue
		if box.clip_contents:
			clipped += 1
			continue
		boxed += 1
		var want: Rect2 = Rect2(box.global_position, box.size)
		assert_true(want.grow(0.5).encloses(_rect(l)),
			"at %sx Text Size, '%s' %s runs outside its own %s box" % [
				scale, _short(l), str(_rect(l)), str(want)])
	assert_gt(boxed, 0, "FLOOR: at %sx not one label had a non-root box, so containment proved nothing" % scale)

	# Off the screen is the other way grown text disappears: the footer strip measured 1050px wide
	# at 2.0x inside a 1280px console, and no ancestor walk can see that -- the root IS the bound.
	# ⛔ READ IT FROM THE VIEWPORT, which is what _build_ui lays out against (`get_visible_rect()` at
	# :364). Asserting against `ui.size` only worked because I had assigned the same 1280x720 the
	# headless viewport happens to have -- a bound that agrees with the subject by coincidence.
	var screen := (ui as Control).get_viewport().get_visible_rect()
	assert_gt(screen.size.x, 0.0, "FLOOR: the viewport must have a size for the screen bound to mean anything")
	for l in all:
		assert_true(screen.grow(0.5).encloses(_rect(l)),
			"at %sx Text Size, '%s' %s is drawn outside the %s console" % [
				scale, _short(l), str(_rect(l)), str(screen.size)])


## ⛔ THE OTHER HALF OF A CLIPPED CONTAINER: clipping stops the overdraw and hides the row instead,
## which is only acceptable because the cursor scrolls it back. The grid never had a viewport, so
## rows past its bottom drew OVER the start button -- at eight rules today, and at two once a 200%
## text size makes each row taller. This arm is the reachability claim, at every preset.
func test_every_rule_row_can_be_brought_into_view() -> void:
	for scale in SettingsMenuScript.TEXT_SIZE_PRESETS:
		var ui: Node = await _console(float(scale))
		var box: Control = ui._grid_container
		assert_true(box != null, "FLOOR: the grid container must exist to scroll inside")
		if box == null:
			return
		assert_gt(box.size.y, 0.0, "FLOOR: the grid viewport must have a height")
		assert_gt(int(ui.rules.size()), 1, "FLOOR: one row cannot demonstrate scrolling")
		var judged: int = 0
		for row in range(int(ui.rules.size())):
			ui.cursor_row = row
			ui.cursor_col = 0
			ui._update_cursor()
			await wait_frames(2)
			var view: Rect2 = Rect2(box.global_position, box.size)
			for c in box.get_children():
				if not (c is Control) or not c.has_meta("cell_type"):
					continue
				if int(c.get_meta("row", -1)) != row or str(c.get_meta("cell_type")) != "condition":
					continue
				judged += 1
				var r: Rect2 = Rect2((c as Control).global_position, (c as Control).size)
				assert_true(view.grow(0.5).encloses(r),
					"at %sx the cursor sits on row %d and that row is still outside the grid's viewport (%s vs %s)" % [
						scale, row, str(r), str(view)])
		assert_gt(judged, 0, "FLOOR: at %sx not one row cell was found, so nothing was judged" % scale)


## A row TALLER than the viewport, which a big enough text size in a small enough grid produces:
## bottom-aligning it alone leaves its TOP off the screen, so the tall case must resolve to the top
## and hold. ⚠️ TEETH, NAMED HONESTLY: reverting the clamp to two independent `if`s does NOT red this
## arm -- the second clamp corrects the first within one pass, so both forms converge, and I had
## written the opposite into a comment before measuring it. What reds it is bottom-align ALONE
## (got 240, wanted 160), which is the implementation a reader would reach for first.
func test_a_row_taller_than_the_viewport_settles() -> void:
	var ladder: Array = SettingsMenuScript.TEXT_SIZE_PRESETS
	var ui: Node = await _console(float(ladder[ladder.size() - 1]))
	var box: Control = ui._grid_container
	assert_true(box != null, "FLOOR: the grid container must exist")
	if box == null:
		return
	var row_h: float = ui._grid_row_height()
	# ⛔ `ui.size` does not reach this layout -- _build_ui reads the VIEWPORT (:364), so a smaller
	# console cannot be had that way. Shrinking the container is what a smaller window does to it.
	box.size.y = 40.0
	assert_gt(row_h, box.size.y,
		"FLOOR: this fixture must actually produce a row taller than the viewport (row %s, view %s)" % [row_h, box.size.y])
	ui.cursor_row = int(ui.rules.size()) - 1
	ui.cursor_col = 0
	ui._update_cursor()
	await wait_frames(2)
	var settled: float = float(ui._grid_scroll)
	assert_almost_eq(settled, float(ui.cursor_row) * (row_h + ui._grew(20)), 1.0,
		"a row taller than the viewport must come to rest with its TOP in view")
	ui._update_cursor()
	await wait_frames(2)
	assert_almost_eq(float(ui._grid_scroll), settled, 0.001,
		"and the next pass must agree -- a scroll that keeps changing rebuilds and re-enters itself")


## ⛔ MY FIXTURE AUTHORS TWO RULES; A PLAYER AUTHORS ANY OF THEM. @cowir-sfx's variant arm tested only
## the keys spelled as literals and was blind to the 39 that arrive from data -- mine would be blind
## to every ability name I did not happen to try, and the one I DID try ("Hallucination Spores", the
## longest single token of the 289) was chosen by me. So this drives the real builder for EVERY
## ability at the largest preset: the claim is that the derivation is text-INDEPENDENT, which is only
## worth anything if the whole population is put through it.
func test_every_ability_name_fits_its_own_action_cell() -> void:
	var ids: Array = _all_ability_ids()
	assert_gt(ids.size(), 250, "CONTROL: abilities.json was read (%d)" % ids.size())
	var ladder: Array = SettingsMenuScript.TEXT_SIZE_PRESETS
	var ui: Node = await _console(float(ladder[ladder.size() - 1]))
	var font_probe := Label.new()
	add_child_autofree(font_probe)
	var f: Font = font_probe.get_theme_font("font")
	assert_true(f != null, "FLOOR: the theme font must resolve, or every height below is zero")
	if f == null:
		return
	var over: Array = []
	var judged: int = 0
	for id in ids:
		var action: Dictionary = {"type": "member_ability", "member": "cleric", "ability": str(id)}
		var text: String = ui._format_action(action)
		var w: float = ui._action_text_width(action)
		var h: float = ui._wrapped_cell_text_height(f, text, w)
		var cell: Control = ui._create_action_cell(0, 0, action, h)
		add_child_autofree(cell)
		await wait_frames(1)
		for c in cell.get_children():
			if not (c is Label) or str((c as Label).text) == "":
				continue
			judged += 1
			var l := c as Label
			var drawn: Vector2 = Vector2(l.size.x, float(l.get_line_count() * l.get_line_height()))
			if l.position.x + drawn.x > w + 24.5 or l.position.y + drawn.y > h - 3.5:
				over.append("%s: %s of text in a %s cell" % [id, str(drawn), str(Vector2(w, h))])
	assert_gt(judged, 250, "FLOOR: a cell was measured for every ability (%d of %d)" % [judged, ids.size()])
	assert_eq(over, [], "%d ability name(s) overflow their own derived cell: %s" % [over.size(), str(over.slice(0, 5))])


func _all_ability_ids() -> Array:
	var fa := FileAccess.open("res://data/abilities.json", FileAccess.READ)
	if fa == null:
		return []
	var parsed = JSON.parse_string(fa.get_as_text())
	var root: Dictionary = parsed.get("abilities", parsed) if parsed is Dictionary else {}
	var out: Array = []
	for id in root:
		if root[id] is Dictionary:
			out.append(str(id))
	out.sort()
	return out
