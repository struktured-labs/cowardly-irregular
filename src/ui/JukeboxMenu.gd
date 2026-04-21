extends Control
class_name JukeboxMenu

## Jukebox - Debug-mode music player submenu for SettingsMenu.
## Follows RetroPanel border style and SettingsMenu patterns.

signal closed()

## All available tracks: [id, display_name]
const TRACKS = [
	["title", "Title Screen"],
	["battle", "Battle (Generic)"],
	["boss", "Boss Battle"],
	["boss_rat_king", "Boss - Rat King"],
	["danger", "Danger / Near Death"],
	["victory", "Victory Fanfare"],
	["game_over", "Game Over"],
	["overworld", "Overworld (Generic)"],
	["overworld_suburban", "Overworld - Suburban"],
	["overworld_steampunk", "Overworld - Steampunk"],
	["overworld_industrial", "Overworld - Industrial"],
	["overworld_futuristic", "Overworld - Futuristic"],
	["overworld_abstract", "Overworld - Abstract"],
	["village", "Village"],
	["cave", "Cave / Dungeon"],
	["battle_suburban", "Battle - Suburban"],
	["battle_urban", "Battle - Urban"],
	["battle_industrial", "Battle - Industrial"],
	["battle_digital", "Battle - Digital"],
	["battle_void", "Battle - Void"],
	["battle_slime", "Battle - Slime"],
	["battle_bat", "Battle - Bat"],
	["battle_mushroom", "Battle - Mushroom"],
	["battle_imp", "Battle - Imp"],
	["battle_goblin", "Battle - Goblin"],
	["battle_skeleton", "Battle - Skeleton"],
	["battle_wolf", "Battle - Wolf"],
	["battle_ghost", "Battle - Ghost"],
	["battle_snake", "Battle - Snake"],
]

## How many rows to show at once in the scroll window
const VISIBLE_ROWS = 14
const ROW_HEIGHT = 32

## Style (matches SettingsMenu / ControlsMenu)
const BG_COLOR = Color(0.05, 0.05, 0.1, 0.95)
const PANEL_COLOR = Color(0.1, 0.1, 0.15)
const BORDER_LIGHT = RetroPanel.BORDER_LIGHT
const BORDER_SHADOW = RetroPanel.BORDER_SHADOW
const SELECTED_COLOR = Color(0.2, 0.3, 0.5)
const TEXT_COLOR = Color(1.0, 1.0, 1.0)
const DISABLED_COLOR = Color(0.4, 0.4, 0.4)
const PLAYING_COLOR = Color(0.3, 1.0, 0.4)

## UI State
var selected_index: int = 0
var scroll_offset: int = 0  # First visible row index
var _currently_playing: String = ""
var _generating: bool = false
var _last_play_time: float = -999.0
const PLAY_DEBOUNCE_SEC = 0.3

## Node references
var _panel: Control
var _row_highlights: Array = []
var _row_labels: Array = []
var _now_playing_label: Label


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	for child in get_children():
		child.queue_free()
	_row_highlights.clear()
	_row_labels.clear()

	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_panel = Control.new()
	_panel.position = Vector2(size.x * 0.15, size.y * 0.06)
	_panel.size = Vector2(size.x * 0.7, size.y * 0.88)
	add_child(_panel)

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(panel_bg)

	RetroPanel.add_border(_panel, _panel.size, BORDER_LIGHT, BORDER_SHADOW)

	var title = Label.new()
	title.text = "JUKEBOX"
	title.position = Vector2(16, 8)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	_panel.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "[DEBUG] Music track browser"
	subtitle.position = Vector2(16, 30)
	subtitle.add_theme_font_size_override("font_size", 10)
	subtitle.add_theme_color_override("font_color", DISABLED_COLOR)
	_panel.add_child(subtitle)

	# Track list area
	var list_y: float = 52.0
	for i in range(VISIBLE_ROWS):
		var highlight = ColorRect.new()
		highlight.position = Vector2(8, list_y + i * ROW_HEIGHT)
		highlight.size = Vector2(_panel.size.x - 16, ROW_HEIGHT - 2)
		highlight.color = Color.TRANSPARENT
		highlight.name = "Row_%d" % i
		_panel.add_child(highlight)
		_row_highlights.append(highlight)

		var lbl = Label.new()
		lbl.position = Vector2(10, 6)
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", TEXT_COLOR)
		highlight.add_child(lbl)
		_row_labels.append(lbl)

		MenuMouseHelper.make_clickable(highlight, i, _panel.size.x - 16, ROW_HEIGHT - 2,
			_on_row_click.bind(i), _on_row_hover.bind(i))

	# Scroll hint (arrow indicators)
	var scroll_up_lbl = Label.new()
	scroll_up_lbl.name = "ScrollUp"
	scroll_up_lbl.text = ""
	scroll_up_lbl.position = Vector2(_panel.size.x - 24, 52)
	scroll_up_lbl.add_theme_font_size_override("font_size", 12)
	scroll_up_lbl.add_theme_color_override("font_color", DISABLED_COLOR)
	_panel.add_child(scroll_up_lbl)

	var scroll_dn_lbl = Label.new()
	scroll_dn_lbl.name = "ScrollDown"
	scroll_dn_lbl.text = ""
	scroll_dn_lbl.position = Vector2(_panel.size.x - 24, 52 + VISIBLE_ROWS * ROW_HEIGHT - ROW_HEIGHT)
	scroll_dn_lbl.add_theme_font_size_override("font_size", 12)
	scroll_dn_lbl.add_theme_color_override("font_color", DISABLED_COLOR)
	_panel.add_child(scroll_dn_lbl)

	# "Now Playing" status bar
	_now_playing_label = Label.new()
	_now_playing_label.position = Vector2(16, _panel.size.y - 48)
	_now_playing_label.size = Vector2(_panel.size.x - 32, 18)
	_now_playing_label.add_theme_font_size_override("font_size", 11)
	_now_playing_label.add_theme_color_override("font_color", PLAYING_COLOR)
	_now_playing_label.name = "NowPlaying"
	_panel.add_child(_now_playing_label)
	_refresh_now_playing()

	# Footer
	var footer = Label.new()
	footer.text = "Up/Down: Navigate   A: Play   B: Stop & Back"
	footer.position = Vector2(16, _panel.size.y - 28)
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", DISABLED_COLOR)
	_panel.add_child(footer)

	MenuMouseHelper.add_right_click_cancel(bg, _close_menu)

	_refresh_list()
	_update_selection()


