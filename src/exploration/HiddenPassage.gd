extends Area2D
class_name HiddenPassage

## HiddenPassage — a disguised wall section that reveals when walked into.
## Zelda-wall-crack energy: the disguise carries a subtle visual tell
## (hairline crack + slightly-off shading) so observant players spot it
## without pixel-hunting. The tile underneath is genuinely walkable —
## the sprite is pure visual disguise, discovery is touch-triggered.
##
## Mirrors TreasureChest's persistence + radar contract exactly:
## "secrets" group registration in _ready, discovered-state persisted
## via story flag "secret_<passage_id>", public _is_discovered for the
## content_radar show_secrets lane (cowir-main wires the HUD side).

signal passage_discovered(passage_id: String)

@export var passage_id: String = "secret_001"
@export var disguise: String = "cave"  # cave | mountain | brick | hedge
@export var passage_width: int = 1  # tiles
@export var passage_height: int = 1  # tiles

const TILE_SIZE: int = 32

var _is_discovered: bool = false
var _sprite: Sprite2D


func _ready() -> void:
	_is_discovered = GameState.get_story_flag("secret_" + passage_id)
	add_to_group("secrets")
	_setup_sprite()
	_setup_collision()
	body_entered.connect(_on_body_entered)


func _setup_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Disguise"
	var img = Image.create(TILE_SIZE * passage_width, TILE_SIZE * passage_height, false, Image.FORMAT_RGBA8)
	_draw_disguise(img)
	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.centered = true
	if _is_discovered:
		_sprite.modulate.a = 0.15  # ghost of the old wall marks the opening
	add_child(_sprite)


func _draw_disguise(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var base: Color
	var dark: Color
	var light: Color
	match disguise:
		"mountain":
			base = Color(0.45, 0.38, 0.32)
			dark = Color(0.32, 0.26, 0.22)
			light = Color(0.55, 0.48, 0.42)
		"brick":
			base = Color(0.55, 0.35, 0.25)
			dark = Color(0.42, 0.26, 0.16)
			light = Color(0.65, 0.45, 0.33)
		"hedge":
			base = Color(0.22, 0.42, 0.20)
			dark = Color(0.14, 0.30, 0.13)
			light = Color(0.30, 0.52, 0.26)
		_:  # cave rock
			base = Color(0.30, 0.26, 0.24)
			dark = Color(0.20, 0.17, 0.16)
			light = Color(0.40, 0.35, 0.32)

	for y in range(h):
		for x in range(w):
			var c := base
			if (x * 7 + y * 13) % 11 == 0:
				c = dark
			elif (x * 3 + y * 5) % 13 == 0:
				c = light
			# The disguise reads a shade flatter than real wall — the tell.
			img.set_pixel(x, y, c.lightened(0.03))

	# Hairline crack tell: thin dark zigzag down the middle third.
	var cx := w / 2
	for y in range(h / 4, h * 3 / 4):
		var wobble := int(2.0 * sin(y * 0.9))
		var px: int = clampi(cx + wobble, 0, w - 1)
		img.set_pixel(px, y, dark.darkened(0.25))
		if y % 3 == 0 and px + 1 < w:
			img.set_pixel(px + 1, y, dark.darkened(0.15))


func _setup_collision() -> void:
	collision_layer = 4
	collision_mask = 2  # Player
	monitoring = true
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(TILE_SIZE * passage_width, TILE_SIZE * passage_height)
	col.shape = shape
	col.scale = Vector2(1.0, 1.67)  # Mode 7 Y-stretch, matches other interactables
	add_child(col)


func _on_body_entered(body: Node2D) -> void:
	if _is_discovered:
		return
	if not (body.is_in_group("player") or body.has_method("set_can_move")):
		return
	_discover()


func _discover() -> void:
	_is_discovered = true
	GameState.set_story_flag("secret_" + passage_id)
	if SoundManager:
		SoundManager.play_ui("secret_found")
	_shimmer_away()
	passage_discovered.emit(passage_id)


func _shimmer_away() -> void:
	if not _sprite:
		return
	var tween = create_tween()
	tween.tween_property(_sprite, "modulate", Color(1.8, 1.8, 2.2, 1.0), 0.15)
	tween.tween_property(_sprite, "modulate", Color(1.0, 1.0, 1.0, 0.15), 0.6)
	# Discovery toast floats up from the wall
	var toast = Label.new()
	toast.text = "Secret passage!"
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.position = Vector2(-52, -40)
	toast.size = Vector2(104, 18)
	toast.add_theme_font_size_override("font_size", 12)
	toast.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast)
	var t2 = create_tween()
	t2.set_parallel(true)
	t2.tween_property(toast, "position:y", toast.position.y - 22, 1.4)
	t2.tween_property(toast, "modulate:a", 0.0, 1.4).set_delay(0.4)
	t2.chain().tween_callback(func():
		if is_instance_valid(toast):
			toast.queue_free()
	)
