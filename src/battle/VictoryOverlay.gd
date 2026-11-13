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
## Cards grow with Text Size so the post-tween top line ("Name  +99999 EXP  ★ Lv.11") still fits,
## but never past what the screen can stack. Set once per build from the party count.
## Width and height are bounded by DIFFERENT things, so they scale separately. The stack is
## height-constrained — five cards have to fit between the loot strip and the bottom bar — while
## the width has most of the screen spare to the right of the column.
var _cscale: float = 1.0
var _wscale: float = 1.0
## The tallest a card's own content can draw (a level-up card with its gains line); a card is never shorter, whatever the fit cap allows.
var _card_min_h: float = 0.0
## The air between cards: CARD_GAP when the column has room, down to MIN_CARD_GAP when cards at their content height must still fit.
var _gap: float = CARD_GAP
const MIN_CARD_GAP := 2.0
## When cards at their content height still overflow the column, their padding gives way, never the text Text Size grew.
var _compact := false
const CARD_PAD := 5
const COMPACT_PAD := 1
## Artist party frames display ~315px centred on the slot; a left flourish reaches ~157px past origin (F12 2026-09-20).
const CARD_SPRITE_GAP := 200.0
const LOG_CLEAR_X := 190.0
## The battle's left column (struktured 2026-11-12: "the exp cards still overlap with the enemy cards"): the cards start right of whichever of these is showing.
const LEFT_COLUMN: Array[String] = ["EnemyStatusPanel", "BattleLogPanel", "CTBTimeline"]
const LEFT_COLUMN_GAP := 10.0
const STRIP_BOTTOM_MARGIN := 64.0
## The continue prompt: its base size, its resting distance from the bottom, and the air it keeps from the hint bar and the cards.
const PROMPT_FONT := 14
const PROMPT_REST := 58.0
const PROMPT_GAP := 4.0

var _scene = null
var _one_shot_rank: String = ""
var _snaps: Array[Callable] = []
var _tweens: Array[Tween] = []
var _complete := false
var _age := 0.0


## Where this overlay settles: the title at rest and docked, every card, the loot strip. Other victory chrome reads it to stay clear.
var _occupied: Array[Rect2] = []


## The Text Size multiplier itself. `TextScale.scaled` rounds to an int, so it is sampled at a
## large base to keep the ratio exact.
func _raw_text_scale() -> float:
	return float(TextScale.scaled(1000)) / 1000.0


## How much the cards may grow IN HEIGHT. Only ever GROWS — at 80% Text Size the cards stay exactly
## as they are today, so 100% and below are pixel-identical to before this change.
##
## The cap is the point of the function: at 200% five cards would need 5*148 + 4*16 = 804px of the
## 600px the stack has between the y=56 clamp and the bottom strip, so an uncapped scale would push
## the party's own cards off the screen to fix a text overflow.
func _fit_card_scale(count: int, vp_y: float) -> float:
	var want: float = maxf(1.0, _raw_text_scale())
	if count <= 0:
		return want
	var room: float = vp_y - _stack_top() - _bottom_margin(vp_y) - float(maxi(0, count - 1)) * CARD_GAP
	var cap: float = room / (float(count) * CARD_H)
	return clampf(want, 1.0, maxf(1.0, cap))


## The first y a card may occupy: below the docked title, and below the loot strip if there is one.
## Both of those grow with Text Size, which is why this is derived rather than the old literal 150.
## Where the continue prompt will sit, reserved BEFORE the cards are placed: at its resting line, lifted clear of the hint bar when the text has grown into it.
var _prompt_rect := Rect2()


func _reserve_prompt() -> void:
	var vp := get_viewport_rect().size
	var px: int = TextScale.scaled(PROMPT_FONT)
	var h: float = get_theme_default_font().get_height(px) if get_theme_default_font() else float(px) * 1.4
	var top: float = vp.y - PROMPT_REST
	var hint: Control = (_scene as Node).get_node_or_null("UI/InputHintBar") as Control if is_instance_valid(_scene) and _scene is Node else null
	if hint != null and hint.is_visible_in_tree() and hint.get_global_rect().has_area():
		top = minf(top, hint.get_global_rect().position.y - PROMPT_GAP - h)
	_prompt_rect = Rect2((vp.x - 320.0) / 2.0, top, 320.0, h)


## How much of the bottom the card column leaves: the shipped margin, or more when the prompt has been lifted.
func _bottom_margin(vp_y: float) -> float:
	if not _prompt_rect.has_area():
		return STRIP_BOTTOM_MARGIN
	return maxf(STRIP_BOTTOM_MARGIN, vp_y - _prompt_rect.position.y + PROMPT_GAP + 2.0)