func _refresh_list() -> void:
	var total = TRACKS.size()
	for i in range(VISIBLE_ROWS):
		var track_idx = scroll_offset + i
		if track_idx < total:
			_row_labels[i].text = TRACKS[track_idx][1]
			var track_id = TRACKS[track_idx][0]
			_row_labels[i].add_theme_color_override("font_color",
				PLAYING_COLOR if track_id == _currently_playing else TEXT_COLOR)
			_row_highlights[i].modulate.a = 1.0
		else:
			_row_labels[i].text = ""
			_row_highlights[i].modulate.a = 0.0

	# Update scroll indicators
	var up_lbl = _panel.get_node_or_null("ScrollUp")
	var dn_lbl = _panel.get_node_or_null("ScrollDown")
	if up_lbl:
		up_lbl.text = "^" if scroll_offset > 0 else ""
	if dn_lbl:
		dn_lbl.text = "v" if (scroll_offset + VISIBLE_ROWS) < total else ""


func _update_selection() -> void:
	var local_row = selected_index - scroll_offset
	for i in range(VISIBLE_ROWS):
		_row_highlights[i].color = SELECTED_COLOR if i == local_row else Color.TRANSPARENT


func _refresh_now_playing() -> void:
	if not _now_playing_label:
		return
	if _currently_playing == "":
		_now_playing_label.text = "Now Playing: (none)"
	else:
		var display = _currently_playing
		for t in TRACKS:
			if t[0] == _currently_playing:
				display = t[1]
				break
		_now_playing_label.text = "Now Playing: %s" % display


func _play_selected() -> void:
	if selected_index < 0 or selected_index >= TRACKS.size():
		return
	if _generating:
		return
	var now = Time.get_ticks_msec() / 1000.0
	if now - _last_play_time < PLAY_DEBOUNCE_SEC:
		return
	_last_play_time = now

	var track_id = TRACKS[selected_index][0]

	_generating = true
	_currently_playing = track_id
	_now_playing_label.text = "Generating..."
	_now_playing_label.add_theme_color_override("font_color", DISABLED_COLOR)

	await get_tree().process_frame
	await get_tree().create_timer(0.05).timeout

	if SoundManager:
		if track_id.begins_with("overworld") or track_id in ["village", "cave"]:
			SoundManager.play_area_music(track_id)
		else:
			SoundManager.play_music(track_id)
		SoundManager.play_ui("menu_select")

	_generating = false
	_now_playing_label.add_theme_color_override("font_color", PLAYING_COLOR)
	_refresh_now_playing()
	_refresh_list()


func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Cancel/Back always works, even while generating
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		_close_menu()
		get_viewport().set_input_as_handled()
		return

	# All other input is suppressed while music is being generated
	if _generating:
		if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") or event.is_action_pressed("ui_accept"):
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_up") and not event.is_echo():
		if selected_index > 0:
			selected_index -= 1
			_clamp_scroll()
			_refresh_list()
			_update_selection()
			if SoundManager:
				SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_down") and not event.is_echo():
		if selected_index < TRACKS.size() - 1:
			selected_index += 1
			_clamp_scroll()
			_refresh_list()
			_update_selection()
			if SoundManager:
				SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		_play_selected()
		get_viewport().set_input_as_handled()


func _clamp_scroll() -> void:
	if selected_index < scroll_offset:
		scroll_offset = selected_index
	elif selected_index >= scroll_offset + VISIBLE_ROWS:
		scroll_offset = selected_index - VISIBLE_ROWS + 1
	scroll_offset = clampi(scroll_offset, 0, max(0, TRACKS.size() - VISIBLE_ROWS))


func _on_row_click(local_row: int) -> void:
	var track_idx = scroll_offset + local_row
	if track_idx >= TRACKS.size():
		return
	selected_index = track_idx
	_update_selection()
	_play_selected()


func _on_row_hover(local_row: int) -> void:
	var track_idx = scroll_offset + local_row
	if track_idx >= TRACKS.size():
		return
	if track_idx != selected_index:
		selected_index = track_idx
		_clamp_scroll()
		_update_selection()
		if SoundManager:
			SoundManager.play_ui("menu_move")


func _close_menu() -> void:
	if SoundManager:
		SoundManager.stop_music()
		SoundManager.play_ui("menu_close")
	closed.emit()
	queue_free()
