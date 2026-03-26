extends Area2D
class_name SavePoint

## SavePoint — glowing crystal that triggers save when interacted with.
## Place at designated spots in villages and dungeons.

signal save_requested()

const TILE_SIZE: int = 32

var _sprite: Sprite2D
var _glow_timer: float = 0.0
var _indicator: Label
var _player_in_zone: bool = false


func _ready() -> void:
	_setup_sprite()
	_setup_collision()
	_setup_indicator()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	add_to_group("interactables")


func _process(delta: float) -> void:
	# Pulsing glow
	_glow_timer += delta * 2.0
	var pulse = 0.7 + 0.3 * sin(_glow_timer)
	if _sprite:
		_sprite.modulate = Color(pulse, pulse, 1.0, 1.0)


func _setup_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"

	# Procedural crystal sprite (32x32)
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var cx = TILE_SIZE / 2
	# Crystal body (diamond shape)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var dx = abs(x - cx)
			var dy = abs(y - cx)
			# Diamond shape
			if dx + dy < 12:
				var t = float(dx + dy) / 12.0
				var c = Color(0.4 + 0.3 * (1.0 - t), 0.6 + 0.2 * (1.0 - t), 1.0, 0.9 - 0.2 * t)
				img.set_pixel(x, y, c)
			# Inner glow
			elif dx + dy < 14:
				img.set_pixel(x, y, Color(0.3, 0.5, 0.9, 0.3))

	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.centered = true
	add_child(_sprite)


func _setup_collision() -> void:
	collision_layer = 4
	collision_mask = 2  # Detect player (layer 2)
	monitoring = true

	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 24.0  # Generous interaction radius
	col.shape = shape
	add_child(col)


func _setup_indicator() -> void:
	_indicator = Label.new()
	_indicator.text = "Save"
	_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_indicator.position = Vector2(-16, -28)
	_indicator.add_theme_font_size_override("font_size", 10)
	_indicator.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	_indicator.visible = false
	_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_indicator)


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("set_can_move") or body.is_in_group("player"):
		_player_in_zone = true
		_indicator.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.has_method("set_can_move") or body.is_in_group("player"):
		_player_in_zone = false
		_indicator.visible = false


func _input(event: InputEvent) -> void:
	if _player_in_zone and event.is_action_pressed("ui_accept"):
		save_requested.emit()
		get_viewport().set_input_as_handled()
