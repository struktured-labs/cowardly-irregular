extends GutTest

## struktured: "make sure nothing ever overlaps unless we intend it" (main 23389). The field menu is the menu every player
## opens most, so it is the first menu judged by the shared helper (test/unit/helpers/overlap_audit.gd), at every Text
## Size the player can pick. An intended overlap is DECLARED below with its reason; anything else is a finding.

const OverlapAudit = preload("res://test/unit/helpers/overlap_audit.gd")
const OverworldMenuScript = preload("res://src/ui/OverworldMenu.gd")
const CombatantScript = preload("res://src/battle/Combatant.gd")

## Intended overlaps, {"a|b": "reason"}, each from a census and each backed by an arm that measures what the reason claims.
const DECLARED := {
	"GutRunner/NameLabel|GutRunner/JobLabel": "the name's 20-line keeps descender room 2*k px into the job row; the letters clear by a pixel at every Text Size (test_a_name_and_its_job_line_do_not_touch_in_ink)",
	"GutRunner/JobLabel|HPBar/Label#0": "at 150% the job line's box grazes the HP label's box by 1 px of descender room; the letters clear by a pixel (test_a_name_and_its_job_line_do_not_touch_in_ink)",
}


func after_each() -> void:
	if GameState:
		GameState.text_size_scale = 1.0


func _presets() -> Array:
	var p: Array = load("res://src/ui/SettingsMenu.gd").get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	return p


func _menu_at(scale: float) -> Control:
	GameState.text_size_scale = scale
	var party: Array = []
	for n in ["Bram", "Marta", "Theron", "Milo"]:
		var pc = CombatantScript.new()
		pc.combatant_name = n
		add_child_autofree(pc)
		party.append(pc)
	var m = OverworldMenuScript.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(m)
	m.setup(party)
	await get_tree().process_frame
	await get_tree().process_frame
	return m


func test_the_floor_names_every_member_this_file_drives() -> void:
	assert_gte(_presets().size(), 2, "SettingsMenu.TEXT_SIZE_PRESETS must exist and offer a choice (%s)" % [_presets()])
	var audit: Array = (OverlapAudit as GDScript).get_script_method_list().map(func(m): return str(m["name"]))
	for f in ["surfaces", "collisions", "stale", "visible_rect", "is_frame_joint"]:
		assert_has(audit, f, "overlap_audit.%s must exist" % f)
	var menu: Array = (OverworldMenuScript as GDScript).get_script_method_list().map(func(m): return str(m["name"]))
	assert_has(menu, "setup", "OverworldMenu.setup must exist")
	var props: Array = (OverworldMenuScript as GDScript).get_script_property_list().map(func(p): return str(p["name"]))
	assert_has(props, "_party_panels", "OverworldMenu._party_panels must exist (the ink arm reads the built cards)")


## CONTROL: the judge can say yes. A label planted over the menu's first surface is reported, so a clean sweep below means
## the menu is clean, not that the helper sees nothing.
func test_a_planted_overlap_is_reported() -> void:
	var m := await _menu_at(1.0)
	var surfs: Array = OverlapAudit.surfaces(m)
	assert_gt(surfs.size(), 3, "CONTROL: the field menu has surfaces to judge (%d)" % surfs.size())
	var first: Rect2 = surfs[0]["rect"]
	var plant := Label.new()
	plant.name = "Planted"
	plant.text = "PLANTED"
	m.add_child(plant)
	plant.global_position = first.position
	plant.size = Vector2(maxf(first.size.x, 20.0), maxf(first.size.y, 12.0))
	await get_tree().process_frame
	var hits: Array = OverlapAudit.collisions(OverlapAudit.surfaces(m), {})
	assert_true(hits.any(func(h): return str(h).contains("Planted")), "a label over %s is a finding: %s" % [surfs[0]["id"], hits])


func _surf(id: String, node: Node, r: Rect2) -> Dictionary:
	return {"id": id, "rect": r, "node": node}


func _label(t: String, parent: Node) -> Label:
	var l := Label.new()
	l.text = t
	parent.add_child(l)
	return l


