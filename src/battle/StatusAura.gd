extends Node2D
class_name StatusAura

## Every status a battler carries, ANIMATED on the battler: Zzz drifting off a sleeper, bubbles rising off poison,
## stars circling a stun, an arrow per stat buff/debuff in that stat's colour (struktured 2026-11-01: "the sleep
## indicator could be animated, the poison, all stats, more of that polish").
##
## One node per battler, a child of its sprite, counter-scaled so a motif is the same size on screen for a 0.5x hero
## and a 2.5x dragon. The BADGE row above the head stays: it carries the turn counters this does not.
##
## CLOCK. Wall time, not the scene clock: at 4x battle speed a scaled clock spins Zzz into a blur, and at a hit-stop
## it freezes them. A status is a STATE, so it reads the same at every speed and is never hidden.
## COST. No per-frame allocation: shapes are const arrays drawn through draw_set_transform, text uses the theme's
## fallback font, and the redraw only runs while something is shown.

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

const ARROW := PackedVector2Array([Vector2(0, -7), Vector2(6, 0), Vector2(2, 0), Vector2(2, 7), Vector2(-2, 7), Vector2(-2, 0), Vector2(-6, 0)])
const STAR := PackedVector2Array([Vector2(0, -5), Vector2(1.5, -1.5), Vector2(5, -1.5), Vector2(2.3, 0.9), Vector2(3.1, 4.6),
	Vector2(0, 2.4), Vector2(-3.1, 4.6), Vector2(-2.3, 0.9), Vector2(-5, -1.5), Vector2(-1.5, -1.5)])
const FLAME := PackedVector2Array([Vector2(0, -9), Vector2(3.5, -2), Vector2(3, 2.5), Vector2(0, 4), Vector2(-3, 2.5), Vector2(-3.5, -2)])
const HEART := PackedVector2Array([Vector2(0, 4), Vector2(-4.5, -0.5), Vector2(-4, -3.5), Vector2(-1.5, -4), Vector2(0, -2),
	Vector2(1.5, -4), Vector2(4, -3.5), Vector2(4.5, -0.5)])
const DROP := PackedVector2Array([Vector2(0, -5), Vector2(2.5, 0), Vector2(1.8, 2.6), Vector2(0, 3.3), Vector2(-1.8, 2.6), Vector2(-2.5, 0)])
const PLUS := PackedVector2Array([Vector2(-1.5, -5), Vector2(1.5, -5), Vector2(1.5, -1.5), Vector2(5, -1.5), Vector2(5, 1.5), Vector2(1.5, 1.5),
	Vector2(1.5, 5), Vector2(-1.5, 5), Vector2(-1.5, 1.5), Vector2(-5, 1.5), Vector2(-5, -1.5), Vector2(-1.5, -1.5)])
const HOURGLASS := PackedVector2Array([Vector2(-4, -6), Vector2(4, -6), Vector2(0.6, 0), Vector2(4, 6), Vector2(-4, 6), Vector2(-0.6, 0)])

## The figure on screen, in this node's units (screen px): set by the scene from the sprite's idle frame.
var body := Rect2(-24, -64, 48, 64)
## Shown motifs, rebuilt only when the status set changes: [{status, kind, color, up, slot, slots}].
var _shown: Array = []
var _clock_ms: int = -1
var _reduce_flashes := false


