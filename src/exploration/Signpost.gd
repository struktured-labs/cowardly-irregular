extends Area2D
class_name Signpost

## Signpost — visual landmark with direction text.
## Shows a sign sprite and popup text when the player is nearby.

const TILE_SIZE: int = 32

@export var sign_text: String = "→ Village"
@export var sign_color: Color = Color(0.55, 0.35, 0.15)  # Wood brown

var _sprite: Sprite2D
var _label: Label
var _player_nearby: bool = false


func _ready() -> void:
	_setup_sprite()
	_setup_collision()
	_setup_label()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _setup_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)

	# Wooden post
	var post_color = sign_color
	var post_dark = post_color.darkened(0.3)
	for y in range(8, 30):
		img.set_pixel(15, y, post_color)
		img.set_pixel(16, y, post_dark)

	# Sign board
	var board_color = sign_color.lightened(0.15)
	var board_dark = sign_color.darkened(0.1)
	for y in range(6, 16):
		for x in range(6, 26):
			if y == 6 or y == 15 or x == 6 or x == 25:
				img.set_pixel(x, y, board_dark)
			else:
				img.set_pixel(x, y, board_color)

	# Arrow on sign (pointing right by default)
	var arrow_color = Color(0.2, 0.15, 0.1)
	for x in range(10, 20):
		img.set_pixel(x, 10, arrow_color)
	for i in range(3):
		img.set_pixel(19 - i, 10 - 1 - i, arrow_color)
		img.set_pixel(19 - i, 10 + 1 + i, arrow_color)

	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.centered = true
	add_child(_sprite)


func _setup_collision() -> void:
	collision_layer = 4
	collision_mask = 2
	monitoring = true

	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 32.0
	col.shape = shape
	add_child(col)


func _setup_label() -> void:
	_label = Label.new()
	_label.text = sign_text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-40, -32)
	_label.add_theme_font_size_override("font_size", 10)
	_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.visible = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("set_can_move") or body.is_in_group("player"):
		_player_nearby = true
		_label.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.has_method("set_can_move") or body.is_in_group("player"):
		_player_nearby = false
		_label.visible = false
