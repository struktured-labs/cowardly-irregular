extends Area2D
class_name MissingPackage

## MissingPackage — the mail carrier's missing package, in a neighbor's yard,
## guarded by a mailbox that has stopped accepting the concept of routes
## (world2_fine_print step 2, path A). Examining fires the rogue_mailbox
## encounter; victory (tracked via BestiarySystem defeat counts against a
## baseline stored at fight time — no BattleManager changes) lets the next
## examine recover the package → credential_obtained.

const QUEST_ID := "world2_fine_print"
const FLAG := "quest_world2_fine_print_credential_obtained"
const BASELINE_KEY := "fine_print_mailbox_baseline"
const MONSTER := "rogue_mailbox"
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
	_sprite.name = "PackageYard"
	var img := Image.create(TILE_SIZE * 2, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var box := Color(0.72, 0.55, 0.35)
	var box_dk := Color(0.58, 0.42, 0.26)
	var tape := Color(0.85, 0.80, 0.62)
	var mailbox := Color(0.25, 0.38, 0.62)
	var post := Color(0.45, 0.35, 0.25)
	# the package, slightly crumpled, half in a hedge
	for y in range(12, 28):
		for x in range(6, 24):
			img.set_pixel(x, y, box if (x + y) % 5 != 0 else box_dk)
	for x in range(6, 24):
		img.set_pixel(x, 19, tape)
	for y in range(12, 28):
		img.set_pixel(14, y, tape)
	# the guarding mailbox, a few feet away, flag up
	for y in range(8, 20):
		for x in range(40, 54):
			img.set_pixel(x, y, mailbox)
	for y in range(20, 30):
		img.set_pixel(46, y, post)
		img.set_pixel(47, y, post)
	# the flag (up — it has mail for you)
	img.set_pixel(54, 9, Color(0.85, 0.2, 0.15))
	img.set_pixel(55, 9, Color(0.85, 0.2, 0.15))
	img.set_pixel(54, 10, Color(0.85, 0.2, 0.15))
	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.centered = true
	add_child(_sprite)


func _setup_collision() -> void:
	collision_layer = 4
	collision_mask = 2
	monitoring = true
	var col := CircleShape2D.new()
	col.radius = 72.0
	var cs := CollisionShape2D.new()
	cs.shape = col
	cs.scale = Vector2(1.0, 1.67)
	add_child(cs)


func _setup_indicator() -> void:
	_indicator = Label.new()
	_indicator.text = "[A] Investigate yard"
	_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_indicator.position = Vector2(-64, -40)
	_indicator.size = Vector2(128, 14)
	_indicator.add_theme_font_size_override("font_size", 10)
	_indicator.add_theme_color_override("font_color", Color(0.85, 0.75, 0.6))
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
	var relevant: bool = qs != null and qs.get_state(QUEST_ID) == "active" \
		and not GameState.get_story_flag(FLAG)
	if not relevant:
		_toast("A tidy yard. The mailbox watches you. Mailboxes don't watch.")
		return

	var count: int = BestiarySystem.get_defeat_count(MONSTER)
	var baseline: int = int(GameState.game_constants.get(BASELINE_KEY, -1))
	if baseline >= 0 and count > baseline:
		# The mailbox is beaten — recover the package.
		GameState.game_constants.erase(BASELINE_KEY)
		GameState.set_story_flag(FLAG)
		qs.notify_flag(FLAG)
		if SoundManager:
			SoundManager.play_ui("item_obtain")
		_toast("You recover the carrier's package from the wreckage. Credential secured.")
		return

	# Fight (or re-fight): store the baseline and fire the encounter.
	GameState.game_constants[BASELINE_KEY] = count
	_toast("The mailbox unbolts itself.")
	if SoundManager:
		SoundManager.play_ui("menu_error")
	_fire_battle()


func _fire_battle() -> void:
	# Walk up to the scene that owns the battle relay (BaseVillage /
	# overworld) — same parent-walk pattern as the transition relay.
	var node = get_parent()
	while node:
		if node.has_method("_on_battle_triggered"):
			node._on_battle_triggered([MONSTER])
			return
		node = node.get_parent()


func _toast(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(-130, -52)
	lbl.size = Vector2(260, 18)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 20.0, 1.6)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.6).set_delay(0.6)
	tw.chain().tween_callback(func():
		if is_instance_valid(lbl):
			lbl.queue_free())
