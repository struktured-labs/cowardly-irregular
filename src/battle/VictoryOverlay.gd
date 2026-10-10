extends Control
class_name VictoryOverlay

## Victory overlay revamp (struktured 2026-08-18, direction locked): VICTORY slam →
## character-anchored cards beside each victory-posing sprite → loot toast strip.
## One press snaps everything to its end state (complete_now), the next dismisses
## (GameLoop._wait_for_confirm_victory drives that contract). ≥4x/turbo/OFF-tier or
## victory_flourish off = built pre-completed. Node is named "VictoryResults" by the
## caller — three consumers key off that name (Select toggle, quip suppression, cleanup).

## Victory grades — he asked for it to "look more amazing against bosses or OP monsters"
## SPOTLIGHT (struktured 2026-09-07 "spotlight should have a victory sequence… make it special"): a won duel is billed to the duelist, boss-scale spectacle in the spotlight's own cool white.
enum Grade { NORMAL = 0, ELITE = 1, BOSS = 2, SPOTLIGHT = 3 }
## An ordinary monster this far above the party reads as "OP" even without a boss flag
const OP_LEVEL_GAP := 3
const GRADE_FONT := {Grade.NORMAL: 48, Grade.ELITE: 58, Grade.BOSS: 72, Grade.SPOTLIGHT: 72}
const GRADE_TRAUMA := {Grade.NORMAL: 0.22, Grade.ELITE: 0.38, Grade.BOSS: 0.62, Grade.SPOTLIGHT: 0.62}
const GRADE_ZOOM := {Grade.NORMAL: 0.035, Grade.ELITE: 0.055, Grade.BOSS: 0.085, Grade.SPOTLIGHT: 0.085}
const GRADE_RINGS := {Grade.NORMAL: 1, Grade.ELITE: 2, Grade.BOSS: 3, Grade.SPOTLIGHT: 4}
const GRADE_HOLD := {Grade.NORMAL: 0.45, Grade.ELITE: 0.62, Grade.BOSS: 0.95, Grade.SPOTLIGHT: 1.1}
const GRADE_TINT := {
	Grade.NORMAL: Color(1.0, 0.85, 0.2),
	Grade.ELITE: Color(1.0, 0.62, 0.95),
	Grade.BOSS: Color(1.0, 0.97, 0.72),
	Grade.SPOTLIGHT: Color(0.78, 0.96, 1.0),
}

## Set by BattleResultsDisplay when GameLoop reports a live Spotlight Duel: the duelist's name.
var spotlight_duelist: String = ""

## 340, not 210: at 210 the one-line level-up clipped its own stats and the learned spell ("MP +9 M").
const CARD_W := 340.0
## Room for the level-up line on EVERY card: at 58 a level-up card grew when its line appeared and overlapped the next.
const CARD_H := 74.0
const CARD_GAP := 8.0
## Artist party frames display ~315px centred on the slot; a left flourish reaches ~157px past origin (F12 2026-09-20).
const CARD_SPRITE_GAP := 200.0
const LOG_CLEAR_X := 190.0
const STRIP_BOTTOM_MARGIN := 64.0

var _scene = null
var _snaps: Array[Callable] = []
var _tweens: Array[Tween] = []
var _complete := false
var _age := 0.0


## Where this overlay settles: the title at rest and docked, every card, the loot strip. Other victory chrome reads it to stay clear.
var _occupied: Array[Rect2] = []


func occupied_rects() -> Array[Rect2]:
	return _occupied.duplicate()


## Where the title rests and sweeps to its dock, and when it has docked: a card that would land there waits (slam -> cards, as documented).
var _title_rest := Rect2()
## Where the title SETTLES (docked, at 0.55 scale); the loot strip hangs under it.
var _title_docked := Rect2()
var _title_clear_at := 0.0


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
	if BattleManager and BattleManager.last_post_battle_restore_serial == BattleManager.battle_serial:
		show_restores(BattleManager.last_post_battle_restore)

	if not flourish:
		complete_now()


