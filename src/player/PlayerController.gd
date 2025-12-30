extends CharacterBody2D
class_name PlayerController

## PlayerController - Controls player movement and interactions in exploration mode

signal moved(steps: int)
signal interaction_triggered(target: Node2D)
signal menu_opened()

## Movement
@export var move_speed: float = 100.0  # Slower speed for Game Boy feel
@export var grid_based: bool = false  # False = free 8-direction (FF Adventure, Link's Awakening style)
@export var grid_size: int = 16  # For encounter step tracking

## State
var can_move: bool = true
var is_in_menu: bool = false
var step_count: int = 0

## Input buffer for grid movement
var input_direction: Vector2 = Vector2.ZERO
var is_moving: bool = false
var target_position: Vector2 = Vector2.ZERO

## Interaction
var nearby_interactables: Array[Node2D] = []

## Animation
@onready var sprite: Sprite2D = $Sprite2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer if has_node("AnimationPlayer") else null
@onready var interaction_area: Area2D = $InteractionArea if has_node("InteractionArea") else null


func _ready() -> void:
	# Register with MapSystem
	MapSystem.set_player(self)

	# Connect interaction area if it exists
	if interaction_area:
		interaction_area.area_entered.connect(_on_interaction_area_entered)
		interaction_area.area_exited.connect(_on_interaction_area_exited)

	# Create sprite if it doesn't exist
	if not has_node("Sprite2D"):
		_create_default_sprite()

	# Create interaction area if it doesn't exist
	if not interaction_area:
		_create_interaction_area()

	target_position = position


func _physics_process(delta: float) -> void:
	if not can_move or is_in_menu:
		return

	if grid_based:
		_handle_grid_movement(delta)
	else:
		_handle_free_movement(delta)


func _unhandled_input(event: InputEvent) -> void:
	# Interaction (talk, examine, enter)
	if event.is_action_pressed("ui_accept"):
		_try_interact()
		get_viewport().set_input_as_handled()

	# Menu
	if event.is_action_pressed("ui_cancel"):
		_open_menu()
		get_viewport().set_input_as_handled()


## Free movement (smooth 8-direction)
func _handle_free_movement(delta: float) -> void:
	"""Handle smooth free movement"""
	var direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	if direction != Vector2.ZERO:
		velocity = direction * move_speed

		# Update sprite direction
		_update_sprite_direction(direction)

		# Track steps for encounters
		var old_pos = position
		move_and_slide()
		var moved_distance = position.distance_to(old_pos)

		if moved_distance > grid_size:
			step_count += 1
			moved.emit(step_count)
	else:
		velocity = Vector2.ZERO
		move_and_slide()


## Grid-based movement (classic JRPG style)
func _handle_grid_movement(delta: float) -> void:
	"""Handle grid-based movement (one tile at a time)"""
	if is_moving:
		# Move toward target position
		var distance = position.distance_to(target_position)
		if distance < 2.0:
			position = target_position
			is_moving = false
			step_count += 1
			moved.emit(step_count)
		else:
			var direction = (target_position - position).normalized()
			velocity = direction * move_speed
			move_and_slide()
	else:
		# Get input for next move
		var direction = Vector2.ZERO

		if Input.is_action_pressed("ui_right"):
			direction = Vector2.RIGHT
		elif Input.is_action_pressed("ui_left"):
			direction = Vector2.LEFT
		elif Input.is_action_pressed("ui_down"):
			direction = Vector2.DOWN
		elif Input.is_action_pressed("ui_up"):
			direction = Vector2.UP

		if direction != Vector2.ZERO:
			# Start moving to next grid position
			target_position = position + direction * grid_size
			is_moving = true
			_update_sprite_direction(direction)


func _update_sprite_direction(direction: Vector2) -> void:
	"""Update sprite based on movement direction"""
	if not sprite:
		return

	# Simple 4-direction facing
	if abs(direction.x) > abs(direction.y):
		# Horizontal movement
		sprite.flip_h = direction.x < 0
	# Could add up/down animations here


## Interaction
func _try_interact() -> void:
	"""Try to interact with nearby objects/NPCs"""
	if nearby_interactables.is_empty():
		return

	# Interact with closest interactable
	var closest = _get_closest_interactable()
	if closest:
		interaction_triggered.emit(closest)

		# Call interact method if it exists
		if closest.has_method("interact"):
			closest.interact(self)


func _get_closest_interactable() -> Node2D:
	"""Get the closest interactable object"""
	if nearby_interactables.is_empty():
		return null

	var closest = nearby_interactables[0]
	var closest_dist = position.distance_to(closest.global_position)

	for interactable in nearby_interactables:
		var dist = position.distance_to(interactable.global_position)
		if dist < closest_dist:
			closest = interactable
			closest_dist = dist

	return closest


func _on_interaction_area_entered(area: Area2D) -> void:
	"""Handle entering an interactable area"""
	if area.owner and area.owner.has_method("interact"):
		nearby_interactables.append(area.owner)


func _on_interaction_area_exited(area: Area2D) -> void:
	"""Handle exiting an interactable area"""
	if area.owner in nearby_interactables:
		nearby_interactables.erase(area.owner)


## Menu
func _open_menu() -> void:
	"""Open the game menu"""
	menu_opened.emit()
	# TODO: Implement menu system
	print("Menu opened (not implemented yet)")


## Movement control
func set_can_move(enabled: bool) -> void:
	"""Enable/disable player movement"""
	can_move = enabled
	if not enabled:
		velocity = Vector2.ZERO


func teleport(new_position: Vector2) -> void:
	"""Teleport player to a position"""
	position = new_position
	target_position = new_position
	is_moving = false


## Setup helpers
func _create_default_sprite() -> void:
	"""Create a simple player sprite (16x16 Game Boy style)"""
	sprite = Sprite2D.new()
	sprite.name = "Sprite2D"
	add_child(sprite)

	# Create 16x16 sprite (Game Boy size)
	var img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	# Draw blue circle for player (smaller)
	for x in range(16):
		for y in range(16):
			var dist_from_center = sqrt(pow(x - 8, 2) + pow(y - 8, 2))
			if dist_from_center < 6:
				var c = Color.DODGER_BLUE
				# Shading
				if y < 6:
					c = c.lightened(0.3)
				elif y > 10:
					c = c.darkened(0.3)
				img.set_pixel(x, y, c)

	var texture = ImageTexture.create_from_image(img)
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # Pixel-perfect


func _create_interaction_area() -> void:
	"""Create interaction detection area"""
	interaction_area = Area2D.new()
	interaction_area.name = "InteractionArea"
	add_child(interaction_area)

	var collision = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 32.0  # Interaction range
	collision.shape = circle
	interaction_area.add_child(collision)

	interaction_area.area_entered.connect(_on_interaction_area_entered)
	interaction_area.area_exited.connect(_on_interaction_area_exited)


## Utility
func get_facing_direction() -> Vector2:
	"""Get the direction the player is facing"""
	if sprite and sprite.flip_h:
		return Vector2.LEFT
	return Vector2.RIGHT


func get_step_count() -> int:
	"""Get total steps taken"""
	return step_count


func reset_step_count() -> void:
	"""Reset step counter"""
	step_count = 0
