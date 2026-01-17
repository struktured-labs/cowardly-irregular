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

var _player_in_zone: bool = false
var _indicator_label: Label


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	if show_indicator:
		_setup_indicator()


func _setup_indicator() -> void:
	_indicator_label = Label.new()
	_indicator_label.name = "Indicator"
	_indicator_label.text = indicator_text if indicator_text != "" else _get_default_indicator_text()
	_indicator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_indicator_label.position = Vector2(-40, -40)
	_indicator_label.visible = false
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
		if _indicator_label:
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


func _get_player_in_zone() -> Node2D:
	for body in get_overlapping_bodies():
		if _is_player(body):
			return body
	return null


func _trigger_transition(player: Node2D) -> void:
	# Disable player movement
	player.set_can_move(false)

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
