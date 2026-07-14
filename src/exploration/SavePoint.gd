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
var _is_saving: bool = false
var _last_fasttrav_ms: int = 0  # Debounce battle_advance (RB button + RT axis 5 both fire on one squeeze)


func _ready() -> void:
	_setup_sprite()
	_setup_collision()
	_setup_indicator()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	add_to_group("interactables")
	add_to_group("save_points")


## True when the player stands in ANY crystal's zone — the save_point_only item gate (F3) reads this.
static func player_at_any(tree: SceneTree) -> bool:
	for sp in tree.get_nodes_in_group("save_points"):
		if sp is SavePoint and sp._player_in_zone:
			return true
	return false


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
	# 128 read as a 4-tile grabber — the [A] Save prompt + save fired from across the plaza (struktured cap 2026-07-11); 48 = stand beside the crystal.
	shape.radius = 48.0
	col.shape = shape
	col.position = Vector2(0, 0)
	col.scale = Vector2(1.0, 1.67)  # Y-stretch: matches Mode 7 billboard Y:X ratio (0.3:0.5)
	add_child(col)


func _setup_indicator() -> void:
	## "[A] Save" prompt floating above the crystal when the player is in
	## interaction range. Includes the button glyph so players know HOW to
	## save without having to guess (pre-fix the label just said "Save"
	## with no action hint — players unfamiliar with JRPG conventions had
	## to mash buttons to discover the interaction). Width grew to fit
	## the [A] glyph cleanly without truncation.
	_indicator = Label.new()
	_indicator.text = _indicator_text()
	_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_indicator.position = Vector2(-56, -28)
	_indicator.size = Vector2(112, 14)
	_indicator.add_theme_font_size_override("font_size", 10)
	_indicator.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	_indicator.visible = false
	_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_indicator)


## "[R] Warp" appears once another crystal is attuned somewhere else.
func _indicator_text() -> String:
	var others: int = 0
	for map_id in GameState.activated_crystals:
		if map_id != _current_map_id():
			others += 1
	return "[A] Save · [R] Warp" if others > 0 else "[A] Save"


func _current_map_id() -> String:
	var game_loop = get_tree().root.get_node_or_null("GameLoop")
	if game_loop and "_current_map_id" in game_loop:
		return str(game_loop._current_map_id)
	return ""


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("set_can_move") or body.is_in_group("player"):
		_player_in_zone = true
		_indicator.visible = true
		SoundManager.play_ui("save_crystal_near")
		# First-time hint explaining the save-crystal interaction. Idempotent
		# via TutorialHint._shown_hints — only the first crystal-approach
		# per session surfaces the hint.
		TutorialHints.show(self, "save_crystal")


func _on_body_exited(body: Node2D) -> void:
	if body.has_method("set_can_move") or body.is_in_group("player"):
		_player_in_zone = false
		_indicator.visible = false


func _input(event: InputEvent) -> void:
	# Cutscene/dialogue lock: this handler grabs ui_accept directly, so without the gate the A-press that advances dialogue ALSO hit the crystal ("Cannot save mid-cutscene" spam — struktured 2026-07-11, second report).
	var ilm = get_tree().root.get_node_or_null("InputLockManager") if is_inside_tree() else null
	if ilm and ilm.is_locked():
		return
	# The "save_crystal" tutorial hint fires on _on_body_entered — without this gate the dismiss A-press ALSO fires a save.
	if TutorialHint.is_any_active():
		return
	if _player_in_zone and not _is_saving and event.is_action_pressed("ui_accept"):
		_is_saving = true
		SoundManager.play_ui("save_crystal_activate")
		# Attune this crystal for fast travel the first time it's used.
		GameState.activate_crystal(_current_map_id())
		_indicator.text = _indicator_text()
		save_requested.emit()
		get_viewport().set_input_as_handled()
		_show_save_confirmation()
	elif _player_in_zone and not _is_saving and event.is_action_pressed("battle_advance"):
		# Debounce: RB button + RT axis 5 both fire on one squeeze; a drifting trigger would open FastTravelMenu twice on top of itself.
		var now_ms := Time.get_ticks_msec()
		if now_ms - _last_fasttrav_ms < 200:
			return
		_last_fasttrav_ms = now_ms
		if _open_fast_travel():
			get_viewport().set_input_as_handled()


## R at an attuned crystal opens the warp menu. battle_advance is battle-only
## elsewhere, so the binding is free in exploration context.
func _open_fast_travel() -> bool:
	var others: int = 0
	for map_id in GameState.activated_crystals:
		if map_id != _current_map_id():
			others += 1
	if others == 0:
		return false

	var player_node = get_tree().get_first_node_in_group("player")
	if player_node and player_node.has_method("set_can_move"):
		player_node.set_can_move(false)

	var menu = FastTravelMenu.new()
	menu.current_map_id = _current_map_id()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	var layer = CanvasLayer.new()
	layer.layer = 50
	get_tree().root.add_child(layer)
	layer.add_child(menu)
	menu.size = get_viewport().get_visible_rect().size

	menu.teleport_requested.connect(func(map_id: String, spawn: String):
		layer.queue_free()
		var game_loop = get_tree().root.get_node_or_null("GameLoop")
		if game_loop and game_loop.has_method("_on_area_transition"):
			game_loop._on_area_transition(map_id, spawn)
	)
	menu.closed.connect(func():
		if is_instance_valid(layer):
			layer.queue_free()
		if is_instance_valid(player_node) and player_node.has_method("set_can_move"):
			player_node.set_can_move(true)
	)
	return true


func _show_save_confirmation() -> void:
	"""Show 'Game Saved!' confirmation with flash and fade."""
	# Flash the crystal bright white
	if _sprite:
		var flash_tween = create_tween()
		flash_tween.tween_property(_sprite, "modulate", Color(2.0, 2.0, 2.5, 1.0), 0.1)
		flash_tween.tween_property(_sprite, "modulate", Color(0.7, 0.7, 1.0, 1.0), 0.4)

	# Create confirmation label
	var confirm = Label.new()
	confirm.text = "Game Saved!"
	confirm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm.position = Vector2(-40, -48)
	confirm.size = Vector2(80, 20)
	confirm.add_theme_font_size_override("font_size", 14)
	confirm.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	confirm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(confirm)

	# Float up and fade out
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(confirm, "position:y", confirm.position.y - 20, 1.5)
	tween.tween_property(confirm, "modulate:a", 0.0, 1.5).set_delay(0.5)
	tween.chain().tween_callback(func():
		if is_instance_valid(confirm):
			confirm.queue_free()
		_is_saving = false
	)