func _stack_top() -> float:
	var y := 56.0
	if _title_docked.has_area():
		y = maxf(y, _title_docked.end.y + CARD_GAP)
	if _strip_rect.has_area():
		y = maxf(y, _strip_rect.end.y + CARD_GAP)
	return y


## How wide the cards may grow: the FULL text scale, clamped only by the screen.
##
## The card's RIGHT edge is anchored to the party sprite minus a fixed gap (`sp.x - _cw() - GAP`,
## so `pos.x + _cw()` is `sp.x - GAP` whatever the width) — growing a card moves its LEFT edge
## toward the battle log, not its right edge toward the screen edge. So the only real bound is
## that the column still starts clear of the log.
func _fit_card_width_scale(vp_x: float) -> float:
	var want: float = maxf(1.0, _raw_text_scale())
	var cap: float = (vp_x - 8.0 - _left_wall(vp_x)) / CARD_W
	return clampf(want, 1.0, maxf(1.0, cap))


## The first x a card may occupy: past the real right edge of every left-column panel on screen, never left of LOG_CLEAR_X.
func _left_wall(vp_x: float) -> float:
	var wall := LOG_CLEAR_X
	if not is_instance_valid(_scene) or not (_scene is Node):
		return wall
	for pname in LEFT_COLUMN:
		var panel := (_scene as Node).find_child(pname, true, false) as Control
		if panel == null or not panel.is_visible_in_tree():
			continue
		var r: Rect2 = panel.get_global_rect()
		## A panel that reaches past mid-screen is not a column (a widened log overlay): it is no wall.
		if r.has_area() and r.end.x <= vp_x * 0.5:
			wall = maxf(wall, r.end.x + LEFT_COLUMN_GAP)
	return wall


func _cw() -> float:
	return CARD_W * _wscale


func _ch() -> float:
	return maxf(CARD_H * _cscale, _card_min_h)


## The tallest card this victory will settle into, measured on each real card built in the tree with its FINAL text (the "★ Lv." top line and the gains line), not a stand-in.
func _measure_card_min_h(char_results: Array) -> float:
	var h := 0.0
	for cr in char_results:
		if not (cr is Dictionary):
			continue
		var probe := _make_card(cr)
		probe.custom_minimum_size = Vector2.ZERO
		var top := probe.find_child("TopLine", true, false) as Label
		if top != null:
			top.text = _final_top_text(cr)
		var gains := probe.find_child("GainsLine", true, false) as Label
		if gains != null and _gains_line(cr) != "":
			gains.text = _gains_line(cr)
			gains.visible = true
		add_child(probe)
		h = maxf(h, probe.get_combined_minimum_size().y)
		remove_child(probe)
		probe.free()
	return h


## The top line a card settles on; the build's roll-up ends here and the snap jumps here.
func _final_top_text(cr: Dictionary) -> String:
	var leveled: bool = bool(cr.get("leveled_up", false))
	var ko_mark := "" if bool(cr.get("is_alive", true)) else "  KO"
	return "%s  +%d EXP%s%s" % [cr.get("name", "?"), int(cr.get("exp_gained", 0)), "  ★ Lv.%d" % int(cr.get("job_level", 1)) if leveled else "", ko_mark]


## True when `count` cards of _ch() at MIN_CARD_GAP cannot fit between the stack top and the bottom margin.
func _overflows(count: int, vp_y: float) -> bool:
	return float(count) * _ch() + float(maxi(0, count - 1)) * MIN_CARD_GAP > vp_y - _stack_top() - _bottom_margin(vp_y)


## The gap that lets `count` cards of _ch() fit between the stack top and the bottom margin, never above CARD_GAP.
func _fit_gap(count: int, vp_y: float) -> float:
	if count <= 1:
		return CARD_GAP
	var spare: float = vp_y - _stack_top() - _bottom_margin(vp_y) - float(count) * _ch()
	return clampf(spare / float(count - 1), MIN_CARD_GAP, CARD_GAP)


func occupied_rects() -> Array[Rect2]:
	return _occupied.duplicate()


## Where the title rests and sweeps to its dock, and when it has docked: a card that would land there waits (slam -> cards, as documented).
var _title_rest := Rect2()
## Where the title SETTLES (docked, at 0.55 scale); the loot strip hangs under it.
var _title_docked := Rect2()
## Where the loot strip lands. The card stack hangs under THIS, so the column is title -> strip
## -> cards, each strictly below the last at every text size.
var _strip_rect := Rect2()
var _title_clear_at := 0.0


## Whether this victory gets the slam at all. Shared, because BattleResultsDisplay holds for the
## downbeat before building and must not reach a different answer than build() then acts on.
static func wants_flourish(scene) -> bool:
	if scene and scene.has_method("_tier"):
		return int(scene._tier()) <= BattleJuice.Tier.REDUCED and Engine.time_scale < 4.0 \
				and BattleJuice.flag("victory_flourish")
	return true


