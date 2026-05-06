extends Control
class_name BattleMode7Floor

## Mode 7-style perspective floor overlay for battle scenes.
##
## Renders a tilted ground plane below the party/enemy sprites: a tinted floor
## with converging vertical lines + exponentially-spaced horizontal lines that
## sell the "camera looking down at a tilted plane" effect without a real
## screen-texture shader.
##
## Procedural draw — no texture asset needed. Tunable params for fast
## iteration. Keep it BEHIND sprites (low z-index) and on top of the
## BattleBackground so it reads as the floor the characters are standing on.
##
## Spike rules: no shared file changes, easy to delete if user doesn't like it.

## How far down the screen the horizon sits (0 = top, 1 = bottom).
## Higher value = camera is more "level" with the ground (less tilt).
@export var horizon_ratio: float = 0.55

## Color of the floor surface (tinted, alpha < 1.0 lets the BattleBackground
## show through so terrain colors blend with the floor).
@export var floor_color: Color = Color(0.10, 0.06, 0.18, 0.55)

## Color of the perspective grid lines.
@export var grid_color: Color = Color(0.55, 0.45, 0.75, 0.85)

## Number of vertical convergence lines fanning out from the horizon center.
## More = denser grid, fewer = cleaner / more retro feel.
@export var vertical_line_count: int = 14

## Number of horizontal depth lines between horizon and camera-bottom.
@export var depth_line_count: int = 9

## Power curve for horizontal line spacing. >1 packs lines near horizon
## (more depth feel), <1 evens them out.
@export var depth_curve: float = 2.4

## How far below the bottom edge the vertical lines extend (>1 = past edge,
## creates the "floor extends past camera" feel).
@export var vertical_overshoot: float = 0.6

## Line thickness in pixels.
@export var line_width: float = 1.0

## Optional camera-tilt animation amplitude (0 = static, >0 = subtle bob).
## Reserved for boss phase-2 emphasis later — keep at 0 for the baseline spike.
@export var tilt_amplitude: float = 0.0

var _time: float = 0.0


func _ready() -> void:
	# Stretch to parent fully, ignore mouse so it doesn't block input.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if tilt_amplitude > 0.0:
		_time += delta
		queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return

	var horizon_y: float = horizon_ratio * h
	# Optional subtle bob for emphasis modes (off by default).
	if tilt_amplitude > 0.0:
		horizon_y += sin(_time * 1.4) * tilt_amplitude * h

	# Fill the floor area with tinted color.
	draw_rect(Rect2(0.0, horizon_y, w, h - horizon_y), floor_color)

	var center_x: float = w * 0.5
	# Endpoints extend past the bottom edge so the lines don't clip awkwardly.
	var bottom_y: float = h * (1.0 + vertical_overshoot)

	# Vertical lines converging from the floor edges to horizon center.
	# Spread the bottom endpoints across the full width plus overshoot
	# proportional to vertical_overshoot for a wider field of view.
	var spread: float = 1.0 + vertical_overshoot * 0.5
	for i in range(-vertical_line_count, vertical_line_count + 1):
		var t: float = float(i) / float(vertical_line_count)
		var x_at_bottom: float = center_x + t * w * spread * 0.5 * 2.0
		draw_line(
			Vector2(center_x, horizon_y),
			Vector2(x_at_bottom, bottom_y),
			grid_color,
			line_width
		)

	# Horizontal depth lines, exponentially spaced toward horizon.
	# At i=0 we're at the horizon (line is a point), at i=count we're at
	# the camera (line is full width). Power curve packs detail near horizon.
	for i in range(1, depth_line_count + 1):
		var t: float = float(i) / float(depth_line_count)
		var depth_t: float = pow(t, depth_curve)
		var y: float = horizon_y + (h - horizon_y) * depth_t
		# Width grows with depth — far lines short, near lines wide.
		var half_w: float = w * spread * 0.5 * depth_t
		# Fade alpha so far lines whisper, near lines shout.
		var line_alpha: float = lerp(0.35, 1.0, depth_t)
		var c: Color = grid_color
		c.a *= line_alpha
		draw_line(
			Vector2(center_x - half_w, y),
			Vector2(center_x + half_w, y),
			c,
			line_width
		)
