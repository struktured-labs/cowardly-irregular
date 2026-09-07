class_name VillageLighting
extends CanvasModulate
## Per-scene day/night modulate (same curve as DayNightOverlay) so PointLight2D lamps pierce the dusk instead of being multiplied into it.

const LAMP_FADE_START := 0.95
const LAMP_FADE_SPAN := 0.30

var _lamps: Array = []
var _light_tex: ImageTexture
## Tooling hook (screenshots): >= 0 pins the phase instead of reading GameState
var phase_override: float = -1.0


static func tint_for(phase: float) -> Color:
	return DayNightOverlay.tint_for_phase(fposmod(phase, 1.0))


## Lamps come up as the tint loses luminance: off in daylight, full by deep dusk.
static func lamp_energy_for(tint: Color, max_energy: float) -> float:
	return max_energy * clampf((LAMP_FADE_START - tint.get_luminance()) / LAMP_FADE_SPAN, 0.0, 1.0)


func _ready() -> void:
	color = Color.WHITE
	_light_tex = _make_light_texture(96)


func _process(_delta: float) -> void:
	color = tint_now()
	for l in _lamps:
		if is_instance_valid(l):
			l.energy = lamp_energy_for(color, float(l.get_meta("max_energy", 0.9)))


func tint_now() -> Color:
	if phase_override >= 0.0:
		return tint_for(phase_override)
	var gs = get_node_or_null("/root/GameState")
	if gs == null or not ("day_phase" in gs):
		return Color.WHITE
	return tint_for(float(gs.day_phase))


func add_lamp(pos: Vector2, lamp_color: Color = Color(1.0, 0.85, 0.55), radius: int = 96, energy: float = 0.9) -> PointLight2D:
	var l := PointLight2D.new()
	l.position = pos
	l.color = lamp_color
	l.texture = _light_tex if radius == 96 else _make_light_texture(radius)
	l.energy = lamp_energy_for(color, energy)
	l.set_meta("max_energy", energy)
	add_child(l)
	_lamps.append(l)
	return l


static func _make_light_texture(radius: int) -> ImageTexture:
	var size := radius * 2
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := size / 2
	for y in range(size):
		for x in range(size):
			var dist := Vector2(x - center, y - center).length()
			var alpha := clampf(1.0 - dist / float(center), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, alpha * alpha))
	return ImageTexture.create_from_image(img)
