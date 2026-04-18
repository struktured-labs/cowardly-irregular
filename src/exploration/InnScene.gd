extends Control
class_name InnScene

## InnScene — rest at an inn, restore HP/MP, optional save.
## Triggered by innkeeper NPC. Gold cost scales by world.
##
## Usage:
##   var inn = InnScene.new()
##   inn.setup(world_index)  # 1–6
##   parent.add_child(inn)
##   await inn.inn_closed

signal inn_closed()

const COSTS_BY_WORLD := {1: 50, 2: 100, 3: 200, 4: 400, 5: 800, 6: 1500}

const BG_COLOR := Color(0.0, 0.0, 0.0, 0.8)
const PANEL_COLOR := Color(0.08, 0.08, 0.14, 0.96)
const BORDER_LIGHT := Color(0.6, 0.8, 1.0)
const BORDER_SHADOW := Color(0.15, 0.2, 0.4)
const TEXT_COLOR := Color(0.9, 0.95, 1.0)
const GOLD_COLOR := Color(1.0, 0.92, 0.55)
const DIM_COLOR := Color(0.55, 0.6, 0.75)
const SUCCESS_COLOR := Color(0.5, 1.0, 0.6)
const ERROR_COLOR := Color(1.0, 0.5, 0.5)

var _world: int = 1
var _cost: int = 50
var _options: Array[String] = ["Rest", "Save", "Leave"]
var _selected: int = 0
var _state: String = "menu"  # "menu", "resting", "done"

var _panel: Control
var _message_label: Label
var _gold_label: Label
var _option_labels: Array[Label] = []

@onready var game_state = get_node("/root/GameState")


func setup(world_index: int = 1) -> void:
	_world = clampi(world_index, 1, 6)
	_cost = COSTS_BY_WORLD.get(_world, 50)


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	process_mode = PROCESS_MODE_ALWAYS
	_build_ui()
	_update_display()


func _build_ui() -> void:
	# Dim backdrop
	var dim := ColorRect.new()
	dim.color = BG_COLOR
	dim.set_anchors_preset(PRESET_FULL_RECT)
	dim.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(dim)

	var vp := get_viewport_rect().size
	if vp.x <= 0:
		vp = Vector2(1280, 720)
	var pw := 420
	var ph := 260

	_panel = RetroPanel.create_panel(pw, ph, PANEL_COLOR, BORDER_LIGHT, BORDER_SHADOW)
	_panel.position = Vector2((vp.x - pw) / 2, (vp.y - ph) / 2)
	add_child(_panel)

	# Title
	var title := Label.new()
	title.text = "Inn"
	title.position = Vector2(20, 12)
	title.size = Vector2(pw - 40, 32)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", GOLD_COLOR)
	title.clip_text = false
	title.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_panel.add_child(title)

	# Gold display (top right)
	_gold_label = Label.new()
	_gold_label.position = Vector2(pw - 160, 16)
	_gold_label.size = Vector2(140, 24)
	_gold_label.add_theme_font_size_override("font_size", 16)
	_gold_label.add_theme_color_override("font_color", GOLD_COLOR)
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gold_label.clip_text = false
	_gold_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_panel.add_child(_gold_label)

	# Divider
	var div := ColorRect.new()
	div.color = Color(0.3, 0.4, 0.6, 0.6)
	div.position = Vector2(20, 50)
	div.size = Vector2(pw - 40, 2)
	_panel.add_child(div)

	# Message
	_message_label = Label.new()
	_message_label.position = Vector2(24, 60)
	_message_label.size = Vector2(pw - 48, 60)
	_message_label.add_theme_font_size_override("font_size", 16)
	_message_label.add_theme_color_override("font_color", TEXT_COLOR)
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_message_label)

	# Options
	for i in _options.size():
		var lbl := Label.new()
		lbl.position = Vector2(40, 130 + i * 34)
		lbl.size = Vector2(pw - 80, 28)
		lbl.add_theme_font_size_override("font_size", 18)
		lbl.clip_text = false
		lbl.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		_panel.add_child(lbl)
		_option_labels.append(lbl)

	# Footer hint
	var hint := Label.new()
	hint.text = "↑↓: Select   A: Confirm   B: Close"
	hint.position = Vector2(20, ph - 30)
	hint.size = Vector2(pw - 40, 20)
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", DIM_COLOR)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(hint)


