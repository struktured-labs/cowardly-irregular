extends Control
class_name VictoryOverlay

## Victory overlay revamp (struktured 2026-08-18, direction locked): VICTORY slam →
## character-anchored cards beside each victory-posing sprite → loot toast strip.
## One press snaps everything to its end state (complete_now), the next dismisses
## (GameLoop._wait_for_confirm_victory drives that contract). ≥4x/turbo/OFF-tier or
## victory_flourish off = built pre-completed. Node is named "VictoryResults" by the
## caller — three consumers key off that name (Select toggle, quip suppression, cleanup).

const CARD_W := 210.0
const CARD_H := 58.0
const CARD_GAP := 8.0
const LOG_CLEAR_X := 190.0
const STRIP_BOTTOM_MARGIN := 64.0

var _scene = null
var _snaps: Array[Callable] = []
var _tweens: Array[Tween] = []
var _complete := false


func build(results: Dictionary, scene) -> void:
	_scene = scene
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var flourish: bool = true
	if scene and scene.has_method("_tier"):
		var tier: int = scene._tier()
		flourish = tier <= BattleJuice.Tier.REDUCED and Engine.time_scale < 4.0 \
				and BattleJuice.flag("victory_flourish")

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.0, 0.05, 0.22)  # party stays lit (2026-07-11 ruling)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	_build_slam(flourish)
	_build_cards(results.get("char_results", []), flourish)
	_build_loot_strip(results, flourish)
	_build_prompt()

	if not flourish:
		complete_now()


func is_complete() -> bool:
	return _complete


## First accept press lands here: every animation jumps to its end state.
func complete_now() -> void:
	if _complete:
		return
	_complete = true
	for t in _tweens:
		if t and t.is_valid():
			t.kill()
	for snap in _snaps:
		snap.call()


func _track(t: Tween) -> Tween:
	_tweens.append(t)
	return t


## -- Stage 1: VICTORY slam --------------------------------------------------

