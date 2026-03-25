extends Area2D
class_name AreaTransition

## AreaTransition - Trigger zone for transitioning between areas
## Place at doorways, cave entrances, etc.

const OverworldPlayerScript = preload("res://src/exploration/OverworldPlayer.gd")

signal transition_triggered(target_map: String, spawn_point: String)

## Target map to load
@export var target_map: String = "overworld"

## Spawn point name in target map
@export var target_spawn: String = "default"

## Optional: require player to press interact button (otherwise auto-trigger)
@export var require_interaction: bool = false

## Visual indicator settings
@export var show_indicator: bool = true
@export var indicator_text: String = ""  # Empty = auto ("Enter Cave", etc.)
@export var show_gate_visual: bool = true  # Draw a visible gate/archway

## Gate visual colors per exit type
const GATE_COLORS = {
	"overworld": {
		"pillar": Color(0.45, 0.38, 0.3),
		"pillar_light": Color(0.58, 0.50, 0.42),
		"pillar_dark": Color(0.30, 0.25, 0.20),
		"arch": Color(0.52, 0.44, 0.36),
		"banner": Color(0.7, 0.2, 0.15),
		"banner_trim": Color(0.85, 0.75, 0.3),
		"ground": Color(0.5, 0.45, 0.35),
	},
	"cave": {
		"pillar": Color(0.35, 0.33, 0.38),
		"pillar_light": Color(0.48, 0.45, 0.52),
		"pillar_dark": Color(0.22, 0.20, 0.25),
		"arch": Color(0.28, 0.25, 0.30),
		"banner": Color(0.15, 0.4, 0.5),
		"banner_trim": Color(0.3, 0.6, 0.7),
		"ground": Color(0.32, 0.30, 0.35),
	},
	"village": {
		"pillar": Color(0.55, 0.42, 0.28),
		"pillar_light": Color(0.68, 0.55, 0.38),
		"pillar_dark": Color(0.38, 0.28, 0.18),
		"arch": Color(0.62, 0.48, 0.32),
		"banner": Color(0.2, 0.5, 0.25),
		"banner_trim": Color(0.8, 0.78, 0.4),
		"ground": Color(0.55, 0.48, 0.38),
	},
}

var _player_in_zone: bool = false
var _indicator_label: Label
var _arrow_blink: float = 0.0
var _redraw_timer: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	if show_indicator:
		_setup_indicator()


func _process(delta: float) -> void:
	if show_gate_visual:
		_arrow_blink += delta * 2.0
		_redraw_timer += delta
		if _redraw_timer > 0.1:
			_redraw_timer = 0.0
			queue_redraw()


func _draw() -> void:
	if not show_gate_visual:
		return

	var gate_type = _get_gate_type()
	var colors = GATE_COLORS.get(gate_type, GATE_COLORS["overworld"])

	# Gate size (fits ~3 tiles wide)
	var gate_w = 48.0
	var gate_h = 56.0
	var half_w = gate_w / 2.0

	# Ground path markers (cobblestone dots leading to gate)
	var ground_color = colors["ground"]
	for i in range(5):
		var dot_y = 20.0 + i * 8.0
		var dot_x = sin(i * 1.3) * 4.0
		draw_circle(Vector2(dot_x, dot_y), 2.0, ground_color)
		draw_circle(Vector2(dot_x + 6, dot_y + 3), 1.5, ground_color.darkened(0.15))
		draw_circle(Vector2(dot_x - 5, dot_y + 5), 1.5, ground_color.darkened(0.1))

	# Left pillar
	draw_rect(Rect2(-half_w - 4, -gate_h, 8, gate_h), colors["pillar_dark"])
	draw_rect(Rect2(-half_w - 3, -gate_h + 1, 6, gate_h - 2), colors["pillar"])
	draw_rect(Rect2(-half_w - 2, -gate_h + 2, 2, gate_h - 4), colors["pillar_light"])
	# Pillar cap
	draw_rect(Rect2(-half_w - 6, -gate_h - 4, 12, 6), colors["pillar_light"])
	draw_rect(Rect2(-half_w - 5, -gate_h - 3, 10, 4), colors["pillar"])

	# Right pillar
	draw_rect(Rect2(half_w - 4, -gate_h, 8, gate_h), colors["pillar_dark"])
	draw_rect(Rect2(half_w - 3, -gate_h + 1, 6, gate_h - 2), colors["pillar"])
	draw_rect(Rect2(half_w + 1, -gate_h + 2, 2, gate_h - 4), colors["pillar_light"])
	# Pillar cap
	draw_rect(Rect2(half_w - 6, -gate_h - 4, 12, 6), colors["pillar_light"])
	draw_rect(Rect2(half_w - 5, -gate_h - 3, 10, 4), colors["pillar"])

	# Arch connecting pillars
	draw_rect(Rect2(-half_w - 3, -gate_h - 2, gate_w + 6, 5), colors["arch"])
	draw_rect(Rect2(-half_w - 2, -gate_h - 1, gate_w + 4, 3), colors["pillar_light"])

	# Banner hanging from arch
	var banner_w = 28.0
	draw_rect(Rect2(-banner_w / 2, -gate_h + 6, banner_w, 16), colors["banner"])
	draw_rect(Rect2(-banner_w / 2, -gate_h + 6, banner_w, 2), colors["banner_trim"])
	draw_rect(Rect2(-banner_w / 2, -gate_h + 20, banner_w, 2), colors["banner_trim"])
	# Banner triangle bottom (pennant shape)
	var tri_points = PackedVector2Array([
		Vector2(-banner_w / 2, -gate_h + 22),
		Vector2(0, -gate_h + 30),
		Vector2(banner_w / 2, -gate_h + 22)
	])
	draw_colored_polygon(tri_points, colors["banner"])

	# Pulsing arrow indicator when player is nearby
	var alpha = 0.5 + sin(_arrow_blink) * 0.3
	var arrow_color = Color(1.0, 1.0, 0.6, alpha)
	if _player_in_zone:
		arrow_color = Color(1.0, 0.9, 0.3, 0.7 + sin(_arrow_blink * 2) * 0.3)

	# Down arrow below gate (pointing toward exit)
	var arrow_y = 8.0
	var arrow_points = PackedVector2Array([
		Vector2(-8, arrow_y),
		Vector2(0, arrow_y + 10),
		Vector2(8, arrow_y)
	])
	draw_colored_polygon(arrow_points, arrow_color)