## The post-victory rest on each card ("+12 MP"), from the amounts actually applied. Either order works:
## GameLoop calls this after applying, and build() reads it if the rest already landed.
func show_restores(by_name: Dictionary) -> void:
	for c in get_children():
		if not (c is PanelContainer) or not c.has_meta("member_name"):
			continue
		var line: Label = c.find_child("RestoreLine", true, false)
		if line == null:
			continue
		var got: Dictionary = by_name.get(str(c.get_meta("member_name")), {})
		var parts: PackedStringArray = []
		if int(got.get("hp", 0)) > 0:
			parts.append("+%d HP" % int(got["hp"]))
		if int(got.get("mp", 0)) > 0:
			parts.append("+%d MP" % int(got["mp"]))
		line.text = "  ".join(parts)
		line.visible = not parts.is_empty()


func is_complete() -> bool:
	return _complete


## A cascade watched to its end is complete too; else the first press "finished" nothing and continuing took a second one.
func _process(delta: float) -> void:
	_age += delta
	if not _complete and _age > 0.5 and _settled():
		complete_now()


func _settled() -> bool:
	if _tweens.is_empty():
		return false
	for t in _tweens:
		if t and t.is_valid() and t.is_running():
			return false
	return true


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

## Boss > elite > normal, from the metas BattleEnemySpawner stamps plus the monster's own data.
## The spawner sets is_boss for minibosses too, so the boss/elite split comes from monsters.json.
func _victory_grade() -> int:
	var grade: int = Grade.NORMAL
	if spotlight_duelist != "":
		return Grade.SPOTLIGHT
	if _scene == null or not ("test_enemies" in _scene):
		return grade
	var party_level: int = _party_level()
	for e in _scene.test_enemies:
		if not is_instance_valid(e):
			continue
		if e.has_meta("is_boss") and e.get_meta("is_boss"):
			var data: Dictionary = BestiarySystem.get_monster_data(str(e.get_meta("monster_type", "")))
			grade = maxi(grade, Grade.BOSS if data.get("boss", false) else Grade.ELITE)
		elif party_level > 0 and "job_level" in e and int(e.job_level) >= party_level + OP_LEVEL_GAP:
			grade = maxi(grade, Grade.ELITE)
	return grade


func _party_level() -> int:
	if _scene == null or not ("party_members" in _scene):
		return 0
	var total := 0
	var n := 0
	for m in _scene.party_members:
		if is_instance_valid(m) and "job_level" in m:
			total += int(m.job_level)
			n += 1
	return int(total / float(n)) if n > 0 else 0


## The name that gets billed under VICTORY on a boss kill
func _headline_foe() -> String:
	if _scene == null or not ("test_enemies" in _scene):
		return ""
	for e in _scene.test_enemies:
		if is_instance_valid(e) and e.has_meta("is_boss") and e.get_meta("is_boss"):
			return str(e.combatant_name) if "combatant_name" in e else ""
	return ""


