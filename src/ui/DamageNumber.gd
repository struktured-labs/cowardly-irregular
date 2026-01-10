extends Node2D
class_name DamageNumber

## Floating damage/heal number that appears near targets

var value: int = 0
var is_heal: bool = false
var is_critical: bool = false

var _label: Label = null
var _lifetime: float = 1.2
var _elapsed: float = 0.0
var _start_pos: Vector2
var _velocity: Vector2


func _ready() -> void:
	_start_pos = position
	# Random horizontal drift
	_velocity = Vector2(randf_range(-30, 30), -60)
	_create_label()


func setup(amount: int, heal: bool = false, crit: bool = false) -> void:
	value = amount
	is_heal = heal
	is_critical = crit


func _create_label() -> void:
	_label = Label.new()
	_label.text = str(value)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Size based on damage amount
	var base_size = 16
	if value >= 100:
		base_size = 24
	elif value >= 50:
		base_size = 20
	elif value >= 25:
		base_size = 18

	if is_critical:
		base_size += 6

	_label.add_theme_font_size_override("font_size", base_size)

	# Color: green for heal, red/orange for damage
	var color: Color
	if is_heal:
		color = Color.LIME_GREEN
	elif is_critical:
		color = Color.ORANGE
	else:
		color = Color.WHITE

	_label.add_theme_color_override("font_color", color)

	# Outline for visibility
	_label.add_theme_constant_override("outline_size", 2)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)

	# Center the label
	_label.position = Vector2(-50, -10)
	_label.custom_minimum_size = Vector2(100, 20)

	add_child(_label)

	# Flash effect for big damage
	if value >= 50 or is_critical:
		_flash_effect()


func _flash_effect() -> void:
	"""Flash the number for emphasis"""
	var tween = create_tween()
	tween.tween_property(_label, "scale", Vector2(1.3, 1.3), 0.1)
	tween.tween_property(_label, "scale", Vector2(1.0, 1.0), 0.1)


func _process(delta: float) -> void:
	_elapsed += delta

	# Float upward with deceleration
	_velocity.y += 80 * delta  # Gravity
	position += _velocity * delta

	# Fade out near end
	var fade_start = _lifetime * 0.6
	if _elapsed > fade_start:
		var fade_progress = (_elapsed - fade_start) / (_lifetime - fade_start)
		modulate.a = 1.0 - fade_progress

	# Remove when done
	if _elapsed >= _lifetime:
		queue_free()