func _build_slam(flourish: bool) -> void:
	var title := Label.new()
	title.text = "V I C T O R Y"
	title.add_theme_font_size_override("font_size", TextScale.scaled(44))
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	title.add_theme_constant_override("outline_size", 3)
	title.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	title.reset_size()
	var vp := get_viewport_rect().size
	var center := Vector2((vp.x - title.size.x) / 2.0 - 120.0, vp.y * 0.30)
	var docked := Vector2(center.x, 28.0)
	title.pivot_offset = title.size / 2.0
	_snaps.append(func() -> void:
		if is_instance_valid(title):
			title.position = docked
			title.scale = Vector2(0.55, 0.55)
			title.modulate.a = 1.0)
	if not flourish:
		return
	title.position = center
	title.scale = Vector2(2.2, 2.2)
	title.modulate.a = 0.0
	var tw := _track(create_tween())
	tw.tween_property(title, "modulate:a", 1.0, 0.08)
	tw.parallel().tween_property(title, "scale", Vector2(0.92, 1.06), 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(title, "scale", Vector2.ONE, 0.13) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.45)
	tw.tween_property(title, "position", docked, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(title, "scale", Vector2(0.55, 0.55), 0.3)
	BattleJuice.punch_zoom(vp / 2.0, 0.03, 0.22)
	if SoundManager._sfx_manifest.has("victory_slam"):
		SoundManager.play_battle("victory_slam")


## -- Stage 2: character cards ----------------------------------------------

func _build_cards(char_results: Array, flourish: bool) -> void:
	var vp := get_viewport_rect().size
	for i in range(char_results.size()):
		var cr: Dictionary = char_results[i]
		var card := _make_card(cr)
		add_child(card)
		card.position = _card_position(i, char_results.size(), vp)
		var delay := 0.5 + i * 0.15
		var final_pos := card.position
		_snaps.append(func() -> void:
			if is_instance_valid(card):
				card.position = final_pos
				card.modulate.a = 1.0)
		if flourish:
			card.modulate.a = 0.0
			card.position.x += 24.0
			var tw := _track(create_tween())
			tw.tween_interval(delay)
			tw.tween_property(card, "modulate:a", 1.0, 0.15)
			tw.parallel().tween_property(card, "position:x", final_pos.x, 0.18) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_animate_card_content(card, cr, i, delay, flourish)


## Card hangs LEFT of its sprite toward mid-screen; clamped clear of the log
## (x>=190) and inside the viewport. Sprite gone/mispositioned → column fallback.
func _card_position(i: int, count: int, vp: Vector2) -> Vector2:
	var y_fallback := vp.y * 0.18 + i * (CARD_H + CARD_GAP)
	var pos := Vector2(vp.x * 0.42, y_fallback)
	if _scene and i < _scene.party_sprite_nodes.size():
		var sprite = _scene.party_sprite_nodes[i]
		if is_instance_valid(sprite) and sprite.is_inside_tree():
			var sp: Vector2 = sprite.get_global_transform_with_canvas().origin
			pos = Vector2(sp.x - CARD_W - 36.0, sp.y - CARD_H / 2.0)
	pos.x = clampf(pos.x, LOG_CLEAR_X, vp.x - CARD_W - 8.0)
	pos.y = clampf(pos.y, 56.0, vp.y - STRIP_BOTTOM_MARGIN - CARD_H)
	return pos


func _make_card(cr: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, CARD_H)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.15, 0.92)
	style.border_color = Color(0.6, 0.5, 0.2) if cr.get("is_alive", true) else Color(0.35, 0.3, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	card.add_theme_stylebox_override("panel", style)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(h)

	# Portrait chip (artist portraits keyed by job; absence is fine)
	var job_key := str(cr.get("job_name", "")).to_lower()
	var tex_path := "res://assets/sprites/portraits/%s.png" % job_key
	if ResourceLoader.exists(tex_path):
		var chip := TextureRect.new()
		chip.texture = load(tex_path)
		chip.custom_minimum_size = Vector2(40, 40)
		chip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		chip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not cr.get("is_alive", true):
			chip.modulate = Color(0.5, 0.5, 0.5)
		h.add_child(chip)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)

	var top := Label.new()
	top.name = "TopLine"
	var alive: bool = cr.get("is_alive", true)
	top.text = "%s  %s" % [cr.get("name", "?"), "+0 EXP" if alive else "KO"]
	top.add_theme_font_size_override("font_size", TextScale.scaled(13))
	top.add_theme_color_override("font_color", Color.WHITE if alive else Color(0.6, 0.45, 0.45))
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)

	if alive:
		var bar_bg := ColorRect.new()
		bar_bg.name = "BarBg"
		bar_bg.color = Color(0.15, 0.12, 0.25)
		bar_bg.custom_minimum_size = Vector2(0, 8)
		bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(bar_bg)
		var fill := ColorRect.new()
		fill.name = "BarFill"
		fill.color = Color(0.2, 0.8, 0.5)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar_bg.add_child(fill)

	var gains := Label.new()
	gains.name = "GainsLine"
	gains.text = ""
	gains.visible = false
	gains.clip_text = true  # one compact line — the 700px 5-level-up clip rule
	gains.add_theme_font_size_override("font_size", TextScale.scaled(11))
	gains.add_theme_color_override("font_color", Color(1.0, 1.0, 0.3))
	gains.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(gains)
	return card


