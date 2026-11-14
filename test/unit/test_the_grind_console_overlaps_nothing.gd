extends GutTest

## struktured: "make sure nothing ever overlaps unless we intend it" (main 23389). The autogrind console is judged by the
## shared helper (test/unit/helpers/overlap_audit.gd) at every Text Size, on the default screen AND inside the permadeath
## modal, with an authored rule set so the rule cells are built. An intended overlap is DECLARED with its reason.
## The modal covers the console by design behind a 70% dim, so in that mode only the dialog itself is judged.

const OverlapAudit = preload("res://test/unit/helpers/overlap_audit.gd")
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const UI := "res://src/ui/autogrind/AutogrindUI.gd"

## Intended overlaps, {"a|b": "reason"}, each from a census (.799, census 2).
const DECLARED := {
	"Cursor/*|Grid/R0Or": "the selection ring is drawn 3 px outside its cell on top of everything (z 10); the OR badge fills the whole row gap, so the ring crosses the badge's top 3 px",
	"Cursor/*|Grid/R0OrText": "at 80/100% the ring crosses the top 1 px of the OR label's BOX; its letters clear the ring (test_the_cursor_ring_never_touches_the_or_letters)",
}

var _ag: Dictionary
var _scale_was: float = 1.0


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	_scale_was = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _scale_was
	AutogrindState.restore(_ag)


func _presets() -> Array:
	var p: Array = load("res://src/ui/SettingsMenu.gd").get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	return p


func _party() -> Array[Combatant]:
	var out: Array[Combatant] = []
	for nm in ["Fighter", "Cleric"]:
		var c := Combatant.new()
		autofree(c)
		c.initialize({"name": nm, "max_hp": 100, "max_mp": 50})
		out.append(c)
	return out


## The second rule carries the longest ability name the game ships, so a rule cell wraps at the largest Text Size.
func _author_a_rule() -> bool:
	return AutogrindSystem.set_autogrind_rules([
		{"enabled": true, "conditions": [{"type": "party_hp_avg", "op": "<", "value": 50}],
		 "actions": [{"type": "heal_party"}]},
		{"enabled": true, "conditions": [{"type": "corruption", "op": ">", "value": 3}],
		 "actions": [{"type": "member_ability", "member": "cleric", "ability": "hallucination_spores"}]},
	])


func _console(scale: float, modal: bool) -> Control:
	GameState.text_size_scale = scale
	assert_true(_author_a_rule(), "FLOOR: the fixture's rules must be ACCEPTED, or this judges the default grid")
	var ui: Control = load(UI).new()
	ui.size = Vector2(1280, 720)
	add_child_autofree(ui)
	ui.setup(_party())
	await wait_frames(3)
	if modal:
		ui._show_permadeath_confirmation()
		await wait_frames(2)
	return ui


func test_the_floor_names_every_member_this_file_drives() -> void:
	assert_gte(_presets().size(), 2, "SettingsMenu.TEXT_SIZE_PRESETS must exist and offer a choice (%s)" % [_presets()])
	var audit: Array = (OverlapAudit as GDScript).get_script_method_list().map(func(m): return str(m["name"]))
	for f in ["surfaces", "collisions", "stale"]:
		assert_has(audit, f, "overlap_audit.%s must exist" % f)
	var ui: Array = (load(UI) as GDScript).get_script_method_list().map(func(m): return str(m["name"]))
	for f in ["setup", "_show_permadeath_confirmation"]:
		assert_has(ui, f, "AutogrindUI.%s must exist" % f)
	assert_has(audit, "is_frame_joint", "overlap_audit.is_frame_joint must exist (the console frames are 2 px strips)")


## CONTROL: the judge can say yes on THIS screen. A label planted over the console's first surface is reported.
func test_a_planted_overlap_is_reported() -> void:
	var ui := await _console(1.0, false)
	var surfs: Array = OverlapAudit.surfaces(ui)
	assert_gt(surfs.size(), 3, "CONTROL: the console has surfaces to judge (%d)" % surfs.size())
	var first: Rect2 = surfs[0]["rect"]
	var plant := Label.new()
	plant.name = "Planted"
	plant.text = "PLANTED"
	ui.add_child(plant)
	plant.global_position = first.position
	plant.size = Vector2(maxf(first.size.x, 20.0), maxf(first.size.y, 12.0))
	await get_tree().process_frame
	var hits: Array = OverlapAudit.collisions(OverlapAudit.surfaces(ui), {})
	assert_true(hits.any(func(h): return str(h).contains("Planted")), "a label over %s is a finding: %s" % [surfs[0]["id"], hits])


