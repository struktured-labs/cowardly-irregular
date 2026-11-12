extends Node2D
class_name StatusAura

## Every status a battler carries, ANIMATED on the battler: Zzz drifting off a sleeper, bubbles rising off poison,
## stars circling a stun, an arrow per stat buff/debuff in that stat's colour (struktured 2026-11-01: "the sleep
## indicator could be animated, the poison, all stats, more of that polish").
##
## One node per battler, a child of its sprite, counter-scaled to SCREEN pixels so the sprite's own scale never
## distorts a motif; its size then follows the figure's height on screen (scale_for). The BADGE row above the head
## stays: it carries the turn counters this does not.
##
## CLOCK. Wall time, not the scene clock: at 4x battle speed a scaled clock spins Zzz into a blur, and at a hit-stop
## it freezes them. A status is a STATE, so it reads the same at every speed and is never hidden.
## COST. No per-frame allocation: shapes are const arrays drawn through draw_set_transform, letters are PixelText's
## cached glyph textures (the damage numbers' own face, rim baked in), and the redraw only runs while something is shown.
##
## SIZE AND RIM (struktured 2026-11-07: the monster status indicators are "kinda stinky"). A motif used to be one fixed
## size, so on a 250 px dragon three 10 px stars were specks, and a flat fill vanished on a body of its own colour.
## Every motif now grows with the figure (scale_for) and carries a rim: dark, or light for the two dark motifs.

## status id -> motif. Every key in BattleScene.STATUS_ICON_CONFIG (itself derived from every applied status by
## test_status_icons_cover_applied_statuses) must appear here: test_a_status_shows_itself derives the set.
const MOTIF := {
	"sleep": "zzz",
	"poison": "bubbles", "festered": "bubbles",
	"burn": "flames", "burning": "flames",
	"stun": "stars", "cannot_act": "stars",
	"confuse": "swirl", "mind_swap": "swirl", "controlled": "swirl",
	"charm": "hearts",
	"fear": "sweat",
	"curse": "wisps", "memory_leak": "wisps",
	"blind": "visor",
	"silence": "mute", "cannot_defer": "mute",
	"attack_up": "arrow", "attack_down": "arrow", "defense_up": "arrow", "defense_down": "arrow",
	"magic_up": "arrow", "magic_down": "arrow", "speed_up": "arrow", "speed_down": "arrow",
	"exposed": "arrow",
	"regen": "plus", "damage_absorb": "plus",
	"barrier": "ring", "reflect": "ring", "armor_thorns": "ring",
	"evasion": "shadow", "shadow_step": "shadow",
	"haste": "lines",
	"slow": "hourglass",
	"doom_counter": "skull",
	## A permakilled battler is gone; drawing on it would contradict that.
	"permakilled": "none",
}

## Stat -> its colour. An arrow's direction says buff or debuff; its colour says WHICH stat.
const STAT_COLOR := {
	"attack": Color(1.0, 0.45, 0.25), "defense": Color(0.45, 0.65, 1.0),
	"magic": Color(0.80, 0.50, 1.0), "speed": Color(1.0, 0.90, 0.30),
}

const FALLBACK := "mote"

## A motif's scale is the figure's height on screen over this, between a floor and a cap. Measured in the first render:
## a slime stands ~70 px, a party member ~170, Pyrroth ~250; at 1.0 a slime's Z was an 8 px speck, hence the floor.
const REFERENCE_BODY_PX := 96.0
const SCALE_MIN := 1.3
const SCALE_MAX := 2.2
const RIM_DARK := Color(0.05, 0.04, 0.08)
const RIM_LIGHT := Color(0.95, 0.95, 1.0)
## The motifs that are themselves dark: a dark rim on them is no rim.
const LIGHT_RIMMED := ["visor", "shadow"]
## Every letter this file draws; each must be a real PixelText glyph (test_a_status_reads_on_a_dragon).
const TEXT_GLYPHS := ["Z", "?"]
const RIM_OFFSETS := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]