func build(results: Dictionary, scene) -> void:
	_scene = scene
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var flourish: bool = wants_flourish(scene)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.0, 0.05, 0.22)  # party stays lit (2026-07-11 ruling)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	## Order matters: the strip's rect feeds both the stack's top and the fit cap, so it has to
	## exist before a single card is placed. Cards were built first before this change, which is
	## why nothing could keep them clear of it.
	_one_shot_rank = _one_shot_rank_of(results.get("bonuses", []), str(results.get("one_shot_rank", "")))
	_build_slam(flourish)
	_build_loot_strip(results, flourish)
	_reserve_prompt()
	_build_cards(results.get("char_results", []), flourish)
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


## struktured 2026-11-07: the yellow sweep line was the wrong language, "make it more SNES-like, similar to the damage numbers".
## The title is PixelText now: letters drop in one at a time on whole pixels, a pixel starburst lands with the last one,
## glints play on the letters through the hold, and a one-shot rank is stamped in on the slam's frame.
const TITLE_TEXT := "VICTORY!"
const LETTER_STAGGER := 0.05
const LETTER_DROP := 0.18
## How far a letter falls, in its own glyph pixels.
const LETTER_FALL_CELLS := 14
## Docked, the title steps down to this share of its slam size, in whole glyph pixels.
const DOCK_SHARE := 0.55
const STAMP_TINT_S := Color(1.0, 0.85, 0.2)
const STAMP_TINT := Color(0.92, 0.95, 1.0)

## When the last letter lands: the slam's frame. Everything after the drop is timed from here.
var _title_land := 0.0
## The title's glyph pixel at the slam, so the starburst is drawn in the same pixel.
var _title_px := 4
var _impact_done := false


## Real time at every battle speed, kept across a mid-beat speed change; under a fixed-fps capture it steps 1/fps per frame (adhoc 23963).
func _wall(t: Tween) -> Tween:
	return _track(t.set_ignore_time_scale(true))


## A row of pixel letters that the overlay's rects, modulate and child lookups treat like the Label it replaced.
class PixelBanner extends Control:
	var text: String = ""
	var glyphs: PixelText = null

	func _init(t: String, px: int, tint: Color) -> void:
		text = t
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		glyphs = PixelText.new(t, px)
		glyphs.modulate = tint
		add_child(glyphs)
		set_px(px)

	## PixelText centres on its origin, so it sits at half the extent and the glyphs start at this Control's corner.
	func set_px(px: int) -> void:
		glyphs.set_pixel_scale(px)
		var cell: Vector2i = glyphs.base_size()
		size = Vector2(cell * px)
		glyphs.position = Vector2(int(cell.x * px / 2), int(cell.y * px / 2))

	func settle() -> void:
		glyphs.set_pixel_scale(glyphs.pixel_scale.x)
		for s in glyphs.glyph_sprites:
			s.visible = true


## Rays of chunky square chips, each with its dark rim, flying out on the glyph pixel grid and blinking out at the end.
class PixelBurst extends Node2D:
	var px := 4
	var rays := 8
	var reach := 160.0
	var trail := 2
	var tint := Color.WHITE
	var progress := 0.0

	func set_progress(v: float) -> void:
		progress = v
		queue_redraw()

	func _draw() -> void:
		for r in rays:
			var dir := Vector2.from_angle(TAU * float(r) / float(rays) - PI / 2.0)
			var length: float = reach * (1.0 if r % 2 == 0 else 0.62)
			for k in trail:
				var p: float = progress - 0.08 * float(k)
				if p <= 0.0 or p >= 1.0 or (p > 0.7 and int(p * 24.0) % 2 == 1):
					continue
				var cells: int = maxi(1, 3 - k - int(p * 3.0))
				var mid: Vector2 = (dir * length * (1.0 - pow(1.0 - p, 3.0)) / float(px)).round() * float(px)
				var at: Vector2 = mid - Vector2(float((cells / 2) * px), float((cells / 2) * px))
				var side := Vector2(float(cells * px), float(cells * px))
				draw_rect(Rect2(at - Vector2(px, px), side + Vector2(px, px) * 2.0), PixelText.OUTLINE)
				draw_rect(Rect2(at, side), Color.WHITE if k == 0 and p < 0.35 else tint)


## The glyph pixel for a grade: the old point size over the glyph's cell, never wider than the screen allows.
func _title_px_for(grade: int, vp_x: float) -> int:
	var px: int = roundi(float(TextScale.scaled(int(GRADE_FONT[grade]))) / 8.0)
	return clampi(px, 2, maxi(2, int((vp_x - 64.0) / float(PixelText.measure(TITLE_TEXT).x))))