func _get_gate_type() -> String:
	"""Determine gate visual style based on target"""
	var t = target_map.to_lower()
	if "village" in t:
		return "village"
	elif "cave" in t or "dungeon" in t:
		return "cave"
	return "overworld"


func _setup_indicator() -> void:
	_indicator_label = Label.new()
	_indicator_label.name = "Indicator"
	_indicator_label.text = indicator_text if indicator_text != "" else _get_default_indicator_text()
	_indicator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_indicator_label.position = Vector2(-40, -72)
	_indicator_label.visible = show_gate_visual  # Always visible when gate is drawn
	_indicator_label.add_theme_font_size_override("font_size", 12)
	_indicator_label.add_theme_color_override("font_color", Color.WHITE)
	_indicator_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_indicator_label.add_theme_constant_override("shadow_offset_x", 1)
	_indicator_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_indicator_label)


func _get_default_indicator_text() -> String:
	if "village" in target_map.to_lower():
		return "Enter Village"
	elif "cave" in target_map.to_lower() or "dungeon" in target_map.to_lower():
		return "Enter Cave"
	elif "overworld" in target_map.to_lower():
		return "Exit"
	return "Enter"


func _on_body_entered(body: Node2D) -> void:
	if _is_player(body):
		_player_in_zone = true
		if _indicator_label:
			_indicator_label.visible = true

		if not require_interaction:
			_trigger_transition(body)


func _on_body_exited(body: Node2D) -> void:
	if _is_player(body):
		_player_in_zone = false
		if _indicator_label and not show_gate_visual:
			_indicator_label.visible = false


func _is_player(body: Node2D) -> bool:
	return body.get_script() == OverworldPlayerScript


func _input(event: InputEvent) -> void:
	if require_interaction and _player_in_zone:
		if event.is_action_pressed("ui_accept"):
			var player = _get_player_in_zone()
			if player:
				_trigger_transition(player)
				get_viewport().set_input_as_handled()
		# Mouse click to interact
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var player = _get_player_in_zone()
			if player:
				_trigger_transition(player)
				get_viewport().set_input_as_handled()


func _get_player_in_zone() -> Node2D:
	for body in get_overlapping_bodies():
		if _is_player(body):
			return body
	return null


func _trigger_transition(_player: Node2D) -> void:
	# GameLoop handles state change — no need to freeze player manually

	# Hide indicator
	if _indicator_label:
		_indicator_label.visible = false

	# Emit signal for scene to handle (GameLoop listens to this)
	transition_triggered.emit(target_map, target_spawn)
	# Note: Don't call SceneTransition/MapSystem directly - GameLoop handles it


## Called by player interaction system
func interact(player: Node2D) -> void:
	if require_interaction and _player_in_zone:
		_trigger_transition(player)
