extends Area2D
class_name BulletinBoard

## BulletinBoard — the Community Center's cork wall (world2_forms_in_triplicate
## giver; TallyWall interactable-giver pattern). Examining offers the quest —
## accepting IS reading the notice (step 1 custom). Mid-quest examines surface
## the seven flagged complaints; Phil's is the load-bearing one.

const QUEST_ID := "world2_forms_in_triplicate"
const NOTICE_FLAG := "quest_world2_forms_in_triplicate_notice_read"
const TILE_SIZE: int = 32

var npc_id: String = "community_bulletin_board"
var npc_name: String = "Bulletin Board"

const COMPLAINTS := [
	"COMPLAINT #041: strip mall rearranged again. Third filing.",
	"COMPLAINT #042: strip mall rearranged AGAIN. Fourth filing. Same pen.",
	"COMPLAINT #044: the mall moved my parking spot. The car was still in it.",
	"COMPLAINT #051: my son was 'community-transferred'. Nobody asked me.",
	"COMPLAINT #052: second missing child this month. Form returned: 'AS INTENDED'.",
	"COMPLAINT #057: there is a monitor visible through the Coordinator's window.",
	"COMPLAINT #060 (P. the Lost): 'I keep seeing this village. Different every time. Same people. Something is wrong with the counting.'",
]

var _sprite: Sprite2D
var _indicator: Label
var _player_in_zone: bool = false
var _busy: bool = false
var _complaint_idx: int = 0


func _ready() -> void:
	add_to_group("interactables")
	_setup_sprite()
	_setup_collision()
	_setup_indicator()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _setup_sprite() -> void:
	_sprite = Sprite2D.new()
	var img := Image.create(TILE_SIZE * 2, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cork := Color(0.72, 0.58, 0.40)
	var frame := Color(0.45, 0.35, 0.25)
	var paper := Color(0.94, 0.93, 0.88)
	var pin := Color(0.85, 0.25, 0.2)
	for y in range(4, 28):
		for x in range(2, 62):
			img.set_pixel(x, y, cork if (x + y) % 9 != 0 else cork.darkened(0.1))
	for x in range(2, 62):
		img.set_pixel(x, 4, frame); img.set_pixel(x, 27, frame)
	for y in range(4, 28):
		img.set_pixel(2, y, frame); img.set_pixel(61, y, frame)
	for px in [8, 22, 38, 50]:
		for y in range(8, 22):
			for x in range(px, px + 9):
				img.set_pixel(x, y, paper)
		img.set_pixel(px + 4, 8, pin)
	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.centered = true
	add_child(_sprite)


func _setup_collision() -> void:
	collision_layer = 4
	collision_mask = 2
	monitoring = true
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 72.0
	cs.shape = shape
	cs.scale = Vector2(1.0, 1.67)
	add_child(cs)


func _setup_indicator() -> void:
	_indicator = Label.new()
	_indicator.text = "[A] Read board"
	_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_indicator.position = Vector2(-48, -36)
	_indicator.size = Vector2(96, 14)
	_indicator.add_theme_font_size_override("font_size", 10)
	_indicator.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
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
		await _examine()
		_busy = false


func _examine() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_can_move"):
		player.set_can_move(false)
	var qs = get_node_or_null("/root/QuestSystem")
	if qs and qs.has_giver_business(npc_id):
		var was_offerable: bool = qs.is_offerable(QUEST_ID)
		await qs.run_giver_dialogue(npc_id, self)
		# Accepting IS reading the notice (step 1, custom).
		if was_offerable and qs.get_state(QUEST_ID) == "active" \
				and not GameState.get_story_flag(NOTICE_FLAG):
			GameState.set_story_flag(NOTICE_FLAG)
			qs.notify_flag(NOTICE_FLAG)
	elif qs and qs.get_state(QUEST_ID) == "active":
		# Mid-quest: surface the flagged complaints, one per read.
		_toast(COMPLAINTS[_complaint_idx % COMPLAINTS.size()])
		_complaint_idx += 1
	else:
		_toast("Bake sales, lost cats, and a surprising number of formal complaints.")
	if player and is_instance_valid(player) and player.has_method("set_can_move"):
		player.set_can_move(true)


func _toast(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.position = Vector2(-150, -64)
	lbl.size = Vector2(300, 34)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.92, 0.9, 0.8))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 18.0, 2.2)
	tw.tween_property(lbl, "modulate:a", 0.0, 2.2).set_delay(1.0)
	tw.chain().tween_callback(func():
		if is_instance_valid(lbl):
			lbl.queue_free())
