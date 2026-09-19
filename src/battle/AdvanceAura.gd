extends Node2D

## The aura on the acting PC while an Advance is being QUEUED — struktured 2026-09-14: "I didn't see
## animated flourishes as u hit advance more — or animated auras, etc."
##
## ⛔ THIRD PASS. Proportional steps (a few % per press) could not carry 1→2 at full screen, and the disc
## sat centred on the sprite origin BEHIND its own body: measured 68-70% hidden by the body at every
## moment, 11% more under the next PC while the actor steps out of formation. So each count now ADDS A
## LAYER, and every layer lives where the body cannot cover it:
##   1 silhouette outline · 2 + a ground disc under the feet · 3 + glyph arms orbiting THROUGH the body
##   (front half drawn in front of it) · 4 + rising motes, faster orbit · 5/5 full bank + gold rim
## INTENSITY still rides the count inside a layer; IDENTITY rides the job (colour + glyph shape).

const LAYER_OUTLINE := 1
const LAYER_DISC := 2
const LAYER_ARMS := 4
const LAYER_MOTES := 8
const LAYER_GOLD := 16
const LAYER_GOLD_OUTLINE := 32
const LAYER_ALL := 63
## The categorical table itself, indexed by count. The full bank, not the count, adds both gold layers.
const LAYERS: Array[int] = [0, LAYER_OUTLINE, LAYER_OUTLINE | LAYER_DISC, LAYER_OUTLINE | LAYER_DISC | LAYER_ARMS,
	LAYER_OUTLINE | LAYER_DISC | LAYER_ARMS | LAYER_MOTES, LAYER_OUTLINE | LAYER_DISC | LAYER_ARMS | LAYER_MOTES]
const LAYER_NAMES := {LAYER_OUTLINE: "outline", LAYER_DISC: "disc", LAYER_ARMS: "arms", LAYER_MOTES: "motes", LAYER_GOLD: "gold_ring", LAYER_GOLD_OUTLINE: "gold_outline"}

## Disc: a flattened ellipse the actor stands in. RADIUS is its horizontal half-width in screen px.
const RADIUS: Array[float] = [0.0, 0.0, 58.0, 66.0, 74.0, 82.0]
const DISC_FLAT: float = 0.36
const FILL_ALPHA: Array[float] = [0.0, 0.0, 0.48, 0.54, 0.60, 0.66]
const RIM_WIDTH: Array[float] = [0.0, 0.0, 3.0, 4.0, 5.0, 6.0]
const PULSE_HZ: Array[float] = [0.0, 0.8, 1.1, 1.5, 2.0, 2.6]
## Arms: glyphs on a tilted orbit around the figure's middle; its lower half passes in front of the body.
const GLYPHS: Array[int] = [0, 0, 0, 6, 8, 10]
const SPIN: Array[float] = [0.0, 0.0, 0.0, 1.4, 2.4, 3.0]
const ORBIT_RX: Array[float] = [0.0, 0.0, 0.0, 70.0, 76.0, 82.0]
const ORBIT_TILT: float = 0.32
## Motes: sparks rising from the disc to the head.
const MOTES: Array[int] = [0, 0, 0, 0, 12, 18]
const RISE_HZ: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.9, 1.2]
## The outline is a DILATION of the body's own alpha, this many screen px wide. ⛔ It was the body scaled up
## 8-16% about the frame centre: a few px of halo on a small sheet (Rogue, Mage), and off-centre wherever the
## figure is not mid-frame — faint on four of five slots (cowir-battle, every-slot frames).
## It breathes in alpha only, and by less than its smallest step, so no phase inverts two counts.
const OUTLINE_WIDTH: Array[float] = [0.0, 5.0, 6.0, 7.0, 8.0, 9.0]
const OUTLINE_ALPHA: Array[float] = [0.0, 0.50, 0.58, 0.66, 0.74, 0.82]
const OUTLINE_ALPHA_PULSE: float = 0.06