static var ARROW := PackedVector2Array([Vector2(0, -7), Vector2(6, 0), Vector2(2, 0), Vector2(2, 7), Vector2(-2, 7), Vector2(-2, 0), Vector2(-6, 0)])
static var STAR := PackedVector2Array([Vector2(0, -5), Vector2(1.5, -1.5), Vector2(5, -1.5), Vector2(2.3, 0.9), Vector2(3.1, 4.6),
	Vector2(0, 2.4), Vector2(-3.1, 4.6), Vector2(-2.3, 0.9), Vector2(-5, -1.5), Vector2(-1.5, -1.5)])
static var FLAME := PackedVector2Array([Vector2(0, -9), Vector2(3.5, -2), Vector2(3, 2.5), Vector2(0, 4), Vector2(-3, 2.5), Vector2(-3.5, -2)])
static var HEART := PackedVector2Array([Vector2(0, 4), Vector2(-4.5, -0.5), Vector2(-4, -3.5), Vector2(-1.5, -4), Vector2(0, -2),
	Vector2(1.5, -4), Vector2(4, -3.5), Vector2(4.5, -0.5)])
static var DROP := PackedVector2Array([Vector2(0, -5), Vector2(2.5, 0), Vector2(1.8, 2.6), Vector2(0, 3.3), Vector2(-1.8, 2.6), Vector2(-2.5, 0)])
static var PLUS := PackedVector2Array([Vector2(-1.5, -5), Vector2(1.5, -5), Vector2(1.5, -1.5), Vector2(5, -1.5), Vector2(5, 1.5), Vector2(1.5, 1.5),
	Vector2(1.5, 5), Vector2(-1.5, 5), Vector2(-1.5, 1.5), Vector2(-5, 1.5), Vector2(-5, -1.5), Vector2(-1.5, -1.5)])
static var SKULL := PackedVector2Array([Vector2(-5, -2), Vector2(-4, -5), Vector2(-2, -6.5), Vector2(2, -6.5), Vector2(4, -5), Vector2(5, -2),
	Vector2(4.5, 1), Vector2(3, 2), Vector2(3, 5), Vector2(-3, 5), Vector2(-3, 2), Vector2(-4.5, 1)])
static var EYE := PackedVector2Array([Vector2(-8, 0), Vector2(-4, -3.5), Vector2(0, -4.5), Vector2(4, -3.5), Vector2(8, 0), Vector2(4, 3.5), Vector2(0, 4.5), Vector2(-4, 3.5)])
static var HOURGLASS := PackedVector2Array([Vector2(-4, -6), Vector2(4, -6), Vector2(0.6, 0), Vector2(4, 6), Vector2(-4, 6), Vector2(-0.6, 0)])

## The figure on screen, in this node's units (screen px): set by the scene from the sprite's idle frame.
var body := Rect2(-24, -64, 48, 64)
## Screen px above the figure's top that belong to the BADGE row (the scene sets it): a motif that floats over the head
## starts above that band, so a Z never lands on its own "SLP 3" label.
var head_clear := 0.0
## Shown motifs, rebuilt only when the status set changes: [{status, kind, color, up, slot, slots}].
var _shown: Array = []
var _clock_ms: int = -1
var _reduce_flashes := false


## The motif a status draws, or FALLBACK for a status nobody mapped: a runtime battler never shows nothing.
static func motif_for(status: String) -> String:
	return str(MOTIF.get(status, FALLBACK))


## How much larger than its drawn size a motif is on a figure this tall (screen px). Never below SCALE_MIN.
static func scale_for(body_height: float) -> float:
	return clampf(body_height / REFERENCE_BODY_PX, SCALE_MIN, SCALE_MAX)


## The rim a motif is drawn inside: what keeps it visible on a body of its own colour.
static func rim_for(kind: String) -> Color:
	return RIM_LIGHT if LIGHT_RIMMED.has(kind) else RIM_DARK