func _build_slam(flourish: bool) -> void:
	var grade: int = _victory_grade()
	var vp := get_viewport_rect().size
	var tint: Color = GRADE_TINT[grade]
	var px: int = _title_px_for(grade, vp.x)
	var dock_px: int = maxi(2, roundi(float(px) * DOCK_SHARE))
	_title_px = px

	var title := PixelBanner.new(TITLE_TEXT, px, tint)
	title.name = "VictoryTitle"
	add_child(title)
	var center := Vector2((vp.x - title.size.x) / 2.0 - 120.0, vp.y * 0.30).round()
	var docked := Vector2(center.x, 28.0)
	var dock_size := Vector2(PixelText.measure(TITLE_TEXT) * dock_px)
	var dock_at: Vector2 = (docked + (title.size - dock_size) / 2.0).round()
	_occupied.append(Rect2(center, title.size))
	_occupied.append(Rect2(dock_at, dock_size))
	_title_docked = Rect2(dock_at, dock_size)
	_title_land = LETTER_STAGGER * float(title.glyphs.glyph_sprites.size() - 1) + LETTER_DROP
	_snaps.append(func() -> void:
		if is_instance_valid(title):
			title.set_px(dock_px)
			title.position = dock_at
			title.settle()
			title.modulate.a = 1.0)

	var impact_at := title.position + title.size / 2.0 if not flourish else center + title.size / 2.0
	var sub: Control = null
	if grade >= Grade.BOSS:
		sub = _build_subtitle(center, title.size, tint, flourish)
	var stamp: Control = _build_stamp(center, title.size, px, flourish)
	if grade >= Grade.ELITE:
		_build_letterbox(vp, grade, flourish)

	if not flourish:
		return

	# Letters drop (stagger x7 + drop), hold, dock (0.3). The footprint is the rest spot, the bill and stamp beside it, and the path up to the dock.
	_title_rest = Rect2(center, title.size).merge(_title_docked)
	if sub != null:
		_title_rest = _title_rest.merge(Rect2(sub.position, sub.size))
	if stamp != null:
		_title_rest = _title_rest.merge(Rect2(stamp.position, stamp.size))
	## The beat runs on the wall clock and the cards on game time, so the wait is the real duration in game seconds.
	_title_clear_at = (_title_land + float(GRADE_HOLD[grade]) + 0.3) * Engine.time_scale
	title.position = center
	var letters: Array[Sprite2D] = title.glyphs.glyph_sprites
	for i in letters.size():
		var spr: Sprite2D = letters[i]
		var rest: Vector2 = title.glyphs.rest_position(spr)
		spr.visible = false
		var lt := _wall(create_tween())
		lt.tween_interval(LETTER_STAGGER * float(i))
		lt.tween_callback(spr.show)
		lt.tween_method(_drop_letter.bind(spr, rest, px), 0.0, 1.0, LETTER_DROP)
		if i < letters.size() - 1:
			lt.tween_callback(_tick_letter.bind(i + 1))

	var tw := _wall(create_tween())
	tw.tween_interval(_title_land)
	tw.tween_callback(func() -> void: _spawn_impact(impact_at, grade, tint))
	tw.tween_interval(float(GRADE_HOLD[grade]))
	tw.tween_method(_dock_step.bind(title, center, dock_at, px, dock_px), 0.0, 1.0, 0.3)
	_snaps.append(func() -> void:
		if not _impact_done:
			_play_slam())
	_spawn_glints(title, grade)


## A tick per landing, rising, for every letter but the last: its landing is the slam's frame and the slam is its voice.
## Pitched to what is sounding under it (cowir-sfx 23509, music 23503); SoundManager skips a key it does not have.
func _tick_letter(n: int) -> void:
	if SoundManager:
		SoundManager.play_victory_letter(n, _letters_under_key())


## What the letters land over, read off the LIVE stream like seconds_until_victory_downbeat: the boss stinger plays for
## minibosses too (BattleScene._check_for_boss), so the grade cannot say. Nothing playing: the world's victory bed.
func _letters_under_key() -> String:
	var mp: AudioStreamPlayer = SoundManager._music_player
	if mp != null and mp.playing and mp.stream != null and str(mp.stream.resource_path) != "":
		return str(mp.stream.resource_path).get_file().get_basename()
	return "victory_" + SoundManager.get_current_world_suffix()


## One letter's fall: a bounce eased in whole glyph pixels, so no frame of it sits between pixels.
func _drop_letter(t: float, spr: Sprite2D, rest: Vector2, px: int) -> void:
	if not is_instance_valid(spr):
		return
	var e: float = Tween.interpolate_value(0.0, 1.0, t, 1.0, Tween.TRANS_BOUNCE, Tween.EASE_OUT)
	spr.position = rest - Vector2(0.0, float(roundi(float(LETTER_FALL_CELLS) * (1.0 - e)) * px))


