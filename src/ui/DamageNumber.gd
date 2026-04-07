extends Node2D
class_name DamageNumber

## Floating damage/heal number that appears near targets

var value: int = 0
var is_heal: bool = false
var is_critical: bool = false
var is_miss: bool = false

var _label: Label = null
var _lifetime: float = 1.2
var _elapsed: float = 0.0
var _start_pos: Vector2
var _velocity: Vector2
var _flash_tween: Tween = null
var _polish_tween: Tween = null


func _ready() -> void:
	_start_pos = position
	# Random horizontal drift
	_velocity = Vector2(randf_range(-30, 30), -60)
	_create_label()


func setup(amount: int, heal: bool = false, crit: bool = false) -> void:
	value = amount
	is_heal = heal
	is_critical = crit


func setup_miss() -> void:
	is_miss = true
	value = 0


func _create_label() -> void:
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var base_size = 16
	var color: Color

	if is_miss:
		_label.text = "MISS"
		base_size = 18
		color = Color(0.65, 0.65, 0.65)
		_lifetime = 0.9
	else:
		_label.text = str(value)

		# Size based on damage amount
		if value >= 100:
			base_size = 24
		elif value >= 50:
			base_size = 20
		elif value >= 25:
			base_size = 18

		if is_critical:
			base_size += 6

		# Color: green for heal, orange for crit, white for normal
		if is_heal:
			color = Color.LIME_GREEN
		elif is_critical:
			color = Color.ORANGE
		else:
			color = Color.WHITE

	_label.add_theme_font_size_override("font_size", base_size)
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

	# Polish animations based on type
	if is_critical:
		_crit_wobble_effect()
	elif is_heal:
		_heal_bounce_effect()

	if not is_heal and not is_miss and value > 50:
		_high_damage_pulse_effect()


func _flash_effect() -> void:
	"""Flash the number for emphasis"""
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_label, "scale", Vector2(1.3, 1.3), 0.1)
	_flash_tween.tween_property(_label, "scale", Vector2(1.0, 1.0), 0.1)


func _crit_wobble_effect() -> void:
	"""Crit numbers get a dramatic rotation wobble + color cycle"""
	if _polish_tween and _polish_tween.is_valid():
		_polish_tween.kill()
	_polish_tween = create_tween()
	var wobble_deg = deg_to_rad(15.0)
	# Quick wobble: 0 -> +15 -> -15 -> +8 -> -8 -> 0 over lifetime
	_polish_tween.tween_property(_label, "rotation", wobble_deg, 0.06)
	_polish_tween.tween_property(_label, "rotation", -wobble_deg, 0.10)
	_polish_tween.tween_property(_label, "rotation", deg_to_rad(8.0), 0.08)
	_polish_tween.tween_property(_label, "rotation", deg_to_rad(-8.0), 0.08)
	_polish_tween.tween_property(_label, "rotation", 0.0, 0.10)
	# Color cycle: orange -> yellow-white -> orange for extra punch
	_polish_tween.parallel().tween_property(_label, "theme_override_colors/font_color", Color(1.0, 1.0, 0.7), 0.08)
	_polish_tween.tween_property(_label, "theme_override_colors/font_color", Color.ORANGE, 0.15)


func _heal_bounce_effect() -> void:
	"""Heal numbers bounce upward with EASE_OUT for a satisfying arc"""
	# Override velocity to move straight up faster with a bounce feel
	_velocity = Vector2(randf_range(-15.0, 15.0), -90.0)
	# Scale bounce: pop up then settle
	if _polish_tween and _polish_tween.is_valid():
		_polish_tween.kill()
	_polish_tween = create_tween()
	_polish_tween.tween_property(_label, "scale", Vector2(1.25, 1.25), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_polish_tween.tween_property(_label, "scale", Vector2(1.0, 1.0), 0.18).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _high_damage_pulse_effect() -> void:
	"""High damage (>50): scale pulse 1.0 -> 1.2 -> 1.0 over lifetime"""
	if _polish_tween and _polish_tween.is_valid():
		_polish_tween.kill()
	_polish_tween = create_tween()
	_polish_tween.tween_property(_label, "scale", Vector2(1.2, 1.2), _lifetime * 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_polish_tween.tween_property(_label, "scale", Vector2(1.0, 1.0), _lifetime * 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _exit_tree() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = null
	if _polish_tween and _polish_tween.is_valid():
		_polish_tween.kill()
	_polish_tween = null


func _process(delta: float) -> void:
	_elapsed += delta

	# Float upward with deceleration
	# Heals use lighter gravity for a floatier bounce feel
	var gravity = 45.0 if is_heal else 80.0
	_velocity.y += gravity * delta
	position += _velocity * delta

	# Fade out near end
	var fade_start = _lifetime * 0.6
	if _elapsed > fade_start:
		var fade_progress = (_elapsed - fade_start) / (_lifetime - fade_start)
		modulate.a = 1.0 - fade_progress

	# Remove when done
	if _elapsed >= _lifetime:
		queue_free()
