extends GutTest

## The field zoom sizes a description with AbilityZoom.fit_px, a measurement off the font, and draws it in a Label with
## AUTOWRAP_WORD. The zoom's own test judges the longest description of ONE job plus a planted one. This sweeps every
## description in abilities.json and passives.json through the real box at every Text Size and judges the BUILT label's
## line count, so a text where the measure and the Label disagree (cowir-battle's refit question, 23339) reds by name.
## The box comes from a real zoomed menu at that Text Size, never from arithmetic copied here.

const MENU := preload("res://src/ui/AbilitiesMenu.gd")
const CombatantScript := preload("res://src/battle/Combatant.gd")

var _saved := 1.0


func before_each() -> void:
	_saved = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.set_text_size_scale(_saved)


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must hold more than one step, or the preset loop proves nothing")
	return p


func _texts() -> Array:
	var seen := {}
	for id in JobSystem.abilities:
		seen[str(JobSystem.abilities[id].get("description", ""))] = true
	for id in PassiveSystem.passives:
		seen[str(PassiveSystem.passives[id].get("description", ""))] = true
	seen.erase("")
	return seen.keys()


## The description box a real zoomed menu builds at the current Text Size.
func _zoom_box() -> Vector2:
	var pc = CombatantScript.new()
	pc.job = JobSystem.get_job("mage")
	add_child_autofree(pc)
	var m: Control = MENU.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(m)
	m.setup(pc)
	m._set_zoom(true)
	await get_tree().process_frame
	var d: Array = m.find_children("Description", "Label", true, false).filter(func(l): return not l.is_queued_for_deletion())
	assert_eq(d.size(), 1, "CONTROL: the zoomed menu built one description label")
	return (d[0] as Label).size if d.size() == 1 else Vector2.ZERO


func test_every_real_description_fits_the_zoom_box_at_every_text_size() -> void:
	var texts := _texts()
	assert_gt(texts.size(), 200, "CONTROL: the sweep covers the abilities and passives data (%d texts)" % texts.size())
	var font: Font = ThemeDB.fallback_font
	var bad: Array = []
	var wrapped := 0
	for s in _presets():
		GameState.set_text_size_scale(s)
		var box: Vector2 = await _zoom_box()
		assert_gt(box.x * box.y, 0.0, "CONTROL @%s: the box has an area" % s)
		var labels: Array = []
		for t in texts:
			var l := Label.new()
			l.autowrap_mode = TextServer.AUTOWRAP_WORD
			l.add_theme_font_size_override("font_size", AbilityZoom.fit_px(font, t, box))
			l.text = t
			add_child_autofree(l)
			l.size = box   # after add_child: outside the tree a Label's minimum is measured at the default 16 px
			labels.append(l)
		await get_tree().process_frame
		for l in labels:
			var px: int = l.get_theme_font_size("font_size")
			var lines: int = l.get_line_count()
			if lines > 1:
				wrapped += 1
			var drawn: float = lines * font.get_height(px)
			var widest: float = 0.0
			for word in l.text.split(" "):
				widest = maxf(widest, font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
			if lines < 1 or drawn > box.y + 0.5 or widest > box.x + 0.5:
				bad.append("@%s '%s' at %d px: %d lines = %.0f tall in %.0f, widest word %.0f in %.0f" % [s, l.text.left(40), px, lines, drawn, box.y, widest, box.x])
			l.queue_free()
	assert_gt(wrapped, 0, "CONTROL: some description wraps to more than one line, so the multi-line fit is exercised")
	assert_eq(bad.size(), 0, "every description fits its zoom box as BUILT: %s" % [bad.slice(0, 6)])