## The dock steps the glyph pixel down one whole size at a time while the title slides up on whole screen pixels.
func _dock_step(t: float, title: PixelBanner, from: Vector2, to: Vector2, px0: int, px1: int) -> void:
	if not is_instance_valid(title):
		return
	var e: float = Tween.interpolate_value(0.0, 1.0, t, 1.0, Tween.TRANS_CUBIC, Tween.EASE_IN_OUT)
	var px: int = roundi(lerpf(float(px0), float(px1), e))
	if title.glyphs.pixel_scale.x != px:
		title.set_px(px)
	title.position = from.lerp(to, e).round()


## Glints on the letters through the hold: a pixel "+" pops on a glyph's corner, grows a pixel, shrinks, and goes.
func _spawn_glints(title: PixelBanner, grade: int) -> void:
	var letters: Array[Sprite2D] = title.glyphs.glyph_sprites
	if letters.is_empty():
		return
	var gpx: int = maxi(2, _title_px / 2)
	var count: int = 2 + 2 * grade
	var step: float = float(GRADE_HOLD[grade]) / float(count)
	for i in count:
		var spr: Sprite2D = letters[(i * 3 + 1) % letters.size()]
		var at: Vector2 = title.glyphs.position + title.glyphs.rest_position(spr) \
				+ Vector2(float(((i % 2) * 4 + 1) * _title_px), float(((i / 2) % 2) * 5 * _title_px))
		var glint := PixelText.new("+", gpx)
		glint.name = "VictoryGlint"
		glint.position = at.round()
		glint.visible = false
		title.add_child(glint)
		var ref: WeakRef = weakref(glint)
		_snaps.append(func() -> void:
			var g: Object = ref.get_ref()
			if g != null:
				g.queue_free())
		var gt := _wall(create_tween())
		gt.tween_interval(_title_land + step * float(i))
		gt.tween_callback(glint.show)
		gt.tween_interval(0.05)
		gt.tween_callback(glint.set_pixel_scale.bind(gpx + 1))
		gt.tween_interval(0.06)
		gt.tween_callback(glint.set_pixel_scale.bind(gpx))
		gt.tween_interval(0.05)
		gt.tween_callback(glint.queue_free)


## S-rank earns its own slam; absent that asset the ordinary one still lands.
func _slam_key() -> String:
	if _one_shot_rank == "S" and SoundManager and SoundManager._sfx_manifest.has("victory_slam_s"):
		return "victory_slam_s"
	return "victory_slam"


## The slam celebrates the RANK, so an unpaid (over-levelled) one-shot keeps it through results.one_shot_rank.
func _one_shot_rank_of(bonuses: Array, reported_rank: String = "") -> String:
	for b in bonuses:
		if b is Dictionary and b.get("type", "") == "one_shot":
			return str(b.get("rank", ""))
	return reported_rank


## The slam's frame: shake, punch, sparks, a pixel starburst from where the title landed, and its own voice.
## struktured 2026-10-03 retired the ring ("amateur"), and 2026-11-07 retired the yellow sweep band that replaced it.
func _spawn_impact(at: Vector2, grade: int, tint: Color) -> void:
	BattleJuice.add_trauma(float(GRADE_TRAUMA[grade]))
	BattleJuice.punch_zoom(get_viewport_rect().size / 2.0, float(GRADE_ZOOM[grade]), 0.22)
	BattleJuice.spawn_burst(at, Vector2(0, -1), 10 + 8 * grade, tint, 180.0 + 60.0 * grade)
	_spawn_starburst(at, tint, grade)
	_play_slam()


## Its OWN voice: on _battle_player this slam replaced the victory fanfare it lands on, and
## in W1/W2 (no agreed downbeat, so no wait) it did so in the same frame.
func _play_slam() -> void:
	_impact_done = true
	var slam := _slam_key()
	if SoundManager and SoundManager._sfx_manifest.has(slam):
		SoundManager.play_victory_sfx(slam)


## Rays of pixel chips from the impact, more and longer per grade, drawn in the title's own glyph pixel.
func _spawn_starburst(at: Vector2, tint: Color, grade: int) -> void:
	var burst := PixelBurst.new()
	burst.name = "VictoryStarburst"
	burst.px = maxi(2, _title_px / 2)
	burst.rays = 8 + 4 * mini(grade, Grade.BOSS)
	burst.trail = int(GRADE_RINGS[grade]) + 1
	burst.reach = get_viewport_rect().size.y * 0.22 + 40.0 * float(grade)
	burst.tint = tint
	burst.position = at.round()
	add_child(burst)
	## The burst frees itself at the tween's end, so the snap holds a WeakRef.
	var burst_ref: WeakRef = weakref(burst)
	_snaps.append(func() -> void:
		var b: Object = burst_ref.get_ref()
		if b != null:
			b.queue_free())
	var t := _wall(create_tween())
	t.tween_method(burst.set_progress, 0.0, 1.0, 0.34 + 0.04 * float(grade))
	t.tween_callback(burst.queue_free)