## The motif a status draws, or FALLBACK for a status nobody mapped: a runtime battler never shows nothing.
static func motif_for(status: String) -> String:
	return str(MOTIF.get(status, FALLBACK))


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
	return body.end.x + 6.0 + float(slot) * 14.0 - (0.0 if slots <= 3 else 7.0 * float(slots - 3))


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
	var head := Vector2(body.get_center().x, body.position.y)
	var heads := 0
	for e in _shown:
		var k: String = e["kind"]
		var c: Color = e["color"]
		match k:
			"zzz":
				var font := ThemeDB.fallback_font
				for i in 3:
					var p := fmod(t * 0.55 + float(i) / 3.0, 1.0)
					var at := head + Vector2(10.0 + p * 18.0 + sin(t * 2.0 + i) * 2.0, -4.0 - p * 26.0)
					draw_string(font, at, "Z", HORIZONTAL_ALIGNMENT_LEFT, -1, int(10 + p * 8.0), Color(c, 1.0 - p))
			"bubbles":
				_tint(c, t)
				for i in 5:
					var p := fmod(t * 0.7 + float(i) * 0.21, 1.0)
					var x := body.position.x + body.size.x * (0.2 + 0.6 * fmod(float(i) * 0.37, 1.0)) + sin(t * 3.0 + i) * 2.0
					draw_circle(Vector2(x, body.end.y - p * body.size.y * 0.9), 2.0 + p * 2.5, Color(c, 0.85 * (1.0 - p)))
			"flames":
				for i in 4:
					var x := body.position.x + body.size.x * (0.15 + 0.23 * float(i))
					var flick := 0.8 + 0.3 * sin(t * 9.0 + float(i) * 1.7)
					_shape(FLAME, Vector2(x, body.end.y - 4.0), Vector2(flick, flick * (1.0 + 0.25 * sin(t * 6.0 + i))), Color(c, 0.9))
			"stars":
				for i in 3:
					var a := t * 3.0 + TAU * float(i) / 3.0
					_shape(STAR, head + Vector2(cos(a) * 16.0, -6.0 + sin(a) * 5.0), Vector2.ONE, Color(c, 0.95))
			"swirl":
				var font := ThemeDB.fallback_font
				var off := Vector2(-14.0 + 10.0 * float(heads), -10.0)
				draw_string(font, head + off + Vector2(sin(t * 4.0) * 3.0, 0), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, c)
				heads += 1
			"hearts":
				for i in 3:
					var p := fmod(t * 0.6 + float(i) / 3.0, 1.0)
					_shape(HEART, head + Vector2(-12.0 + 12.0 * float(i), -2.0 - p * 18.0), Vector2.ONE * (0.8 + 0.4 * p), Color(c, 1.0 - p))
			"sweat":
				var p := fmod(t * 0.9, 1.0)
				_shape(DROP, head + Vector2(body.size.x * 0.35, 6.0 + p * 10.0), Vector2.ONE, Color(c, 1.0 - p))
			"wisps":
				for i in 3:
					var p := fmod(t * 0.45 + float(i) / 3.0, 1.0)
					var x := body.get_center().x + sin(t * 2.0 + float(i) * 2.1) * body.size.x * 0.4
					draw_circle(Vector2(x, body.end.y - p * body.size.y), 3.0 * (1.0 - p) + 1.0, Color(c, 0.7 * (1.0 - p)))
			"visor":
				var eye_y := body.position.y + body.size.y * 0.16
				draw_rect(Rect2(body.position.x + body.size.x * 0.18, eye_y - 3.0 + sin(t * 2.0), body.size.x * 0.64, 6.0), Color(c, 0.85))
			"mute":
				var at := head + Vector2(-16.0, -8.0)
				draw_arc(at, 6.0, 0.0, TAU, 16, c, 1.5)
				draw_line(at + Vector2(-4, 4), at + Vector2(4, -4), c, 2.0)
			"arrow":
				var slots: int = e["slots"]
				var x := arrow_x(int(e["slot"]), slots)
				var travel := fmod(t * 0.8 + float(e["slot"]) * 0.17, 1.0)
				var y := body.get_center().y + (12.0 - travel * 24.0 if e["up"] else -12.0 + travel * 24.0)
				var flip := 1.0 if e["up"] else -1.0
				_shape(ARROW, Vector2(x, y), Vector2(1.0, flip), Color(c, 0.35 + 0.65 * sin(travel * PI)))
			"plus":
				var p := fmod(t * 0.6, 1.0)
				_shape(PLUS, Vector2(body.get_center().x, body.end.y - p * body.size.y), Vector2.ONE, Color(c, 1.0 - p))
			"ring":
				var r := maxf(body.size.x, body.size.y) * 0.55
				draw_arc(body.get_center(), r + sin(t * 3.0) * 1.5, 0.0, TAU, 32, Color(c, 0.55), 2.0)
			"shadow":
				draw_rect(body.grow(-2.0), Color(c, 0.18 + 0.1 * sin(t * 4.0)), false, 2.0)
			"lines":
				for i in 3:
					var y := body.position.y + body.size.y * (0.3 + 0.2 * float(i))
					var p := fmod(t * 2.0 + float(i) * 0.3, 1.0)
					draw_line(Vector2(body.end.x + 4.0 + p * 10.0, y), Vector2(body.end.x + 14.0 + p * 10.0, y), Color(c, 1.0 - p), 2.0)
			"hourglass":
				_shape(HOURGLASS, head + Vector2(16.0, -6.0), Vector2(1.0, cos(t * 1.5)), Color(c, 0.9))
			"skull":
				var font := ThemeDB.fallback_font
				draw_string(font, head + Vector2(-6.0, -10.0 + sin(t * 2.5) * 2.0), "☠", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, c)
			_:
				var a := t * 2.0
				draw_circle(head + Vector2(cos(a) * 12.0, -6.0 + sin(a) * 4.0), 2.5, Color(c, 0.9))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _shape(points: PackedVector2Array, at: Vector2, sc: Vector2, color: Color) -> void:
	draw_set_transform(at, 0.0, sc)
	draw_colored_polygon(points, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A sick tint over the figure: the pulse is what reads at a glance. reduce_flashes keeps the tint and drops the pulse.
func _tint(c: Color, t: float) -> void:
	var a := 0.10 if _reduce_flashes else 0.08 + 0.10 * (0.5 + 0.5 * sin(t * 4.0))
	draw_rect(body, Color(c, a))