## The flat-panel rule, and every shape it must still catch (battle 24944, adhoc 24943). Each finding arm is one hole.
func test_a_flat_panel_owns_its_labels_and_nothing_else() -> void:
	var root := Control.new()
	add_child_autofree(root)
	var card := Control.new()
	root.add_child(card)
	var other := Control.new()
	root.add_child(other)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	card.add_child(bg)
	var panel := _surf("Bg", bg, Rect2(0, 0, 200, 100))
	var on := _surf("On", _label("on", card), Rect2(10, 10, 50, 20))
	assert_eq(OverlapAudit.collisions([panel, on], {}), [], "a label wholly on its own panel, drawn after it, is content")
	assert_eq(OverlapAudit.collisions([panel, _surf("Edge", _label("edge", card), Rect2(180, 10, 50, 20))], {}).size(), 1, "a label hanging off the panel's edge is a finding")
	assert_eq(OverlapAudit.collisions([on, panel], {}).size(), 1, "a panel drawn AFTER a label covers it: a finding")
	assert_eq(OverlapAudit.collisions([panel, _surf("Stray", _label("stray", other), Rect2(10, 40, 50, 20))], {}).size(), 1, "another container's label on this panel is a finding")
	var wide := _surf("Wide", _label("a wide line of text", card), Rect2(0, 0, 200, 20))
	assert_eq(OverlapAudit.collisions([wide, _surf("Over", _label("over", card), Rect2(10, 2, 40, 16))], {}).size(), 1, "text printed over text is a finding")
	var fig := Node2D.new()
	card.add_child(fig)
	assert_eq(OverlapAudit.collisions([panel, _surf("Figure", fig, Rect2(20, 20, 40, 40))], {}).size(), 1, "a figure under a panel is a finding")


## The FLAT shape OverworldMenu really has (adhoc 24948): two panels, their borders and labels all siblings. A label that
## drifted off panel B onto panel A belongs to B, so it is a finding on A; each panel's own label, and a border ring whose
## strips are the same shape as each other, change nothing. Panel B is smaller than A, so A could own B: the drifted label must
## still fail at its own first link (B does not hold it), not be passed up the chain to A.
func test_a_label_that_drifts_onto_another_flat_panel_is_a_finding() -> void:
	var menu := Control.new()
	add_child_autofree(menu)
	var bg_a := ColorRect.new()
	menu.add_child(bg_a)
	var a := _surf("BgA", bg_a, Rect2(0, 0, 200, 100))
	var strip := ColorRect.new()
	menu.add_child(strip)
	var s := _surf("StripA", strip, Rect2(0, 0, 200, 4))
	var strip2 := ColorRect.new()
	menu.add_child(strip2)
	var s2 := _surf("StripA2", strip2, Rect2(0, 96, 200, 4))
	var la := _surf("LabelA", _label("a", menu), Rect2(10, 10, 50, 20))
	var bg_b := ColorRect.new()
	menu.add_child(bg_b)
	var b := _surf("BgB", bg_b, Rect2(0, 120, 180, 80))
	var stays := _surf("LabelB", _label("b", menu), Rect2(10, 130, 50, 20))
	assert_eq(OverlapAudit.collisions([a, s, s2, la, b, stays], {}), [], "CONTROL: each flat panel owns its own label and its border ring, past a strip of the same shape")
	var drift := _surf("Drifted", _label("b", menu), Rect2(10, 40, 50, 20))
	var hits: Array = OverlapAudit.collisions([a, s, s2, la, b, drift], {})
	assert_eq(hits.size(), 1, "panel B's label lying on panel A is a finding, not A's content: %s" % [hits])
	assert_true(hits.size() == 1 and str(hits[0]).contains("BgA") and str(hits[0]).contains("Drifted"), "and it names the two: %s" % [hits])