func _build_slam(flourish: bool) -> void:
	var grade: int = _victory_grade()
	var vp := get_viewport_rect().size
	var tint: Color = GRADE_TINT[grade]

	var title := Label.new()
	title.text = "V I C T O R Y"
	title.add_theme_font_size_override("font_size", TextScale.scaled(int(GRADE_FONT[grade])))
	title.add_theme_color_override("font_color", tint)
	title.add_theme_constant_override("outline_size", 3 if grade == Grade.NORMAL else 5)
	title.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	title.reset_size()
	var center := Vector2((vp.x - title.size.x) / 2.0 - 120.0, vp.y * 0.30)
	var docked := Vector2(center.x, 28.0)
	_occupied.append(Rect2(center, title.size))
	_occupied.append(Rect2(docked, title.size * 0.55))
	title.pivot_offset = title.size / 2.0
	_title_docked = Rect2(docked + title.pivot_offset * 0.45, title.size * 0.55)
	_snaps.append(func() -> void:
		if is_instance_valid(title):
			title.position = docked
			title.scale = Vector2(0.55, 0.55)
			title.modulate.a = 1.0)

	var impact_at := title.position + title.pivot_offset if not flourish else center + title.pivot_offset
	var sub: Label = null
	if grade >= Grade.BOSS:
		sub = _build_subtitle(center, title.size, tint, flourish)
	if grade >= Grade.ELITE:
		_build_letterbox(vp, grade, flourish)

	if not flourish:
		return

	# Slam in (0.20 + 0.09 + 0.11), hold, dock (0.3). The footprint is the rest spot, a boss subtitle beneath it, and the path up to the dock.
	_title_rest = Rect2(center, title.size).merge(Rect2(docked + title.pivot_offset * 0.45, title.size * 0.55))
	if sub != null:
		_title_rest = _title_rest.merge(Rect2(sub.position, sub.size))
	_title_clear_at = 0.40 + float(GRADE_HOLD[grade]) + 0.3
	title.position = center
	title.scale = Vector2(2.6 if grade >= Grade.BOSS else 2.2, 2.6 if grade >= Grade.BOSS else 2.2)
	title.modulate.a = 0.0

	var tw := _track(create_tween())
	tw.tween_property(title, "modulate:a", 1.0, 0.07)
	tw.parallel().tween_property(title, "scale", Vector2(0.92, 1.08), 0.20) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(title, "scale", Vector2(1.04, 0.96), 0.09).set_trans(Tween.TRANS_SINE)
	tw.tween_property(title, "scale", Vector2.ONE, 0.11) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(float(GRADE_HOLD[grade]))
	tw.tween_property(title, "position", docked, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(title, "scale", Vector2(0.55, 0.55), 0.3)
	if sub != null:
		var st := _track(create_tween())
		st.tween_interval(0.20 + float(GRADE_HOLD[grade]) + 0.30)
		st.tween_property(sub, "modulate:a", 0.0, 0.25)

	_spawn_impact(impact_at, grade, tint)


## The sweep + punch that makes the landing read as an IMPACT rather than a fade-in. struktured
## 2026-10-03: "the victory Circle with victory text in the middle is also amateur imho — we need
## VISUALS" — replaces the old expanding-ring with a bolder band that sweeps the full screen width.
func _spawn_impact(at: Vector2, grade: int, tint: Color) -> void:
	BattleJuice.add_trauma(float(GRADE_TRAUMA[grade]))
	BattleJuice.punch_zoom(get_viewport_rect().size / 2.0, float(GRADE_ZOOM[grade]), 0.22)
	BattleJuice.spawn_burst(at, Vector2(0, -1), 10 + 8 * grade, tint, 180.0 + 60.0 * grade)
	_spawn_sweep_band(at, tint, grade)
	if SoundManager and SoundManager._sfx_manifest.has("victory_slam"):
		SoundManager.play_battle("victory_slam")


## A bolder banner than a ring: a tinted band sweeps the full screen width through the impact
## point, then narrows and fades as the title finishes its punch-in — a "whoosh", not a circle.
func _spawn_sweep_band(at: Vector2, tint: Color, grade: int) -> void:
	var vp := get_viewport_rect().size
	var h: float = 26.0 + 10.0 * grade
	var band := ColorRect.new()
	band.name = "VictorySweepBand"
	band.color = Color(tint.r, tint.g, tint.b, 0.0)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.size = Vector2(vp.x * 1.6, h)
	band.rotation = deg_to_rad(-3.0)
	band.pivot_offset = Vector2(band.size.x / 2.0, h / 2.0)
	band.position = Vector2(-vp.x * 0.8, at.y - h / 2.0)
	add_child(band)
	## Same as the old ring: the band frees itself at the tween's end, so the snap uses a WeakRef.
	var band_ref: WeakRef = weakref(band)
	_snaps.append(func() -> void:
		var b: Object = band_ref.get_ref()
		if b != null:
			b.queue_free())
	var t := _track(create_tween())
	t.tween_property(band, "color:a", 0.85, 0.05)
	t.parallel().tween_property(band, "position:x", vp.x * 0.5 - band.size.x / 2.0, 0.16) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(band, "color:a", 0.0, 0.22 + 0.05 * grade)
	t.parallel().tween_property(band, "position:x", vp.x * 1.3 - band.size.x / 2.0, 0.26 + 0.05 * grade) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_callback(band.queue_free)

	# A thinner counter-sweep for elite+ grades, same timing, opposite direction — more banner, less circle.
	if grade < Grade.ELITE:
		return
	var band2 := ColorRect.new()
	band2.name = "VictorySweepBandCounter"
	band2.color = Color(1.0, 1.0, 1.0, 0.0)
	band2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band2.size = Vector2(vp.x * 1.6, h * 0.4)
	band2.rotation = deg_to_rad(3.0)
	band2.pivot_offset = Vector2(band2.size.x / 2.0, band2.size.y / 2.0)
	band2.position = Vector2(vp.x * 1.3, at.y - band2.size.y / 2.0)
	add_child(band2)
	var band2_ref: WeakRef = weakref(band2)
	_snaps.append(func() -> void:
		var b2: Object = band2_ref.get_ref()
		if b2 != null:
			b2.queue_free())
	var t2 := _track(create_tween())
	t2.tween_interval(0.05)
	t2.tween_property(band2, "color:a", 0.6, 0.05)
	t2.parallel().tween_property(band2, "position:x", vp.x * 0.5 - band2.size.x / 2.0, 0.16) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t2.tween_property(band2, "color:a", 0.0, 0.2)
	t2.parallel().tween_property(band2, "position:x", -vp.x * 0.8, 0.24) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t2.tween_callback(band2.queue_free)


## Boss kills get billed: the foe's name under the title
func _build_subtitle(center: Vector2, title_size: Vector2, tint: Color, flourish: bool) -> Label:
	var foe := _headline_foe()
	if foe == "" and spotlight_duelist == "":
		return null
	var sub := Label.new()
	sub.text = "%s FELLED" % foe.to_upper()
	if spotlight_duelist != "":
		sub.text = "%s TAKES THE SPOTLIGHT" % spotlight_duelist.to_upper()
		if foe != "":
			sub.text += " — %s FELLED" % foe.to_upper()
	sub.add_theme_font_size_override("font_size", TextScale.scaled(20))
	sub.add_theme_color_override("font_color", tint)
	sub.add_theme_constant_override("outline_size", 4)
	sub.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.0))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sub)
	sub.reset_size()
	sub.position = Vector2(center.x + (title_size.x - sub.size.x) / 2.0, center.y + title_size.y + 6.0)
	_snaps.append(func() -> void:
		if is_instance_valid(sub):
			sub.modulate.a = 0.0)
	if not flourish:
		sub.modulate.a = 0.0
		return sub
	sub.modulate.a = 0.0
	var t := _track(create_tween())
	t.tween_interval(0.34)
	t.tween_property(sub, "modulate:a", 1.0, 0.18)
	return sub


