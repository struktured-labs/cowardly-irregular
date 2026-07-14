extends Control
class_name TitleScreen

## TitleScreen — atmospheric JRPG title with art background, logo overlay,
## pulsing "PRESS START", and fade-in menu.

signal new_game_selected()
signal continue_selected()
signal settings_selected()

## State machine: PRESS_START → MENU
enum Phase { PRESS_START, MENU }
var _phase: Phase = Phase.PRESS_START

## Menu
var selected_index: int = 0
var menu_items: Array[Dictionary] = []
var _can_input: bool = false
var _menu_container: VBoxContainer = null

## UI refs
var _bg_texture: TextureRect = null
var _logo: TextureRect = null
var _press_start: Label = null
var _press_tween: Tween = null
var _version_label: Label = null
var _stars: Array[ColorRect] = []
var _help_overlay: Control = null
var _help_scroll_target: RichTextLabel = null
const HELP_SCROLL_STEP_PX: float = 48.0

## Colors
const MENU_COLOR := Color(0.95, 0.95, 1.0)
const MENU_SELECTED := Color(1.0, 0.95, 0.5)
const MENU_DISABLED := Color(0.4, 0.4, 0.5)
const CURSOR_COLOR := Color(1.0, 0.9, 0.3)

## Cursor blink
var _cursor_blink: bool = true
var _blink_timer: float = 0.0

# Tick 203: single source of truth for Continue's target slot. Pre-fix _check_for_save (file-existence) and _build_continue_subtitle (metadata-driven get_most_recent_slot) could disagree — a save with missing metadata showed Continue, subtitle was empty, and load attempts went to slot -1.
var _cached_continue_slot: int = -1


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	_build_ui()
	if SoundManager:
		SoundManager.play_music("title")
	await get_tree().create_timer(0.5).timeout
	_can_input = true


func _process(delta: float) -> void:
	# Logo gentle float
	if _logo:
		_logo.position.y = _logo_base_y() + sin(Time.get_ticks_msec() / 1200.0) * 4.0

	# Star twinkle
	for i in _stars.size():
		var star: ColorRect = _stars[i]
		if is_instance_valid(star):
			star.modulate.a = sin(Time.get_ticks_msec() / 400.0 + i * 0.7) * 0.3 + 0.7

	# Cursor blink (menu phase)
	if _phase == Phase.MENU:
		_blink_timer += delta
		if _blink_timer >= 0.4:
			_blink_timer = 0.0
			_cursor_blink = not _cursor_blink
			_update_cursor()


func _build_ui() -> void:
	var vp := _vp_size()

	# Background art (full viewport, aspect-fill)
	_bg_texture = TextureRect.new()
	var bg_tex := load("res://assets/sprites/ui/title_screen.png") as Texture2D
	if bg_tex:
		_bg_texture.texture = bg_tex
	_bg_texture.set_anchors_preset(PRESET_FULL_RECT)
	_bg_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_texture.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_bg_texture)

	# Subtle vignette darken edges
	_add_vignette(vp)

	# Twinkling star particles over the sky area
	_spawn_stars(vp)

	# Logo disabled — title_screen.png already has the title baked in
	_logo = null

	# "PRESS START" disabled — already baked into title_screen.png
	_press_start = null

	# Menu (built hidden, revealed after PRESS START)
	_menu_container = VBoxContainer.new()
	_menu_container.position = Vector2(vp.x / 2 - 100, vp.y * 0.58)
	_menu_container.add_theme_constant_override("separation", 8)
	_menu_container.modulate.a = 0.0
	add_child(_menu_container)
	_build_menu()

	# Version
	_version_label = Label.new()
	_version_label.text = Version.display()
	# 80px clipped "v3.33.1xx-alpha (hash)" off the right edge (title smoke shot 2026-07-11) — right-align in a real box.
	_version_label.position = Vector2(vp.x - 292, vp.y - 28)
	_version_label.size = Vector2(280, 20)
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_version_label.add_theme_font_size_override("font_size", 10)
	_version_label.add_theme_color_override("font_color", Color(0.4, 0.35, 0.5, 0.6))
	add_child(_version_label)