## 5/5 is the payoff, not a louder 4: a saturated gold ring AROUND the disc — near half in front of the feet,
## uniform width, never squashed by the disc's flattening — and the outline turns gold. ⛔ .348 drew a 3 px
## rim inside the flattening transform and behind the body: a pale arc on the disc's lower edge (cowir-main).
const FULL_BANK_RIM: Color = Color(1.0, 0.78, 0.10)
const FULL_BANK_HIGHLIGHT: Color = Color(1.0, 0.96, 0.62)
const FULL_BANK_RIM_WIDTH: float = 6.0
const FULL_BANK_GLOW_WIDTH: float = 12.0
const FULL_BANK_GLOW_ALPHA: float = 0.4
const FULL_BANK_RIM_GAP: float = 4.0
const FULL_BANK_OUTLINE_GOLD: float = 1.0
## At 5/5 the outline also THICKENS: a width step reads where a colour step cannot — the Cleric's own
## colour is already pale gold (cowir-adhoc).
const FULL_BANK_OUTLINE_BONUS: float = 4.0
const FULL_BANK_PULSE_HZ: float = 3.6
const RING_SEGMENTS := 32
## Breathe and kick, as fractions of the disc radius. The breathe stays under the smallest radius gap.
const PULSE_DEPTH: float = 0.04
const KICK_DEPTH: float = 0.10
const KICK_DECAY_S: float = 0.18
## Where the figure's middle sits for the orbit, as a fraction of its height below its top.
const ORBIT_HEIGHT: float = 0.55
## Disc centre lifted above the feet line by this fraction of its smallest vertical radius.
const DISC_LIFT: float = 0.35

var count: int = 0
var full_bank: bool = false
var color: Color = Color.WHITE
var shape: String = "sparks"
## Which layers may draw. Only the proof tool narrows it, to measure one layer at a time on screen.
var draw_layers: int = LAYER_ALL
var _t: float = 0.0
var _kick: float = 0.0
var _body: AnimatedSprite2D = null
var _outline: AnimatedSprite2D = null
var _front: Node2D = null
var _figure: Rect2 = Rect2()

static var _outline_shader: Shader = null
static var _figure_cache: Dictionary = {}


static func layers_for(n: int, is_full_bank: bool) -> int:
	var i: int = clampi(n, 0, LAYERS.size() - 1)
	return LAYERS[i] | (LAYER_GOLD | LAYER_GOLD_OUTLINE if is_full_bank and i > 0 else 0)


static func params_for(n: int, is_full_bank: bool) -> Dictionary:
	var i: int = clampi(n, 0, RADIUS.size() - 1)
	return {
		"layers": layers_for(i, is_full_bank),
		"radius": RADIUS[i],
		"fill_alpha": FILL_ALPHA[i],
		"rim_width": RIM_WIDTH[i],
		"pulse_hz": FULL_BANK_PULSE_HZ if (is_full_bank and i > 0) else PULSE_HZ[i],
		"glyphs": GLYPHS[i],
		"spin": SPIN[i],
		"orbit_rx": ORBIT_RX[i],
		"motes": MOTES[i],
		"rise_hz": RISE_HZ[i],
		"outline_width": OUTLINE_WIDTH[i],
		"outline_alpha": OUTLINE_ALPHA[i],
		"gold_rim": is_full_bank and i > 0,
	}


## Off at MINIMAL (2x+); OFF already covers turbo, the grind console and 4x.
static func should_show(tier: int, flag_on: bool) -> bool:
	if not flag_on:
		return false
	return tier == BattleJuice.Tier.FULL or tier == BattleJuice.Tier.REDUCED


## Furthest horizontal reach from its anchor at the most extreme moment. A figure bound, NOT bubble clearance.
static func max_reach() -> float:
	var top: int = RADIUS.size() - 1
	var r: float = RADIUS[top] * (1.0 + PULSE_DEPTH) * (1.0 + KICK_DEPTH)
	var disc_edge: float = r + maxf(RIM_WIDTH[top] * 0.5, FULL_BANK_RIM_GAP + FULL_BANK_GLOW_WIDTH * 0.5)
	var arm_edge: float = ORBIT_RX[top] + _glyph_size(top) * 1.2
	return maxf(disc_edge, arm_edge)


