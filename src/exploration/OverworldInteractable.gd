extends Area2D
class_name OverworldInteractable

## OverworldInteractable - Base class for interactable objects in exploration
## Shops, Inn, treasure chests, signs, etc.

signal interaction_started()
signal interaction_ended()

## Interactable properties
@export var interactable_name: String = "Object"
@export var interactable_type: String = "generic"  # inn, weapon_shop, armor_shop, item_shop, treasure, sign, bar
@export var require_facing: bool = true  # Must player face this to interact?

## Visual
var sprite: Sprite2D
var name_label: Label

## State
var _player_nearby: bool = false
var _is_interacting: bool = false

const TILE_SIZE: int = 32


func _ready() -> void:
	_generate_sprite()
	_setup_collision()
	_setup_name_label()

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _generate_sprite() -> void:
	sprite = Sprite2D.new()
	sprite.name = "Sprite"

	var image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	_draw_interactable(image)

	var texture = ImageTexture.create_from_image(image)
	sprite.texture = texture
	sprite.centered = true
	add_child(sprite)


func _draw_interactable(image: Image) -> void:
	# Override in subclasses for custom visuals
	image.fill(Color(0.5, 0.5, 0.5))


func _setup_collision() -> void:
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(TILE_SIZE, TILE_SIZE)
	collision.shape = shape
	add_child(collision)

	# Layer 4 = interactables
	collision_layer = 4
	collision_mask = 2  # Player layer
	monitoring = true
	monitorable = true


func _setup_name_label() -> void:
	name_label = Label.new()
	name_label.text = interactable_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(-40, -24)
	name_label.size = Vector2(80, 20)
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	name_label.visible = false
	add_child(name_label)


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("set_can_move"):
		_player_nearby = true
		name_label.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.has_method("set_can_move"):
		_player_nearby = false
		name_label.visible = false
		if _is_interacting:
			_end_interaction()


## Called by OverworldController when player presses interact
func interact(player: Node2D) -> void:
	if _is_interacting:
		_continue_interaction()
	else:
		_start_interaction(player)


func _start_interaction(player: Node2D) -> void:
	_is_interacting = true
	interaction_started.emit()


func _continue_interaction() -> void:
	# Override in subclasses
	pass


func _end_interaction() -> void:
	_is_interacting = false
	interaction_ended.emit()