## A one-shot's rank, stamped above the title's last letters on the slam's frame: it starts three times its size and
## lands in two whole steps. An S rank stamps in gold with its own burst; the S slam is its voice (_slam_key).
func _build_stamp(center: Vector2, title_size: Vector2, px: int, flourish: bool) -> Control:
	if _one_shot_rank == "":
		return null
	var spx: int = maxi(2, px / 2)
	var is_s: bool = _one_shot_rank == "S"
	var stamp := PixelBanner.new("%s-RANK!" % _one_shot_rank, spx, STAMP_TINT_S if is_s else STAMP_TINT)
	stamp.name = "VictoryRankStamp"
	add_child(stamp)
	var vp := get_viewport_rect().size
	## Above the title's right end, clear of the word: over the corner it hid "RY!" for the whole hold (2026-11-08 clip).
	var x: float = minf(center.x + title_size.x - stamp.size.x, vp.x - 8.0 - stamp.size.x)
	stamp.position = Vector2(x, center.y - stamp.size.y - float(px)).round()
	var mid: Vector2 = stamp.position + stamp.size / 2.0
	_snaps.append(func() -> void:
		if is_instance_valid(stamp):
			stamp.modulate.a = 0.0)
	stamp.modulate.a = 0.0
	if not flourish:
		return stamp
	var t := _wall(create_tween())
	t.tween_interval(maxf(0.0, _title_land - 0.08))
	t.tween_callback(func() -> void:
		stamp.set_px(spx * 3)
		stamp.position = (mid - stamp.size / 2.0).round()
		stamp.modulate.a = 1.0)
	for k in [2, 1]:
		t.tween_interval(0.04)
		t.tween_callback(func() -> void:
			stamp.set_px(spx * k)
			stamp.position = (mid - stamp.size / 2.0).round())
	if is_s:
		t.tween_callback(func() -> void: _spawn_starburst(mid, STAMP_TINT_S, Grade.NORMAL))
	t.tween_interval(float(GRADE_HOLD[_victory_grade()]))
	t.tween_callback(func() -> void: stamp.modulate.a = 0.0)
	return stamp


