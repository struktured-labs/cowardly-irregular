extends Area2D
class_name CivicBackDoor

## CivicBackDoor — the Community Center's service alley (world2_fine_print's
## Rogue gap). A Rogue lead can slip in and take a blank form off the stack:
## credential + form in one move, flagging rogue_gap_used for the turn-in
## variant. Locked to everyone else — the lock is load-bearing civic theater.

const QUEST_ID := "world2_fine_print"
const CRED_FLAG := "quest_world2_fine_print_credential_obtained"
const FORM_FLAG := "quest_world2_fine_print_form_obtained"
const GAP_FLAG := "quest_world2_fine_print_rogue_gap_used"
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
	_sprite.name = "ServiceDoor"
	var img := Image.create(TILE_SIZE, TILE_SIZE * 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var wall := Color(0.55, 0.52, 0.48)
	var door := Color(0.35, 0.36, 0.40)
	var door_dk := Color(0.28, 0.29, 0.33)
	var sign_c := Color(0.85, 0.82, 0.70)
	# alley wall stub + a gray service door, slightly ajar
	for y in range(4, 60):
		for x in range(2, 30):
			img.set_pixel(x, y, wall if (x + y) % 8 != 0 else wall.darkened(0.08))
	for y in range(12, 56):
		for x in range(8, 24):
			img.set_pixel(x, y, door if x < 22 else door_dk)
	# handle + STAFF ONLY placard
	img.set_pixel(20, 34, Color(0.75, 0.72, 0.6))
	img.set_pixel(21, 34, Color(0.75, 0.72, 0.6))
	for y in range(16, 22):
		for x in range(10, 22):
			img.set_pixel(x, y, sign_c)
	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.centered = true
	add_child(_sprite)


func _setup_collision() -> void:
	collision_layer = 4
	collision_mask = 2
	monitoring = true
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 56.0
	cs.shape = shape
	cs.scale = Vector2(1.0, 1.67)
	add_child(cs)


func _setup_indicator() -> void:
	_indicator = Label.new()
	_indicator.text = "[A] Service door"
	_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_indicator.position = Vector2(-52, -48)
	_indicator.size = Vector2(104, 14)
	_indicator.add_theme_font_size_override("font_size", 10)
	_indicator.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
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
		_try_door()
		_busy = false


func _try_door() -> void:
	var qs = get_node_or_null("/root/QuestSystem")
	var relevant: bool = qs != null and qs.get_state(QUEST_ID) == "active" \
		and not GameState.get_story_flag(FORM_FLAG)
	if not relevant:
		_toast("STAFF ONLY. The lock looks decorative. The sign does the real work.")
		return
	if _lead_job() != "rogue":
		_toast("Locked. A Rogue would notice the latch doesn't actually reach the strike plate.")
		return
	# The Rogue gap: credential AND form in one move, no line, no stamp.
	GameState.set_story_flag(GAP_FLAG)
	GameState.set_story_flag(CRED_FLAG)
	qs.notify_flag(CRED_FLAG)
	GameState.set_story_flag(FORM_FLAG)
	qs.notify_flag(FORM_FLAG)
	if SoundManager:
		SoundManager.play_ui("secret_found")
	_toast("The latch never reached the strike plate. One blank form, off the top of the stack. Nobody counts blanks.")


func _lead_job() -> String:
	var game_loop = get_node_or_null("/root/GameLoop")
	if game_loop == null or not ("party" in game_loop) or game_loop.party.is_empty():
		return ""
	var idx: int = 0
	var gs = get_node_or_null("/root/GameState")
	if gs and "party_leader_index" in gs:
		idx = clampi(gs.party_leader_index, 0, game_loop.party.size() - 1)
	var leader = game_loop.party[idx]
	if leader.job is Dictionary:
		return leader.job.get("id", "")
	elif leader.job is String:
		return leader.job
	return ""


func _toast(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.position = Vector2(-150, -70)
	lbl.size = Vector2(300, 34)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.87, 0.92))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 18.0, 2.0)
	tw.tween_property(lbl, "modulate:a", 0.0, 2.0).set_delay(0.9)
	tw.chain().tween_callback(func():
		if is_instance_valid(lbl):
			lbl.queue_free())
