extends Node
class_name WeatherSystem

## WeatherSystem v2 — pure RENDERER of GameState.weather_condition (2026-09-04).
## v1 rolled rain cycles privately per scene, so villages/battle/saves could not agree
## it was raining. State now lives in GameState (rolled per world, save-persisted);
## this node polls it each frame and renders the matching effect. Overworlds AND
## villages instantiate it; battle has its own lighter overlay in BattleScene.

var _canvas: CanvasLayer
var _overlay: ColorRect
var _rain_emitter: CPUParticles2D
var _lightning_flash: ColorRect
var _glitch_flash: ColorRect
var _player_ref: Node2D
var _current_world: String = ""

var _rendered_condition: String = ""
var _overlay_target_alpha: float = 0.0
var _overlay_base_color: Color = Color(0, 0, 0, 0)
var _fog_breathe: bool = false
var _fog_time: float = 0.0
var _lightning_timer: float = 0.0
var _glitch_timer: float = 0.0

## Per-world ambient tint on the clear state (kept from v1's atmosphere pass).
const WORLD_TINTS: Dictionary = {
	"medieval": Color(0.0, 0.0, 0.0, 0.0),
	"suburban": Color(1.0, 0.97, 0.88, 0.04),
	"steampunk": Color(0.55, 0.45, 0.3, 0.08),
	"industrial": Color(0.22, 0.22, 0.2, 0.1),
	"digital": Color(0.0, 0.08, 0.18, 0.06),
}

## Condition → render params. Overlay colors here are the ACTIVE-weather tint; the
## clear state falls back to the world tint above.
const RENDER: Dictionary = {
	"clear": {},
	"drizzle": {"rain_amount": 40, "rain_velocity": 160.0, "overlay": Color(0.3, 0.34, 0.4, 0.08), "ambient": "weather_rain"},
	"rain": {"rain_amount": 110, "rain_velocity": 260.0, "overlay": Color(0.12, 0.14, 0.2, 0.18), "ambient": "weather_rain"},
	"storm": {"rain_amount": 220, "rain_velocity": 380.0, "overlay": Color(0.08, 0.09, 0.15, 0.3), "ambient": "weather_rain", "lightning": true},
	"fog": {"overlay": Color(0.55, 0.45, 0.3, 0.16), "breathe": true, "ambient": "weather_steam"},
	"smog": {"overlay": Color(0.22, 0.22, 0.2, 0.22), "breathe": true, "ambient": "weather_smog"},
	"glitchstorm": {"overlay": Color(0.0, 0.1, 0.2, 0.1), "glitch": true, "ambient": "weather_glitch"},
}

const WORLD_IDS: Dictionary = {1: "medieval", 2: "suburban", 3: "steampunk", 4: "industrial", 5: "digital", 6: "abstract"}

## Fair-weather ambient beds per world (v1 played these at setup; clear restores them).
const WORLD_CLEAR_AMBIENTS: Dictionary = {
	"suburban": "weather_sunny",
	"steampunk": "weather_steam",
	"industrial": "weather_smog",
	"digital": "weather_glitch",
}


static func world_id_for(world_num: int) -> String:
	return str(WORLD_IDS.get(world_num, "abstract"))


func setup(parent: Node, player: Node2D, world_id: String) -> void:
	_player_ref = player
	_current_world = world_id
	if world_id == "abstract":
		return

	_canvas = CanvasLayer.new()
	_canvas.name = "WeatherLayer"
	_canvas.layer = 3
	parent.add_child(_canvas)

	_overlay = ColorRect.new()
	_overlay.name = "WeatherOverlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_base_color = WORLD_TINTS.get(world_id, Color(0, 0, 0, 0))
	_overlay.color = _overlay_base_color
	_overlay_target_alpha = _overlay_base_color.a
	_canvas.add_child(_overlay)

	_setup_rain()
	_lightning_flash = _make_flash_rect("LightningFlash", Color(1.0, 1.0, 1.0, 0.0))
	_glitch_flash = _make_flash_rect("GlitchFlash", Color(0.0, 1.0, 0.8, 0.0))
	_rendered_condition = ""


