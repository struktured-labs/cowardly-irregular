extends Area2D
class_name WildflowerPatch

## WildflowerPatch — Gerald's noncompliant wildflower (world2_acceptable_variance
## step 2). One flower, growing exactly where the field used to be. Any
## magic-capable party member (mage / cleric / bard) can read the persistence;
## a mundane party gets the shape of the mystery without the flag.

const QUEST_ID := "world2_acceptable_variance"
const FLAG := "quest_world2_acceptable_variance_flower_examined"
const TILE_SIZE: int = 32
const MAGIC_JOBS := ["mage", "cleric", "bard"]

var _sprite: Sprite2D
var _indicator: Label
var _player_in_zone: bool = false
var _busy: bool = false
var _sway_t: float = 0.0


func _ready() -> void:
	add_to_group("interactables")
	_setup_sprite()
	_setup_collision()
	_setup_indicator()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	if _sprite:
		_sway_t += delta * 2.0
		_sprite.rotation = sin(_sway_t) * 0.06


func _setup_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Wildflower"
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var stem := Color(0.28, 0.52, 0.24)
	var petal := Color(0.95, 0.72, 0.22)
	var petal_dk := Color(0.85, 0.58, 0.14)
	var core := Color(0.45, 0.28, 0.12)
	# stem with one leaf
	for y in range(14, 30):
		img.set_pixel(15, y, stem)
		img.set_pixel(16, y, stem.darkened(0.15))
	img.set_pixel(13, 20, stem); img.set_pixel(14, 19, stem)
	# petals — a ring around the core
	for a in range(8):
		var px := 15 + int(round(5.0 * cos(a * PI / 4.0)))
		var py := 10 + int(round(5.0 * sin(a * PI / 4.0)))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var x := px + dx
				var y := py + dy
				if x >= 0 and x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
					img.set_pixel(x, y, petal if (dx + dy) % 2 == 0 else petal_dk)
	# core
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if abs(dx) + abs(dy) <= 2:
				img.set_pixel(15 + dx, 10 + dy, core)
	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.centered = true
	_sprite.offset = Vector2(0, -6)
	add_child(_sprite)


func _setup_collision() -> void:
	collision_layer = 4
	collision_mask = 2
	monitoring = true
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 56.0
	col.shape = shape
	col.scale = Vector2(1.0, 1.67)
	add_child(col)


func _setup_indicator() -> void:
	_indicator = Label.new()
	_indicator.text = "[A] Examine flower"
	_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_indicator.position = Vector2(-56, -40)
	_indicator.size = Vector2(112, 14)
	_indicator.add_theme_font_size_override("font_size", 10)
	_indicator.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
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
	if _player_in_zone and not _busy and event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_busy = true
		_examine()
		_busy = false


func _examine() -> void:
	var qs = get_node_or_null("/root/QuestSystem")
	if qs == null or qs.get_state(QUEST_ID) != "active" or GameState.get_story_flag(FLAG):
		_toast("A single wildflower, dead-center in a regulation lawn. Thriving.")
		return
	if _party_has_magic():
		if SoundManager:
			SoundManager.play_ui("magic_surge")
		GameState.set_story_flag(FLAG)
		qs.notify_flag(FLAG)
		_toast("Local persistence — established in a way normal flowers aren't. Older than the lawn.")
	else:
		_toast("It looks... rooted. Deeply. Someone attuned to magic might read more.")


func _party_has_magic() -> bool:
	var game_loop = get_node_or_null("/root/GameLoop")
	if game_loop == null or not ("party" in game_loop):
		return false
	for member in game_loop.party:
		var jid := ""
		if member.job is Dictionary:
			jid = member.job.get("id", "")
		elif member.job is String:
			jid = member.job
		if jid in MAGIC_JOBS:
			return true
	return false


func _toast(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(-130, -52)
	lbl.size = Vector2(260, 18)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 20.0, 1.6)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.6).set_delay(0.6)
	tw.chain().tween_callback(func():
		if is_instance_valid(lbl):
			lbl.queue_free())
