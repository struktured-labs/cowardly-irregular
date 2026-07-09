extends Area2D
class_name TallyWall

## TallyWall — the Warden's tally in the Whispering Cave (world1_thirty_seven).
## An interactable-giver, not an NPC: the first approach plays the Warden
## encounter cutscene (which sets the quest's prereq flag — the encounter IS
## the tally beat: "Thirty-seven failed attempts. The record must be clear."),
## after which examining the wall offers the quest through QuestSystem's giver
## path (npc_id "warden_tally_wall"). Accepting completes step 1 (the examine).
## Post-completion, re-examining offers the 38th-mark ritual: an explicit
## choice, no reward, chalk on old stone.

const QUEST_ID := "world1_thirty_seven"
const ENCOUNTER_FLAG := "world1_warden_encounter_complete"
const TALLY_FLAG := "quest_world1_thirty_seven_tally_examined"
const MARK_FLAG := "quest_world1_thirty_seven_mark_added"
const TILE_SIZE: int = 32

## QuestSystem giver identity + dialogue-presenter name.
var npc_id: String = "warden_tally_wall"
var npc_name: String = "The Warden's Tally"

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
	_sprite.name = "TallySprite"
	var img := Image.create(TILE_SIZE * 2, TILE_SIZE * 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var stone := Color(0.34, 0.31, 0.30)
	var stone_lt := Color(0.42, 0.39, 0.37)
	var carve := Color(0.82, 0.78, 0.70)
	var carve_dim := Color(0.62, 0.58, 0.52)
	# Wall slab
	for y in range(4, 60):
		for x in range(6, 58):
			img.set_pixel(x, y, stone if (x + y) % 7 != 0 else stone_lt)
	# 37 tally marks: 7 groups of 5 (4 strokes + diagonal) + 2 strokes
	var groups := 7
	for g in range(groups):
		var gx := 10 + (g % 4) * 12
		var gy := 10 + (g / 4) * 16
		for s in range(4):
			for y in range(gy, gy + 10):
				img.set_pixel(gx + s * 2, y, carve)
		for d in range(9):
			img.set_pixel(gx + d, gy + 9 - d, carve_dim)  # the diagonal fifth
	# the 36th + 37th strokes, separate and newer-looking
	for y in range(42, 52):
		img.set_pixel(46, y, carve)
		img.set_pixel(49, y, carve)
	# faint prayer lines carved beneath
	for x in range(10, 50):
		if x % 3 != 0:
			img.set_pixel(x, 56, carve_dim.darkened(0.2))
	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.centered = true
	add_child(_sprite)


func _setup_collision() -> void:
	collision_layer = 4
	collision_mask = 2
	monitoring = true
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 96.0
	col.shape = shape
	col.scale = Vector2(1.0, 1.67)  # Mode 7 Y-stretch, matches other interactables
	add_child(col)


func _setup_indicator() -> void:
	_indicator = Label.new()
	_indicator.text = "[A] Examine"
	_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_indicator.position = Vector2(-48, -44)
	_indicator.size = Vector2(96, 14)
	_indicator.add_theme_font_size_override("font_size", 10)
	_indicator.add_theme_color_override("font_color", Color(0.85, 0.80, 0.65))
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
		await _examine()
		_busy = false


func _examine() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_can_move"):
		player.set_can_move(false)

	# First approach: the Warden encounter cutscene IS the tally reveal.
	# CutsceneDirector is GameLoop-owned, NOT an autoload (msg 2314 catch —
	# a /root/ lookup silently falls back and the encounter never plays).
	if not GameState.is_story_flag_set(ENCOUNTER_FLAG):
		var director = null
		var game_loop = get_node_or_null("/root/GameLoop")
		if game_loop and game_loop.has_method("get_cutscene_director"):
			director = game_loop.get_cutscene_director()
		if director and director.has_method("play_cutscene"):
			await director.play_cutscene("world1_warden_encounter")
		else:
			# Defensive: never strand the quest if the director is missing.
			GameState.set_story_flag(ENCOUNTER_FLAG)
	else:
		var qs = get_node_or_null("/root/QuestSystem")
		if qs and qs.has_giver_business(npc_id):
			var was_offerable: bool = qs.is_offerable(QUEST_ID)
			await qs.run_giver_dialogue(npc_id, self)
			# Accepting the quest at the wall IS the examination (step 1, custom).
			if was_offerable and qs.get_state(QUEST_ID) == "active" \
					and not GameState.get_story_flag(TALLY_FLAG):
				GameState.set_story_flag(TALLY_FLAG)
				qs.notify_flag(TALLY_FLAG)
		elif qs and qs.get_state(QUEST_ID) == "complete" and not GameState.get_story_flag(MARK_FLAG):
			await _offer_thirty_eighth_mark()
		else:
			_toast("Thirty-seven marks. Someone counted every attempt.")

	if player and is_instance_valid(player) and player.has_method("set_can_move"):
		player.set_can_move(true)


## Post-completion ritual: an explicit choice to add the 38th mark. No reward.
func _offer_thirty_eighth_mark() -> void:
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 60
	var root_attach: Node = get_tree().current_scene
	if root_attach == null:
		root_attach = self
	root_attach.add_child(ui_layer)
	var menu := DialogueChoiceMenu.new()
	menu.name = "TallyMarkChoice"
	ui_layer.add_child(menu)
	var add_label := "Add a thirty-eighth mark"
	var chosen: String = await menu.present([add_label, "Leave the wall as it is"])
	if is_instance_valid(menu):
		menu.queue_free()
	if is_instance_valid(ui_layer):
		ui_layer.queue_free()
	if chosen == add_label:
		GameState.set_story_flag(MARK_FLAG)
		if SoundManager:
			SoundManager.play_ui("chalk_tap")
		_toast("You add your mark beside the others.")
	else:
		_toast("The wall keeps its count.")


func _toast(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(-120, -56)
	lbl.size = Vector2(240, 18)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.87, 0.75))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 20.0, 1.6)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.6).set_delay(0.6)
	tw.chain().tween_callback(func():
		if is_instance_valid(lbl):
			lbl.queue_free())