func _logo_base_y() -> float:
	return _vp_size().y * 0.08


func _add_vignette(vp: Vector2) -> void:
	# Top strip
	var top := ColorRect.new()
	top.color = Color(0, 0, 0, 0.25)
	top.position = Vector2.ZERO
	top.size = Vector2(vp.x, vp.y * 0.08)
	top.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(top)
	# Bottom strip (stronger for menu contrast)
	var bottom := ColorRect.new()
	bottom.color = Color(0, 0, 0, 0.45)
	bottom.position = Vector2(0, vp.y * 0.7)
	bottom.size = Vector2(vp.x, vp.y * 0.3)
	bottom.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bottom)


func _spawn_stars(vp: Vector2) -> void:
	"""Tiny twinkling dots in the upper sky portion of the background."""
	_stars.clear()
	var sky_h := vp.y * 0.35
	for i in range(40):
		var star := ColorRect.new()
		var sz := randf_range(1.0, 2.5)
		star.size = Vector2(sz, sz)
		star.position = Vector2(randf() * vp.x, randf() * sky_h)
		star.color = Color(
			randf_range(0.7, 1.0),
			randf_range(0.7, 1.0),
			randf_range(0.85, 1.0),
			randf_range(0.4, 0.9),
		)
		star.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(star)
		_stars.append(star)


func _start_press_pulse() -> void:
	if not _press_start:
		return
	_press_tween = create_tween().set_loops()
	_press_tween.tween_property(_press_start, "modulate:a", 0.3, 1.0).set_trans(Tween.TRANS_SINE)
	_press_tween.tween_property(_press_start, "modulate:a", 1.0, 1.0).set_trans(Tween.TRANS_SINE)


## — Menu building —

func _build_menu() -> void:
	menu_items.clear()
	for child in _menu_container.get_children():
		child.queue_free()

	if _check_for_save():
		menu_items.append({
			"id": "continue",
			"label": "CONTINUE",
			"subtitle": _build_continue_subtitle(),
			"enabled": true,
		})
	menu_items.append({"id": "new_game", "label": "NEW GAME", "enabled": true})
	menu_items.append({"id": "settings", "label": "SETTINGS", "enabled": true})
	menu_items.append({"id": "help", "label": "HELP", "enabled": true})
	menu_items.append({"id": "quit", "label": "QUIT", "enabled": true})

	for i in menu_items.size():
		_menu_container.add_child(_create_menu_row(i, menu_items[i]))
	_update_selection()


func _create_menu_row(index: int, item: Dictionary) -> Control:
	var row := Control.new()
	# Continue rows surface a save-context subtitle below the main label,
	# so they need extra vertical room. Other items stay at the original
	# compact height so the menu reads tightly.
	var subtitle: String = str(item.get("subtitle", ""))
	var row_h: int = 44 if subtitle != "" else 28
	row.custom_minimum_size = Vector2(360, row_h)
	row.name = "MenuItem_%d" % index
	row.mouse_filter = MOUSE_FILTER_STOP
	row.mouse_entered.connect(_on_menu_hover.bind(index))
	row.gui_input.connect(_on_menu_click.bind(index))

	var cursor := Label.new()
	cursor.name = "Cursor"
	cursor.text = "▸"
	cursor.position = Vector2(0, 2)
	cursor.add_theme_font_size_override("font_size", 18)
	cursor.add_theme_color_override("font_color", CURSOR_COLOR)
	cursor.visible = (index == selected_index)
	cursor.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(cursor)

	var label := Label.new()
	label.name = "Label"
	label.text = item.label
	label.position = Vector2(24, 2)
	label.add_theme_font_size_override("font_size", 18)
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color",
		(MENU_SELECTED if index == selected_index else MENU_COLOR) if item.enabled else MENU_DISABLED)
	row.add_child(label)

	if subtitle != "":
		var sub := Label.new()
		sub.name = "Subtitle"
		sub.text = subtitle
		sub.position = Vector2(40, 22)
		sub.size = Vector2(320, 16)
		sub.add_theme_font_size_override("font_size", 11)
		sub.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8, 0.85))
		sub.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_child(sub)

	return row