func _make_flash_rect(rect_name: String, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = rect_name
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = color
	_canvas.add_child(rect)
	return rect


func _setup_rain() -> void:
	_rain_emitter = CPUParticles2D.new()
	_rain_emitter.name = "RainParticles"
	_rain_emitter.z_index = 10
	_rain_emitter.emitting = false
	_rain_emitter.one_shot = false
	_rain_emitter.explosiveness = 0.0
	_rain_emitter.randomness = 0.3
	_rain_emitter.amount = 100
	_rain_emitter.lifetime = 0.6
	_rain_emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_rain_emitter.emission_rect_extents = Vector2(700, 50)
	_rain_emitter.gravity = Vector2(40.0, 500.0)
	_rain_emitter.initial_velocity_min = 200.0
	_rain_emitter.initial_velocity_max = 350.0
	_rain_emitter.direction = Vector2(0.1, 1.0)
	_rain_emitter.spread = 5.0
	_rain_emitter.color = Color(0.75, 0.8, 0.9, 0.25)
	_rain_emitter.scale_amount_min = 0.5
	_rain_emitter.scale_amount_max = 1.5
	_rain_emitter.position = Vector2(640, -20)
	_canvas.add_child(_rain_emitter)


func process(delta: float) -> void:
	if not _canvas:
		return
	var condition := _game_weather()
	if condition != _rendered_condition:
		_apply_condition(condition)

	var params: Dictionary = RENDER.get(_rendered_condition, {})
	if _fog_breathe and _overlay:
		_fog_time += delta * 0.3
		_overlay.color.a = clampf(_overlay_target_alpha + sin(_fog_time) * 0.04, 0.0, 0.4)
	elif _overlay:
		_overlay.color.a = lerpf(_overlay.color.a, _overlay_target_alpha, 2.0 * delta)

	if bool(params.get("lightning", false)):
		_lightning_timer -= delta
		if _lightning_timer <= 0.0:
			_trigger_lightning()
			_lightning_timer = randf_range(4.0, 12.0)

	if bool(params.get("glitch", false)):
		_glitch_timer -= delta
		if _glitch_timer <= 0.0:
			_trigger_glitch()
			_glitch_timer = randf_range(6.0, 18.0)


func _game_weather() -> String:
	var gs: Node = _autoload("GameState")
	if gs and gs.has_method("get_weather"):
		return str(gs.get_weather())
	return "clear"


func _apply_condition(condition: String) -> void:
	_rendered_condition = condition
	var params: Dictionary = RENDER.get(condition, {})
	_fog_breathe = bool(params.get("breathe", false))
	var raining := params.has("rain_amount")
	if _rain_emitter:
		_rain_emitter.emitting = raining
		if raining:
			_rain_emitter.amount = int(params["rain_amount"])
			_rain_emitter.initial_velocity_min = float(params["rain_velocity"]) * 0.8
			_rain_emitter.initial_velocity_max = float(params["rain_velocity"]) * 1.3
	if params.has("overlay"):
		var oc: Color = params["overlay"]
		_overlay.color = Color(oc.r, oc.g, oc.b, _overlay.color.a)
		_overlay_target_alpha = oc.a
	else:
		_overlay.color = Color(_overlay_base_color.r, _overlay_base_color.g, _overlay_base_color.b, _overlay.color.a)
		_overlay_target_alpha = _overlay_base_color.a
	_lightning_timer = randf_range(2.0, 6.0)
	_glitch_timer = randf_range(3.0, 10.0)

	var sm: Node = _autoload("SoundManager")
	if sm and sm.has_method("play_ambient"):
		# Clear falls back to the world's fair-weather bed (v1 behavior), not silence.
		# Literal keys per branch so the sfx-orphan audit can see every ambient this plays.
		match str(params.get("ambient", WORLD_CLEAR_AMBIENTS.get(_current_world, ""))):
			"weather_rain": sm.play_ambient("weather_rain")
			"weather_steam": sm.play_ambient("weather_steam")
			"weather_smog": sm.play_ambient("weather_smog")
			"weather_glitch": sm.play_ambient("weather_glitch")
			"weather_sunny": sm.play_ambient("weather_sunny")
			_: if sm.has_method("stop_ambient"): sm.stop_ambient()


func _flashes_suppressed() -> bool:
	var gs: Node = _autoload("GameState")
	return gs != null and ("reduce_flashes" in gs) and bool(gs.reduce_flashes)


func _trigger_lightning() -> void:
	if not _lightning_flash or not _player_ref or _flashes_suppressed():
		return
	_lightning_flash.color = Color(1.0, 1.0, 1.0, 0.35)
	var tween = _player_ref.create_tween()
	tween.tween_property(_lightning_flash, "color:a", 0.0, 0.2)
	var sm: Node = _autoload("SoundManager")
	if sm and sm.has_method("play_battle"):
		sm.play_battle("ability_lightning")


func _trigger_glitch() -> void:
	if not _glitch_flash or not _player_ref or _flashes_suppressed():
		return
	var tween = _player_ref.create_tween()
	_glitch_flash.color = [
		Color(0.0, 1.0, 0.8, 0.15),
		Color(1.0, 0.0, 0.5, 0.12),
		Color(0.0, 0.5, 1.0, 0.18),
	].pick_random()
	tween.tween_property(_glitch_flash, "color:a", 0.0, 0.15)
	_glitch_flash.position = Vector2(randf_range(-3, 3), randf_range(-2, 2))
	tween.parallel().tween_property(_glitch_flash, "position", Vector2.ZERO, 0.15)


func _autoload(autoload_name: String) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null(autoload_name)
