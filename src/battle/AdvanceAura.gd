extends Node2D

## The persistent aura on the acting PC while an Advance is being QUEUED — struktured 2026-09-14:
## "I didn't see animated flourishes as u hit advance more — or animated auras, etc."
##
## ⛔ SECOND PASS. The first version rose on every channel and still could not be SEEN below 5/5:
## cowir-main read the folded frames and found counts 1-4 a thin faint ring you had to hunt for,
## half-hidden under the battle-start quip bubbles — which is the exact thing he said he could not
## see. "Rises monotonically" was true and was the wrong bar. Every channel now steps by a VISIBLE
## minimum per press, pinned by the guard, and a silhouette outline hugs the body so the lower half
## reads even when a bubble covers the upper half.
##
## Two axes, the split the resolution flourish already uses: INTENSITY rides the count (fill, rim,
## radius, orbit, outline), IDENTITY rides the job (colour + glyph shape).
##
## Attached as a child of the actor's sprite with show_behind_parent, so it follows the body and
## draws behind it. Counter-scaled, so a 256px sheet drawn at 0.8x does not shrink the aura with it.

## Indexed by queued count; 0 is unused (an empty queue has no aura).
const RADIUS: Array[float] = [0.0, 36.0, 44.0, 52.0, 60.0, 68.0]
const FILL_ALPHA: Array[float] = [0.0, 0.20, 0.28, 0.36, 0.44, 0.52]
const RIM_WIDTH: Array[float] = [0.0, 3.0, 4.5, 6.0, 7.5, 9.0]
const PULSE_HZ: Array[float] = [0.0, 0.8, 1.1, 1.5, 2.0, 2.6]
const GLYPHS: Array[int] = [0, 4, 6, 8, 11, 14]
## Orbit speed of the glyph arms, radians per second.
const SPIN: Array[float] = [0.0, 0.8, 1.2, 1.7, 2.3, 3.0]
## The silhouette outline: how much larger than the body, and how strong. The outline does NOT pulse
## in scale — at ±4% against a +2% step it made count 2 draw smaller than count 1 at an unlucky phase
## (cowir-adhoc, from the frames). It breathes in alpha only, and less than its smallest step.
const OUTLINE_GROW: Array[float] = [1.0, 1.06, 1.10, 1.14, 1.18, 1.22]
const OUTLINE_ALPHA: Array[float] = [0.0, 0.40, 0.50, 0.60, 0.70, 0.80]
const OUTLINE_ALPHA_PULSE: float = 0.08

## The minimum VISIBLE step between counts is owned by the guard, not declared here: a floor stored
## beside the table it bounds can be lowered in the same edit that flattens the table, and stay green.

## 5/5 is its own state, not a louder fourth: a gold rim and a faster pulse.
const FULL_BANK_RIM: Color = Color(1.0, 0.84, 0.25)
const FULL_BANK_RIM_WIDTH: float = 3.0
const FULL_BANK_RIM_GAP: float = 4.0
const FULL_BANK_PULSE_HZ: float = 3.6
## How far the ring breathes, and how hard a press kicks it, as fractions of radius. The breathe must
## stay under the smallest radius gap between counts, or a higher count draws smaller than a lower one
## at the wrong phase: at 0.08 counts 3->4 and 4->5 overlapped (60 x 0.92 < 52 x 1.08). The guard samples
## the whole cycle, so this cannot quietly grow back.
const PULSE_DEPTH: float = 0.05
const KICK_DEPTH: float = 0.10
const KICK_DECAY_S: float = 0.18
## Glyphs orbit just inside the ring so their tips never extend the reach.
const GLYPH_ORBIT: float = 0.9

var count: int = 0
var full_bank: bool = false
var color: Color = Color.WHITE
var shape: String = "sparks"
var _t: float = 0.0
var _kick: float = 0.0
var _body: AnimatedSprite2D = null
var _outline: AnimatedSprite2D = null

static var _outline_shader: Shader = null


