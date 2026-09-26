extends GutTest

## Header titles, counters, and footer hints used a fixed pixel row. At 200% text size the
## font box grew under the next panel and off the bottom of the screen. Every Text Size preset
## (80/100/125/150/200) keeps those rects inside the viewport, clear of each other, and clear
## of whatever is drawn on top of them. The hint words are unchanged.

const SCALES: Array = [0.8, 1.0, 1.25, 1.5, 2.0]

var _prior_text_scale: float = 1.0


func before_each() -> void:
	_prior_text_scale = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _prior_text_scale


func test_header_and_footer_stay_on_screen_at_every_text_size() -> void:
	var failures: PackedStringArray = []
	for scale in SCALES:
		GameState.text_size_scale = float(scale)
		failures.append_array(await _bestiary(float(scale)))
		failures.append_array(await _party(float(scale)))
		failures.append_array(await _status(float(scale)))
		failures.append_array(await _items(float(scale)))
		failures.append_array(await _equipment(float(scale)))
		failures.append_array(await _settings(float(scale)))
		failures.append_array(await _shop(float(scale)))
	assert_eq(failures.size(), 0, "\n".join(failures))


func _fighter() -> Combatant:
	var who := Combatant.new()
	who.initialize({
		"name": "Tester", "max_hp": 100, "max_mp": 40,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10,
	})
	who.job = {"id": "fighter", "name": "Fighter"}
	return who


func _bestiary(scale: float) -> PackedStringArray:
	var menu := BestiaryMenu.new()
	add_child(menu)
	await wait_frames(3)
	var where := "bestiary %.2f" % scale
	var failures := _check(where, menu, ["ScreenTitle", "ScreenCounter", "ScreenFooter"])
	var title := _labeled(menu, "ScreenTitle")
	var counter := _labeled(menu, "ScreenCounter")
	var footer := _labeled(menu, "ScreenFooter")
	if title != null and title.text != "Bestiary":
		failures.append("%s title text is '%s'" % [where, title.text])
	if counter != null and not str(counter.text).contains("seen"):
		failures.append("%s counter lost the seen tally ('%s')" % [where, counter.text])
	var vp_x := menu.get_viewport().get_visible_rect().size.x
	if counter != null and vp_x > 720.0 and not str(counter.text).contains("defeated"):
		failures.append("%s wide counter lost the defeated tally ('%s')" % [where, counter.text])
	if footer != null and not str(footer.text).contains("hover to preview"):
		failures.append("%s footer hint changed ('%s')" % [where, footer.text])
	menu.free()
	return failures


func _party(scale: float) -> PackedStringArray:
	var who := _fighter()
	var menu := PartyStatusScreen.new()
	menu.party = [who]
	add_child(menu)
	await wait_frames(3)
	var where := "party %.2f" % scale
	var failures := _check(where, menu, ["ScreenTitle", "GoldLabel", "ScreenFooter"])
	var title := _labeled(menu, "ScreenTitle")
	var gold := _labeled(menu, "GoldLabel")
	var footer := _labeled(menu, "ScreenFooter")
	if title != null and title.text != "PARTY STATUS":
		failures.append("%s title text is '%s'" % [where, title.text])
	if gold != null and not str(gold.text).begins_with("Gold:"):
		failures.append("%s gold text is '%s'" % [where, gold.text])
	if footer != null and not str(footer.text).contains("Switch member"):
		failures.append("%s footer hint changed ('%s')" % [where, footer.text])
	menu.free()
	who.free()
	return failures


func _status(scale: float) -> PackedStringArray:
	var who := _fighter()
	var menu := StatusMenu.new()
	menu.character = who
	add_child(menu)
	await wait_frames(3)
	var where := "status %.2f" % scale
	var failures := _check(where, menu, ["ScreenTitle", "ScreenCounter", "ScreenFooter"])
	var title := _labeled(menu, "ScreenTitle")
	var counter := _labeled(menu, "ScreenCounter")
	var footer := _labeled(menu, "ScreenFooter")
	if title != null and title.text != "Tester":
		failures.append("%s title text is '%s'" % [where, title.text])
	if counter != null and not str(counter.text).begins_with("EXP:"):
		failures.append("%s exp text is '%s'" % [where, counter.text])
	if footer != null and not str(footer.text).contains("Back"):
		failures.append("%s footer hint changed ('%s')" % [where, footer.text])
	menu.free()
	who.free()
	return failures


func _items(scale: float) -> PackedStringArray:
	var menu := ItemsMenu.new()
	add_child(menu)
	menu.setup([], {"potion": 1})
	await wait_frames(3)
	var where := "items %.2f" % scale
	var failures := _check(where, menu, ["ScreenTitle", "ScreenFooter"])
	var title := _labeled(menu, "ScreenTitle")
	var footer := _labeled(menu, "ScreenFooter")
	if title != null and title.text != "ITEMS":
		failures.append("%s title text is '%s'" % [where, title.text])
	if footer != null and not str(footer.text).contains("Select"):
		failures.append("%s footer hint changed ('%s')" % [where, footer.text])
	menu.free()
	return failures


