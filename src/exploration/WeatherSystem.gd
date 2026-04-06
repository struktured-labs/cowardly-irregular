extends Node
class_name WeatherSystem

## WeatherSystem — per-world weather overlays that complement ZoneParticles.
## Rain in medieval, fog in steampunk, smog in industrial, glitch in digital.
## Weather events cycle on/off for atmosphere.

var _canvas: CanvasLayer
var _overlay: ColorRect  # Fog/haze/darkening
var _rain_emitter: CPUParticles2D
var _player_ref: Node2D
var _current_world: String = ""

## Rain cycling state
var _rain_active: bool = false
var _rain_timer: float = 0.0
var _rain_phase_duration: float = 0.0
var _overlay_base_alpha: float = 0.0
var _overlay_rain_alpha: float = 0.0

## Glitch state (W5 digital)
var _glitch_enabled: bool = false
var _glitch_timer: float = 0.0
var _glitch_flash: ColorRect

## Fog breathing (oscillating opacity for atmosphere)
var _fog_breathe: bool = false
var _fog_time: float = 0.0

const PRESETS: Dictionary = {
	"medieval": {
		"rain": true,
		"rain_color": Color(0.75, 0.8, 0.9, 0.25),
		"rain_amount": 100,
		"rain_lifetime": 0.6,
		"rain_gravity": Vector2(40.0, 500.0),
		"rain_on_min": 20.0,
		"rain_on_max": 45.0,
		"rain_off_min": 30.0,
		"rain_off_max": 80.0,
		"overlay_color": Color(0.0, 0.0, 0.0, 0.0),
		"rain_overlay_color": Color(0.12, 0.14, 0.2, 0.18),
	},
	"suburban": {
		"overlay_color": Color(1.0, 0.97, 0.88, 0.04),
		"fog_breathe": true,
	},
	"steampunk": {
		"overlay_color": Color(0.55, 0.45, 0.3, 0.14),
		"fog_breathe": true,
	},
	"industrial": {
		"overlay_color": Color(0.22, 0.22, 0.2, 0.2),
		"fog_breathe": true,
	},
	"digital": {
		"overlay_color": Color(0.0, 0.08, 0.18, 0.06),
		"glitch": true,
		"glitch_min": 6.0,
		"glitch_max": 18.0,
	},
}


func setup(parent: Node, player: Node2D, world_id: String) -> void:
	_player_ref = player
	_current_world = world_id

	if not PRESETS.has(world_id):
		return

	var preset: Dictionary = PRESETS[world_id]

	_canvas = CanvasLayer.new()
	_canvas.name = "WeatherLayer"
	_canvas.layer = 3
	parent.add_child(_canvas)

	# Fog/haze overlay
	_overlay = ColorRect.new()
	_overlay.name = "WeatherOverlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base_color: Color = preset.get("overlay_color", Color(0, 0, 0, 0))
	_overlay.color = base_color
	_overlay_base_alpha = base_color.a
	_canvas.add_child(_overlay)

	_fog_breathe = preset.get("fog_breathe", false)

	# Start ambient sound for this world
	var ambient_key = _get_ambient_key(world_id)
	if ambient_key != "" and world_id != "medieval":
		# Medieval rain ambient handled by rain cycling below
		SoundManager.play_ambient(ambient_key)

	# Rain system
	if preset.get("rain", false):
		_setup_rain(preset)
		_rain_active = false
		_rain_timer = randf_range(5.0, 20.0)  # First rain starts soon
		_rain_phase_duration = _rain_timer
		_overlay_rain_alpha = preset.get("rain_overlay_color", Color(0, 0, 0, 0)).a

	# Glitch system
	if preset.get("glitch", false):
		_glitch_enabled = true
		_glitch_timer = randf_range(preset.get("glitch_min", 6.0), preset.get("glitch_max", 18.0))
		_glitch_flash = ColorRect.new()
		_glitch_flash.name = "GlitchFlash"
		_glitch_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		_glitch_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_glitch_flash.color = Color(0.0, 1.0, 0.8, 0.0)
		_canvas.add_child(_glitch_flash)