func _update_display() -> void:
	if game_state:
		_gold_label.text = "%d G" % game_state.get_gold()

	_message_label.text = "Rest for the night? (%d G)\nAll party members will be fully healed." % _cost

	for i in _option_labels.size():
		var lbl: Label = _option_labels[i]
		var opt: String = _options[i]
		if i == _selected:
			lbl.text = "▸ %s" % opt
			lbl.add_theme_color_override("font_color", GOLD_COLOR)
		else:
			lbl.text = "  %s" % opt
			lbl.add_theme_color_override("font_color", TEXT_COLOR)


func _input(event: InputEvent) -> void:
	if _state != "menu":
		return
	if event.is_action_pressed("ui_up"):
		_selected = (_selected - 1 + _options.size()) % _options.size()
		_update_display()
		if SoundManager:
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_selected = (_selected + 1) % _options.size()
		_update_display()
		if SoundManager:
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_confirm()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _confirm() -> void:
	match _options[_selected]:
		"Rest":
			_do_rest()
		"Save":
			_do_save()
		"Leave":
			_close()


func _do_rest() -> void:
	if not game_state:
		return
	if game_state.get_gold() < _cost:
		_message_label.text = "Not enough gold! You need %d G." % _cost
		_message_label.add_theme_color_override("font_color", ERROR_COLOR)
		if SoundManager:
			SoundManager.play_ui("menu_error")
		# Reset color after delay
		var timer := get_tree().create_timer(1.5)
		await timer.timeout
		if not is_instance_valid(self):
			return
		_message_label.add_theme_color_override("font_color", TEXT_COLOR)
		_update_display()
		return

	_state = "resting"
	game_state.spend_gold(_cost)
	_gold_label.text = "%d G" % game_state.get_gold()

	# Heal entire party via GameLoop's runtime Combatants
	var game_loop := _find_game_loop()
	if game_loop and "party" in game_loop:
		for member in game_loop.party:
			if is_instance_valid(member):
				member.current_hp = member.max_hp
				member.current_mp = member.max_mp
				member.is_alive = true

	if SoundManager:
		SoundManager.play_ui("menu_select")

	_message_label.text = "Your party rests peacefully...\nHP and MP fully restored!"
	_message_label.add_theme_color_override("font_color", SUCCESS_COLOR)

	# Brief pause before returning to menu
	var timer := get_tree().create_timer(2.0)
	await timer.timeout
	if not is_instance_valid(self):
		return
	_state = "menu"
	_message_label.add_theme_color_override("font_color", TEXT_COLOR)
	_update_display()


func _do_save() -> void:
	if not SaveSystem:
		return
	_state = "resting"
	if SaveSystem.has_method("quick_save"):
		if SaveSystem.quick_save():
			_message_label.text = "Game saved!"
			_message_label.add_theme_color_override("font_color", SUCCESS_COLOR)
			if SoundManager:
				SoundManager.play_ui("menu_select")
		else:
			_message_label.text = "Could not save here."
			_message_label.add_theme_color_override("font_color", ERROR_COLOR)
			if SoundManager:
				SoundManager.play_ui("menu_error")
	var timer := get_tree().create_timer(1.5)
	await timer.timeout
	if not is_instance_valid(self):
		return
	_state = "menu"
	_message_label.add_theme_color_override("font_color", TEXT_COLOR)
	_update_display()


func _close() -> void:
	if SoundManager:
		SoundManager.play_ui("menu_close")
	inn_closed.emit()
	queue_free()


func _find_game_loop() -> Node:
	"""Walk the scene tree to find the GameLoop node."""
	var root := get_tree().root
	for child in root.get_children():
		if child is Node and child.get_script() and "party" in child:
			return child
	return null
