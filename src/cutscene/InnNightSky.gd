extends Control
class_name InnNightSky

## The night an inn rest shows (struktured 2026-11-12: the moon and three Z's were "really lame"): a pixel sky drawn on a
## chunky grid. A crescent moon crosses it, stars twinkle, a cloud drifts, the inn's last window goes dark, and dawn
## climbs the sky as the night ends. Everything is drawn on whole cells from one `progress` (0 = dusk, 1 = morning), so
## the same picture comes out at any frame rate and a skip can jump straight to dawn.

const NIGHT_TOP := Color(0.03, 0.04, 0.12)
const NIGHT_LOW := Color(0.08, 0.10, 0.26)
const DAWN_TOP := Color(0.36, 0.48, 0.74)
const DAWN_LOW := Color(0.98, 0.72, 0.52)
const MOON := Color(0.96, 0.95, 0.82)
const STAR := Color(0.92, 0.94, 1.0)
const CLOUD := Color(0.20, 0.23, 0.42)
const ROOF := Color(0.02, 0.02, 0.05)
const WINDOW := Color(1.0, 0.82, 0.42)
const BANDS := 10
const STARS := 70
## When dawn starts to climb, and when the moon has set.
## The ditty's last note lands at 4.75 of its 5.7 s (cowir-music 24210): dawn is well up by then.
const DAWN_AT := 0.72
const MOON_SET := 0.82
const WINDOW_OUT := 0.16

var progress := 0.0
## Seconds since the night began, for the twinkle only; the picture itself is a function of `progress`.
var clock := 0.0
var _stars: Array[Vector3i] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in STARS:
		_stars.append(Vector3i(rng.randi_range(0, 399), rng.randi_range(0, 150), rng.randi_range(0, 6)))


func set_night(p: float, seconds: float) -> void:
	progress = clampf(p, 0.0, 1.0)
	clock = seconds
	queue_redraw()


## One sky pixel in screen px: the screen is about 180 cells tall, whatever its size.
func cell() -> float:
	return maxf(2.0, roundf(size.y / 180.0))


## How far dawn has come, 0 at night and 1 at morning.
func dawn() -> float:
	return clampf((progress - DAWN_AT) / (1.0 - DAWN_AT), 0.0, 1.0)


## The moon's centre in CELLS: a low arc from the left edge to the right, setting by MOON_SET.
func moon_cell() -> Vector2i:
	var t: float = clampf(progress / MOON_SET, 0.0, 1.0)
	var cols: float = size.x / cell()
	var rows: float = size.y / cell()
	return Vector2i(roundi(lerpf(cols * 0.12, cols * 0.88, t)), roundi(rows * 0.62 - sin(t * PI) * rows * 0.42))


func _block(cx: int, cy: int, w: int, h: int, colour: Color) -> void:
	var c := cell()
	draw_rect(Rect2(float(cx) * c, float(cy) * c, float(w) * c, float(h) * c), colour)


func _draw() -> void:
	var c := cell()
	var cols := int(ceil(size.x / c))
	var rows := int(ceil(size.y / c))
	var d := dawn()
	var band_h := int(ceil(float(rows) / float(BANDS)))
	for b in BANDS:
		var t := float(b) / float(BANDS - 1)
		_block(0, b * band_h, cols, band_h, NIGHT_TOP.lerp(NIGHT_LOW, t).lerp(DAWN_TOP.lerp(DAWN_LOW, t), d))
	## Stars thin out as dawn comes, a few at a time, and each one blinks on its own beat.
	for i in _stars.size():
		var s: Vector3i = _stars[i]
		if float(i) / float(_stars.size()) < d * 1.4 or (int(clock * 3.0) + s.z) % 7 == 0:
			continue
		_block(s.x * cols / 400, s.y * rows / 180, 1, 1, STAR)
	if progress < MOON_SET:
		var m := moon_cell()
		for y in range(-6, 7):
			for x in range(-6, 7):
				if x * x + y * y <= 36 and (x - 3) * (x - 3) + (y + 1) * (y + 1) > 30:
					_block(m.x + x, m.y + y, 1, 1, MOON)
	## One cloud, drifting right across the whole night.
	var cloud_x := roundi(lerpf(-40.0, float(cols) + 10.0, progress))
	var cloud_y := roundi(float(rows) * 0.30)
	var cloud_colour: Color = CLOUD.lerp(Color(0.95, 0.78, 0.72), d)
	_block(cloud_x, cloud_y, 34, 5, cloud_colour)
	_block(cloud_x + 6, cloud_y - 3, 16, 4, cloud_colour)
	_block(cloud_x + 18, cloud_y - 2, 10, 3, cloud_colour)
	## The inn's roofline along the bottom, its last lit window going dark early in the night.
	var ground := rows - 22
	_block(0, ground + 10, cols, 12, ROOF)
	var roof_x := int(cols * 0.58)
	for step in 12:
		_block(roof_x + step, ground + 10 - step, 60 - step * 2, 1, ROOF)
	_block(roof_x + 44, ground - 8, 6, 9, ROOF)
	if progress < WINDOW_OUT:
		_block(roof_x + 20, ground + 3, 4, 5, WINDOW)
	elif d > 0.6:
		_block(roof_x + 20, ground + 3, 4, 5, WINDOW.lerp(Color.WHITE, 0.3))