func _setup_rain(preset: Dictionary) -> void:
	_rain_emitter = CPUParticles2D.new()
	_rain_emitter.name = "RainParticles"
	_rain_emitter.z_index = 10
	_rain_emitter.emitting = false
	_rain_emitter.one_shot = false
	_rain_emitter.explosiveness = 0.0
	_rain_emitter.randomness = 0.3
	_rain_emitter.amount = preset.get("rain_amount", 100)
	_rain_emitter.lifetime = preset.get("rain_lifetime", 0.6)
	_rain_emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_rain_emitter.emission_rect_extents = Vector2(700, 50)
	_rain_emitter.gravity = preset.get("rain_gravity", Vector2(40.0, 500.0))
	_rain_emitter.initial_velocity_min = 200.0
	_rain_emitter.initial_velocity_max = 350.0
	_rain_emitter.direction = Vector2(0.1, 1.0)
	_rain_emitter.spread = 5.0
	_rain_emitter.color = preset.get("rain_color", Color(0.75, 0.8, 0.9, 0.25))
	_rain_emitter.scale_amount_min = 0.5
	_rain_emitter.scale_amount_max = 1.5
	# Position rain at top of screen
	_rain_emitter.position = Vector2(640, -20)
	_canvas.add_child(_rain_emitter)


func process(delta: float) -> void:
	if not _canvas:
		return

	# Fog breathing
	if _fog_breathe and _overlay:
		_fog_time += delta * 0.3
		var breathe = sin(_fog_time) * 0.04
		_overlay.color.a = clampf(_overlay_base_alpha + breathe, 0.0, 0.4)

	# Rain cycling
	if _rain_emitter:
		_rain_timer -= delta
		if _rain_timer <= 0.0:
			_rain_active = not _rain_active
			_rain_emitter.emitting = _rain_active
			# Toggle rain ambient sound
			if _rain_active:
				SoundManager.play_ambient("weather_rain")
			else:
				SoundManager.stop_ambient()
			var preset = PRESETS.get(_current_world, {})
			if _rain_active:
				_rain_phase_duration = randf_range(preset.get("rain_on_min", 20.0), preset.get("rain_on_max", 45.0))
			else:
				_rain_phase_duration = randf_range(preset.get("rain_off_min", 30.0), preset.get("rain_off_max", 80.0))
			_rain_timer = _rain_phase_duration

		# Smooth overlay transition during rain
		if _overlay:
			var target_alpha = _overlay_base_alpha
			if _rain_active:
				target_alpha = _overlay_rain_alpha
			_overlay.color.a = lerpf(_overlay.color.a, target_alpha, 2.0 * delta)

	# Glitch static
	if _glitch_enabled:
		_glitch_timer -= delta
		if _glitch_timer <= 0.0:
			_trigger_glitch()
			var preset = PRESETS.get(_current_world, {})
			_glitch_timer = randf_range(preset.get("glitch_min", 6.0), preset.get("glitch_max", 18.0))


func _trigger_glitch() -> void:
	if not _glitch_flash or not _player_ref:
		return
	# Quick cyan flash + random offset
	var tween = _player_ref.create_tween()
	var flash_color = [
		Color(0.0, 1.0, 0.8, 0.15),
		Color(1.0, 0.0, 0.5, 0.12),
		Color(0.0, 0.5, 1.0, 0.18),
	].pick_random()
	_glitch_flash.color = flash_color
	tween.tween_property(_glitch_flash, "color:a", 0.0, 0.15)
	# Brief screen jitter via overlay offset
	_glitch_flash.position = Vector2(randf_range(-3, 3), randf_range(-2, 2))
	tween.parallel().tween_property(_glitch_flash, "position", Vector2.ZERO, 0.15)


func _get_ambient_key(world_id: String) -> String:
	"""Map world ID to weather ambient sound key."""
	match world_id:
		"medieval": return "weather_rain"
		"suburban": return "weather_sunny"
		"steampunk": return "weather_steam"
		"industrial": return "weather_smog"
		"digital": return "weather_glitch"
		_: return ""
