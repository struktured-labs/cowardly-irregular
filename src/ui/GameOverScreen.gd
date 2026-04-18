extends CanvasLayer
class_name GameOverScreen

## GameOverScreen — dramatic game over overlay with retry/load options.
## Fades in with dramatic text, offers Retry (restart from overworld) or
## Continue (if autosave exists).
## Title + subtitle vary per world (reads GameState.current_world).

signal retry_selected()
signal continue_selected()

## World-specific titles (falls back to GAME OVER). W6 is the one world
## whose aesthetic benefits from replacing the title — every other world
## keeps the classic.
const TITLES_BY_WORLD := {
	6: "OPTIMIZED",
}

## Subtitle pools. One is picked at random on each show_game_over().
## Entries in world 0 are the universal fallback for pre-W1 / unknown.
const SUBTITLES_BY_WORLD := {
	0: [
		"The party has fallen.",
	],
	1: [
		"The cave claims another expedition.",
		"Mordaine's ledger has a new entry.",
		"Someone in Harmonia will pour out a drink tonight.",
		"The thirty-eighth party did not make it.",
	],
	2: [
		"The neighborhood has taken care of it.",
		"The HOA will note your absence in the minutes.",
		"Another retirement. Another pension claim filed.",
		"The school nurse cannot, in fact, revive you.",
	],
	3: [
		"Scheduled expiration. Thank you for your service.",
		"The Grand Schedule continues without you.",
		"The clock tower chimes. It is now 4:08.",
		"Your downtime has been filed under 'expected'.",
	],
	4: [
		"You are no longer on the manifest.",
		"Shift concluded. Benefits discontinued.",
		"Union dues refunded in full.",
		"A memo regarding your absence has been drafted.",
	],
	5: [
		"Process terminated. Exit code 137.",
		"Segmentation fault (core dumped).",
		"Session expired. Please reauthenticate.",
		"free() called successfully.",
	],
	6: [
		"You have been optimized out.",
		"The variable is now unused.",
		"Reduced to nothing. As expected.",
		"Your function has returned.",
	],
}

var _container: Control
var _title_label: Label
var _subtitle_label: Label
var _retry_label: Label
var _continue_label: Label
var _selected_index: int = 0
var _active: bool = false
var _has_save: bool = false


func _ready() -> void:
	layer = 99  # Above everything except transitions
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false


func _build_ui() -> void:
	var screen_size = Vector2(1280, 720)  # Default, updated on show

	_container = Control.new()
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)

	# Dark background
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.02, 0.02, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(bg)

	# "GAME OVER" title
	_title_label = Label.new()
	_title_label.text = "GAME OVER"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.size = Vector2(screen_size.x, 60)
	_title_label.add_theme_font_size_override("font_size", 48)
	_title_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.15))
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(_title_label)

	# Subtitle
	_subtitle_label = Label.new()
	_subtitle_label.text = "The party has fallen."
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.size = Vector2(screen_size.x, 25)
	_subtitle_label.add_theme_font_size_override("font_size", 16)
	_subtitle_label.add_theme_color_override("font_color", Color(0.6, 0.5, 0.45))
	_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(_subtitle_label)

	# Retry option
	_retry_label = Label.new()
	_retry_label.text = "> Retry"
	_retry_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_retry_label.size = Vector2(screen_size.x, 25)
	_retry_label.add_theme_font_size_override("font_size", 20)
	_retry_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	_retry_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(_retry_label)

	# Continue option
	_continue_label = Label.new()
	_continue_label.text = "  Continue"
	_continue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_continue_label.size = Vector2(screen_size.x, 25)
	_continue_label.add_theme_font_size_override("font_size", 20)
	_continue_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.45))
	_continue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(_continue_label)


func show_game_over(has_save: bool = false) -> void:
	"""Show the game over screen with fade-in animation."""
	_has_save = has_save
	_selected_index = 0
	_active = false
	visible = true

	_apply_world_flavor()

	var screen_size = get_viewport().get_visible_rect().size
	_title_label.position.y = screen_size.y * 0.3
	_subtitle_label.position.y = screen_size.y * 0.3 + 60
	_retry_label.position.y = screen_size.y * 0.55
	_continue_label.position.y = screen_size.y * 0.55 + 35
	_continue_label.visible = has_save


func _apply_world_flavor() -> void:
	"""Pick title + subtitle based on GameState.current_world."""
	var world := 0
	var gs := get_node_or_null("/root/GameState")
	if gs and "current_world" in gs:
		world = int(gs.current_world)

	_title_label.text = TITLES_BY_WORLD.get(world, "GAME OVER")

	var pool: Array = SUBTITLES_BY_WORLD.get(world, SUBTITLES_BY_WORLD[0])
	if pool.is_empty():
		pool = SUBTITLES_BY_WORLD[0]
	_subtitle_label.text = pool[randi() % pool.size()]

	# Fade in
	_container.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(_container, "modulate:a", 1.0, 1.5)
	await tween.finished

	# Brief pause before accepting input
	await get_tree().create_timer(0.5).timeout
	_active = true
	_update_selection()


func _update_selection() -> void:
	if _selected_index == 0:
		_retry_label.text = "> Retry"
		_retry_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
		_continue_label.text = "  Continue"
		_continue_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.45))
	else:
		_retry_label.text = "  Retry"
		_retry_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.45))
		_continue_label.text = "> Continue"
		_continue_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))


func _input(event: InputEvent) -> void:
	if not _active:
		return

	if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		if _has_save:
			_selected_index = 1 - _selected_index
			_update_selection()
			if SoundManager:
				SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	if event.is_action_pressed("ui_accept"):
		_active = false
		if SoundManager:
			SoundManager.play_ui("menu_select")
		get_viewport().set_input_as_handled()
		_confirm_selection()


func _confirm_selection() -> void:
	"""Fade out and emit selection signal (separated from _input to avoid await issues)."""
	var tween = create_tween()
	tween.tween_property(_container, "modulate:a", 0.0, 0.5)
	await tween.finished
	visible = false
	if _selected_index == 0:
		retry_selected.emit()
	else:
		continue_selected.emit()