static func _glyph_size(n: int) -> float:
	return 9.0 + 1.5 * float(n)


## The opaque bounds of a frame, in that frame's pixels. Cached per texture; the whole frame if unreadable.
## TWIN, deliberately not shared: HybridSpriteLoader.figure_rect(sheet_path) answers the same
## question from a SHEET PATH and falls back to an EMPTY rect, because an absent sheet has no
## bounds to guess. This one takes a LIVE TEXTURE and falls back to the whole frame, because a
## texture in hand always has bounds. Harmonising the fallbacks breaks one caller either way.
## Retire the split when a caller needs both inputs: then take the Texture2D and let the path
## side load and delegate.
static func figure_rect_of(tex: Texture2D) -> Rect2:
	if tex == null:
		return Rect2()
	var key: int = tex.get_instance_id()
	if _figure_cache.has(key):
		return _figure_cache[key]
	var rect := Rect2(Vector2.ZERO, tex.get_size())
	var img: Image = tex.get_image()
	if img != null and not img.is_empty():
		var used: Rect2i = img.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			rect = Rect2(used)
	_figure_cache[key] = rect
	return rect


func is_active() -> bool:
	return count > 0 and visible


## Returns true when the count ROSE; the caller pops on exactly those presses. A rise kicks the disc.
func set_state(new_count: int, is_full_bank: bool, new_color: Color, new_shape: String) -> bool:
	var rose: bool = new_count > count
	count = maxi(new_count, 0)
	full_bank = is_full_bank and count > 0
	color = new_color
	shape = new_shape
	visible = count > 0
	if rose:
		_kick = 1.0
	set_process(count > 0)
	_sync_outline()
	_redraw()
	return rose


func kick_amount() -> float:
	return _kick


func has_layer(layer: int) -> bool:
	return (layers_for(count, full_bank) & draw_layers & layer) != 0


## The disc's horizontal radius as drawn THIS frame; 0 while the disc layer is absent.
func current_radius() -> float:
	if (layers_for(count, full_bank) & LAYER_DISC) == 0:
		return 0.0
	var p: Dictionary = params_for(count, full_bank)
	return float(p["radius"]) * _breathe(p)


## The outline's alpha as applied this frame — ranges [a x (1 - OUTLINE_ALPHA_PULSE), a], where `a` is
## this layer count's OUTLINE_ALPHA entry (an Array since f93d8ed89, not the scalar the lost line named).
## Restored 2026-09-19: that commit's restructure dropped this block as collateral, so its absence was
## never a decision about this function — nothing else documents the pulse range.
func current_outline_alpha() -> float:
	var p: Dictionary = params_for(count, full_bank)
	return float(p["outline_alpha"]) * (1.0 - OUTLINE_ALPHA_PULSE * 0.5 * (1.0 - sin(TAU * float(p["pulse_hz"]) * _t)))


func clear() -> void:
	count = 0
	full_bank = false
	_kick = 0.0
	visible = false
	set_process(false)
	if _outline and is_instance_valid(_outline):
		_outline.visible = false
	if _front and is_instance_valid(_front):
		_front.visible = false
	queue_redraw()


## Narrow which layers draw (the proof tool's per-layer measurement), and redraw every part now.
func set_draw_layers(mask: int) -> void:
	draw_layers = mask
	_sync_outline()
	_redraw()


## The body the outline mirrors and the layers stand on. Rebinding moves the front layer with the aura.
func bind_body(sprite: AnimatedSprite2D) -> void:
	_body = sprite
	if _outline == null or not is_instance_valid(_outline):
		_outline = AnimatedSprite2D.new()
		_outline.name = "AdvanceOutline"
		var mat := ShaderMaterial.new()
		mat.shader = _get_outline_shader()
		_outline.material = mat
		add_child(_outline)
	if _front == null or not is_instance_valid(_front):
		_front = Node2D.new()
		_front.name = "AdvanceAuraFront"
		_front.draw.connect(_draw_front)
	if _front.get_parent() != sprite:
		if _front.get_parent():
			_front.get_parent().remove_child(_front)
		sprite.add_child(_front)
	_measure_figure()
	_sync_outline()
	_redraw()