func _update_selection() -> void:
	for i in _menu_container.get_child_count():
		var row := _menu_container.get_child(i)
		var cursor := row.get_node_or_null("Cursor")
		var label := row.get_node_or_null("Label")
		var is_sel := (i == selected_index)
		if cursor:
			cursor.visible = is_sel and _cursor_blink
		if label and i < menu_items.size():
			if menu_items[i].enabled:
				label.add_theme_color_override("font_color", MENU_SELECTED if is_sel else MENU_COLOR)


func _update_cursor() -> void:
	if selected_index < _menu_container.get_child_count():
		var row := _menu_container.get_child(selected_index)
		var cursor := row.get_node_or_null("Cursor")
		if cursor:
			cursor.visible = _cursor_blink


## — Phase transitions —

func _transition_to_menu() -> void:
	_phase = Phase.MENU
	# Kill press-start pulse, fade it out
	if _press_tween and _press_tween.is_valid():
		_press_tween.kill()
	if _press_start:
		var fade_out := create_tween()
		fade_out.tween_property(_press_start, "modulate:a", 0.0, 0.3)
	# Fade in menu
	var fade_in := create_tween()
	fade_in.tween_property(_menu_container, "modulate:a", 1.0, 0.5).set_delay(0.2)
	if SoundManager:
		SoundManager.play_ui("menu_select")


## — Input —

