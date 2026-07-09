extends Area2D
class_name QuestChicken

## QuestChicken — a catchable hen for "One Chicken Problem, Actually Seven"
## (world1_one_chicken_problem step 2, the 7-catch movement puzzle).
##
## Seven of these are scattered across W1 (overworld cave approach, Inn kitchen,
## Harmonia). Each is ambient flavour until the quest is active; while active,
## walking into one "corners" it — sets a per-chicken story flag, poofs it home,
## and when all seven are caught emits quest_world1_one_chicken_problem_all_chickens
## (the step-2 custom emitter cowir-main temp-gated the offer behind).
##
## Persistence mirrors the TreasureChest / HiddenPassage contract: story flag
## "chicken_caught_<id>" per hen, so a caught hen stays home across save/scene.

@export var chicken_id: String = "chicken_1"
## Optional line shown on catch (Phil's well hen carries the thematic line).
@export var catch_line: String = ""

const TILE_SIZE: int = 32
const QUEST_ID := "world1_one_chicken_problem"
const ALL_CAUGHT_FLAG := "quest_world1_one_chicken_problem_all_chickens"

## The canonical seven — tally reads these. Placement lives in the scenes;
## this list is the source of truth for "how many total".
const ALL_CHICKEN_IDS := [
	"chicken_cave_approach", "chicken_inn_kitchen", "chicken_guild",
	"chicken_harmonia_market", "chicken_harmonia_flowerbed",
	"chicken_harmonia_backlot", "chicken_phil_well",
]

var _sprite: Sprite2D
var _bob_t: float = 0.0
var _caught: bool = false


func _ready() -> void:
	_caught = GameState.get_story_flag("chicken_caught_" + chicken_id)
	add_to_group("quest_chicken")
	_setup_sprite()
	_setup_collision()
	body_entered.connect(_on_body_entered)
	if _caught:
		# Already home — don't render a duplicate hen.
		visible = false
		monitoring = false


func _process(delta: float) -> void:
	if _caught or _sprite == null:
		return
	# Gentle idle bob so the hens read as alive.
	_bob_t += delta * 4.0
	_sprite.position.y = -2.0 + sin(_bob_t) * 1.5


func _setup_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "ChickenSprite"
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var body := Color(0.96, 0.96, 0.92)
	var body_sh := Color(0.82, 0.82, 0.78)
	var comb := Color(0.85, 0.20, 0.18)
	var beak := Color(0.95, 0.65, 0.20)
	var leg := Color(0.90, 0.60, 0.18)
	var eye := Color(0.12, 0.10, 0.10)
	# body (oval)
	for y in range(6, 14):
		for x in range(4, 13):
			var dx := float(x - 8) / 4.5
			var dy := float(y - 10) / 4.0
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, body_sh if x < 7 else body)
	# head
	for y in range(3, 8):
		for x in range(9, 14):
			var dx := float(x - 11) / 2.5
			var dy := float(y - 5) / 2.5
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, body)
	# comb
	img.set_pixel(11, 2, comb); img.set_pixel(12, 2, comb); img.set_pixel(12, 3, comb)
	# beak
	img.set_pixel(14, 5, beak); img.set_pixel(15, 5, beak)
	# eye
	img.set_pixel(12, 5, eye)
	# legs
	img.set_pixel(7, 14, leg); img.set_pixel(7, 15, leg)
	img.set_pixel(10, 14, leg); img.set_pixel(10, 15, leg)
	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.scale = Vector2(1.6, 1.6)
	_sprite.position = Vector2(0, -2)
	add_child(_sprite)


func _setup_collision() -> void:
	collision_layer = 4
	collision_mask = 2  # Player
	monitoring = true
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 20.0
	col.shape = shape
	col.scale = Vector2(1.0, 1.67)  # Mode 7 Y-stretch, matches other interactables
	add_child(col)


func _on_body_entered(body: Node2D) -> void:
	if _caught:
		return
	if not (body.is_in_group("player") or body.has_method("set_can_move")):
		return
	var qs := get_node_or_null("/root/QuestSystem")
	if qs == null or qs.get_state(QUEST_ID) != "active":
		# Ambient hen — a cluck, but no progress until the quest is taken.
		if SoundManager:
			SoundManager.play_ui("menu_move")
		return
	_catch()


func _catch() -> void:
	_caught = true
	GameState.set_story_flag("chicken_caught_" + chicken_id)
	if SoundManager:
		SoundManager.play_ui("secret_found")
	_poof()
	_tally()


func _tally() -> void:
	var caught_count := 0
	for cid in ALL_CHICKEN_IDS:
		if GameState.get_story_flag("chicken_caught_" + cid):
			caught_count += 1
	var qs := get_node_or_null("/root/QuestSystem")
	if caught_count >= ALL_CHICKEN_IDS.size():
		GameState.set_story_flag(ALL_CAUGHT_FLAG)
		if qs and qs.has_method("notify_flag"):
			qs.notify_flag(ALL_CAUGHT_FLAG)
		_toast("All seven chickens rounded up! Return to Farmer Aldwick.")
	else:
		var line := catch_line if catch_line != "" else "Chicken cornered! (%d / 7)" % caught_count
		_toast(line)


func _poof() -> void:
	# Flee + fade: the hen darts up-screen and vanishes (caught → going home).
	if _sprite == null:
		return
	monitoring = false
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_sprite, "position:y", _sprite.position.y - 18.0, 0.35)
	tw.tween_property(_sprite, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(func(): visible = false)


func _toast(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(-96, -44)
	lbl.size = Vector2(192, 18)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 22.0, 1.5)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.5).set_delay(0.5)
	tw.chain().tween_callback(func():
		if is_instance_valid(lbl):
			lbl.queue_free())
