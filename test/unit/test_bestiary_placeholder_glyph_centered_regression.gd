extends GutTest

## The unknown-monster '?' is a Label pinned to the portrait's top-left and
## told to center. A Label cannot be shorter than its font height, and this
## glyph is TextScale 96, so the control is 198px at 100% and 395px at 200%
## inside a 180px box. Vertical centering then centers the line in that taller
## control. The ink sits low: about 11px at 100%, and at 200% its center is
## ~113px below the portrait center and the glyph hangs ~94px past the bottom.
## Empty bestiary and a monster with no sheet share this one placeholder.
##
## The rect below is the glyph the renderer draws (shaped ascent padded up to
## the font height, then the glyph's own offset and size), not the Label's
## control rect — that rect already matched the portrait and hid the bug.

const GuardSubject := preload("res://test/unit/helpers/guard_subject.gd")
const SCALES: Array = [0.8, 1.0, 1.25, 1.5, 2.0]


var _prior_text_scale: float = 1.0


func before_each() -> void:
	_prior_text_scale = GameState.text_size_scale


func after_each() -> void:
	GameState.text_size_scale = _prior_text_scale


func _build_menu() -> Node:
	var menu = load("res://src/ui/BestiaryMenu.gd").new()
	add_child_autofree(menu)
	await wait_frames(3)
	return menu


func _missing_entry() -> Dictionary:
	return {
		"id": "no_such_monster_placeholder",
		"name": "Unseen",
		"level": 1,
		"epithet": "",
		"stats": {},
		"weaknesses": [],
		"resistances": [],
		"immunities": [],
		"flavor": "",
		"defeated": false,
		"drops": [],
		"one_shot_reward": null,
		"one_shot_hint": "",
		"pools": [],
		"last_location": "",
		"exp_reward": 0,
		"gold_reward": 0,
		"defeat_count": 0,
	}


## Parent-space rect of the '?' ink, using the same draw the Label uses.
func _glyph_ink(label: Label) -> Rect2:
	var font: Font = label.get_theme_font("font")
	if font == null or label.text.is_empty():
		return Rect2()
	var fs := label.get_theme_font_size("font_size")
	var bounds := label.get_character_bounds(0)
	if bounds.size.x < 1.0 or bounds.size.y < 1.0:
		return Rect2()
	var tp := TextParagraph.new()
	tp.add_string(label.text, font, fs)
	if tp.get_line_count() < 1:
		return Rect2()
	var asc := tp.get_line_ascent(0)
	var dsc := tp.get_line_descent(0)
	var font_h := font.get_height(fs)
	if asc + dsc < font_h:
		var diff := font_h - (asc + dsc)
		asc += diff / 2.0
		dsc += diff - (diff / 2.0)
	var ts := TextServerManager.get_primary_interface()
	var ch := label.text.unicode_at(0)
	for rid in font.get_rids():
		var idx := ts.font_get_glyph_index(rid, fs, ch, 0)
		if idx == 0:
			continue
		var gsz: Vector2 = ts.font_get_glyph_size(rid, Vector2i(fs, 0), idx)
		var goff: Vector2 = ts.font_get_glyph_offset(rid, Vector2i(fs, 0), idx)
		if gsz.x < 1.0 or gsz.y < 1.0:
			continue
		var local := Rect2(Vector2(bounds.position.x, bounds.position.y + asc) + goff, gsz)
		return Rect2(label.position + local.position, local.size)
	return Rect2()


func test_placeholder_glyph_is_inside_and_centered_at_every_text_size() -> void:
	var failures: Array = []
	var saw := 0
	for scale in SCALES:
		GameState.text_size_scale = scale
		for mode in ["empty", "missing"]:
			var menu = await _build_menu()
			var bg: ColorRect = menu.get("_detail_sprite_bg")
			var ph: Label = menu.get("_detail_placeholder")
			var where := "scale %s %s" % [scale, mode]
			if bg == null or ph == null:
				failures.append("%s missing portrait or placeholder" % where)
				continue
			if mode == "empty":
				menu.set("_entries", [])
				menu.set("_selected", 0)
			else:
				menu.set("_entries", [_missing_entry()])
				menu.set("_selected", 0)
			menu.call("_refresh_detail")
			await wait_frames(2)
			saw += 1
			if not ph.visible:
				failures.append("%s placeholder hidden" % where)
				continue
			if bg.size != Vector2(180, 180):
				failures.append("%s portrait size changed to %s" % [where, bg.size])
			if ph.get_theme_font_size("font_size") != TextScale.scaled(96):
				failures.append("%s font size changed to %s" % [where, ph.get_theme_font_size("font_size")])
			if ph.text != "?":
				failures.append("%s glyph text is '%s'" % [where, ph.text])
			var box := Rect2(bg.position, bg.size)
			var ink := _glyph_ink(ph)
			if ink.size.x < 1.0 or ink.size.y < 1.0:
				failures.append("%s glyph ink could not be measured" % where)
				continue
			var delta: Vector2 = ink.get_center() - box.get_center()
			if absf(delta.x) > 1.5 or absf(delta.y) > 1.5:
				failures.append("%s glyph center off by %s (ink %s box %s)" % [where, delta, ink, box])
			if not box.grow(1.0).encloses(ink):
				failures.append("%s glyph %s is not inside portrait %s" % [where, ink, box])
			menu.queue_free()
	assert_eq(saw, SCALES.size() * 2, "both placeholder paths must be measured at every text size")
	var shown: Array = failures.slice(0, 8)
	assert_eq(failures.size(), 0,
		"%d placeholder-centering failures (first %d): %s" % [failures.size(), shown.size(), shown])


## Names are derived from this file's own text.
func test_every_member_this_guard_drives_by_name_exists() -> void:
	var subject: Object = load("res://src/ui/BestiaryMenu.gd").new()
	add_child_autofree(subject)
	var calls: Dictionary = GuardSubject.audit_calls("res://test/unit/test_bestiary_placeholder_glyph_centered_regression.gd", subject)
	var props: Dictionary = GuardSubject.audit_properties("res://test/unit/test_bestiary_placeholder_glyph_centered_regression.gd", subject)
	assert_eq((str(calls["why"]) + " " + str(props["why"])).strip_edges(), "",
		"the comment strip failed: %s %s" % [calls["why"], props["why"]])
	assert_gt(int(calls["found"]) + int(props["found"]), 0,
		"VOID: no .call or .get name found in this file")
	assert_eq(calls["missing"], [],
		"this guard drives those methods by name and the subject no longer has them: %s" % [calls["missing"]])
	assert_eq(props["missing"], [],
		"this guard reads those properties by name and the subject no longer has them: %s" % [props["missing"]])
