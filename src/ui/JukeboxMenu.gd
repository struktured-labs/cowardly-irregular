extends Control
class_name JukeboxMenu

## Jukebox - Debug-mode music player submenu for SettingsMenu.
## Follows RetroPanel border style and SettingsMenu patterns.

signal closed()

const MUSIC_MANIFEST := "res://data/music_manifest.json"

# Tick 199: TRACKS now loads from music_manifest.json. Pre-fix the const had 29 stale entries — many ids ("battle", "boss", "overworld", "cave", "battle_urban", "battle_void") didn't match the live 150-entry manifest, so half the jukebox played nothing or fell to procedural fallback.
var TRACKS: Array = []  # [[id, display_name], ...] populated by _load_manifest_tracks() in _ready

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
# Tick 201: per-category tints — vertical color bands in the sorted list show category boundaries at a glance. PLAYING_COLOR still overrides for the active track.
const CAT_BATTLE_COLOR := Color(0.95, 0.55, 0.55)   # muted red — combat
const CAT_BOSS_COLOR := Color(0.95, 0.80, 0.40)     # gold — boss
const CAT_OVERWORLD_COLOR := Color(0.50, 0.85, 0.95) # cyan — open world
const CAT_VILLAGE_COLOR := Color(0.65, 0.80, 1.00)  # pastel blue — settlement
const CAT_DUNGEON_COLOR := Color(0.80, 0.65, 1.00)  # purple — interior dungeon
const CAT_DANGER_COLOR := Color(0.95, 0.65, 0.30)   # orange — alert

## UI State
var selected_index: int = 0
var scroll_offset: int = 0  # First visible row index
var _currently_playing: String = ""
var _generating: bool = false
var _last_play_time: float = -999.0
const PLAY_DEBOUNCE_SEC = 0.3
## Track that was playing when the jukebox opened, so we can resume it
## on close. Bug fix (2026-04-30): pre-fix, _close_menu unconditionally
## called SoundManager.stop_music(), leaving the overworld silent until
## the next area transition.
var _resume_track: String = ""

## Node references
var _panel: Control
var _row_highlights: Array = []
var _row_labels: Array = []
var _now_playing_label: Label


func _ready() -> void:
	# Tick 199: load tracks from manifest before _build_ui so the list reflects live music.
	TRACKS = _load_manifest_tracks()
	# Snapshot the currently-playing music so _close_menu can restore it
	# instead of leaving silence behind.
	if SoundManager and "_current_music" in SoundManager:
		_resume_track = SoundManager._current_music
	_build_ui()


# Tick 199: load + sort tracks from music_manifest.json. Loud-fail on missing/malformed file so a broken manifest doesn't silently render an empty jukebox.
static func _load_manifest_tracks() -> Array:
	if not FileAccess.file_exists(MUSIC_MANIFEST):
		push_warning("[JukeboxMenu] music_manifest.json not found — jukebox empty")
		return []
	var f := FileAccess.open(MUSIC_MANIFEST, FileAccess.READ)
	if not f:
		push_warning("[JukeboxMenu] music_manifest.json open failed (error %d)" % FileAccess.get_open_error())
		return []
	var raw := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(raw) != OK:
		push_warning("[JukeboxMenu] music_manifest.json parse error: %s" % json.get_error_message())
		return []
	if not (json.data is Dictionary) or not json.data.has("tracks"):
		push_warning("[JukeboxMenu] music_manifest.json missing 'tracks' root key")
		return []
	var tracks_map = json.data["tracks"]
	if not (tracks_map is Dictionary):
		push_warning("[JukeboxMenu] music_manifest.json 'tracks' is not a Dictionary")
		return []
	var ids: Array = tracks_map.keys()
	ids.sort()
	var out: Array = []
	for id in ids:
		var entry = tracks_map.get(id, {})
		var title: String = ""
		var duration: float = 0.0
		if entry is Dictionary:
			title = str(entry.get("title", ""))
			duration = float(entry.get("duration", 0.0))
		var display: String = title if title != "" else _titlecase(str(id))
		# Tick 200: duration helps the player skim 150 entries — append "M:SS" when authored (>0 means rendered).
		out.append([str(id), display, duration])
	return out


# Tick 201: prefix-based category lookup so the sorted list reads as vertical color bands. Unknown ids (title, victory, game_over, autogrind, ...) stay TEXT_COLOR.
static func _category_color(track_id: String) -> Color:
	if track_id.begins_with("boss_") or track_id == "boss":
		return CAT_BOSS_COLOR
	if track_id.begins_with("battle_") or track_id == "battle":
		return CAT_BATTLE_COLOR
	if track_id.begins_with("overworld_") or track_id == "overworld":
		return CAT_OVERWORLD_COLOR
	if track_id.begins_with("village_") or track_id == "village":
		return CAT_VILLAGE_COLOR
	if track_id.begins_with("dungeon_") or track_id == "dungeon":
		return CAT_DUNGEON_COLOR
	if track_id.begins_with("danger_") or track_id == "danger":
		return CAT_DANGER_COLOR
	return TEXT_COLOR


