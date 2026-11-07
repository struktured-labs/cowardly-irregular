extends GutTest

## The key-item reveal shows the name and description written on each cutscene's grant_item step, not items.json's,
## and the Text Size guards built only items.json's longest description. This walks EVERY authored reveal at EVERY
## preset and judges the card as BUILT: the name fits its width, the description's built label stays inside the card,
## and its drawn lines (the label's own count x the font height) end above the continue hint (cowir-cutscenes 2026-11-07).

const CUTSCENES := "res://data/cutscenes/"

var _saved_scale: float = 1.0
var _host: Control = null


func before_each() -> void:
	_saved_scale = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _saved_scale
	if _host != null and is_instance_valid(_host):
		_host.queue_free()
	_host = null


func _presets() -> Array:
	var p: Array = load("res://src/ui/SettingsMenu.gd").get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	return p


func _collect(o, out: Array) -> void:
	if o is Dictionary:
		if str(o.get("type", "")) == "grant_item":
			out.append(o)
		for v in o.values():
			_collect(v, out)
	elif o is Array:
		for v in o:
			_collect(v, out)


## Every authored grant_item step, branch-nested ones included, shaped as CutsceneDirector hands it to the popup.
func _reveals() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(CUTSCENES):
		if not f.ends_with(".json"):
			continue
		var steps: Array = []
		_collect(JSON.parse_string(FileAccess.get_file_as_string(CUTSCENES + f)), steps)
		for s in steps:
			var id := str(s.get("item", ""))
			out.append({"file": f, "item_id": id, "name": str(s.get("name", id)), "description": str(s.get("description", ""))})
	return out


func _show(scale: float, item: Dictionary):
	GameState.text_size_scale = scale
	_host = Control.new()
	_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_host)
	await get_tree().process_frame
	var pop = KeyItemPopup.show_item(_host, item)
	await get_tree().process_frame
	return pop


func _close(pop) -> void:
	pop.queue_free()
	_host.queue_free()
	_host = null


func _px(l: Label) -> int:
	return l.get_theme_font_size("font_size")


func test_the_corpus_was_read() -> void:
	var r := _reveals()
	assert_gt(r.size(), 15, "floor: the authored grant_item steps were read (%d)" % r.size())
	assert_gt(_presets().size(), 2, "floor: the Text Size ladder was read")
	var longest := 0
	for it in r:
		longest = maxi(longest, str(it["description"]).length())
	assert_gt(longest, 200, "CONTROL: some authored description is long enough to wrap")


func test_every_authored_reveal_fits_its_card_at_every_size() -> void:
	var bad: Array = []
	var judged := 0
	for p in _presets():
		for it in _reveals():
			var pop = await _show(float(p), it)
			var panel: Control = pop.get("_panel")
			var hint: Label = pop.get("_hint")
			for c in panel.get_children():
				if not (c is Label):
					continue
				var l: Label = c
				var font: Font = l.get_theme_font("font")
				if l.autowrap_mode == TextServer.AUTOWRAP_OFF:
					if font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _px(l)).x > panel.size.x:
						bad.append("%s @%s: '%s' wider than the card" % [it["file"], p, l.text])
				elif l != hint and l.text != "":
					judged += 1
					if l.position.x + l.size.x > panel.size.x - l.position.x + 0.5:
						bad.append("%s @%s: description built %.0f px wide in a %.0f card" % [it["file"], p, l.size.x, panel.size.x])
					var drawn: float = l.get_line_count() * font.get_height(_px(l))
					if l.position.y + drawn > hint.position.y:
						bad.append("%s @%s: %d lines end at %.0f, under the hint at %.0f" % [it["file"], p, l.get_line_count(), l.position.y + drawn, hint.position.y])
			_close(pop)
	assert_gt(judged, 15 * 3, "CONTROL: descriptions were judged across the ladder (%d)" % judged)
	assert_eq(bad, [], "every authored reveal fits its card at every Text Size")
