extends GutTest

## MEASUREMENT PROBE (controller, measure-first per adhoc 28147 / main 28151), not a guard: it prints, it asserts only its floors.
## RadialPicker draws every label at a fixed 10 / 13 / 15 px. This rebuilds each label's drawn box with _draw's own placement
## (a mirror of RadialPicker._draw, stated as such) for the real ring users at every Text Size, twice: at the shipped fixed px
## ("now"), and at TextScale-scaled px on the authored radius ("if scaled"), which is what a px-only fix would draw.

const RP := "res://src/ui/RadialPicker.gd"
const VP := Vector2(1280, 720)

var _saved = null


func before_each() -> void:
	_saved = GameState.text_size_scale


func after_each() -> void:
	GameState.text_size_scale = _saved


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must resolve: " + str(p))
	return p


## The autogrind OPTIONS ring as _options_ring_spec builds it (states filled with their longest plausible values), in pages of 10.
func _autogrind_labels() -> Array:
	var l: Array = ["Ludicrous: OFF        (H)", "Permadeath: OFF       (P)", "Auto-Advance: OFF     (W)",
		"Stop at HP: 25%", "Stop after: 100 battles", "Stop on Death: OFF", "Stop when Out of Items: OFF",
		"Toggle This Rule        (Tab)", "Explain These Rules", "Cycle Member: Everyone", "Cycle Ability: Fireball",
		"Cycle Status: poison", "Preset: Casual          (1)", "Preset: Standard        (2)", "Preset: Hardcore        (3)",
		"Save as Preset          (S)", "Delete Last Preset      (D)", "Resume Saved Grind      (R)",
		"Custom Slot 1           (4)", "Custom Slot 2           (5)", "Custom Slot 3           (6)",
		"Export to File          (E)", "Import from File        (I)", "Copy Share Code   (Shift+E)",
		"Paste Share Code  (Shift+I)", "Restore Shipped Profiles"]
	return l


## The ten longest ability names (the ability ring's worst page) and the ten longest consumables (the item ring's).
func _longest(names: Array) -> Array:
	names.sort_custom(func(a, b): return str(a).length() > str(b).length())
	return names.slice(0, 10)


func _ability_labels() -> Array:
	var out: Array = []
	for id in JobSystem.abilities.keys():
		out.append(str(JobSystem.abilities[id].get("name", id)))
	return _longest(out)


func _item_labels() -> Array:
	var out: Array = []
	for id in ItemSystem.items.keys():
		if int(ItemSystem.items[id].get("category", 0)) in [0, 1, 2, 3]:
			out.append(str(ItemSystem.items[id].get("name", id)))
	return _longest(out)


## Mirror of RadialPicker._draw's label placement for slot i of n: the label's drawn rect at font size fs on radius r.
func _label_rect(font: Font, label: String, i: int, n: int, fs: int, r: float, node_r: float) -> Rect2:
	var c := VP * 0.5
	var a := -PI / 2.0 + TAU * float(i) / float(maxi(1, n))
	var out := Vector2(cos(a), sin(a))
	var p := c + out * r
	var lp := p + out * (node_r + 12.0)
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if out.x < -0.2:
		lp.x -= w
	elif absf(out.x) <= 0.2:
		lp.x -= w * 0.5
	var base := lp.y + 4.0
	return Rect2(lp.x, base - font.get_ascent(fs), w, font.get_height(fs))


func _measure(font: Font, labels: Array, fs: int, fs_sel: int, r: float, node_r: float) -> Dictionary:
	var n := labels.size()
	var rects: Array = []
	for i in n:
		rects.append(_label_rect(font, str(labels[i]), i, n, fs, r, node_r))
	var worst := 0.0
	var worst_pair := ""
	for i in n:
		for j in range(i + 1, n):
			var ov: Rect2 = (rects[i] as Rect2).intersection(rects[j])
			if ov.get_area() > worst:
				worst = ov.get_area()
				worst_pair = "'%s' x '%s' (%.0fx%.0f)" % [str(labels[i]).left(18), str(labels[j]).left(18), ov.size.x, ov.size.y]
	var off := 0
	for rr in rects:
		if not Rect2(Vector2.ZERO, VP).encloses(rr):
			off += 1
	## The selected label is drawn centred at the ring's middle; it must clear the 3 and 9 o'clock nodes' inner edges.
	var widest_sel := 0.0
	for l in labels:
		widest_sel = maxf(widest_sel, font.get_string_size(str(l), HORIZONTAL_ALIGNMENT_LEFT, -1, fs_sel).x)
	return {"worst_px2": worst, "pair": worst_pair, "off_screen": off, "sel_w": widest_sel, "inner": 2.0 * (r - node_r)}


func test_measure_every_ring_at_every_preset() -> void:
	var font: Font = ThemeDB.fallback_font
	var R: float = (load(RP) as GDScript).get_script_constant_map()["RADIUS"]
	var NR: float = (load(RP) as GDScript).get_script_constant_map()["NODE_RADIUS"]
	var CAP: int = (load(RP) as GDScript).get_script_constant_map()["RING_CAPACITY"]
	var rings := {"autogrind": _autogrind_labels(), "ability": _ability_labels(), "item": _item_labels()}
	assert_gt((rings["ability"] as Array).size(), 0, "FLOOR: abilities resolved")
	assert_gt((rings["item"] as Array).size(), 0, "FLOOR: consumables resolved")
	for scale in _presets():
		GameState.text_size_scale = float(scale)
		for name in rings.keys():
			var all: Array = rings[name]
			for pg in range(int(ceil(float(all.size()) / CAP))):
				var page: Array = all.slice(pg * CAP, mini(all.size(), (pg + 1) * CAP))
				var now := _measure(font, page, 10, 15, R, NR)
				var sc := _measure(font, page, TextScale.scaled(10), TextScale.scaled(15), R, NR)
				gut.p("RING %.2fx %-9s p%d n=%d | NOW worst=%.0f off=%d sel=%.0f/%.0f %s | SCALED(%d/%d) worst=%.0f off=%d sel=%.0f/%.0f %s" % [
					float(scale), name, pg + 1, page.size(), now["worst_px2"], now["off_screen"], now["sel_w"], now["inner"], now["pair"],
					TextScale.scaled(10), TextScale.scaled(15), sc["worst_px2"], sc["off_screen"], sc["sel_w"], sc["inner"], sc["pair"]])
	var hint := "[Dir] Aim   %s Confirm   %s Back" % [InputProfileManager.hint_for_action("ui_accept"), InputProfileManager.hint_for_action("ui_cancel")]
	gut.p("RING hint '%s' w@10=%.0f" % [hint, font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x])
	assert_true(true, "probe printed")
