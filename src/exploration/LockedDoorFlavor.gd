extends Area2D
class_name LockedDoorFlavor

## LockedDoorFlavor — a lightweight "this door looks enterable but isn't"
## interactable (struktured msg 2780 item 1 general rule: any door-shaped
## visual must respond to interact). Player walking into the trigger zone
## sees the [A] Examine indicator; ui_accept fires a short flavor toast.
## Save-state-free by design — these are ambient jokes, not quests.
##
## First consumer: the TavernInterior "locked private quarters" staircase
## at the bottom-right (UU tiles). Reusable for any future door-shaped
## deco the player might mistake for an entry.

const TILE_SIZE: int = 32

## The line shown on interact. Author whatever tone the room calls for.
@export var flavor_line: String = "The door doesn't budge."

## Optional [A] indicator label — leave default or tune per instance.
@export var indicator_text: String = "[A] Examine"

## Trigger zone radius in pixels. Default is comfortable for a 1-2 tile
## door footprint; enlarge for wider doors.
@export var trigger_radius: float = 48.0

var _indicator: Label
var _player_in_zone: bool = false
var _busy: bool = false


func _ready() -> void:
	add_to_group("interactables")
	_setup_collision()
	_setup_indicator()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _setup_collision() -> void:
	collision_layer = 4
	collision_mask = 2
	monitoring = true
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = trigger_radius
	cs.shape = shape
	add_child(cs)


func _setup_indicator() -> void:
	_indicator = Label.new()
	_indicator.text = indicator_text
	_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_indicator.position = Vector2(-56, -40)
	_indicator.size = Vector2(112, 14)
	_indicator.add_theme_font_size_override("font_size", 10)
	_indicator.add_theme_color_override("font_color", Color(0.85, 0.85, 0.92))
	_indicator.visible = false
	_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_indicator)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") or body.has_method("set_can_move"):
		_player_in_zone = true
		_indicator.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") or body.has_method("set_can_move"):
		_player_in_zone = false
		_indicator.visible = false


func _input(event: InputEvent) -> void:
	# Zone-listener class fix (subagent 2026-07-12): a cutscene/dialogue A-press must not also fire the interactable, and a tutorial-hint dismiss press must not either.
	if TutorialHint.is_any_active():
		return
	var ilm = get_tree().root.get_node_or_null("InputLockManager") if is_inside_tree() else null
	if ilm and ilm.is_locked():
		return
	if _player_in_zone and not _busy and event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_busy = true
		_toast(flavor_line)
		if SoundManager:
			SoundManager.play_ui("menu_error")
		_busy = false


func _toast(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.position = Vector2(-150, -68)
	lbl.size = Vector2(300, 40)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.90, 0.88, 0.80))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 20.0, 2.0)
	tw.tween_property(lbl, "modulate:a", 0.0, 2.0).set_delay(1.0)
	tw.chain().tween_callback(func():
		if is_instance_valid(lbl):
			lbl.queue_free())