func outline() -> AnimatedSprite2D:
	return _outline


## The half of the aura drawn IN FRONT of the body: the near side of the orbit and the rising motes.
func front() -> Node2D:
	return _front


## The figure's opaque bounds in this node's space (screen px, sprite origin at 0,0).
func figure_rect() -> Rect2:
	return _figure


## Under the feet, lifted a little so the feet stand inside the disc rather than on its far rim.
func disc_center() -> Vector2:
	return Vector2(_figure.get_center().x, _figure.end.y - RADIUS[2] * DISC_FLAT * DISC_LIFT)


## Half of the full-bank ring, in unflattened space so its line width is the same all the way round.
## The near half is the lower one on screen, and is drawn on the front layer.
func gold_ring_points(near: bool) -> PackedVector2Array:
	var c: Vector2 = disc_center()
	var rx: float = current_radius() + FULL_BANK_RIM_GAP
	var ry: float = rx * DISC_FLAT
	var from: float = 0.0 if near else PI
	var pts := PackedVector2Array()
	for k in RING_SEGMENTS + 1:
		var a: float = from + PI * float(k) / float(RING_SEGMENTS)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


## The outline's width in screen px this frame, thicker at a full bank.
func current_outline_width() -> float:
	var w: float = float(params_for(count, full_bank)["outline_width"])
	return w + (FULL_BANK_OUTLINE_BONUS if has_layer(LAYER_GOLD_OUTLINE) else 0.0)


## The outline's tint this frame: the job colour, gold at a full bank.
func outline_tint() -> Color:
	var base: Color = color.lerp(FULL_BANK_RIM, FULL_BANK_OUTLINE_GOLD) if has_layer(LAYER_GOLD_OUTLINE) else color
	return Color(base.r, base.g, base.b, current_outline_alpha())


func orbit_center() -> Vector2:
	return Vector2(_figure.get_center().x, _figure.position.y + _figure.size.y * ORBIT_HEIGHT)


## Screen-space position of glyph i this frame, and whether it is on the near (front) side of the orbit.
func glyph_at(i: int) -> Dictionary:
	var p: Dictionary = params_for(count, full_bank)
	var n: int = maxi(int(p["glyphs"]), 1)
	var a: float = TAU * float(i) / float(n) + _t * float(p["spin"]) * (1.0 if count % 2 == 1 else -1.0)
	var rx: float = float(p["orbit_rx"])
	return {"pos": orbit_center() + Vector2(cos(a) * rx, sin(a) * rx * ORBIT_TILT), "front": sin(a) >= 0.0, "angle": a}


static func _get_outline_shader() -> Shader:
	if _outline_shader == null:
		_outline_shader = Shader.new()
		## Dilates the body's alpha by `radius` texels in 16 directions at two distances, flat job colour,
		## drawn behind the body — so what shows is a band of even width around any sheet's silhouette.
		_outline_shader.code = """shader_type canvas_item;
uniform vec4 tint : source_color = vec4(1.0);
uniform float radius = 3.0;
void fragment() {
	float a = texture(TEXTURE, UV).a;
	for (int i = 0; i < 16; i++) {
		float ang = 6.2831853 * float(i) / 16.0;
		vec2 d = vec2(cos(ang), sin(ang)) * TEXTURE_PIXEL_SIZE * radius;
		a = max(a, texture(TEXTURE, UV + d).a);
		a = max(a, texture(TEXTURE, UV + d * 0.5).a);
	}
	COLOR = vec4(tint.rgb, a * tint.a);
}
"""
	return _outline_shader