func _equipment(scale: float) -> PackedStringArray:
	var who := _fighter()
	var menu := EquipmentMenu.new()
	add_child(menu)
	menu.setup(who, [], [], [])
	await wait_frames(3)
	var where := "equipment %.2f" % scale
	var failures := _check(where, menu, ["ScreenTitle", "ScreenCounter", "ScreenFooter"])
	var title := _labeled(menu, "ScreenTitle")
	var counter := _labeled(menu, "ScreenCounter")
	var footer := _labeled(menu, "ScreenFooter")
	if title != null and title.text != "Tester":
		failures.append("%s title text is '%s'" % [where, title.text])
	if counter != null and not str(counter.text).begins_with("Lv"):
		failures.append("%s level text is '%s'" % [where, counter.text])
	if footer != null and not str(footer.text).contains("Select"):
		failures.append("%s footer hint changed ('%s')" % [where, footer.text])
	menu.free()
	who.free()
	return failures


func _settings(scale: float) -> PackedStringArray:
	var menu := SettingsMenu.new()
	menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
	menu.position = Vector2.ZERO
	menu.size = Vector2(1280, 720)
	add_child(menu)
	await wait_frames(3)
	if menu.size.x < 200.0:
		menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
		menu.size = Vector2(1280, 720)
		menu._build_ui()
		await wait_frames(2)
	var where := "settings %.2f" % scale
	var failures := _check(where, menu, ["ScreenTitle", "ScreenFooter"])
	var title := _labeled(menu, "ScreenTitle")
	var footer := _labeled(menu, "ScreenFooter")
	if title != null and title.text != "SETTINGS":
		failures.append("%s title text is '%s'" % [where, title.text])
	if footer != null and not str(footer.text).contains("Adjust"):
		failures.append("%s footer hint changed ('%s')" % [where, footer.text])
	menu.free()
	return failures


func _shop(scale: float) -> PackedStringArray:
	var menu := ShopScene.new()
	menu.setup(ShopScene.ShopType.ITEM, "General Store", [])
	add_child(menu)
	await wait_frames(4)
	var where := "shop %.2f" % scale
	var failures := _check(where, menu, ["GoldLabel"])
	var gold := _labeled(menu, "GoldLabel")
	if gold != null and not str(gold.text).ends_with(" G"):
		failures.append("%s gold text is '%s'" % [where, gold.text])
	menu.free()
	return failures


func _check(where: String, root: Node, names: Array) -> PackedStringArray:
	var failures: PackedStringArray = []
	var vp := root.get_viewport().get_visible_rect()
	if vp.size.x < 1.0 or vp.size.y < 1.0:
		vp = Rect2(Vector2.ZERO, Vector2(1280, 720))
	var rects: Array[Rect2] = []
	var labels: Array[Label] = []
	for node_name in names:
		var label := _labeled(root, str(node_name))
		if label == null:
			failures.append("%s missing %s" % [where, node_name])
			continue
		var rect := label.get_global_rect()
		if rect.size.x < 1.0 or rect.size.y < 1.0:
			failures.append("%s %s has an empty box %s" % [where, node_name, rect])
		elif not _inside(rect, vp):
			failures.append("%s %s %s is outside %s" % [where, node_name, rect, vp])
		var need := label.get_minimum_size()
		if need.x > label.size.x + 1.0 or need.y > label.size.y + 1.0:
			failures.append("%s %s text %s does not fit box %s" % [where, node_name, need, label.size])
		var cover := _cover(label)
		if cover != "":
			failures.append("%s %s is covered by %s" % [where, node_name, cover])
		rects.append(rect)
		labels.append(label)
	for i in range(rects.size()):
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				failures.append("%s %s overlaps %s (%s vs %s)" % [
					where, labels[i].name, labels[j].name, rects[i], rects[j]])
	return failures


func _inside(rect: Rect2, vp: Rect2) -> bool:
	return rect.position.x >= vp.position.x - 1.0 \
		and rect.position.y >= vp.position.y - 1.0 \
		and rect.end.x <= vp.end.x + 1.0 \
		and rect.end.y <= vp.end.y + 1.0


func _cover(label: Control) -> String:
	var rect := label.get_global_rect().grow(-1.0)
	if rect.size.x < 1.0 or rect.size.y < 1.0:
		rect = label.get_global_rect()
	var node: Node = label
	while node != null and node.get_parent() != null:
		var parent := node.get_parent()
		var seen := false
		for child in parent.get_children():
			if child == node:
				seen = true
				continue
			if not seen or not (child is Control):
				continue
			if not (child as CanvasItem).visible:
				continue
			var other := child as Control
			var r := other.get_global_rect()
			if minf(r.size.x, r.size.y) < 8.0:
				continue
			if r.intersects(rect):
				var shown := str(other.name)
				if shown == "":
					shown = other.get_class()
				return "%s %s" % [shown, r]
		node = parent
	return ""


func _labeled(root: Node, node_name: String) -> Label:
	var found := _find(root, node_name)
	if found is Label:
		return found
	return null


func _find(root: Node, node_name: String) -> Node:
	if str(root.name) == node_name:
		return root
	for child in root.get_children():
		var found := _find(child, node_name)
		if found != null:
			return found
	return null
