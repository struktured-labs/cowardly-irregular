extends Area2D
class_name QuestExaminePoint

## A custom quest objective advances ONLY through QuestSystem.notify_flag — notify_talk
## skips type "custom" — so a step with no emitter strands the quest permanently.

const TILE_SIZE: int = 32

@export var quest_id: String = ""
@export var flag: String = ""
@export var indicator_text: String = "[A] Examine"
@export var examine_text: String = ""
@export var idle_text: String = ""
@export var glyph_color: Color = Color(0.85, 0.78, 0.5)

var _sprite: Sprite2D
var _indicator: Label
var _player_in_zone: bool = false
var _busy: bool = false
var _pulse_t: float = 0.0


func _ready() -> void:
	add_to_group("interactables")
	_setup_sprite()
	_setup_collision()
	_setup_indicator()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	if _sprite and _is_live():
		_pulse_t += delta * 2.2
		_sprite.modulate.a = 0.72 + 0.28 * abs(sin(_pulse_t))


func _setup_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "ExamineGlyph"
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var edge := glyph_color.darkened(0.35)
	for a in range(24):
		var t: float = a * TAU / 24.0
		var px: int = 16 + int(round(9.0 * cos(t)))
		var py: int = 16 + int(round(9.0 * sin(t)))
		if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
			img.set_pixel(px, py, edge)
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			if abs(dx) + abs(dy) <= 4:
				img.set_pixel(16 + dx, 16 + dy, glyph_color if (dx + dy) % 2 == 0 else edge)
	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.centered = true
	_sprite.offset = Vector2(0, -4)
	add_child(_sprite)


func _setup_collision() -> void:
	collision_layer = 4
	collision_mask = 2
	monitoring = true
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 52.0
	col.shape = shape
	col.scale = Vector2(1.0, 1.6)
	add_child(col)


func _setup_indicator() -> void:
	_indicator = Label.new()
	_indicator.text = indicator_text
	_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_indicator.position = Vector2(-72, -40)
	_indicator.size = Vector2(144, 14)
	_indicator.add_theme_font_size_override("font_size", 10)
	_indicator.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	_indicator.visible = false
	_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_indicator)


## Live only while THIS flag is the current objective's requirement — setting it on a
## later step would consume the notify the step actually needs and strand the quest again.
func _is_live() -> bool:
	var qs = get_node_or_null("/root/QuestSystem")
	if qs == null or quest_id == "" or flag == "":
		return false
	if qs.get_state(quest_id) != "active":
		return false
	# get_objective_index clamps only when objectives is NON-empty, and this runs every frame from _process
	var objectives: Array = qs.get_quest(quest_id).get("objectives", [])
	var idx: int = qs.get_objective_index(quest_id)
	if idx < 0 or idx >= objectives.size():
		return false
	var obj: Dictionary = objectives[idx]
	return obj.get("type", "") == "custom" and obj.get("required_flag", "") == flag


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") or body.has_method("set_can_move"):
		_player_in_zone = true
		_indicator.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") or body.has_method("set_can_move"):
		_player_in_zone = false
		_indicator.visible = false


func _unhandled_input(event: InputEvent) -> void:
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
	if not _is_live():
		if SoundManager:
			SoundManager.play_ui("menu_error")
		_toast(idle_text)
		return
	var qs = get_node_or_null("/root/QuestSystem")
	if SoundManager:
		SoundManager.play_ui("secret_found")
	var job_line := _job_variant_text(qs)
	GameState.set_story_flag(flag)
	qs.notify_flag(flag)
	_toast(examine_text if job_line == "" else examine_text + "\n\n" + job_line)


## The lead job's authored read of THIS point, or "". 16 of these sat in quest data
## rendered by nothing until struktured's "wire / rewrite" ruling.
func _job_variant_text(qs: Node) -> String:
	if qs == null or not qs.has_method("_leader_job_id"):
		return ""
	var job: String = str(qs._leader_job_id())
	if job == "":
		return ""
	var variant = qs.get_quest(quest_id).get("rewards", {}).get("job_variants", {}).get(job, {})
	if not (variant is Dictionary):
		return ""
	## examine_flag scopes the beat to ONE point — a quest with several points would
	## otherwise show its single job read at whichever the player reached first.
	if str(variant.get("examine_flag", "")) != flag:
		return ""
	return str(variant.get("examine_text", ""))


func _toast(text: String) -> void:
	if text == "":
		return
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(-150, -58)
	lbl.size = Vector2(300, 36)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 20.0, 2.2)
	tw.tween_property(lbl, "modulate:a", 0.0, 2.2).set_delay(1.0)
	tw.chain().tween_callback(func():
		if is_instance_valid(lbl):
			lbl.queue_free())
