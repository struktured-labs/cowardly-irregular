extends Area2D
class_name Signpost

## Signpost — visual landmark with direction text.
## Shows a sign sprite and popup text when the player is nearby.

const TILE_SIZE: int = 32
## Authored world-space presentation, restored whenever a map is not running Mode 7.
const FLAT_OFFSET := Vector2(-40, -32)
const FLAT_FONT: int = 10

@export var sign_text: String = "→ Village"
@export var sign_color: Color = Color(0.55, 0.35, 0.15)  # Wood brown

var _sprite: Sprite2D
var _label: Label
var _player_nearby: bool = false
var _near_player: Node2D = null
## Signs in range of one player yield to the nearest: two side by side drew one text over the other.
const SIGN_GROUP := &"signposts"
## Mode 7 warps every world-space pixel, and a 10px sign label came out as an unreadable smudge.
var _prompt_layer: CanvasLayer


func _ready() -> void:
	add_to_group(SIGN_GROUP)
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
	shape.radius = InteractGeometry.SIGNPOST_RADIUS_MODE7 if InteractGeometry.is_mode7() else InteractGeometry.SIGNPOST_RADIUS_FLAT  # was 128 unconditional — a 4-tile label zone in flat villages (audit defect #5)
	col.shape = shape
	col.position = Vector2(0, 0)
	col.scale = Vector2(1.0, InteractGeometry.MODE7_Y_STRETCH)  # Y-stretch: matches Mode 7 billboard Y:X ratio (0.3:0.5)
	add_child(col)


func _setup_label() -> void:
	_label = Label.new()
	_label.text = sign_text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = FLAT_OFFSET
	_label.add_theme_font_size_override("font_size", FLAT_FONT)
	_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.visible = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Without this the sign reads from under the player who walked up to read it.
	Mode7Prompt.pin_above_sprites(_label)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_label)
	_layout_flat.call_deferred()  # the one-line minimum width is cached until the label has settled


## Lore signs carry whole sentences: wrap at FLAT_WIDTH, centred over the post, growing upward from it.
const FLAT_WIDTH: float = 220.0
const FLAT_BOTTOM: float = -18.0


func _layout_flat() -> void:
	if _label == null or not is_instance_valid(_label) or _prompt_layer != null:
		return
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.update_minimum_size()
	_label.size = Vector2(FLAT_WIDTH, 0.0)
	_label.position = Vector2(-FLAT_WIDTH * 0.5, FLAT_BOTTOM - _label.get_minimum_size().y)


## Directions are info, not an action, so they take the upper row and never collide with an entrance prompt.
func _process(_delta: float) -> void:
	if _label == null:
		return
	if _player_nearby:
		_label.visible = not _a_nearer_sign_has(_near_player)
	if InteractGeometry.is_mode7():
		if _prompt_layer == null:
			_prompt_layer = Mode7Prompt.lift(self, _label)
		if _player_nearby:
			Mode7Prompt.place(_label, get_viewport_rect().size, Mode7Prompt.ROW_INFO)
	elif _prompt_layer != null:
		Mode7Prompt.drop(self, _prompt_layer, _label, FLAT_OFFSET, FLAT_FONT)
		_label.visible = _player_nearby and not _a_nearer_sign_has(_near_player)
		_prompt_layer = null
		_layout_flat.call_deferred()


func _a_nearer_sign_has(player: Node2D) -> bool:
	if player == null or not is_instance_valid(player) or not is_inside_tree():
		return false
	var mine: float = global_position.distance_to(player.global_position)
	for other in get_tree().get_nodes_in_group(SIGN_GROUP):
		if other == self or not other._player_nearby or other._near_player != player:
			continue
		var theirs: float = other.global_position.distance_to(player.global_position)
		# A tie (player square between two posts) goes to one sign, never both.
		if theirs < mine - 0.5 or (absf(theirs - mine) <= 0.5 and other.get_instance_id() < get_instance_id()):
			return true
	return false


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("set_can_move") or body.is_in_group("player"):
		_player_nearby = true
		_near_player = body
		_label.visible = true
		_keep_flat_label_on_screen()


## A sign by the map's top edge grew its wrapped text up off the screen; read it below the post there instead.
const FLAT_BELOW: float = 22.0


func _keep_flat_label_on_screen() -> void:
	if _prompt_layer != null or not is_inside_tree():
		return
	_layout_flat()
	var top: float = _label.get_global_transform_with_canvas().origin.y
	if top < 0.0:
		_label.position.y = FLAT_BELOW


func _on_body_exited(body: Node2D) -> void:
	if body.has_method("set_can_move") or body.is_in_group("player"):
		_player_nearby = false
		_label.visible = false
