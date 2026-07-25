extends Area2D
class_name FireplaceSecret

## FireplaceSecret — the loose hearthstone in the inn (struktured directive,
## msg 2764 item 2: "add a SECRET on fireplace interact — gamepad-
## interactable, one-time, save-persisted flag").
##
## Deliberately quiet: no "!" marker, no map pin, no NPC pointing at it. The
## reward for poking a fireplace is that poking fireplaces turns out to be
## worth doing — signposting it would spend the discovery to buy nothing.
## The [A] prompt only appears once the player is already standing at the
## hearth, which is the hint.
##
## Persistence rides GameState.story_flags (saved), so a found cache stays
## found across save/load and re-entry. cowir-story is welcome to replace
## the flavor text; the mechanism doesn't care what it says.

const SECRET_FLAG := "inn_fireplace_secret_found"
const SECRET_GOLD := 150

const FOUND_LINE := "A hearthstone sits proud of its neighbours. Behind it: a purse, sooted black, and a note reading 'FOR WHOEVER FINALLY LOOKS.'"
const ALREADY_LINE := "The loose hearthstone sits back in place. Whoever left the purse is presumably still waiting to be thanked."

var _indicator: Label
var _player_in_zone: bool = false
var _busy: bool = false


func _ready() -> void:
	add_to_group("interactables")
	collision_layer = InteractGeometry.LAYER_INTERACTABLE
	collision_mask = InteractGeometry.MASK_PLAYER
	monitoring = true
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	# 3x2 tiles across the hearth mouth — wide enough to catch an approach
	# from either side of the fire without reaching the stairs at col 15.
	shape.size = Vector2(96, 64)
	cs.shape = shape
	add_child(cs)
	_setup_indicator()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _setup_indicator() -> void:
	_indicator = Label.new()
	_indicator.text = "[A] Examine hearth"
	_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_indicator.position = Vector2(-64, -44)
	_indicator.size = Vector2(128, 14)
	_indicator.add_theme_font_size_override("font_size", 10)
	_indicator.add_theme_color_override("font_color", Color(1.0, 0.82, 0.55))
	_indicator.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_indicator.add_theme_constant_override("shadow_offset_x", 1)
	_indicator.add_theme_constant_override("shadow_offset_y", 1)
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
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return
	# Already claimed — acknowledge without re-granting. The zone stays
	# interactable on purpose: a dead prompt reads as a bug, a wry line
	# reads as the room remembering you.
	if gs.is_story_flag_set(SECRET_FLAG):
		_toast(ALREADY_LINE)
		if SoundManager:
			SoundManager.play_ui("menu_select")
		return
	# Flag BEFORE the grant so a mid-frame re-entry can't double-pay.
	gs.set_story_flag(SECRET_FLAG)
	if gs.has_method("add_gold"):
		gs.add_gold(SECRET_GOLD)
	if SoundManager:
		SoundManager.play_ui("secret_found")
	_toast(FOUND_LINE + "  (+%d G)" % SECRET_GOLD)


func _toast(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.position = Vector2(-190, -76)
	lbl.size = Vector2(380, 48)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.90, 0.72))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 22.0, 3.0)
	tw.tween_property(lbl, "modulate:a", 0.0, 3.0).set_delay(1.8)
	tw.chain().tween_callback(func():
		if is_instance_valid(lbl):
			lbl.queue_free())
