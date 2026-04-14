extends Area2D
class_name WanderingNPC

## WanderingNPC — ambient NPC that walks a short patrol path on the overworld.
## Shows one line of dialogue when the player is nearby.
## Makes the world feel lived-in between towns.

const TILE_SIZE: int = 32
const WANDER_SPEED: float = 40.0
const PAUSE_MIN: float = 2.0
const PAUSE_MAX: float = 5.0
const ANIM_FPS: float = 4.0

@export var npc_name: String = "Traveler"
@export var dialogue: String = "The road stretches on..."
@export var sprite_color: Color = Color(0.6, 0.5, 0.4)

## Story-aware dialogue hints — checked in order, last matching flag wins.
## Format: [{"flag": "story_flag", "text": "dialogue"}, ...]
## If empty, falls back to static dialogue.
var dialogue_hints: Array = []

var _sprite: Sprite2D
var _label: Label
var _player_nearby: bool = false
var _npc_dialogue: Node = null  # NPCDialogue instance for proper dialogue boxes
var _in_conversation: bool = false

## NPC theme/portrait for dialogue boxes (defaults to "mysterious")
@export var dialogue_theme: String = "mysterious"
@export var dialogue_portrait: String = "mysterious"

# Patrol state
var _patrol_points: Array[Vector2] = []
var _current_target: int = 0
var _paused: bool = false
var _pause_timer: float = 0.0
var _anim_timer: float = 0.0
var _anim_frame: int = 0
var _facing_right: bool = true


func _ready() -> void:
	_setup_sprite()
	_setup_collision()
	_setup_label()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func set_patrol(points: Array[Vector2]) -> void:
	_patrol_points = points
	if _patrol_points.size() > 0:
		global_position = _patrol_points[0]


func _process(delta: float) -> void:
	if _patrol_points.size() < 2:
		return

	if _paused:
		_pause_timer -= delta
		if _pause_timer <= 0:
			_paused = false
			_current_target = (_current_target + 1) % _patrol_points.size()
		return

	var target = _patrol_points[_current_target]
	var dir = (target - global_position)
	var dist = dir.length()

	if dist < 4.0:
		# Reached target — pause
		_paused = true
		_pause_timer = randf_range(PAUSE_MIN, PAUSE_MAX)
		return

	dir = dir.normalized()
	global_position += dir * WANDER_SPEED * delta
	_facing_right = dir.x > 0
	_sprite.flip_h = not _facing_right

	# Walk animation
	_anim_timer += delta * ANIM_FPS
	if _anim_timer >= 1.0:
		_anim_timer -= 1.0
		_anim_frame = (_anim_frame + 1) % 2
		_sprite.modulate.a = 0.95 if _anim_frame == 0 else 1.0  # Subtle bob


func _setup_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)

	var body = sprite_color
	var dark = sprite_color.darkened(0.3)
	var skin = Color(0.85, 0.7, 0.55)
	var hair = sprite_color.darkened(0.4)

	# Simple chibi figure
	# Head
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if dx * dx + dy * dy <= 5:
				img.set_pixel(16 + dx, 8 + dy, skin)
	# Hair
	for dx in range(-2, 3):
		img.set_pixel(16 + dx, 6, hair)
		img.set_pixel(16 + dx, 7, hair)
	# Body
	for y in range(12, 22):
		for x in range(13, 20):
			img.set_pixel(x, y, body if (x + y) % 3 != 0 else dark)
	# Legs
	for y in range(22, 28):
		img.set_pixel(14, y, dark)
		img.set_pixel(15, y, dark)
		img.set_pixel(17, y, dark)
		img.set_pixel(18, y, dark)
	# Feet
	img.set_pixel(13, 28, dark)
	img.set_pixel(14, 28, dark)
	img.set_pixel(18, 28, dark)
	img.set_pixel(19, 28, dark)

	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.centered = true
	_sprite.scale = Vector2(3.0, 3.0)  # Scale up for Mode 7 visibility
	add_child(_sprite)


func _setup_collision() -> void:
	collision_layer = 4
	collision_mask = 2
	monitoring = true

	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(64, 160)  # Wide + very tall — compensates for Mode 7 vertical compression
	col.shape = shape
	col.position = Vector2(0, -48)  # Shifted north — Mode 7 log-warp makes objects appear closer than they are
	add_child(col)


func _setup_label() -> void:
	_label = Label.new()
	_label.text = "%s: \"%s\"" % [npc_name, dialogue]
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-100, -60)
	_label.size = Vector2(200, 40)
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.visible = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func _get_current_dialogue() -> String:
	if dialogue_hints.is_empty():
		return dialogue
	var best = dialogue
	for hint in dialogue_hints:
		var flag = hint.get("flag", "")
		if flag == "" or GameState.get_story_flag(flag):
			best = hint.get("text", dialogue)
	return best


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("set_can_move") or body.is_in_group("player"):
		_player_nearby = true
		_label.text = "[A] %s" % npc_name
		_label.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.has_method("set_can_move") or body.is_in_group("player"):
		_player_nearby = false
		_label.visible = false


func _input(event: InputEvent) -> void:
	if not _player_nearby or _in_conversation:
		return

	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		# Defer conversation start to avoid await inside _input
		call_deferred("_start_conversation")


func _start_conversation() -> void:
	"""Open a proper dialogue box for this NPC."""
	_in_conversation = true
	_label.visible = false

	# Freeze player during conversation
	var player = _get_player()
	if player and player.has_method("set_can_move"):
		player.set_can_move(false)

	# Create NPCDialogue if needed
	if not _npc_dialogue or not is_instance_valid(_npc_dialogue):
		var NPCDialogueClass = load("res://src/cutscene/NPCDialogue.gd")
		_npc_dialogue = NPCDialogueClass.new()
		add_child(_npc_dialogue)

	var text = _get_current_dialogue()
	await _npc_dialogue.say(npc_name, text, dialogue_theme, dialogue_portrait)

	# Unfreeze player
	if player and player.has_method("set_can_move"):
		player.set_can_move(true)

	_in_conversation = false
	if _player_nearby:
		_label.text = "[A] %s" % npc_name
		_label.visible = true


func _get_player() -> Node:
	"""Find the player node."""
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]
	# Try MapSystem
	if Engine.has_singleton("MapSystem"):
		return Engine.get_singleton("MapSystem").get_player()
	return null