## An arrow's [stat, up?] for a stat buff/debuff. exposed reads as a defense drop, which is what it does.
static func arrow_of(status: String) -> Array:
	if status == "exposed":
		return ["defense", false]
	var up := status.ends_with("_up")
	return [status.trim_suffix("_up").trim_suffix("_down"), up]


func set_statuses(statuses: Array) -> void:
	var shown: Array = []
	var arrows := 0
	for s in statuses:
		var status := str(s)
		var kind := motif_for(status)
		if kind == "none":
			continue
		var entry := {"status": status, "kind": kind, "color": _color_of(status, kind), "up": true, "slot": 0}
		if kind == "arrow":
			var a := arrow_of(status)
			entry["color"] = STAT_COLOR.get(a[0], Color(0.8, 0.8, 0.8))
			entry["up"] = a[1]
			entry["slot"] = arrows
			arrows += 1
		shown.append(entry)
	for e in shown:
		e["slots"] = arrows
	_shown = shown
	_reduce_flashes = ("reduce_flashes" in GameState) and bool(GameState.reduce_flashes) if GameState else false
	visible = not _shown.is_empty()
	set_process(visible)
	queue_redraw()


func shown_kinds() -> Array:
	var out: Array = []
	for e in _shown:
		out.append(e["kind"])
	return out


## Where an arrow stands: arrows line up beside the figure's shoulder, one column each, so five of them never overlap.
func arrow_x(slot: int, slots: int) -> float:
	return body.end.x + (6.0 + float(slot) * 14.0 - (0.0 if slots <= 3 else 7.0 * float(slots - 3))) * motif_scale()


func motif_scale() -> float:
	return scale_for(body.size.y)


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # the letters are pixel glyphs, drawn at whole multiples


func _ready() -> void:
	set_process(not _shown.is_empty())


func _process(_delta: float) -> void:
	queue_redraw()


func _color_of(status: String, kind: String) -> Color:
	match kind:
		"zzz": return Color(0.75, 0.80, 1.0)
		"bubbles": return Color(0.55, 0.90, 0.30)
		"flames": return Color(1.0, 0.55, 0.15)
		"stars": return Color(1.0, 0.95, 0.35)
		"swirl": return Color(0.90, 0.55, 0.95)
		"hearts": return Color(1.0, 0.45, 0.70)
		"sweat": return Color(0.60, 0.80, 1.0)
		"wisps": return Color(0.65, 0.30, 0.85)
		"visor": return Color(0.08, 0.08, 0.10)
		"mute": return Color(0.75, 0.75, 0.80)
		"plus": return AccessibilityPalette.heal() if status == "regen" else AccessibilityPalette.bonus()
		"ring": return Color(0.45, 0.85, 1.0)
		"shadow": return Color(0.45, 0.40, 0.75)
		"lines": return AccessibilityPalette.bonus()
		"hourglass": return AccessibilityPalette.penalty()
		"skull": return Color(0.75, 0.30, 0.90)
	return Color(0.85, 0.85, 0.85)