## A card inside a panel: the card's bar fill belongs to the bar, the bar to the card, the card to the panel. Every link
## encloses the next, so the fill is the PANEL's content too. A card hanging off the panel's foot breaks the chain.
func test_content_of_content_is_content() -> void:
	var menu := Control.new()
	add_child_autofree(menu)
	var panel_bg := ColorRect.new()
	menu.add_child(panel_bg)
	var card := Control.new()
	menu.add_child(card)
	var card_bg := ColorRect.new()
	card.add_child(card_bg)
	var bar := Control.new()
	card.add_child(bar)
	var bar_bg := ColorRect.new()
	bar.add_child(bar_bg)
	var fill := ColorRect.new()
	bar.add_child(fill)
	var p := _surf("Panel", panel_bg, Rect2(0, 0, 300, 300))
	var c := _surf("Card", card_bg, Rect2(10, 10, 280, 100))
	var b := _surf("Bar", bar_bg, Rect2(60, 40, 100, 10))
	var f := _surf("Fill", fill, Rect2(60, 40, 50, 10))
	assert_eq(OverlapAudit.collisions([p, c, b, f], {}), [], "CONTROL: a fill in a bar in a card in a panel is all content")
	var low := _surf("Card", card_bg, Rect2(10, 250, 280, 100))
	var hits: Array = OverlapAudit.collisions([p, low, _surf("Fill", fill, Rect2(60, 260, 50, 10))], {})
	assert_eq(hits.size(), 1, "a card hanging off the panel's foot is a finding on the panel, and only the card is: %s" % [hits])


## A row scrolled out of its list is not on screen, so it is not judged where it would be; the visible part still is.
func test_a_clipped_node_is_judged_by_what_shows() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, 0)
	scroll.size = Vector2(200, 100)
	host.add_child(scroll)
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(200, 400)
	scroll.add_child(inner)
	var row := ColorRect.new()
	row.color = Color.BLACK
	row.position = Vector2(0, 300)
	row.size = Vector2(200, 40)
	inner.add_child(row)
	var half := ColorRect.new()
	half.color = Color.BLACK
	half.position = Vector2(0, 80)
	half.size = Vector2(200, 40)
	inner.add_child(half)
	await get_tree().process_frame
	assert_eq(OverlapAudit.visible_rect(row).size, Vector2.ZERO, "a row scrolled out of view shows nothing (%s)" % OverlapAudit.visible_rect(row))
	assert_almost_eq(OverlapAudit.visible_rect(half).size.y, 20.0, 0.5, "a row half in view is judged by its visible half (%s)" % OverlapAudit.visible_rect(half))


## Ink rows [top, bottom] of `text` drawn by `l` at its own position: each glyph's rendered bitmap against the baseline.
func _ink_rows(l: Label, text: String, y0: float = 0.0) -> Vector2:
	var f: Font = l.get_theme_font("font")
	var px: int = l.get_theme_font_size("font_size")
	var ts := TextServerManager.get_primary_interface()
	var rid := ts.create_shaped_text()
	ts.shaped_text_add_string(rid, text, f.get_rids(), px)
	var base: float = y0 + l.position.y + f.get_ascent(px)
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


## NameLabel ∩ JobLabel: at a 20·k job line the letters DID touch (-1.0 px at 100%, -1.2 at 125%, measured .798). The
## lowest descender a name can have against the tallest letter a job name has (job names are ASCII), at every Text Size.
func test_a_name_and_its_job_line_do_not_touch_in_ink() -> void:
	var gaps: Array = []
	for s in _presets():
		var m := await _menu_at(float(s))
		var card: Control = m._party_panels[0]
		var name_l := card.get_node("NameLabel") as Label
		var job_l := card.get_node("JobLabel") as Label
		var low: Vector2 = _ink_rows(name_l, "gjpqy")
		var high: Vector2 = _ink_rows(job_l, "ABDEFHKLTbdfhklt")
		var job_low: Vector2 = _ink_rows(job_l, "gjpqy")
		var hp := card.get_node("HPBar") as Control
		var hp_top: Vector2 = _ink_rows(hp.get_child(0) as Label, "HP", hp.position.y)
		assert_gt(low.y - low.x, 2.0, "CONTROL: the name's glyphs have ink at %s%% (%s)" % [s, low])
		gaps.append("at %s%%, %.1f px (name ink to %.1f, job ink from %.1f; boxes overlap %.1f)" % [int(roundf(float(s) * 100.0)), high.x - low.y, low.y, high.x, name_l.position.y + name_l.size.y - job_l.position.y])
		assert_gte(high.x - low.y, 0.99, "a name's descender clears the job line's tallest letter by a pixel at %s%%: %s" % [s, gaps.back()])
		gaps.append("job->HP at %s%%, %.1f px" % [int(roundf(float(s) * 100.0)), hp_top.x - job_low.y])
		assert_gte(hp_top.x - job_low.y, 0.99, "a job's descender (Fighter's g) clears the HP label by a pixel at %s%%: %s" % [s, gaps.back()])
		m.queue_free()
		await get_tree().process_frame
	gut.p("ink gaps, name descender -> job letter: %s" % [gaps])


