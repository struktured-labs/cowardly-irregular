extends Area2D
class_name SwordInscription

## SwordInscription — the Returned Sword on its rack by Ironclad Arms
## (world1_untested_edge step 2, emitter path A). A Mage in the party can
## cast light on the blade to read the inscription that shouldn't be there.
## (Path B — the Guild scholar's translation — lives in QuestSystem's
## dialogue-emitter table; either sets the same flag.)

const QUEST_ID := "world1_untested_edge"
const FLAG := "quest_world1_untested_edge_inscription_read"
const TILE_SIZE: int = 32

var _sprite: Sprite2D
var _indicator: Label
var _player_in_zone: bool = false
var _busy: bool = false


func _ready() -> void:
	add_to_group("interactables")
	_setup_sprite()
	_setup_collision()
	_setup_indicator()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _setup_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "SwordRack"
	var img := Image.create(TILE_SIZE, TILE_SIZE * 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var wood := Color(0.42, 0.28, 0.15)
	var steel := Color(0.72, 0.74, 0.80)
	var steel_dk := Color(0.52, 0.54, 0.62)
	var hilt := Color(0.55, 0.42, 0.20)
	# rack posts
	for y in range(8, 60):
		img.set_pixel(6, y, wood)
		img.set_pixel(7, y, wood)
		img.set_pixel(24, y, wood)
		img.set_pixel(25, y, wood)
	# crossbars
	for x in range(6, 26):
		img.set_pixel(x, 20, wood)
		img.set_pixel(x, 44, wood)
	# the sword, resting diagonally: blade
	for i in range(30):
		var x := 9 + i / 2
		var y := 52 - i
		if x < TILE_SIZE and y >= 0:
			img.set_pixel(x, y, steel if i % 3 != 0 else steel_dk)
			img.set_pixel(x + 1, y, steel_dk)
	# hilt + guard
	for x in range(22, 28):
		if x < TILE_SIZE:
			img.set_pixel(x, 22, hilt)
	img.set_pixel(24, 20, hilt)
	img.set_pixel(24, 21, hilt)
	# faint inscription glint on the flat (the wrongness, barely visible)
	img.set_pixel(14, 42, Color(0.9, 0.95, 1.0, 0.8))
	img.set_pixel(16, 38, Color(0.9, 0.95, 1.0, 0.6))
	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.centered = true
	add_child(_sprite)


func _setup_collision() -> void:
	collision_layer = 4
	collision_mask = 2
	monitoring = true
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 72.0
	col.shape = shape
	col.scale = Vector2(1.0, 1.67)
	add_child(col)


func _setup_indicator() -> void:
	_indicator = Label.new()
	_indicator.text = "[A] Examine sword"
	_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_indicator.position = Vector2(-56, -44)
	_indicator.size = Vector2(112, 14)
	_indicator.add_theme_font_size_override("font_size", 10)
	_indicator.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
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
	# Zone-listener class fix (subagent 2026-07-12): a cutscene/dialogue A-press must not also fire the interactable, and a tutorial-hint dismiss press must not either.
	if TutorialHint.is_any_active():
		return
	var ilm = get_tree().root.get_node_or_null("InputLockManager") if is_inside_tree() else null
	if ilm and ilm.is_locked():
		return
	if _player_in_zone and not _busy and event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_busy = true
		_examine()
		_busy = false


func _examine() -> void:
	var qs = get_node_or_null("/root/QuestSystem")
	if qs == null or qs.get_state(QUEST_ID) != "active" or GameState.get_story_flag(FLAG):
		_toast("A sword rests on the rack. Sword-shaped, and somehow wrong.")
		return
	if _party_has_mage():
		# The Mage raises a light — the inscription answers it.
		if SoundManager:
			SoundManager.play_ui("magic_surge")
		_glint()
		GameState.set_story_flag(FLAG)
		qs.notify_flag(FLAG)
		_toast("The Mage's light finds letters under the steel. They were waiting.")
	else:
		_toast("Faint marks under the surface — too dim to read. Magelight might reach them. Or a scholar.")


func _party_has_mage() -> bool:
	var game_loop = get_node_or_null("/root/GameLoop")
	if game_loop == null or not ("party" in game_loop):
		return false
	for member in game_loop.party:
		var jid := ""
		if member.job is Dictionary:
			jid = member.job.get("id", "")
		elif member.job is String:
			jid = member.job
		if jid == "mage":
			return true
	return false


func _glint() -> void:
	if _sprite == null:
		return
	var tw := create_tween()
	tw.tween_property(_sprite, "modulate", Color(1.6, 1.7, 2.0, 1.0), 0.25)
	tw.tween_property(_sprite, "modulate", Color.WHITE, 0.6)


func _toast(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(-130, -56)
	lbl.size = Vector2(260, 18)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 20.0, 1.6)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.6).set_delay(0.6)
	tw.chain().tween_callback(func():
		if is_instance_valid(lbl):
			lbl.queue_free())