func _draw() -> void:
	if _shown.is_empty():
		return
	var t := float(Time.get_ticks_msec()) / 1000.0
	var k := motif_scale()
	var unit := Vector2.ONE * k
	var px := maxi(2, roundi(k * 1.2))  # a glyph's pixel, whole so it never shimmers
	var head := Vector2(body.get_center().x, body.position.y - head_clear)
	var heads := 0
	for e in _shown:
		var kind: String = e["kind"]
		var c: Color = e["color"]
		var rim := rim_for(kind)
		match kind:
			"zzz":
				for i in 3:
					var p := fmod(t * 0.55 + float(i) / 3.0, 1.0)
					var at := head + Vector2(10.0 + p * 18.0 + sin(t * 2.0 + i) * 2.0, -14.0 - p * 26.0) * k
					_glyph("Z", at, px + (0 if p < 0.5 else 1), Color(c, 1.0 - p))
			"bubbles":
				_tint(c, t)
				for i in 5:
					var p := fmod(t * 0.7 + float(i) * 0.21, 1.0)
					var x := body.position.x + body.size.x * (0.2 + 0.6 * fmod(float(i) * 0.37, 1.0)) + sin(t * 3.0 + i) * 2.0 * k
					_dot(Vector2(x, body.end.y - p * body.size.y * 0.9), (2.0 + p * 2.5) * k, Color(c, 0.85 * (1.0 - p)), rim, k)
			"flames":
				for i in 4:
					var x := body.position.x + body.size.x * (0.15 + 0.23 * float(i))
					var flick := 0.8 + 0.3 * sin(t * 9.0 + float(i) * 1.7)
					_shape(FLAME, Vector2(x, body.end.y - 4.0 * k), Vector2(flick, flick * (1.0 + 0.25 * sin(t * 6.0 + i))) * k, Color(c, 0.9), rim, k)
			"stars":
				for i in 3:
					var a := t * 3.0 + TAU * float(i) / 3.0
					_shape(STAR, head + Vector2(cos(a) * 16.0, -6.0 + sin(a) * 5.0) * k, unit, Color(c, 0.95), rim, k)
			"swirl":
				var off := Vector2(-14.0 + 10.0 * float(heads), -24.0) * k
				_glyph("?", head + off + Vector2(sin(t * 4.0) * 3.0 * k, 0), px + 1, c)
				heads += 1
			"hearts":
				for i in 3:
					var p := fmod(t * 0.6 + float(i) / 3.0, 1.0)
					_shape(HEART, head + Vector2(-12.0 + 12.0 * float(i), -2.0 - p * 18.0) * k, unit * (0.8 + 0.4 * p), Color(c, 1.0 - p), rim, k)
			"sweat":
				var p := fmod(t * 0.9, 1.0)
				_shape(DROP, Vector2(body.get_center().x + body.size.x * 0.35, body.position.y + (6.0 + p * 10.0) * k), unit, Color(c, 1.0 - p), rim, k)  # on the brow, not over the badges
			"wisps":
				for i in 3:
					var p := fmod(t * 0.45 + float(i) / 3.0, 1.0)
					var x := body.get_center().x + sin(t * 2.0 + float(i) * 2.1) * body.size.x * 0.4
					_dot(Vector2(x, body.end.y - p * body.size.y), (3.0 * (1.0 - p) + 1.0) * k, Color(c, 0.7 * (1.0 - p)), rim, k)
			"visor":
				var at := head + Vector2(16.0, -10.0 + sin(t * 2.0)) * k
				_shape(EYE, at, unit, Color(c, 0.95), rim, k)
				draw_circle(at, 2.0 * k, Color(rim, 0.95))
				draw_line(at + Vector2(-8, 6) * k, at + Vector2(8, -6) * k, Color(c, 0.95), 2.0 * k + 2.0)
				draw_line(at + Vector2(-8, 6) * k, at + Vector2(8, -6) * k, Color(rim, 0.95), 2.0 * k)
			"mute":
				var at := head + Vector2(-16.0, -8.0) * k
				draw_arc(at, 6.0 * k, 0.0, TAU, 16, Color(rim, 0.9), 1.5 * k + 2.0)
				draw_line(at + Vector2(-4, 4) * k, at + Vector2(4, -4) * k, Color(rim, 0.9), 2.0 * k + 2.0)
				draw_arc(at, 6.0 * k, 0.0, TAU, 16, c, 1.5 * k)
				draw_line(at + Vector2(-4, 4) * k, at + Vector2(4, -4) * k, c, 2.0 * k)
			"arrow":
				var slots: int = e["slots"]
				var x := arrow_x(int(e["slot"]), slots)
				var travel := fmod(t * 0.8 + float(e["slot"]) * 0.17, 1.0)
				var y := body.get_center().y + (12.0 - travel * 24.0 if e["up"] else -12.0 + travel * 24.0) * k
				var flip := 1.0 if e["up"] else -1.0
				_shape(ARROW, Vector2(x, y), Vector2(1.0, flip) * k, Color(c, 0.35 + 0.65 * sin(travel * PI)), rim, k)
			"plus":
				var p := fmod(t * 0.6, 1.0)
				_shape(PLUS, Vector2(body.get_center().x, body.end.y - p * body.size.y), unit, Color(c, 1.0 - p), rim, k)
			"ring":
				var r := maxf(body.size.x, body.size.y) * 0.55 + sin(t * 3.0) * 1.5 * k
				draw_arc(body.get_center(), r, 0.0, TAU, 48, Color(rim, 0.45), 2.0 * k + 2.0)
				draw_arc(body.get_center(), r, 0.0, TAU, 48, Color(c, 0.75), 2.0 * k)
			"shadow":
				var pulse := 0.1 * sin(t * 4.0)
				draw_rect(body.grow(-2.0), Color(rim, 0.22 + pulse), false, 2.0 * k + 2.0)
				draw_rect(body.grow(-2.0), Color(c, 0.55 + pulse), false, 2.0 * k)
			"lines":
				for i in 3:
					var y := body.position.y + body.size.y * (0.3 + 0.2 * float(i))
					var p := fmod(t * 2.0 + float(i) * 0.3, 1.0)
					var from := Vector2(body.end.x + (4.0 + p * 10.0) * k, y)
					draw_line(from, from + Vector2(10.0 * k, 0), Color(rim, 0.9 * (1.0 - p)), 2.0 * k + 2.0)
					draw_line(from, from + Vector2(10.0 * k, 0), Color(c, 1.0 - p), 2.0 * k)
			"hourglass":
				_shape(HOURGLASS, head + Vector2(16.0, -6.0) * k, Vector2(1.0, cos(t * 1.5)) * k, Color(c, 0.9), rim, k)
			"skull":
				var at := head + Vector2(0.0, -12.0 + sin(t * 2.5) * 2.0) * k
				_shape(SKULL, at, unit, c, rim, k)
				draw_circle(at + Vector2(-2.0, -2.0) * k, 1.5 * k, rim)
				draw_circle(at + Vector2(2.0, -2.0) * k, 1.5 * k, rim)
				draw_line(at + Vector2(0.0, 2.6) * k, at + Vector2(0.0, 5.0) * k, rim, maxf(1.0, k * 0.8))
			_:
				var a := t * 2.0
				_dot(head + Vector2(cos(a) * 12.0, -6.0 + sin(a) * 4.0) * k, 2.5 * k, Color(c, 0.9), rim, k)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A filled shape inside its rim: the rim is the same polygon stamped one rim-width out on four sides, so nothing allocates.
