extends Node2D

## The persistent aura on the acting PC while an Advance is being QUEUED — struktured 2026-09-14:
## "I didn't see animated flourishes as u hit advance more — or animated auras, etc."
##
## The resolution flourish (BattleScene._spawn_advance_flourish) fires once, when the queue is
## spent. Nothing escalated while the player was BUILDING the queue, which is the part they do by
## hand. This is that part: one aura that grows with every press and shrinks on every undo.
##
## Two axes, the same split the flourish already uses: INTENSITY rides the count on four channels
## at once (radius, pulse rate, glyph density, brightness), IDENTITY rides the job (colour + glyph
## shape). A Mage at 2 and a Mage at 5 are the same idea at different volumes.
##
## Attached as a child of the actor's sprite with show_behind_parent, so it follows the body and
## draws behind it with no z-order bookkeeping. Counter-scaled, so a 256px sheet drawn at 0.8x does
## not shrink the aura with it.
##
## Budget: cowir-cutscenes measured the turn-one battle-start quip anchored 105 px above sprite
## centre. The largest reach here — full-bank radius at the top of its pulse — is kept under that.

## Indexed by queued count; 0 is unused (an empty queue has no aura). Each channel strictly rises.
const RADIUS: Array[float] = [0.0, 34.0, 42.0, 51.0, 61.0, 74.0]
const PULSE_HZ: Array[float] = [0.0, 0.8, 1.1, 1.5, 2.0, 2.6]
const GLYPHS: Array[int] = [0, 3, 5, 7, 10, 14]
const BRIGHTNESS: Array[float] = [0.0, 0.22, 0.30, 0.40, 0.52, 0.66]

## 5/5 is its own state, not a louder fourth: a gold rim and a faster pulse.
const FULL_BANK_RIM: Color = Color(1.0, 0.84, 0.25)
const FULL_BANK_PULSE_HZ: float = 3.6
## How far the ring breathes, as a fraction of radius. Kept here so the budget check can read it.
const PULSE_DEPTH: float = 0.1

var count: int = 0
var full_bank: bool = false
var color: Color = Color.WHITE
var shape: String = "sparks"
var _t: float = 0.0


static func params_for(n: int, is_full_bank: bool) -> Dictionary:
	var i: int = clampi(n, 0, RADIUS.size() - 1)
	return {
		"radius": RADIUS[i],
		"pulse_hz": FULL_BANK_PULSE_HZ if (is_full_bank and i > 0) else PULSE_HZ[i],
		"glyphs": GLYPHS[i],
		"brightness": BRIGHTNESS[i],
		"gold_rim": is_full_bank and i > 0,
	}


## Off at MINIMAL (2x+), and OFF already covers turbo, the grind console and 4x — the work order's
## three exclusions are exactly "tier is not FULL or REDUCED".
static func should_show(tier: int, flag_on: bool) -> bool:
	if not flag_on:
		return false
	return tier == BattleJuice.Tier.FULL or tier == BattleJuice.Tier.REDUCED


## The furthest any part of the aura reaches from its centre, for the layout budget.
static func max_reach() -> float:
	return RADIUS[RADIUS.size() - 1] * (1.0 + PULSE_DEPTH)


func is_active() -> bool:
	return count > 0 and visible


## Returns true when the count ROSE — the caller fires the per-press pop on exactly those presses,
## never on an undo or a repeat of the same count.
func set_state(new_count: int, is_full_bank: bool, new_color: Color, new_shape: String) -> bool:
	var rose: bool = new_count > count
	count = maxi(new_count, 0)
	full_bank = is_full_bank and count > 0
	color = new_color
	shape = new_shape
	visible = count > 0
	set_process(count > 0)
	queue_redraw()
	return rose


func clear() -> void:
	count = 0
	full_bank = false
	visible = false
	set_process(false)
	queue_redraw()


func _ready() -> void:
	show_behind_parent = true
	set_process(count > 0)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if count <= 0:
		return
	var p: Dictionary = params_for(count, full_bank)
	var r: float = float(p["radius"])
	var breathe: float = 1.0 + PULSE_DEPTH * sin(TAU * float(p["pulse_hz"]) * _t)
	var glow := Color(color.r, color.g, color.b, float(p["brightness"]))
	## Soft body glow: three nested discs, falling off outward.
	for k in 3:
		var f: float = 1.0 - 0.28 * float(k)
		draw_circle(Vector2.ZERO, r * f * breathe, Color(glow.r, glow.g, glow.b, glow.a * (0.35 + 0.2 * float(k))))
	## The ring that carries the pulse.
	var ring := Color(color.r, color.g, color.b, clampf(glow.a + 0.25, 0.0, 1.0))
	draw_arc(Vector2.ZERO, r * breathe, 0.0, TAU, 48, ring, 2.0 + 0.4 * float(count), true)
	if full_bank:
		draw_arc(Vector2.ZERO, r * breathe + 4.0, 0.0, TAU, 48, FULL_BANK_RIM, 3.0, true)
	## Orbiting class glyphs — density rides the count, direction alternates so 4 and 5 read apart.
	var n: int = int(p["glyphs"])
	var spin: float = _t * (0.6 + 0.25 * float(count)) * (1.0 if count % 2 == 1 else -1.0)
	for i in n:
		var a: float = TAU * float(i) / float(n) + spin
		_draw_glyph(Vector2(cos(a), sin(a)) * r * breathe, a, ring)


func _draw_glyph(at: Vector2, ang: float, c: Color) -> void:
	var s: float = 3.0 + 0.6 * float(count)
	match shape:
		"runes":
			var pts := PackedVector2Array([at + Vector2(0, -s), at + Vector2(s, 0), at + Vector2(0, s), at + Vector2(-s, 0), at + Vector2(0, -s)])
			draw_polyline(pts, c, 1.5)
		"motes":
			draw_circle(at, s * 0.55, c)
		"slashes":
			var d := Vector2(cos(ang + 0.7), sin(ang + 0.7)) * s
			draw_line(at - d, at + d, c, 2.0)
		"notes":
			draw_circle(at, s * 0.45, c)
			draw_line(at + Vector2(s * 0.45, 0), at + Vector2(s * 0.45, -s * 1.6), c, 1.5)
		_:
			var d2 := Vector2(cos(ang), sin(ang)) * s
			draw_line(at - d2, at + d2, c, 2.0)