static func params_for(n: int, is_full_bank: bool) -> Dictionary:
	var i: int = clampi(n, 0, RADIUS.size() - 1)
	return {
		"radius": RADIUS[i],
		"fill_alpha": FILL_ALPHA[i],
		"rim_width": RIM_WIDTH[i],
		"pulse_hz": FULL_BANK_PULSE_HZ if (is_full_bank and i > 0) else PULSE_HZ[i],
		"glyphs": GLYPHS[i],
		"spin": SPIN[i],
		"outline_grow": OUTLINE_GROW[i],
		"outline_alpha": OUTLINE_ALPHA[i],
		"gold_rim": is_full_bank and i > 0,
	}


## Off at MINIMAL (2x+), and OFF already covers turbo, the grind console and 4x — the work order's
## three exclusions are exactly "tier is not FULL or REDUCED".
static func should_show(tier: int, flag_on: bool) -> bool:
	if not flag_on:
		return false
	return tier == BattleJuice.Tier.FULL or tier == BattleJuice.Tier.REDUCED


## The furthest the DISC reaches from sprite centre at its most extreme moment — full bank, top of
## the pulse, mid-kick, outer edge of the gold rim. This bounds the aura to its own actor's figure; it
## is NOT a bubble-clearance guarantee. The first version claimed one against a 105 px quip anchor,
## and cowir-cutscenes measured that for the lead PC the bubble is clamped DOWN onto the body, so the
## check passed while the overlap existed. Bubble placement is BattleSpeechBubble's to guarantee.
## The silhouette outline is excluded: it hugs the body and is what reads beside a bubble.
static func max_reach() -> float:
	var top: int = RADIUS.size() - 1
	var r: float = RADIUS[top] * (1.0 + PULSE_DEPTH) * (1.0 + KICK_DEPTH)
	var ring_edge: float = r + RIM_WIDTH[top] * 0.5
	var bank_edge: float = r + FULL_BANK_RIM_GAP + FULL_BANK_RIM_WIDTH * 0.5
	var glyph_edge: float = r * GLYPH_ORBIT + _glyph_size(top)
	return maxf(ring_edge, maxf(bank_edge, glyph_edge))


static func _glyph_size(n: int) -> float:
	return 4.0 + 1.2 * float(n)


func is_active() -> bool:
	return count > 0 and visible


## Returns true when the count ROSE — the caller fires the per-press pop on exactly those presses,
## never on an undo or a repeat of the same count. A rise also kicks the ring outward.
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
	queue_redraw()
	return rose


func kick_amount() -> float:
	return _kick


## The disc's radius as drawn THIS frame. _draw and the guard both read it, so a test sampling phases
## measures what is on screen rather than a restatement of the tables.
func current_radius() -> float:
	var p: Dictionary = params_for(count, full_bank)
	return float(p["radius"]) * _breathe(p)


## The outline's alpha as applied this frame — ranges [OUTLINE_ALPHA x (1 - OUTLINE_ALPHA_PULSE), OUTLINE_ALPHA].
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
	queue_redraw()


## The body the outline mirrors. Rebinding to a new actor moves the outline with the aura.
func bind_body(sprite: AnimatedSprite2D) -> void:
	_body = sprite
	if _outline == null or not is_instance_valid(_outline):
		_outline = AnimatedSprite2D.new()
		_outline.name = "AdvanceOutline"
		var mat := ShaderMaterial.new()
		mat.shader = _get_outline_shader()
		_outline.material = mat
		add_child(_outline)
	_sync_outline()


func outline() -> AnimatedSprite2D:
	return _outline


static func _get_outline_shader() -> Shader:
	if _outline_shader == null:
		_outline_shader = Shader.new()
		## Every opaque pixel of the body becomes the job colour — a flat silhouette, scaled a touch
		## larger and drawn behind the body, reads as an outline on any sheet without knowing where
		## the art sits inside its frame.
		_outline_shader.code = "shader_type canvas_item;\nuniform vec4 tint : source_color = vec4(1.0);\nvoid fragment() {\n\tCOLOR = vec4(tint.rgb, texture(TEXTURE, UV).a * tint.a);\n}\n"
	return _outline_shader


