class_name DayClockWidget
extends CanvasLayer
## Per-world day/night clock (struktured 2026-07-18: "some indicator on the
## overworld about what time of day it is... appropriate for that particular
## overworld... should disappear when you enter the menu"). Dial hand sweeps a
## full day; phase glyph + band label; ring/face themed per world. GameLoop
## drives outdoor/menu flags; _process hides it outside pure exploration.

const WORLD_THEMES := {
	1: {"ring": Color(0.58, 0.44, 0.24), "face": Color(0.16, 0.13, 0.09, 0.88)},
	2: {"ring": Color(0.85, 0.58, 0.75), "face": Color(0.10, 0.12, 0.18, 0.88)},
	3: {"ring": Color(0.75, 0.57, 0.24), "face": Color(0.12, 0.10, 0.06, 0.88)},
	4: {"ring": Color(0.55, 0.58, 0.62), "face": Color(0.10, 0.10, 0.11, 0.88)},
	5: {"ring": Color(0.25, 0.88, 0.84), "face": Color(0.05, 0.08, 0.14, 0.88)},
	6: {"ring": Color(0.86, 0.86, 0.86), "face": Color(0.05, 0.05, 0.05, 0.88)},
}
const BAND_GLYPH := {"dawn": "🌅", "day": "☀", "dusk": "🌇", "night": "🌙"}

var _outdoor: bool = false
var _menu_open: bool = false
var _world: int = 1
var _dial: Control = null


func _ready() -> void:
	layer = 45
	_dial = Control.new()
	_dial.name = "DayClockDial"
	_dial.custom_minimum_size = Vector2(72, 88)
	_dial.size = Vector2(72, 88)
	_dial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dial.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_dial.position = Vector2(get_viewport().get_visible_rect().size.x / 2.0 - 36, 8)
	_dial.draw.connect(_draw_dial)
	add_child(_dial)


func set_outdoor(outdoor: bool) -> void:
	_outdoor = outdoor


func set_menu_open(open_now: bool) -> void:
	_menu_open = open_now


func set_world(world: int) -> void:
	_world = clampi(world, 1, 6)


func _process(_delta: float) -> void:
	var gl = get_parent()
	var exploring: bool = gl != null and "current_state" in gl and int(gl.current_state) == int(gl.LoopState.EXPLORATION)
	var vis: bool = _outdoor and not _menu_open and exploring \
		and get_node_or_null("/root/GameState") != null and "day_phase" in GameState
	if visible != vis:
		visible = vis
	if visible and _dial:
		_dial.queue_redraw()


func _draw_dial() -> void:
	var theme_c: Dictionary = WORLD_THEMES.get(_world, WORLD_THEMES[1])
	var center := Vector2(36, 36)
	var band: String = GameState.get_time_of_day_name() if GameState.has_method("get_time_of_day_name") else "day"
	# Face tinted faintly toward the current sky color so the clock agrees with the world
	var sky: Color = DayNightOverlay.tint_for_phase(fposmod(float(GameState.day_phase), 1.0))
	_dial.draw_circle(center, 30.0, theme_c["face"])
	_dial.draw_arc(center, 30.0, 0, TAU, 40, theme_c["ring"], 3.0)
	_dial.draw_arc(center, 25.0, 0, TAU, 40, Color(sky.r, sky.g, sky.b, 0.35), 2.0)
	# Hand: phase 0 at top, sweeping clockwise through the full day
	var angle: float = fposmod(float(GameState.day_phase), 1.0) * TAU - PI / 2.0
	_dial.draw_line(center, center + Vector2(cos(angle), sin(angle)) * 22.0, theme_c["ring"].lightened(0.3), 2.5)
	_dial.draw_circle(center, 3.0, theme_c["ring"])
	# Phase glyph inside the face (FontFallbacks makes the emoji real on web)
	var font := ThemeDB.fallback_font
	_dial.draw_string(font, Vector2(24, 30), BAND_GLYPH.get(band, "☀"), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	# Band label under the dial
	_dial.draw_string(font, Vector2(0, 82), band.capitalize(), HORIZONTAL_ALIGNMENT_CENTER, 72, 12, theme_c["ring"].lightened(0.4))
