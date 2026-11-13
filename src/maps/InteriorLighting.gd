class_name InteriorLighting
extends CanvasModulate

## One room's light (struktured 2026-11-12: "the inside of the inn is still pretty basic or crude"). A room gets a
## darkness for its lamps to read against, a look that follows the day clock, a night, and one hook the inn's rest
## scene drives. The village rig's indoor counterpart: lamps and the hearth are lit all day and carry the room at night.

## A lit room by day: a little under white, warm, so a lamp's pool shows.
const DAY_AMBIENT := Color(0.86, 0.82, 0.76)
## The same room at night, lamps aside: cool and dim, never black.
const NIGHT_AMBIENT := Color(0.34, 0.36, 0.52)
## How dark it is outside before the room starts to follow, and over what span of the sky's luminance.
const DARK_START := 0.95
const DARK_SPAN := 0.45
## A lamp's share of its full energy at noon; it reaches full by night.
const LAMP_DAY_SHARE := 0.55
const REST_FADE_SEC := 0.6
## False holds every flicker still (the store screenshots compare frames pixel by pixel).
static var flicker_enabled: bool = true

var day_ambient: Color = DAY_AMBIENT
var night_ambient: Color = NIGHT_AMBIENT
## Tooling hook (screenshots, tests): >= 0 pins the phase instead of reading GameState.
var phase_override: float = -1.0
var _lamps: Array = []
var _time: float = 0.0
## >= 0 while the inn's rest scene holds the room's darkness (0 = day, 1 = night); -1 = the clock decides.
var _rest_dark: float = -1.0
var _rest_tween: Tween = null


## How dark the room is, 0 (day) to 1 (night), for a day phase.
static func darkness_for(phase: float) -> float:
	var sky: Color = DayNightOverlay.tint_for_phase(fposmod(phase, 1.0))
	return clampf((DARK_START - sky.get_luminance()) / DARK_SPAN, 0.0, 1.0)


## A lamp's energy at a darkness: lit by day, full at night.
static func lamp_energy_for(dark: float, max_energy: float) -> float:
	return max_energy * lerpf(LAMP_DAY_SHARE, 1.0, clampf(dark, 0.0, 1.0))


func _ready() -> void:
	color = tint_now()


func darkness_now() -> float:
	if _rest_dark >= 0.0:
		return _rest_dark
	if phase_override >= 0.0:
		return darkness_for(phase_override)
	var gs = get_node_or_null("/root/GameState") if is_inside_tree() else null
	if gs == null or not ("day_phase" in gs):
		return 0.0
	return darkness_for(float(gs.day_phase))


func tint_now() -> Color:
	return day_ambient.lerp(night_ambient, darkness_now())


## Take charge of a light the room already built: its energy now follows the room's darkness. `flicker` is the share
## of its energy that wavers (a lantern 0.06, a hearth 0.25); 0 = steady.
func adopt(light: PointLight2D, flicker: float = 0.0) -> PointLight2D:
	light.set_meta("max_energy", light.energy)
	light.set_meta("flicker", flicker)
	light.set_meta("flicker_seed", float(_lamps.size()) * 1.7)
	_lamps.append(light)
	return light


func lamp_count() -> int:
	return _lamps.size()


func _process(delta: float) -> void:
	_time += delta
	var dark := darkness_now()
	color = day_ambient.lerp(night_ambient, dark)
	for l in _lamps:
		if not is_instance_valid(l):
			continue
		var e: float = lamp_energy_for(dark, float(l.get_meta("max_energy", 0.5)))
		var f: float = float(l.get_meta("flicker", 0.0))
		if f > 0.0 and flicker_enabled:
			var s: float = float(l.get_meta("flicker_seed", 0.0))
			e *= 1.0 + f * (0.7 * sin(_time * 7.3 + s) + 0.3 * sin(_time * 13.1 + s * 2.0))
		(l as PointLight2D).energy = e


## The inn's rest scene: "night" draws the room down to its night look, "dawn" lets it back up to what the clock
## says now (the scene has already set the morning). Any other word hands the room straight back to the clock.
func rest_light(moment: String) -> void:
	if _rest_tween != null and _rest_tween.is_valid():
		_rest_tween.kill()
	match moment:
		"night":
			_rest_dark = darkness_now()
			_rest_tween = create_tween()
			_rest_tween.tween_property(self, "_rest_dark", 1.0, REST_FADE_SEC)
		"dawn":
			var from: float = _rest_dark if _rest_dark >= 0.0 else 1.0
			_rest_dark = -1.0
			var to: float = darkness_now()
			_rest_dark = from
			_rest_tween = create_tween()
			_rest_tween.tween_property(self, "_rest_dark", to, REST_FADE_SEC)
			_rest_tween.tween_callback(func(): _rest_dark = -1.0)
		_:
			_rest_dark = -1.0
