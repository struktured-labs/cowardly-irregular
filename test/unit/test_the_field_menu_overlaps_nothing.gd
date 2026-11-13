extends GutTest

## struktured: "make sure nothing ever overlaps unless we intend it" (main 23389). The field menu is the menu every player
## opens most, so it is the first menu judged by the shared helper (test/unit/helpers/overlap_audit.gd), at every Text
## Size the player can pick. An intended overlap is DECLARED below with its reason; anything else is a finding.

const OverlapAudit = preload("res://test/unit/helpers/overlap_audit.gd")
const OverworldMenuScript = preload("res://src/ui/OverworldMenu.gd")
const CombatantScript = preload("res://src/battle/Combatant.gd")

## Intended overlaps, {"a|b": "reason"}. Empty until the first census names what the menu draws on purpose.
const DECLARED := {}


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
	for f in ["surfaces", "collisions", "stale"]:
		assert_has(audit, f, "overlap_audit.%s must exist" % f)
	var menu: Array = (OverworldMenuScript as GDScript).get_script_method_list().map(func(m): return str(m["name"]))
	assert_has(menu, "setup", "OverworldMenu.setup must exist")


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
