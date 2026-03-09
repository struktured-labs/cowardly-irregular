extends Control
class_name SparklineChart

var _values: Array[float] = []
var _max_values: int = 60
var line_color: Color = Color(0.4, 0.9, 0.4)
var fill_color: Color = Color(0.4, 0.9, 0.4, 0.15)
var line_width: float = 1.5
var show_fill: bool = true

## Pulse animation for trending charts
var _pulse_time: float = 0.0
var _is_trending_up: bool = false
var _is_trending_down: bool = false
const TREND_PULSE_SPEED: float = 3.0


func _init(max_vals: int = 60, color: Color = Color(0.4, 0.9, 0.4)) -> void:
	_max_values = max_vals
	line_color = color
	fill_color = Color(color.r, color.g, color.b, 0.15)


func push_value(v: float) -> void:
	_values.append(v)
	if _values.size() > _max_values:
		_values.remove_at(0)
	_update_trend()
	queue_redraw()


func clear() -> void:
	_values.clear()
	_is_trending_up = false
	_is_trending_down = false
	queue_redraw()


func _update_trend() -> void:
	if _values.size() < 4:
		_is_trending_up = false
		_is_trending_down = false
		return
	var window := mini(_values.size(), 8)
	var recent := _values[_values.size() - 1]
	var older := _values[_values.size() - window]
	var delta := recent - older
	var threshold := maxf(absf(older) * 0.08, 0.1)
	_is_trending_up = delta > threshold
	_is_trending_down = delta < -threshold


func _process(delta: float) -> void:
	if _is_trending_up or _is_trending_down:
		_pulse_time += delta * TREND_PULSE_SPEED
		queue_redraw()


func _draw() -> void:
	if _values.size() < 2:
		return

	var rect = get_rect()
	var w = rect.size.x
	var h = rect.size.y

	var v_min = _values[0]
	var v_max = _values[0]
	for v in _values:
		v_min = min(v_min, v)
		v_max = max(v_max, v)

	var v_range = v_max - v_min
	if v_range < 0.001:
		v_range = 1.0
		v_min = v_min - 0.5

	var points: PackedVector2Array = PackedVector2Array()
	var step_x = w / max(_max_values - 1, 1)
	var offset_x = w - (_values.size() - 1) * step_x

	for i in range(_values.size()):
		var x = offset_x + i * step_x
		var y = h - (((_values[i] - v_min) / v_range) * (h - 4)) - 2
		points.append(Vector2(x, y))

	# Fill — brighten slightly when trending up
	if show_fill and points.size() >= 2:
		var actual_fill = fill_color
		if _is_trending_up:
			actual_fill = Color(fill_color.r, fill_color.g, fill_color.b,
				fill_color.a + 0.08 * (0.5 + 0.5 * sin(_pulse_time)))
		var fill_points = points.duplicate()
		fill_points.append(Vector2(points[-1].x, h))
		fill_points.append(Vector2(points[0].x, h))
		draw_colored_polygon(fill_points, actual_fill)

	if points.size() >= 2:
		draw_polyline(points, line_color, line_width, true)

	# Glow dot on the latest data point
	var tip := points[-1]
	var pulse_scale := 1.0
	if _is_trending_up or _is_trending_down:
		pulse_scale = 1.0 + 0.35 * (0.5 + 0.5 * sin(_pulse_time))

	var dot_color := line_color
	if _is_trending_down:
		dot_color = Color(0.9, 0.4, 0.4)  # Red tint when falling

	# Outer glow ring (semi-transparent, larger)
	draw_circle(tip, 4.0 * pulse_scale, Color(dot_color.r, dot_color.g, dot_color.b, 0.25))
	# Inner solid dot
	draw_circle(tip, 2.5 * pulse_scale, dot_color)