## Cinematic bars for elite/boss kills — they retract with the title so the cards are never boxed in
func _build_letterbox(vp: Vector2, grade: int, flourish: bool) -> void:
	var h: float = 34.0 + 14.0 * (grade - Grade.ELITE)
	for edge in [0.0, 1.0]:
		var bar := ColorRect.new()
		bar.color = Color(0.0, 0.0, 0.02, 0.85)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.size = Vector2(vp.x, h)
		var shown := Vector2(0.0, (vp.y - h) * edge)
		var hidden := Vector2(0.0, -h if edge == 0.0 else vp.y)
		bar.position = hidden if flourish else hidden
		add_child(bar)
		## Same as the ring: the bar frees itself, so the snap must not hold it.
		var bar_ref: WeakRef = weakref(bar)
		_snaps.append(func() -> void:
			var b: Object = bar_ref.get_ref()
			if b != null:
				b.queue_free())
		if not flourish:
			continue
		var t := _track(create_tween())
		t.tween_property(bar, "position", shown, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_interval(float(GRADE_HOLD[grade]) + 0.30)
		t.tween_property(bar, "position", hidden, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		t.tween_callback(bar.queue_free)


## -- Stage 2: character cards ----------------------------------------------

func _build_cards(char_results: Array, flourish: bool) -> void:
	var vp := get_viewport_rect().size
	var column := _column_positions(char_results.size(), vp)
	## The column enters as ONE cascade, top to bottom. Per-card waits let a card clear of the title slam
	## arrive alone, mid-column, before the ones above it; if any card must wait, they all start together.
	var start := 0.5
	for p in column:
		if _title_rest.has_area() and Rect2(p, Vector2(CARD_W, CARD_H)).intersects(_title_rest):
			start = maxf(start, _title_clear_at)
	for i in range(char_results.size()):
		var cr: Dictionary = char_results[i]
		var card := _make_card(cr)
		add_child(card)
		card.position = column[i]
		var delay := start + i * 0.12
		var final_pos := card.position
		_occupied.append(Rect2(final_pos, Vector2(CARD_W, CARD_H)))
		_snaps.append(func() -> void:
			if is_instance_valid(card):
				card.position = final_pos
				card.modulate.a = 1.0)
		if flourish:
			card.modulate.a = 0.0
			card.position.x += 48.0
			var tw := _track(create_tween())
			tw.tween_interval(delay)
			tw.tween_property(card, "modulate:a", 1.0, 0.15)
			tw.parallel().tween_property(card, "position:x", final_pos.x, 0.26) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_animate_card_content(card, cr, i, delay, flourish)


## Card hangs LEFT of its sprite (party faces left). CARD_SPRITE_GAP clears the centred 315px flourish.
func _card_position(i: int, count: int, vp: Vector2) -> Vector2:
	var y_fallback := vp.y * 0.18 + i * (CARD_H + CARD_GAP)
	var pos := Vector2(vp.x * 0.42, y_fallback)
	if _scene and i < _scene.party_sprite_nodes.size():
		var sprite = _scene.party_sprite_nodes[i]
		if is_instance_valid(sprite) and sprite.is_inside_tree():
			var sp: Vector2 = sprite.get_global_transform_with_canvas().origin
			# Anchor on the SETTLED spot, not the transient one (struktured cap 2026-08-31:
			# Cleric's card stranded mid-screen — she was mid-return from a heal lunge when
			# cards were placed, then settled home). Same class + fix as the bubble anchor.
			if sprite.has_meta("home_position"):
				var home = sprite.get_meta("home_position")
				if home is Vector2:
					sp += (home - sprite.position)
			pos = Vector2(sp.x - CARD_W - CARD_SPRITE_GAP, sp.y - CARD_H / 2.0)
	pos.x = clampf(pos.x, LOG_CLEAR_X, vp.x - CARD_W - 8.0)
	pos.y = clampf(pos.y, 56.0, vp.y - STRIP_BOTTOM_MARGIN - CARD_H)
	return pos


## The cards as ONE column: each still at its own character's height, but sharing the leftmost card's x
## and never closer than a card apart, so a staggered formation no longer scatters them diagonally.
func _column_positions(count: int, vp: Vector2) -> Array[Vector2]:
	var raw: Array[Vector2] = []
	var x := INF
	for i in range(count):
		var p := _card_position(i, count, vp)
		raw.append(p)
		x = minf(x, p.x)
	## Evenly spaced, centred on where the party stands: anchored per character, the gaps followed the
	## formation's stagger and read as scattered. Order still follows the party, top to bottom.
	var mid := 0.0
	for p in raw:
		mid += p.y
	mid /= maxf(1.0, float(raw.size()))
	var block_h := count * CARD_H + maxi(0, count - 1) * CARD_GAP
	var top := mid + CARD_H / 2.0 - block_h / 2.0
	## Never up into the docked title and the loot strip that hangs under it.
	top = maxf(top, 150.0)
	var out: Array[Vector2] = []
	for i in range(count):
		out.append(Vector2(x, clampf(top + i * (CARD_H + CARD_GAP), 56.0, vp.y)))
	## Pushed past the bottom: lift the whole column, keeping the spacing.
	var bottom_limit := vp.y - STRIP_BOTTOM_MARGIN - CARD_H
	if out.size() > 0 and out[out.size() - 1].y > bottom_limit:
		var lift := out[out.size() - 1].y - bottom_limit
		for i in range(out.size()):
			out[i].y = maxf(56.0, out[i].y - lift)
	return out


func _make_card(cr: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, CARD_H)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.15, 0.50)
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

	# Portrait chip — through the world-aware resolver, never a hand-built path (2026-08-09 six-surfaces defect)
	var job_key := str(cr.get("job_name", "")).to_lower()
	var tex_path: String = HybridSpriteLoader.portrait_path(job_key)
	if tex_path != "" and ResourceLoader.exists(tex_path):
		var chip := TextureRect.new()
		chip.custom_minimum_size = Vector2(40, 40)
		chip.texture = HybridSpriteLoader.fitted_portrait(load(tex_path), chip.custom_minimum_size)
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
	# A KO who was paid still needs the bar. A KO with +0 stays bar-less so the card keeps reading "KO".
	var earned_down: bool = not alive and (int(cr.get("exp_gained", 0)) > 0 or bool(cr.get("leveled_up", false)))
	top.text = "%s  %s" % [cr.get("name", "?"), "+0 EXP" if alive else "KO"]
	top.add_theme_font_size_override("font_size", TextScale.scaled(13))
	top.add_theme_color_override("font_color", Color.WHITE if alive else Color(0.6, 0.45, 0.45))
	## Outlined so the line reads over any backdrop while the card itself stays translucent.
	top.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	top.add_theme_constant_override("outline_size", 4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top_row := HBoxContainer.new()
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(top)
	v.add_child(top_row)

	if alive or earned_down:
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

	## What the post-victory rest gave this member, filled by show_restores; empty (and hidden) for a KO
	## or a full bar, because "+0 MP" is noise.
	var rest := Label.new()
	rest.name = "RestoreLine"
	rest.visible = false
	rest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rest.add_theme_font_size_override("font_size", TextScale.scaled(12))
	rest.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
	rest.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	rest.add_theme_constant_override("outline_size", 4)
	rest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## On the NAME row, right-aligned: beside the whole column it took width from the bar and the
	## one-line level-up, which clipped again.
	top_row.add_child(rest)
	card.set_meta("member_name", str(cr.get("name", "")))

	var gains := Label.new()
	gains.name = "GainsLine"
	gains.text = ""
	gains.visible = false
	gains.clip_text = true  # one compact line — the 700px 5-level-up clip rule
	gains.add_theme_font_size_override("font_size", TextScale.scaled(11))
	gains.add_theme_color_override("font_color", Color(1.0, 1.0, 0.3))
	gains.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	gains.add_theme_constant_override("outline_size", 4)
	gains.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(gains)
	return card


func _animate_card_content(card: PanelContainer, cr: Dictionary, idx: int, delay: float, flourish: bool) -> void:
	var alive: bool = bool(cr.get("is_alive", true))
	var exp_gained: int = int(cr.get("exp_gained", 0))
	var leveled: bool = bool(cr.get("leveled_up", false))
	# Posthumous Credit pays this while KO. Show the grant; do not play the victory pose on a corpse.
	if not alive and exp_gained <= 0 and not leveled:
		return
	var top: Label = card.find_child("TopLine", true, false)
	var bar_bg: ColorRect = card.find_child("BarBg", true, false)
	var fill: ColorRect = card.find_child("BarFill", true, false)
	var gains: Label = card.find_child("GainsLine", true, false)

	var exp_before: int = int(cr.get("job_exp_before", 0))
	var exp_to_next: int = maxi(1, int(cr.get("exp_to_next", 100)))
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
	var ko_mark := "" if alive else "  KO"
	var final_top := "%s  +%d EXP%s%s" % [cr.get("name", "?"), exp_gained, "  ★ Lv.%d" % int(cr.get("job_level", 1)) if leveled else "", ko_mark]
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
				top.text = "%s  +%d EXP%s" % [cr.get("name", "?"), shown, ko_mark]).set_delay(0.04)
	if leveled:
		tw.tween_property(fill, "size:x", bar_w, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func() -> void:
			if alive:
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
	## A learned spell FIRST: the line is one clipped line, so whatever is last is what gets cut.
	var learned: Array = cr.get("learned_abilities", [])
	if not learned.is_empty():
		var names: PackedStringArray = []
		for aid in learned:
			var ab: Dictionary = JobSystem.get_ability(str(aid)) if JobSystem else {}
			names.append(str(ab.get("name", str(aid).capitalize())))
		parts.append("✦ " + ", ".join(names))
	var gains: Dictionary = cr.get("stat_gains", {})
	for stat in ["HP", "MP", "ATK", "DEF", "MAG", "SPD"]:
		if gains.has(stat) and int(gains[stat]) != 0:
			parts.append("%s +%d" % [stat, int(gains[stat])])
	return "LEVEL UP!  " + "  ".join(parts)


func _level_up_flare(card: PanelContainer, fill: ColorRect, idx: int) -> void:
	if is_instance_valid(fill):
		var flash := _track(create_tween())
		flash.tween_property(fill, "color", Color(1.0, 0.9, 0.2), 0.12)
		flash.tween_property(fill, "color", Color(0.2, 0.8, 0.5), 0.18)
	if SoundManager._sfx_manifest.has("levelup_flourish"):
		SoundManager.play_flourish("levelup_flourish")
	else:
		SoundManager.play_music("stinger_level_up")
		SoundManager.play_flourish("level_up")
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
		chips.append([txt, txt, Color(0.6, 0.9, 1.0), "item", str(drop.get("item", ""))])
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
		var chip_px := TextScale.scaled(14)
		lbl.add_theme_font_size_override("font_size", chip_px)
		lbl.add_theme_color_override("font_color", chip[2])
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon_id := str(chip[4]) if chip.size() > 4 else ""
		if icon_id != "":
			var row := HBoxContainer.new()
			row.name = "LootItem"
			row.add_theme_constant_override("separation", 4)
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(ItemIcons.make_rect(icon_id, 32))
			row.add_child(lbl)
			h.add_child(row)
		else:
			h.add_child(lbl)
		labels.append(lbl)

	# center-bottom, above the hint bar
	await get_tree().process_frame
	if not is_instance_valid(strip):
		return
	## Under the VICTORY title, not over the battle log: the rewards read as the headline's second line.
	strip.position = Vector2((vp.x - strip.size.x) / 2.0, vp.y - STRIP_BOTTOM_MARGIN - strip.size.y)
	if _title_docked.has_area():
		strip.position = Vector2(_title_docked.get_center().x - strip.size.x / 2.0, _title_docked.end.y + 6.0)
		strip.position.x = clampf(strip.position.x, 8.0, vp.x - strip.size.x - 8.0)
	_occupied.append(Rect2(strip.position, strip.size))
	if _complete:
		return  # snapped mid-layout-frame — labels already carry final text, stay visible

	_snaps.append(func() -> void:
		if is_instance_valid(strip):
			strip.modulate.a = 1.0
		for li in range(labels.size()):
			if is_instance_valid(labels[li]):
				labels[li].text = chips[li][1]
				labels[li].modulate.a = 1.0
				var holder := labels[li].get_parent() as CanvasItem
				if holder != null and str(holder.name) == "LootItem":
					holder.modulate.a = 1.0)
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
		var fade: CanvasItem = lbl
		var holder := lbl.get_parent() as CanvasItem
		if holder != null and str(holder.name) == "LootItem":
			fade = holder
		fade.modulate.a = 0.0
		var ctw := _track(create_tween())
		ctw.tween_interval(base_delay + 0.25 + li * 0.22)
		ctw.tween_property(fade, "modulate:a", 1.0, 0.12)
		if kind == "gold":
			ctw.tween_callback(func() -> void: SoundManager.play_pickup("gold_pickup"))
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


## The prompt a player reads after EVERY battle. `ui_accept` advances it (GameLoop's
## _wait_for_confirm_victory), and this game puts Confirm on the EAST face — Ⓐ on a Switch pad, Ⓑ on
## Xbox, ○ on PlayStation, and Z/Enter/Space on a keyboard. The frozen "A" was right on exactly one
## family and named a button keyboard players do not have.
func _confirm_token() -> String:
	var ipm = Engine.get_main_loop().root.get_node_or_null("InputProfileManager")
	if ipm == null:
		return "Z"
	var hint: String = ipm.hint_for_action("ui_accept")
	return hint if hint != "" else "Z"


static func tally_prompt(tok: String) -> String:
	return "%s: skip" % tok


func _build_prompt() -> void:
	var prompt := Label.new()
	# One key, one job at a time: the old line named the confirm button twice, for finish and then for continue.
	prompt.text = tally_prompt(_confirm_token())
	prompt.add_theme_font_size_override("font_size", TextScale.scaled(14))
	prompt.add_theme_color_override("font_color", Color(0.92, 0.92, 0.85))
	prompt.add_theme_constant_override("outline_size", 3)
	prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(prompt)
	var vp := get_viewport_rect().size
	# Bottom-centre above the hint bar; it sat at 11px grey on the grass under the party panel's corner.
	prompt.size = Vector2(320.0, 0.0)
	prompt.position = Vector2((vp.x - 320.0) / 2.0, vp.y - 58.0)
	_snaps.append(func() -> void:
		if is_instance_valid(prompt):
			prompt.text = "%s: continue" % _confirm_token()
			prompt.modulate.a = 1.0)
	var blink := create_tween()  # untracked: an endless loop must not hold the cascade open
	blink.set_loops()
	blink.tween_property(prompt, "modulate:a", 0.55, 0.8)
	blink.tween_property(prompt, "modulate:a", 1.0, 0.8)