func _input(event: InputEvent) -> void:
	if not _can_input:
		return

	# Help overlay intercept — cancel closes; up/down scroll the long content via controller.
	if _help_overlay:
		if event.is_action_pressed("ui_cancel"):
			_close_help_overlay()
			get_viewport().set_input_as_handled()
			return
		var dy: float = 0.0
		if event.is_action_pressed("ui_down"):
			dy = HELP_SCROLL_STEP_PX
		elif event.is_action_pressed("ui_up"):
			dy = -HELP_SCROLL_STEP_PX
		if dy != 0.0:
			_scroll_help(dy)
			get_viewport().set_input_as_handled()
			return

	if _phase == Phase.PRESS_START:
		# Accept gamepad/keyboard confirm/start, OR a mouse click anywhere
		# (modern players reach for the mouse before figuring out the
		# keyboard binding). Fix 2026-05-03 per accessibility audit.
		var clicked = (event is InputEventMouseButton
			and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT)
		if (event.is_action_pressed("ui_accept")
				or event.is_action_pressed("ui_menu")
				or clicked):
			_transition_to_menu()
			get_viewport().set_input_as_handled()
		return

	# MENU phase
	if event.is_action_pressed("ui_up") and not event.is_echo():
		_move_selection(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down") and not event.is_echo():
		_move_selection(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		_select_item()
		get_viewport().set_input_as_handled()


func _move_selection(delta: int) -> void:
	var old := selected_index
	selected_index = clampi(selected_index + delta, 0, menu_items.size() - 1)
	while selected_index >= 0 and selected_index < menu_items.size():
		if menu_items[selected_index].enabled:
			break
		selected_index += delta
	selected_index = clampi(selected_index, 0, menu_items.size() - 1)
	if selected_index != old:
		if SoundManager:
			SoundManager.play_ui("menu_move")
		_update_selection()


func _select_item() -> void:
	if selected_index >= menu_items.size():
		return
	var item := menu_items[selected_index]
	if not item.enabled:
		return
	if SoundManager:
		SoundManager.play_ui("menu_select")
	match item.id:
		"new_game":
			new_game_selected.emit()
		"continue":
			continue_selected.emit()
		"settings":
			settings_selected.emit()
		"help":
			_show_help_overlay()
		"quit":
			# Title-screen quit. Skip the in-game "Quit to Title" confirmation
			# flow — there's no game in progress to lose.
			get_tree().quit()


func _on_menu_hover(index: int) -> void:
	if not _can_input or _phase != Phase.MENU or index >= menu_items.size():
		return
	if menu_items[index].enabled and index != selected_index:
		selected_index = index
		_update_selection()
		if SoundManager:
			SoundManager.play_ui("menu_move")


func _on_menu_click(event: InputEvent, index: int) -> void:
	if not _can_input or _phase != Phase.MENU or index >= menu_items.size():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if menu_items[index].enabled:
			selected_index = index
			_update_selection()
			_select_item()
			get_viewport().set_input_as_handled()


## — Helpers —

func _check_for_save() -> bool:
	# Tick 203: use get_most_recent_slot as the single source of truth — its
	# semantics (a save WITH METADATA exists) match what Continue actually
	# needs. has_save() (file-existence only) could disagree, showing
	# Continue for a save the load path couldn't actually parse.
	_cached_continue_slot = -1
	if SaveSystem and SaveSystem.has_method("get_most_recent_slot"):
		_cached_continue_slot = SaveSystem.get_most_recent_slot()
		return _cached_continue_slot >= 0
	# Fallback when SaveSystem isn't ready yet (very early boot path). These
	# file-existence checks remain as a safety net — better to show Continue
	# than to hide it on a transient autoload race.
	if FileAccess.file_exists("user://save_data.json"):
		return true
	if FileAccess.file_exists("user://saves/save_00.json"):
		return true
	return false


func _build_continue_subtitle() -> String:
	## Peek at the most-recent save's metadata to surface "where will I
	## resume?" on the title screen. Returns an empty string if the save
	## is missing, lacks metadata, or SaveSystem isn't available — in
	## which case the row falls back to the bare "CONTINUE" label.
	if not SaveSystem:
		return ""
	# Tick 203: prefer the cached slot from _check_for_save (called immediately before this by _build_menu) so subtitle and load target stay consistent. Fall back to a fresh lookup if cache is empty (e.g., very early boot path).
	var slot: int = _cached_continue_slot
	if slot < 0 and SaveSystem.has_method("get_most_recent_slot"):
		slot = SaveSystem.get_most_recent_slot()
	if slot < 0:
		return ""
	# Tick 202: slot label is always shown when we have one — players need to know whether Continue resumes Slot 2, a Quick Save, or an Auto-Save. Pre-fix the choice was silent.
	var slot_label: String = _format_continue_slot_label(slot)
	if not SaveSystem.has_method("get_save_info"):
		return slot_label
	var info: Dictionary = SaveSystem.get_save_info(slot)
	if info.is_empty():
		return slot_label
	# Prefer chapter + location together when both exist; degrade gracefully
	# to whichever piece IS available so the subtitle is never half-formed.
	var location: String = str(info.get("location_name", "")).strip_edges()
	var chapter: String = str(info.get("chapter_title", "")).strip_edges()
	var detail: String = ""
	if chapter != "" and location != "":
		detail = "%s — %s" % [chapter, location]
	elif location != "":
		detail = location
	elif chapter != "":
		detail = chapter
	if slot_label == "":
		return detail
	if detail == "":
		return slot_label
	return "%s · %s" % [slot_label, detail]


# Tick 202: map slot int → human label. SaveSystem.AUTO_SAVE_SLOT=98, QUICK_SAVE_SLOT=99, 0..2 are manual.
static func _format_continue_slot_label(slot: int) -> String:
	if slot < 0:
		return ""
	if SaveSystem:
		if "QUICK_SAVE_SLOT" in SaveSystem and slot == SaveSystem.QUICK_SAVE_SLOT:
			return "Quick Save"
		if "AUTO_SAVE_SLOT" in SaveSystem and slot == SaveSystem.AUTO_SAVE_SLOT:
			return "Auto-Save"
	return "Slot %d" % (slot + 1)


func _vp_size() -> Vector2:
	var vp := get_viewport_rect().size
	if vp.x <= 0 or vp.y <= 0:
		vp = Vector2(1280, 720)
	return vp


## — Help overlay (unchanged) —

func _show_help_overlay() -> void:
	if _help_overlay:
		return
	_can_input = false
	_help_overlay = Control.new()
	_help_overlay.set_anchors_preset(PRESET_FULL_RECT)
	_help_overlay.z_index = 50
	add_child(_help_overlay)

	var bg := ColorRect.new()
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.05, 0.92)
	bg.mouse_filter = MOUSE_FILTER_STOP
	_help_overlay.add_child(bg)

	var vp := _vp_size()
	var title := Label.new()
	title.text = "HOW TO PLAY"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(vp.x / 2 - 120, 30)
	title.size = Vector2(240, 30)
	_help_overlay.add_child(title)

	var content := RichTextLabel.new()
	_help_scroll_target = content
	content.bbcode_enabled = true
	content.scroll_active = true
	content.position = Vector2(60, 75)
	content.size = Vector2(vp.x - 120, vp.y - 120)
	content.add_theme_font_size_override("normal_font_size", 13)
	content.add_theme_font_size_override("bold_font_size", 14)
	content.add_theme_color_override("default_color", Color(0.9, 0.9, 0.95))
	content.text = """[b][color=yellow]CONTROLS[/color][/b]
[color=gray]Gamepad          Keyboard          Mouse[/color]
D-Pad             Arrow Keys        —                Navigate
A Button          Z / Enter         L-Click          Confirm / Select
B Button          X / Escape        R-Click          Cancel / Back
L Shoulder        L Key             —                Defer / Party Chat
R Shoulder        R Key             —                Advance (queue action)
Start (Plus)      F5                —                Open Autobattle Editor
Back (Minus)      F6                —                Toggle Autobattle
                  F2                —                Quick Save
                  F3                —                Quick Load
                  F12               —                Screenshot
                  ─                 Wheel            Scroll lists / change selection

[b][color=yellow]BATTLE SYSTEM (CTB)[/color][/b]
Each turn you choose: [color=lime]Attack[/color], use [color=cyan]Magic[/color], or strategize with AP.

[color=white]AP (Action Points)[/color] range from -4 to +4.
  [color=lime]Defer (L)[/color]: Skip your turn. Gain +1 AP, take less damage.
  [color=cyan]Advance (R)[/color]: Queue extra actions. Each costs 1 AP.
    Queue up to 4 actions, then they all execute at once!

[b][color=yellow]AUTOBATTLE[/color][/b]
This game is designed to be automated!
Open the [color=lime]Autobattle Editor[/color] (Start/F5) to write rules:
  IF [condition] THEN [action]
Rules are checked top-to-bottom. First match wins.
Toggle autobattle per character with Select/F6.

[b][color=yellow]PARTY CHAT[/color][/b]
Press [color=lime]L[/color] during exploration when the indicator appears to access
optional story conversations. These are flavor, not required.

[b][color=yellow]TIPS[/color][/b]
- Deferring builds AP for powerful multi-action turns later
- Queue multiple heals or attacks with Advance for burst plays
- Autobattle scripts run automatically — master them to win!
- Visit inns to heal and save your progress
- Check the Bestiary and World Map from the pause menu

[color=gray]Press B / X / Escape / Right-click to close[/color]"""
	_help_overlay.add_child(content)
	# Right-click anywhere closes the overlay (in addition to Esc / B).
	# Wire on the bg ColorRect we added above.
	bg.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
			_close_help_overlay()
			get_viewport().set_input_as_handled()
	)
	await get_tree().create_timer(0.3).timeout
	_can_input = true


func _close_help_overlay() -> void:
	if _help_overlay:
		_help_overlay.queue_free()
		_help_overlay = null
		_help_scroll_target = null
		_can_input = true  # Restore input ability after close


## Scroll the open help overlay's content by `dy` pixels (positive = down).
func _scroll_help(dy: float) -> void:
	if _help_scroll_target == null or not is_instance_valid(_help_scroll_target):
		return
	var sb := _help_scroll_target.get_v_scroll_bar()
	if sb == null:
		return
	sb.value = clampf(sb.value + dy, sb.min_value, max(sb.min_value, sb.max_value - sb.page))


func _exit_tree() -> void:
	# Kill any looping press-start pulse tween so it doesn't outlive the node.
	if _press_tween and _press_tween.is_valid():
		_press_tween.kill()
	_press_tween = null