## A frame drawn as four full-length 2 px strips meets itself at its corners (the grind console, autogrind 25071): those
## joints are one frame, not four collisions. A strip crossing another's MIDDLE, or two thick bars meeting, still report.
func test_a_frame_corner_is_not_an_overlap() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var parts: Array = []
	for r in [Rect2(0, 0, 200, 2), Rect2(0, 98, 200, 2), Rect2(0, 0, 2, 100), Rect2(198, 0, 2, 100)]:
		var c := ColorRect.new()
		host.add_child(c)
		parts.append(_surf("Strip%d" % parts.size(), c, r))
	assert_eq(OverlapAudit.collisions(parts, {}), [], "CONTROL: four strips meeting at their ends are one frame")
	var cross := ColorRect.new()
	host.add_child(cross)
	var mid: Array = OverlapAudit.collisions([parts[0], _surf("Cross", cross, Rect2(100, -10, 2, 20))], {})
	assert_eq(mid.size(), 1, "a strip crossing another's middle is a finding: %s" % [mid])
	var bar_a := ColorRect.new()
	host.add_child(bar_a)
	var bar_b := ColorRect.new()
	host.add_child(bar_b)
	var thick: Array = OverlapAudit.collisions([_surf("BarA", bar_a, Rect2(0, 0, 200, 10)), _surf("BarB", bar_b, Rect2(0, 0, 10, 100))], {})
	assert_eq(thick.size(), 1, "two thick bars meeting at a corner are not a frame line: %s" % [thick])


## A small chip beside a label is the label's NEIGHBOUR, not its panel (autogrind 25092: the OR badge, 28x20, claimed the 16x20
## arrow next to it, so the arrow was reported on the rules panel that holds them both).
func test_a_neighbouring_chip_does_not_own_a_label() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var bg := ColorRect.new()
	host.add_child(bg)
	var chip := ColorRect.new()
	host.add_child(chip)
	var panel := _surf("Rules", bg, Rect2(0, 0, 300, 200))
	var badge := _surf("Badge", chip, Rect2(20, 40, 28, 20))
	var arrow := _surf("Arrow", _label(">", host), Rect2(52, 40, 16, 20))
	assert_eq(OverlapAudit.collisions([panel, badge, arrow], {}), [], "a badge and the arrow beside it both sit on the panel that holds them")
	# At other Text Sizes the badge is more than twice the arrow (the area ratio passes): it is still a neighbour, not the panel.
	var big_badge := _surf("Badge", chip, Rect2(20, 40, 40, 24))
	var small_arrow := _surf("Arrow", _label(">", host), Rect2(64, 42, 12, 18))
	assert_eq(OverlapAudit.collisions([panel, big_badge, small_arrow], {}), [], "a chip more than twice the label's size is still a neighbour on their shared panel")


func test_nothing_in_the_field_menu_overlaps_at_any_text_size() -> void:
	var used := {}
	var found: Array = []
	var judged := 0
	for s in _presets():
		var m := await _menu_at(float(s))
		var surfs: Array = OverlapAudit.surfaces(m)
		judged += surfs.size()
		for hit in OverlapAudit.collisions(surfs, DECLARED, used):
			found.append("%s%%: %s" % [int(roundf(float(s) * 100.0)), hit])
		m.queue_free()
		await get_tree().process_frame
	assert_gt(judged, 3 * _presets().size(), "CONTROL: every preset built a menu with surfaces (%d)" % judged)
	assert_eq(found, [], "every overlap in the field menu is declared with a reason:\n%s" % "\n".join(PackedStringArray(found.map(func(x): return str(x)))))
	assert_eq(OverlapAudit.stale(DECLARED, used), [], "every declared overlap still happens and says why")