# Tick 200: M:SS for non-zero durations; empty string when unrendered (duration 0.0 in manifest signals pending/no-audio).
static func _format_duration(sec: float) -> String:
	if sec <= 0.0:
		return ""
	var total: int = int(round(sec))
	var minutes: int = total / 60
	var seconds: int = total % 60
	return "%d:%02d" % [minutes, seconds]


# Tick 199: proper multi-word title-case (String.capitalize() only does first letter — see tick 186).
static func _titlecase(s: String) -> String:
	if s == "":
		return ""
	var parts: PackedStringArray = s.split("_")
	for i in parts.size():
		if parts[i].length() == 0:
			continue
		parts[i] = parts[i][0].to_upper() + parts[i].substr(1).to_lower()
	return " ".join(parts)


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
	title.add_theme_font_size_override("font_size", TextScale.scaled(18))
	title.add_theme_color_override("font_color", TEXT_COLOR)
	_panel.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "[DEBUG] Music track browser"
	subtitle.position = Vector2(16, 30)
	subtitle.add_theme_font_size_override("font_size", TextScale.scaled(10))
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
		lbl.add_theme_font_size_override("font_size", TextScale.scaled(13))
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
	scroll_up_lbl.add_theme_font_size_override("font_size", TextScale.scaled(12))
	scroll_up_lbl.add_theme_color_override("font_color", DISABLED_COLOR)
	_panel.add_child(scroll_up_lbl)

	var scroll_dn_lbl = Label.new()
	scroll_dn_lbl.name = "ScrollDown"
	scroll_dn_lbl.text = ""
	scroll_dn_lbl.position = Vector2(_panel.size.x - 24, 52 + VISIBLE_ROWS * ROW_HEIGHT - ROW_HEIGHT)
	scroll_dn_lbl.add_theme_font_size_override("font_size", TextScale.scaled(12))
	scroll_dn_lbl.add_theme_color_override("font_color", DISABLED_COLOR)
	_panel.add_child(scroll_dn_lbl)

	# "Now Playing" status bar
	_now_playing_label = Label.new()
	_now_playing_label.position = Vector2(16, _panel.size.y - 48)
	_now_playing_label.size = Vector2(_panel.size.x - 32, 18)
	_now_playing_label.add_theme_font_size_override("font_size", TextScale.scaled(11))
	_now_playing_label.add_theme_color_override("font_color", PLAYING_COLOR)
	_now_playing_label.name = "NowPlaying"
	_panel.add_child(_now_playing_label)
	_refresh_now_playing()

	# Footer
	var footer = Label.new()
	footer.text = "Up/Down: Navigate   A: Play   B: Stop & Back"
	footer.position = Vector2(16, _panel.size.y - 28)
	footer.add_theme_font_size_override("font_size", TextScale.scaled(12))
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
			# Tick 200: append M:SS duration so the player can spot long vs short loops at a glance.
			var display: String = TRACKS[track_idx][1]
			var dur_str: String = _format_duration(TRACKS[track_idx][2] if TRACKS[track_idx].size() > 2 else 0.0)
			_row_labels[i].text = ("%s   ·   %s" % [display, dur_str]) if dur_str != "" else display
			var track_id = TRACKS[track_idx][0]
			# Tick 201: category color band replaces the bare TEXT_COLOR fallback. PLAYING_COLOR still wins for the active track.
			_row_labels[i].add_theme_color_override("font_color",
				PLAYING_COLOR if track_id == _currently_playing else _category_color(track_id))
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
		# Compare against what's ACTUALLY playing right now, not against
		# _currently_playing (which is only set when the user clicks Play
		# inside the jukebox). Pre-fix: if the player opened the jukebox
		# while music was playing and closed without clicking anything,
		# the branch below saw _currently_playing == "" and re-fired
		# play_music(_resume_track) — restarting the SAME track that was
		# already playing seamlessly. Audible hitch on every "just
		# browsed and backed out" close. Comparing against the live
		# current_music makes this branch a true no-op in that case.
		var current_track: String = ""
		if "_current_music" in SoundManager:
			current_track = str(SoundManager._current_music)
		# Resume the track that was playing before the jukebox opened, if any.
		# Falls back to stopping music if there was no prior track.
		if _resume_track != "" and _resume_track != current_track:
			if SoundManager.has_method("play_music"):
				SoundManager.play_music(_resume_track)
		elif _resume_track == "" and current_track != "":
			# Smooth fade rather than hard cut — the jukebox was playing
			# but the player opened it from silent context, so we're
			# returning them to silence. Fade keeps the close from feeling
			# like a buzz-cut. Falls back to stop_music if fade_out_music
			# isn't available (defensive — SoundManager may be mid-refactor).
			if SoundManager.has_method("fade_out_music"):
				SoundManager.fade_out_music(0.4)
			else:
				SoundManager.stop_music()
		SoundManager.play_ui("menu_close")
	closed.emit()
	queue_free()