func _animate_card_content(card: PanelContainer, cr: Dictionary, idx: int, delay: float, flourish: bool) -> void:
	if not cr.get("is_alive", true):
		return
	var top: Label = card.find_child("TopLine", true, false)
	var bar_bg: ColorRect = card.find_child("BarBg", true, false)
	var fill: ColorRect = card.find_child("BarFill", true, false)
	var gains: Label = card.find_child("GainsLine", true, false)

	var exp_gained: int = int(cr.get("exp_gained", 0))
	var exp_before: int = int(cr.get("job_exp_before", 0))
	var exp_to_next: int = maxi(1, int(cr.get("exp_to_next", 100)))
	var leveled: bool = cr.get("leveled_up", false)
	var bar_w := CARD_W - 76.0
	var start_ratio := clampf(float(exp_before) / float(exp_to_next), 0.0, 1.0)
	var end_ratio: float
	if leveled:
		var new_max: int = maxi(1, int(cr.get("job_level", 1)) * 100)
		end_ratio = clampf(float(int(cr.get("job_exp", 0))) / float(new_max), 0.0, 1.0)
	else:
		end_ratio = clampf(float(exp_before + exp_gained) / float(exp_to_next), 0.0, 1.0)
	fill.size = Vector2(bar_w * start_ratio, 8)

	var gains_text := _gains_line(cr)
	var final_top := "%s  +%d EXP%s" % [cr.get("name", "?"), exp_gained, "  ★ Lv.%d" % int(cr.get("job_level", 1)) if leveled else ""]
	_snaps.append(func() -> void:
		if is_instance_valid(fill):
			fill.size = Vector2(bar_w * end_ratio, 8)
			fill.color = Color(0.2, 0.8, 0.5)
		if is_instance_valid(top):
			top.text = final_top
		if is_instance_valid(gains) and gains_text != "":
			gains.text = gains_text
			gains.visible = true)
	if not flourish:
		return

	var tw := _track(create_tween())
	tw.tween_interval(delay + 0.15)
	tw.tween_callback(func() -> void:
		if exp_gained > 0:
			SoundManager.play_ui("exp_tick"))
	# EXP roll-up on the top line
	var steps := mini(maxi(exp_gained, 1), 14)
	for s in range(1, steps + 1):
		var shown := int(float(exp_gained) * s / steps)
		tw.tween_callback(func() -> void:
			if is_instance_valid(top):
				top.text = "%s  +%d EXP" % [cr.get("name", "?"), shown]).set_delay(0.04)
	if leveled:
		tw.tween_property(fill, "size:x", bar_w, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func() -> void:
			_level_up_flare(card, fill, idx)
			if is_instance_valid(top):
				top.text = final_top
			if is_instance_valid(gains) and gains_text != "":
				gains.text = gains_text
				gains.visible = true)
		tw.tween_property(fill, "size:x", 0.0, 0.05)
		tw.tween_property(fill, "size:x", bar_w * end_ratio, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_property(fill, "size:x", bar_w * end_ratio, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _gains_line(cr: Dictionary) -> String:
	if not cr.get("leveled_up", false):
		return ""
	var parts: Array = []
	var gains: Dictionary = cr.get("stat_gains", {})
	for stat in ["HP", "MP", "ATK", "DEF", "MAG", "SPD"]:
		if gains.has(stat) and int(gains[stat]) != 0:
			parts.append("%s+%d" % [stat, int(gains[stat])])
	var learned: Array = cr.get("learned_abilities", [])
	if not learned.is_empty():
		var names: PackedStringArray = []
		for aid in learned:
			var ab: Dictionary = JobSystem.get_ability(str(aid)) if JobSystem else {}
			names.append(str(ab.get("name", str(aid).capitalize())))
		parts.append("✦ " + ", ".join(names))
	return "LEVEL UP!  " + "  ".join(parts)


func _level_up_flare(card: PanelContainer, fill: ColorRect, idx: int) -> void:
	if is_instance_valid(fill):
		var flash := _track(create_tween())
		flash.tween_property(fill, "color", Color(1.0, 0.9, 0.2), 0.12)
		flash.tween_property(fill, "color", Color(0.2, 0.8, 0.5), 0.18)
	if SoundManager._sfx_manifest.has("levelup_flourish"):
		SoundManager.play_battle("levelup_flourish")
	else:
		SoundManager.play_music("stinger_level_up")
		SoundManager.play_battle("level_up")
	# Burst at the sprite + replay its victory pose — the celebration belongs to the CHARACTER
	if _scene and idx < _scene.party_sprite_nodes.size():
		var sprite = _scene.party_sprite_nodes[idx]
		if is_instance_valid(sprite):
			BattleJuice.spawn_burst(sprite.global_position, Vector2(0, -0.6), 16, Color(1.0, 0.9, 0.3))
	if _scene and idx < _scene.party_animators.size():
		var animator = _scene.party_animators[idx]
		if is_instance_valid(animator) and animator.has_method("play_victory"):
			animator.play_victory()


## -- Stage 3: loot toast strip ----------------------------------------------

func _build_loot_strip(results: Dictionary, flourish: bool) -> void:
	var total_gold: int = int(results.get("total_gold", 0))
	var item_drops: Array = results.get("item_drops", [])
	var injuries: Array = results.get("injuries", [])
	var bonuses: Array = results.get("bonuses", [])
	if total_gold <= 0 and item_drops.is_empty() and injuries.is_empty() and bonuses.is_empty():
		return

	var vp := get_viewport_rect().size
	var strip := PanelContainer.new()
	strip.name = "LootStrip"
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.15, 0.92)
	style.border_color = Color(0.6, 0.5, 0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	strip.add_theme_stylebox_override("panel", style)
	add_child(strip)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(h)

	var chips: Array = []  # [label, final_text, color, kind]
	if total_gold > 0:
		chips.append(["0 G", "%d G" % total_gold, Color(1.0, 0.85, 0.2), "gold"])
	for drop in item_drops:
		var qty: int = int(drop.get("qty", 1))
		var txt: String = "+ %s%s" % [drop.get("name", "?"), " x%d" % qty if qty > 1 else ""]
		chips.append([txt, txt, Color(0.6, 0.9, 1.0), "item"])
	for bonus in bonuses:
		if bonus.get("type", "") == "one_shot":
			chips.append(["ONE-SHOT x%.1f" % bonus.get("multiplier", 1.0), "ONE-SHOT x%.1f" % bonus.get("multiplier", 1.0), Color(1.0, 0.9, 0.0), "bonus"])
		elif bonus.get("type", "") == "autobattle":
			chips.append(["AUTO x%.1f" % bonus.get("multiplier", 1.0), "AUTO x%.1f" % bonus.get("multiplier", 1.0), Color(0.3, 0.9, 1.0), "bonus"])
	for inj in injuries:
		var injury_data: Dictionary = inj.get("injury", {})
		var itxt: String = "⚠ %s: -%d %s" % [inj.get("name", "?"), int(injury_data.get("penalty", 0)), str(injury_data.get("stat", "")).capitalize()]
		chips.append([itxt, itxt, Color(1.0, 0.3, 0.3), "injury"])  # injuries LAST — permanent, they get the final word

	var labels: Array = []
	for chip in chips:
		var lbl := Label.new()
		lbl.text = chip[1]
		lbl.add_theme_font_size_override("font_size", TextScale.scaled(14))
		lbl.add_theme_color_override("font_color", chip[2])
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(lbl)
		labels.append(lbl)

	# center-bottom, above the hint bar
	await get_tree().process_frame
	if not is_instance_valid(strip):
		return
	strip.position = Vector2((vp.x - strip.size.x) / 2.0, vp.y - STRIP_BOTTOM_MARGIN - strip.size.y)
	if _complete:
		return  # snapped mid-layout-frame — labels already carry final text, stay visible

	_snaps.append(func() -> void:
		if is_instance_valid(strip):
			strip.modulate.a = 1.0
		for li in range(labels.size()):
			if is_instance_valid(labels[li]):
				labels[li].text = chips[li][1]
				labels[li].modulate.a = 1.0)
	if not flourish:
		return

	strip.modulate.a = 0.0
	var base_delay := 1.5
	var tw := _track(create_tween())
	tw.tween_interval(base_delay)
	tw.tween_property(strip, "modulate:a", 1.0, 0.2)
	for li in range(labels.size()):
		var lbl: Label = labels[li]
		var kind: String = chips[li][3]
		lbl.modulate.a = 0.0
		var ctw := _track(create_tween())
		ctw.tween_interval(base_delay + 0.25 + li * 0.22)
		ctw.tween_property(lbl, "modulate:a", 1.0, 0.12)
		if kind == "gold":
			ctw.tween_callback(func() -> void: SoundManager.play_battle("gold_pickup"))
			var gold_final: String = chips[li][1]
			var total := int(gold_final.split(" ")[0])
			var gsteps := mini(maxi(total, 1), 18)
			for s in range(1, gsteps + 1):
				var shown := int(float(total) * s / gsteps)
				ctw.tween_callback(func() -> void:
					if is_instance_valid(lbl):
						lbl.text = "%d G" % shown).set_delay(0.03)
		elif kind == "item" and SoundManager._sfx_manifest.has("loot_pop"):
			ctw.tween_callback(func() -> void: SoundManager.play_battle("loot_pop"))
		elif kind == "injury":
			ctw.tween_callback(func() -> void:
				if SoundManager._sfx_manifest.has("injury_sting"):
					SoundManager.play_death("injury_sting"))


func _build_prompt() -> void:
	var prompt := Label.new()
	prompt.text = "A: finish · A: continue"
	prompt.add_theme_font_size_override("font_size", TextScale.scaled(11))
	prompt.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(prompt)
	var vp := get_viewport_rect().size
	prompt.position = Vector2(vp.x - 220.0, vp.y - 26.0)
	_snaps.append(func() -> void:
		if is_instance_valid(prompt):
			prompt.text = "A: continue"
			prompt.modulate.a = 1.0)
	var blink := _track(create_tween())
	blink.set_loops()
	blink.tween_property(prompt, "modulate:a", 0.3, 0.8)
	blink.tween_property(prompt, "modulate:a", 1.0, 0.8)