## Boss kills get billed: the foe's name under the title, in the same pixel letters.
func _build_subtitle(center: Vector2, title_size: Vector2, tint: Color, flourish: bool) -> Control:
	var foe := _headline_foe()
	if foe == "" and spotlight_duelist == "":
		return null
	var text := "%s FELLED" % foe.to_upper()
	if spotlight_duelist != "":
		text = "%s TAKES THE SPOTLIGHT" % spotlight_duelist.to_upper()
		if foe != "":
			text += " — %s FELLED" % foe.to_upper()
	var vp := get_viewport_rect().size
	var spx: int = clampi(roundi(float(TextScale.scaled(20)) / 8.0), 2,
			maxi(2, int((vp.x - 32.0) / float(PixelText.measure(text).x))))
	var sub := PixelBanner.new(text, spx, tint)
	sub.name = "VictorySubtitle"
	add_child(sub)
	sub.position = Vector2(center.x + (title_size.x - sub.size.x) / 2.0, center.y + title_size.y + 6.0).round()
	_snaps.append(func() -> void:
		if is_instance_valid(sub):
			sub.modulate.a = 0.0)
	sub.modulate.a = 0.0
	if not flourish:
		return sub
	var t := _wall(create_tween())
	t.tween_interval(_title_land)
	t.tween_callback(func() -> void: sub.modulate.a = 1.0)
	t.tween_interval(float(GRADE_HOLD[_victory_grade()]))
	t.tween_callback(func() -> void: sub.modulate.a = 0.0)
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
		var t := _wall(create_tween())
		t.tween_property(bar, "position", shown, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_interval(_title_land - 0.18 + float(GRADE_HOLD[grade]) + 0.08)
		t.tween_property(bar, "position", hidden, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		t.tween_callback(bar.queue_free)


## -- Stage 2: character cards ----------------------------------------------

func _build_cards(char_results: Array, flourish: bool) -> void:
	var _vp_for_scale := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1280, 720)
	_cscale = _fit_card_scale(char_results.size(), _vp_for_scale.y)
	_wscale = _fit_card_width_scale(_vp_for_scale.x)
	_compact = false
	_card_min_h = _measure_card_min_h(char_results)
	if _overflows(char_results.size(), _vp_for_scale.y):
		_compact = true
		_card_min_h = _measure_card_min_h(char_results)
	_gap = _fit_gap(char_results.size(), _vp_for_scale.y)
	var vp := get_viewport_rect().size
	var column := _column_positions(char_results.size(), vp)
	## The column enters as ONE cascade, top to bottom. Per-card waits let a card clear of the title slam
	## arrive alone, mid-column, before the ones above it; if any card must wait, they all start together.
	var start := 0.5
	for p in column:
		if _title_rest.has_area() and Rect2(p, Vector2(_cw(), _ch())).intersects(_title_rest):
			start = maxf(start, _title_clear_at)
	for i in range(char_results.size()):
		var cr: Dictionary = char_results[i]
		var card := _make_card(cr)
		add_child(card)
		card.position = column[i]
		var delay := start + i * 0.12
		var final_pos := card.position
		_occupied.append(Rect2(final_pos, Vector2(_cw(), _ch())))
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
	var y_fallback := _stack_top() + i * (_ch() + _gap)
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
			pos = Vector2(sp.x - _cw() - CARD_SPRITE_GAP, sp.y - _ch() / 2.0)
	pos.x = clampf(pos.x, maxf(LOG_CLEAR_X, _left_wall(vp.x)), vp.x - _cw() - 8.0)
	## ⚠️ FLOOR STAYS AT 56, NOT _stack_top(). This function PLACES NOTHING — `_column_positions`
	## calls it only to average the party's anchored ys into the column's centre. Raising this floor
	## lifted the topmost sprite's y and dragged that average with it, moving the whole 100% column
	## down 3px (155 -> 158) for a clamp that keeps no card clear of anything. The floor that does
	## the work is the one on the column itself.
	pos.y = clampf(pos.y, 56.0, vp.y - STRIP_BOTTOM_MARGIN - _ch())
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
	var block_h := float(count) * _ch() + float(maxi(0, count - 1)) * _gap
	var top := mid + _ch() / 2.0 - block_h / 2.0
	## Never up into the docked title and the loot strip that hangs under it.
	top = maxf(top, _stack_top())
	var out: Array[Vector2] = []
	for i in range(count):
		out.append(Vector2(x, clampf(top + i * (_ch() + _gap), _stack_top(), vp.y)))
	## Pushed past the bottom: lift the whole column, keeping the spacing.
	var bottom_limit := vp.y - _bottom_margin(vp.y) - _ch()
	if out.size() > 0 and out[out.size() - 1].y > bottom_limit:
		## One block, never squeezed: a per-card clamp at the stack top collapsed the upper cards onto each other.
		var lift := minf(out[out.size() - 1].y - bottom_limit, maxf(0.0, out[0].y - _stack_top()))
		for i in range(out.size()):
			out[i].y -= lift
	return out


func _make_card(cr: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(_cw(), _ch())
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.15, 0.50)
	style.border_color = Color(0.6, 0.5, 0.2) if cr.get("is_alive", true) else Color(0.35, 0.3, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = COMPACT_PAD if _compact else CARD_PAD
	style.content_margin_bottom = COMPACT_PAD if _compact else CARD_PAD
	card.add_theme_stylebox_override("panel", style)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(h)

	# Portrait chip — through the world-aware resolver, never a hand-built path (2026-08-09 six-surfaces defect)
	# A KEY, so the job id: the name lowercased was "time mage" for time_mage.png, and is "school nurse" in W2 (sprites 21968).
	var job_key := str(cr.get("job_id", "")) if str(cr.get("job_id", "")) != "" else str(cr.get("job_name", "")).to_lower()
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
	## LAST RESORT, after the growth above. Once the fit cap is measured against the room left
	## under the loot strip, the capped card at 200% holds the worst authored line with 0px to
	## spare — so a longer name or a 6-digit award would draw outside it again. Trimming on a WORD
	## boundary keeps "Scriptweaver  +99999 EXP" readable and drops the tail rather than cutting a
	## number in half. `clip_text` is what makes the width binding at all: without it the Label's
	## minimum size is its own content width and the box is only a suggestion.
	top.clip_text = true
	top.text_overrun_behavior = TextServer.OVERRUN_TRIM_WORD_ELLIPSIS
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
	var bar_w := _cw() - 76.0
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
	var final_top := _final_top_text(cr)
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

## The fight's shape as a chip, or {} when it was unremarkable. Pure, so the precedence is testable.
## ⛔ NO "FLAWLESS" CHIP, DELIBERATELY: most trash fights end untouched, so it would print on nearly
## every victory and tell the player nothing. Only the two rare, informative outcomes earn a chip.
static func fight_shape_chip(low_water_pct: float, anyone_fell: bool) -> Dictionary:
	if anyone_fell:
		## Outranks a close call: being raised is strictly worse than merely dipping, and injuries
		## only show the KOs that rolled a permanent one, so this is the rest of that story.
		return {"text": "COSTLY", "color": Color(1.0, 0.55, 0.35)}
	if low_water_pct < VoiceLineTags.CLOSE_CALL_PCT:
		return {"text": "CLOSE CALL", "color": Color(1.0, 0.75, 0.25)}
	return {}


func _build_loot_strip(results: Dictionary, flourish: bool) -> void:
	var total_gold: int = int(results.get("total_gold", 0))
	var item_drops: Array = results.get("item_drops", [])
	var injuries: Array = results.get("injuries", [])
	var bonuses: Array = results.get("bonuses", [])
	## How the fight WENT, computed BEFORE the early-return: a close call with no loot is still worth a
	## strip, and leaving it out of this condition made the chip invisible on exactly those fights.
	var shape: Dictionary = fight_shape_chip(float(results.get("low_water_pct", 100.0)), bool(results.get("anyone_fell", false)))
	if total_gold <= 0 and item_drops.is_empty() and injuries.is_empty() and bonuses.is_empty() and shape.is_empty():
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
	## Between the bonuses and the injuries that get the final word.
	if not shape.is_empty():
		chips.append([str(shape["text"]), str(shape["text"]), shape["color"], "shape"])
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

	## ⚠️ RESERVE THE SPACE BEFORE THE AWAIT. The card stack hangs under this strip and `_build_cards`
	## runs in the SAME frame, so it cannot wait for the layout pass below — reordering the two calls
	## in `build()` achieved nothing on its own, because this function returns at the await and
	## `_strip_rect` was still set a frame too late. `get_combined_minimum_size()` is what the
	## container will size itself to, available without a pass. The authoritative rect is still taken
	## after the await; this only has to reserve the right room.
	var pre_size := strip.get_combined_minimum_size()
	var pre_pos := Vector2((vp.x - pre_size.x) / 2.0, vp.y - STRIP_BOTTOM_MARGIN - pre_size.y)
	if _title_docked.has_area():
		pre_pos = Vector2(_title_docked.get_center().x - pre_size.x / 2.0, _title_docked.end.y + 6.0)
		pre_pos.x = clampf(pre_pos.x, 8.0, vp.x - pre_size.x - 8.0)
	_strip_rect = Rect2(pre_pos, pre_size)

	# center-bottom, above the hint bar
	await get_tree().process_frame
	if not is_instance_valid(strip):
		return
	## Under the VICTORY title, not over the battle log: the rewards read as the headline's second line.
	strip.position = Vector2((vp.x - strip.size.x) / 2.0, vp.y - STRIP_BOTTOM_MARGIN - strip.size.y)
	if _title_docked.has_area():
		strip.position = Vector2(_title_docked.get_center().x - strip.size.x / 2.0, _title_docked.end.y + 6.0)
		strip.position.x = clampf(strip.position.x, 8.0, vp.x - strip.size.x - 8.0)
	_strip_rect = Rect2(strip.position, strip.size)
	_occupied.append(_strip_rect)
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
## Xbox, ○ on PlayStation, and X/Enter/Space on a keyboard. The frozen "A" was right on exactly one
## family and named a button keyboard players do not have.
func _confirm_token() -> String:
	var ipm = Engine.get_main_loop().root.get_node_or_null("InputProfileManager")
	if ipm == null:
		return KeyLabel.first_key("ui_accept", "Confirm")
	var hint: String = ipm.hint_for_action("ui_accept")
	return hint if hint != "" else KeyLabel.first_key("ui_accept", "Confirm")


static func tally_prompt(tok: String) -> String:
	return "%s: skip" % tok


func _build_prompt() -> void:
	var prompt := Label.new()
	# One key, one job at a time: the old line named the confirm button twice, for finish and then for continue.
	prompt.text = tally_prompt(_confirm_token())
	prompt.name = "ContinuePrompt"
	prompt.add_theme_font_size_override("font_size", TextScale.scaled(PROMPT_FONT))
	prompt.add_theme_color_override("font_color", Color(0.92, 0.92, 0.85))
	prompt.add_theme_constant_override("outline_size", 3)
	prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(prompt)
	var vp := get_viewport_rect().size
	# Bottom-centre above the hint bar; it sat at 11px grey on the grass under the party panel's corner.
	prompt.size = Vector2(320.0, 0.0)
	prompt.position = Vector2((vp.x - 320.0) / 2.0, _prompt_rect.position.y if _prompt_rect.has_area() else vp.y - PROMPT_REST)
	_snaps.append(func() -> void:
		if is_instance_valid(prompt):
			prompt.text = "%s: continue" % _confirm_token()
			prompt.modulate.a = 1.0)
	var blink := create_tween()  # untracked: an endless loop must not hold the cascade open
	blink.set_loops()
	blink.tween_property(prompt, "modulate:a", 0.55, 0.8)
	blink.tween_property(prompt, "modulate:a", 1.0, 0.8)