func _ready() -> void:
	show_behind_parent = true
	set_process(count > 0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _front != null and is_instance_valid(_front) and not _front.is_queued_for_deletion():
		_front.queue_free()


func _process(delta: float) -> void:
	_t += delta
	if _kick > 0.0:
		_kick = maxf(0.0, _kick - delta / KICK_DECAY_S)
	_sync_outline()
	_redraw()


func _redraw() -> void:
	queue_redraw()
	if _front and is_instance_valid(_front):
		_front.queue_redraw()


func _breathe(p: Dictionary) -> float:
	return (1.0 + PULSE_DEPTH * sin(TAU * float(p["pulse_hz"]) * _t)) * (1.0 + KICK_DEPTH * _kick)


## The figure's bounds around a sprite's OWN ORIGIN, in screen px at its current scale — flip, offset and
## centering applied. The one place that mapping lives: the aura draws from it, the party's feet are placed
## from it (BattleScene.party_feet_correction), the melee lunge stops by it, and the speech bubble lifts by
## it. Empty when the frame cannot be read, so every caller can tell "unmeasurable" from "measured zero".
## `anim` empty means "whatever this sprite is playing" (the aura's outline mirrors the live frame);
## a caller that must not move when the animation changes — a lunge's stop distance, a slot placement —
## asks for &"idle" explicitly.
static func figure_rect_in_sprite(sprite: AnimatedSprite2D, want: StringName = &"") -> Rect2:
	if sprite == null or not is_instance_valid(sprite) or sprite.sprite_frames == null:
		return Rect2()
	var anim: StringName = want if want != &"" else sprite.animation
	if not sprite.sprite_frames.has_animation(anim) or sprite.sprite_frames.get_frame_count(anim) == 0:
		anim = &"idle"
	if not sprite.sprite_frames.has_animation(anim) or sprite.sprite_frames.get_frame_count(anim) == 0:
		return Rect2()
	var tex: Texture2D = sprite.sprite_frames.get_frame_texture(anim, 0)
	if tex == null:
		return Rect2()
	var size: Vector2 = tex.get_size()
	var fr: Rect2 = figure_rect_of(tex)
	var origin: Vector2 = sprite.offset - (size * 0.5 if sprite.centered else Vector2.ZERO)
	var x0: float = origin.x + (size.x - fr.end.x if sprite.flip_h else fr.position.x)
	var y0: float = origin.y + (size.y - fr.end.y if sprite.flip_v else fr.position.y)
	var s: Vector2 = sprite.scale.abs()
	return Rect2(Vector2(x0, y0) * s, fr.size * s)


func _measure_figure() -> void:
	_figure = figure_rect_in_sprite(_body)


func _sync_outline() -> void:
	if _front and is_instance_valid(_front):
		_front.visible = count > 0 and visible
		_front.position = position
		_front.scale = scale
	if _outline == null or not is_instance_valid(_outline):
		return
	if not has_layer(LAYER_OUTLINE) or _body == null or not is_instance_valid(_body) or _body.sprite_frames == null:
		_outline.visible = false
		return
	_outline.visible = true
	_outline.sprite_frames = _body.sprite_frames
	if _outline.animation != _body.animation:
		_outline.animation = _body.animation
	_outline.frame = _body.frame
	_outline.flip_h = _body.flip_h
	_outline.flip_v = _body.flip_v
	_outline.centered = _body.centered
	_outline.offset = _body.offset
	## Counter-scaled against the body, so multiply the body's scale back in: an exact mirror, no grow.
	_outline.scale = _body.scale
	var mat := _outline.material as ShaderMaterial
	mat.set_shader_parameter("tint", outline_tint())
	mat.set_shader_parameter("radius", current_outline_width() / maxf(absf(_body.scale.x), 0.001))


## Behind the body: the ground disc, the far half of the gold ring, and the far half of the orbit.
func _draw() -> void:
	if count <= 0:
		return
	var p: Dictionary = params_for(count, full_bank)
	if has_layer(LAYER_DISC):
		var r: float = current_radius()
		var fill: float = float(p["fill_alpha"])
		draw_set_transform(disc_center(), 0.0, Vector2(1.0, DISC_FLAT))
		draw_circle(Vector2.ZERO, r, Color(color.r, color.g, color.b, fill))
		var core: Color = color.lightened(0.3)
		draw_circle(Vector2.ZERO, r * 0.6, Color(core.r, core.g, core.b, fill * 0.7))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(color.r, color.g, color.b, clampf(0.45 + fill, 0.0, 1.0)), float(p["rim_width"]), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if has_layer(LAYER_GOLD):
		_draw_gold_ring(self, false)
	if has_layer(LAYER_ARMS):
		_draw_arms(self, false)


## In front of the body: the near half of the gold ring and of the orbit, and the rising motes.
func _draw_front() -> void:
	if count <= 0 or _front == null:
		return
	if has_layer(LAYER_GOLD):
		_draw_gold_ring(_front, true)
	if has_layer(LAYER_ARMS):
		_draw_arms(_front, true)
	if has_layer(LAYER_MOTES):
		var p: Dictionary = params_for(count, full_bank)
		var n: int = int(p["motes"])
		var base: Vector2 = disc_center()
		var rise: float = maxf(_figure.size.y, 60.0)
		var c := color.lightened(0.45)
		for i in n:
			var ph: float = fposmod(_t * float(p["rise_hz"]) + float(i) / float(n), 1.0)
			var x: float = sin(float(i) * 2.39996) * float(p["radius"]) * 0.8
			var at := base + Vector2(x, -ph * rise)
			var fade: float = sin(ph * PI)
			var rad: float = 3.5 + 2.5 * (1.0 - ph)
			_front.draw_circle(at, rad, Color(c.r, c.g, c.b, fade))
			_front.draw_circle(at, rad * 0.45, Color(1.0, 1.0, 1.0, fade))


func _draw_gold_ring(canvas: CanvasItem, near: bool) -> void:
	var pts: PackedVector2Array = gold_ring_points(near)
	canvas.draw_polyline(pts, Color(FULL_BANK_RIM.r, FULL_BANK_RIM.g, FULL_BANK_RIM.b, FULL_BANK_GLOW_ALPHA), FULL_BANK_GLOW_WIDTH, true)
	canvas.draw_polyline(pts, FULL_BANK_RIM, FULL_BANK_RIM_WIDTH, true)
	canvas.draw_polyline(pts, FULL_BANK_HIGHLIGHT, 2.0, true)


func _draw_arms(canvas: CanvasItem, near: bool) -> void:
	var n: int = int(params_for(count, full_bank)["glyphs"])
	var glyph := Color(color.r, color.g, color.b, 1.0).lightened(0.45)
	for i in n:
		var g: Dictionary = glyph_at(i)
		if bool(g["front"]) != near:
			continue
		var depth: float = 0.8 + 0.4 * (sin(float(g["angle"])) * 0.5 + 0.5)
		var c: Color = glyph if near else glyph.darkened(0.25)
		_draw_glyph(canvas, g["pos"], float(g["angle"]), c, _glyph_size(count) * depth)


## A dark under-stroke first, so a glyph crossing a body the same hue as the job colour still reads.
func _draw_glyph(canvas: CanvasItem, at: Vector2, ang: float, c: Color, s: float) -> void:
	var dark := Color(0.05, 0.03, 0.08, c.a * 0.85)
	_stroke_glyph(canvas, at, ang, dark, s, 5.5)
	_stroke_glyph(canvas, at, ang, c, s, 3.0)


func _stroke_glyph(canvas: CanvasItem, at: Vector2, ang: float, c: Color, s: float, w: float) -> void:
	match shape:
		"runes":
			var pts := PackedVector2Array([at + Vector2(0, -s), at + Vector2(s, 0), at + Vector2(0, s), at + Vector2(-s, 0), at + Vector2(0, -s)])
			canvas.draw_polyline(pts, c, w)
		"motes":
			canvas.draw_circle(at, s * 0.45 + w * 0.5, c)
		"slashes":
			var d := Vector2(cos(ang + 0.7), sin(ang + 0.7)) * s
			canvas.draw_line(at - d, at + d, c, w)
		"notes":
			canvas.draw_circle(at, s * 0.35 + w * 0.5, c)
			canvas.draw_line(at + Vector2(s * 0.45, 0), at + Vector2(s * 0.45, -s * 1.4), c, w * 0.8)
		_:
			var d2 := Vector2(cos(ang), sin(ang)) * s
			canvas.draw_line(at - d2, at + d2, c, w)