func _ready() -> void:
	show_behind_parent = true
	set_process(count > 0)


func _process(delta: float) -> void:
	_t += delta
	if _kick > 0.0:
		_kick = maxf(0.0, _kick - delta / KICK_DECAY_S)
	_sync_outline()
	queue_redraw()


func _breathe(p: Dictionary) -> float:
	return (1.0 + PULSE_DEPTH * sin(TAU * float(p["pulse_hz"]) * _t)) * (1.0 + KICK_DEPTH * _kick)


func _sync_outline() -> void:
	if _outline == null or not is_instance_valid(_outline):
		return
	if count <= 0 or _body == null or not is_instance_valid(_body) or _body.sprite_frames == null:
		_outline.visible = false
		return
	var p: Dictionary = params_for(count, full_bank)
	_outline.visible = true
	_outline.sprite_frames = _body.sprite_frames
	if _outline.animation != _body.animation:
		_outline.animation = _body.animation
	_outline.frame = _body.frame
	_outline.flip_h = _body.flip_h
	_outline.flip_v = _body.flip_v
	_outline.centered = _body.centered
	_outline.offset = _body.offset
	## The aura is counter-scaled against the body, so multiply the body's scale back in. No pulse term.
	_outline.scale = _body.scale * float(p["outline_grow"])
	(_outline.material as ShaderMaterial).set_shader_parameter("tint", Color(color.r, color.g, color.b, current_outline_alpha()))


func _draw() -> void:
	if count <= 0:
		return
	var p: Dictionary = params_for(count, full_bank)
	var r: float = current_radius()
	var fill: float = float(p["fill_alpha"])
	## A translucent filled disc from press 1, with a softer halo — the body of the aura.
	draw_circle(Vector2.ZERO, r, Color(color.r, color.g, color.b, fill))
	draw_circle(Vector2.ZERO, r * 0.62, Color(color.r, color.g, color.b, fill * 0.6))
	## The rim carries the pulse; its width steps with the count.
	var rim := Color(color.r, color.g, color.b, clampf(0.55 + fill, 0.0, 1.0))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 56, rim, float(p["rim_width"]), true)
	if full_bank:
		draw_arc(Vector2.ZERO, r + FULL_BANK_RIM_GAP, 0.0, TAU, 56, FULL_BANK_RIM, FULL_BANK_RIM_WIDTH, true)
	## Orbiting class glyphs — more of them and faster as the count rises, direction alternating.
	var n: int = int(p["glyphs"])
	var spin: float = _t * float(p["spin"]) * (1.0 if count % 2 == 1 else -1.0)
	var glyph := Color(color.r, color.g, color.b, 1.0).lightened(0.25)
	for i in n:
		var a: float = TAU * float(i) / float(n) + spin
		_draw_glyph(Vector2(cos(a), sin(a)) * r * GLYPH_ORBIT, a, glyph)


func _draw_glyph(at: Vector2, ang: float, c: Color) -> void:
	var s: float = _glyph_size(count)
	match shape:
		"runes":
			var pts := PackedVector2Array([at + Vector2(0, -s), at + Vector2(s, 0), at + Vector2(0, s), at + Vector2(-s, 0), at + Vector2(0, -s)])
			draw_polyline(pts, c, 2.0)
		"motes":
			draw_circle(at, s * 0.55, c)
		"slashes":
			var d := Vector2(cos(ang + 0.7), sin(ang + 0.7)) * s
			draw_line(at - d, at + d, c, 2.5)
		"notes":
			draw_circle(at, s * 0.45, c)
			draw_line(at + Vector2(s * 0.45, 0), at + Vector2(s * 0.45, -s * 1.6), c, 2.0)
		_:
			var d2 := Vector2(cos(ang), sin(ang)) * s
			draw_line(at - d2, at + d2, c, 2.5)