## The subtree a mode is judged on: the whole console, or the permadeath dialog alone.
func _judged(ui: Control, modal: bool) -> Node:
	return ui.find_child("PermadeathDialog", true, false) if modal else ui


## Ink rows [top, bottom] of a Label's own text in screen space: each glyph's rendered bitmap against the baseline.
func _ink_rows(l: Label) -> Vector2:
	var f: Font = l.get_theme_font("font")
	var px: int = l.get_theme_font_size("font_size")
	var ts := TextServerManager.get_primary_interface()
	var rid := ts.create_shaped_text()
	ts.shaped_text_add_string(rid, l.text, f.get_rids(), px)
	var base: float = l.get_global_transform_with_canvas().origin.y + f.get_ascent(px)
	var top := INF
	var bottom := -INF
	for g in ts.shaped_text_get_glyphs(rid):
		var fr: RID = g["font_rid"]
		if not fr.is_valid():
			continue
		ts.font_render_glyph(fr, Vector2i(px, 0), int(g["index"]))
		var off: Vector2 = ts.font_get_glyph_offset(fr, Vector2i(px, 0), int(g["index"]))
		var sz: Vector2 = ts.font_get_glyph_size(fr, Vector2i(px, 0), int(g["index"]))
		if sz.y <= 0.0:
			continue
		top = minf(top, base + off.y)
		bottom = maxf(bottom, base + off.y + sz.y)
	ts.free_rid(rid)
	return Vector2(top, bottom)


## The DECLARED R0OrText entry says the ring crosses the label's box but not its letters. This is that measurement, at
## every Text Size: the cursor's lower band against the ink of "OR".
func test_the_cursor_ring_never_touches_the_or_letters() -> void:
	var gaps: Array = []
	for s in _presets():
		var ui := await _console(float(s), false)
		var text := ui.find_child("R0OrText", true, false) as Label
		var cursor := ui.find_child("Cursor", true, false) as Control
		assert_not_null(text, "FLOOR: the OR label is built at %s" % s)
		assert_true(cursor != null and cursor.get_child_count() >= 2, "FLOOR: the cursor ring is built at %s" % s)
		if text == null or cursor == null or cursor.get_child_count() < 2:
			continue
		var band: Rect2 = OverlapAudit.screen_rect(cursor.get_child(1) as Control)
		var ink: Vector2 = _ink_rows(text)
		assert_gt(ink.y - ink.x, 2.0, "CONTROL: OR has ink at %s (%s)" % [s, ink])
		gaps.append("%s: ring to %.1f, ink from %.1f" % [s, band.end.y, ink.x])
		assert_gte(ink.x - band.end.y, 0.99, "the ring clears the OR letters by a pixel at %s: %s" % [s, gaps.back()])
		ui.queue_free()
		await get_tree().process_frame
	gut.p("cursor ring -> OR ink: %s" % [gaps])


func test_nothing_in_the_grind_console_overlaps_at_any_text_size() -> void:
	var used := {}
	var found: Array = []
	var judged := {}
	for modal in [false, true]:
		for s in _presets():
			var ui := await _console(float(s), modal)
			var root: Node = _judged(ui, modal)
			assert_not_null(root, "FLOOR: the %s judged root exists at %s" % ["modal" if modal else "console", s])
			if root == null:
				continue
			var surfs: Array = OverlapAudit.surfaces(root)
			judged["%s/%s" % [modal, s]] = surfs.size()
			for hit in OverlapAudit.collisions(surfs, DECLARED, used):
				found.append("%s %s%%: %s" % ["modal" if modal else "console", int(roundf(float(s) * 100.0)), hit])
			ui.queue_free()
			await get_tree().process_frame
	assert_eq(judged.size(), 2 * _presets().size(), "CONTROL: every preset was built in both modes (%s)" % [judged])
	assert_true(judged.values().all(func(n): return int(n) > 3), "CONTROL: every build had surfaces to judge (%s)" % [judged])
	assert_eq(found, [], "every overlap in the grind console is declared with a reason:\n%s" % "\n".join(PackedStringArray(found.map(func(x): return str(x)))))
	assert_eq(OverlapAudit.stale(DECLARED, used), [], "every declared overlap still happens and says why")