func _shape(points: PackedVector2Array, at: Vector2, sc: Vector2, color: Color, rim: Color, k: float) -> void:
	var edge := Color(rim, color.a * 0.9)
	var w := maxf(1.0, k)
	for off in RIM_OFFSETS:
		draw_set_transform(at + off * w, 0.0, sc)
		draw_colored_polygon(points, edge)
	draw_set_transform(at, 0.0, sc)
	draw_colored_polygon(points, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _dot(at: Vector2, radius: float, color: Color, rim: Color, k: float) -> void:
	draw_circle(at, radius + maxf(1.0, k), Color(rim, color.a * 0.9))
	draw_circle(at, radius, color)


## One PixelText glyph, its top-left at `at`, each glyph pixel `px` screen pixels: the texture carries its own dark rim.
func _glyph(ch: String, at: Vector2, px: int, color: Color) -> void:
	var tex := PixelText.glyph_texture(ch)
	draw_texture_rect(tex, Rect2(at.round(), Vector2(tex.get_size()) * float(px)), false, color)


## A sick tint over the figure: the pulse is what reads at a glance. reduce_flashes keeps the tint and drops the pulse.
func _tint(c: Color, t: float) -> void:
	var a := 0.10 if _reduce_flashes else 0.08 + 0.10 * (0.5 + 0.5 * sin(t * 4.0))
	draw_rect(body, Color(c, a))
