extends CanvasLayer
class_name CutsceneDirector

## CutsceneDirector - Orchestrates cutscene sequences using await/signal patterns.
## Manages dialogue, camera, character movement, screen effects, and input blocking.
## Cutscenes are driven by JSON data files in data/cutscenes/.

signal cutscene_started(cutscene_id: String)
signal cutscene_finished(cutscene_id: String)
signal cutscene_skipped(cutscene_id: String)

## Current state
var _active: bool = false
var _cutscene_id: String = ""
var _skipping: bool = false
var _fast_forward: bool = false
var _skip_hold_time: float = 0.0

## Letterbox bars
var _letterbox_top: ColorRect
var _letterbox_bottom: ColorRect
var _letterbox_visible: bool = false

## Skip indicator
var _skip_indicator: Control
var _skip_label: Label
var _skip_bar: ColorRect
var _skip_bar_bg: ColorRect

## Dialogue reference (created on demand)
var _dialogue: Node = null

## Background layer (captured screenshot or solid color behind dialogue)
var _background_texture: TextureRect
var _background_dim: ColorRect

## Screen effects overlay
var _effects_rect: ColorRect

## Camera state (for restoring after cutscene)
var _original_camera_zoom: Vector2 = Vector2.ONE
var _original_camera_position: Vector2 = Vector2.ZERO

## Configuration
const LETTERBOX_HEIGHT: int = 40
const LETTERBOX_ANIM_DURATION: float = 0.4
const SKIP_THRESHOLD: float = 1.5
const SKIP_BAR_WIDTH: float = 120.0
const SKIP_BAR_HEIGHT: float = 6.0

## Per-world backdrop colors (top, bottom gradient) for cutscenes without game scene behind them
const WORLD_BACKDROP_COLORS = {
	1: [Color(0.08, 0.12, 0.22), Color(0.15, 0.20, 0.10)],  # Medieval: dark blue sky → dark green
	2: [Color(0.10, 0.15, 0.25), Color(0.18, 0.15, 0.12)],  # Suburban: dusk blue → warm brown
	3: [Color(0.15, 0.10, 0.05), Color(0.20, 0.12, 0.08)],  # Steampunk: dark amber → copper
	4: [Color(0.10, 0.10, 0.10), Color(0.15, 0.15, 0.15)],  # Industrial: dark gray → gray
	5: [Color(0.02, 0.08, 0.05), Color(0.05, 0.15, 0.08)],  # Digital: near-black → dark green
	6: [Color(0.15, 0.15, 0.18), Color(0.20, 0.20, 0.22)],  # Abstract: soft dark gray → lighter
}

## Current cutscene world (for backdrop color fallback)
var _current_world: int = 0


func _ready() -> void:
	layer = 95  # Above game (50), below battle transitions (100)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false


func _build_ui() -> void:
	# Background layer — captures viewport screenshot as backdrop behind dialogue
	_background_texture = TextureRect.new()
	_background_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background_texture.visible = false
	add_child(_background_texture)

	_background_dim = ColorRect.new()
	_background_dim.color = Color(0, 0, 0, 0.5)
	_background_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background_dim.visible = false
	add_child(_background_dim)

	# Letterbox bars
	_letterbox_top = ColorRect.new()
	_letterbox_top.color = Color.BLACK
	_letterbox_top.position = Vector2(0, -LETTERBOX_HEIGHT)
	_letterbox_top.size = Vector2(1280, LETTERBOX_HEIGHT)
	_letterbox_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_letterbox_top)

	_letterbox_bottom = ColorRect.new()
	_letterbox_bottom.color = Color.BLACK
	_letterbox_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_letterbox_bottom)

	# Skip indicator (top-right corner)
	_skip_indicator = Control.new()
	_skip_indicator.visible = false
	add_child(_skip_indicator)

	_skip_label = Label.new()
	_skip_label.text = "Hold B to skip..."
	_skip_label.add_theme_font_size_override("font_size", 11)
	_skip_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.8))
	_skip_indicator.add_child(_skip_label)

	_skip_bar_bg = ColorRect.new()
	_skip_bar_bg.color = Color(0.2, 0.2, 0.2, 0.6)
	_skip_bar_bg.size = Vector2(SKIP_BAR_WIDTH, SKIP_BAR_HEIGHT)
	_skip_indicator.add_child(_skip_bar_bg)

	_skip_bar = ColorRect.new()
	_skip_bar.color = Color(0.8, 0.6, 0.2, 0.9)
	_skip_bar.size = Vector2(0, SKIP_BAR_HEIGHT)
	_skip_indicator.add_child(_skip_bar)

	# Effects overlay (for flashes, fades, etc.)
	_effects_rect = ColorRect.new()
	_effects_rect.color = Color(1, 1, 1, 0)
	_effects_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_effects_rect.visible = false
	add_child(_effects_rect)

	_update_layout()


func _update_layout() -> void:
	var screen_size = get_viewport().get_visible_rect().size

	_background_texture.position = Vector2.ZERO
	_background_texture.size = screen_size
	_background_dim.position = Vector2.ZERO
	_background_dim.size = screen_size

	_letterbox_top.size.x = screen_size.x
	_letterbox_bottom.size = Vector2(screen_size.x, LETTERBOX_HEIGHT)
	_letterbox_bottom.position = Vector2(0, screen_size.y)

	_skip_indicator.position = Vector2(screen_size.x - SKIP_BAR_WIDTH - 16, 8)
	_skip_label.position = Vector2(0, 0)
	_skip_bar_bg.position = Vector2(0, 18)
	_skip_bar.position = Vector2(0, 18)

	_effects_rect.position = Vector2.ZERO
	_effects_rect.size = screen_size


func _process(delta: float) -> void:
	if not _active:
		return

	# Handle skip input (hold B/X/Escape)
	var skip_pressed = Input.is_action_pressed("ui_cancel")
	if skip_pressed and not _skipping:
		_skip_hold_time += delta
		_skip_indicator.visible = true
		_skip_bar.size.x = minf((_skip_hold_time / SKIP_THRESHOLD) * SKIP_BAR_WIDTH, SKIP_BAR_WIDTH)
		if _skip_hold_time >= SKIP_THRESHOLD:
			_trigger_skip()
	else:
		if not skip_pressed:
			_skip_hold_time = 0.0
			_skip_indicator.visible = false
			_skip_bar.size.x = 0


## =====================
## PUBLIC API
## =====================

func is_active() -> bool:
	return _active


func play_cutscene(cutscene_id: String) -> void:
	"""Load and play a cutscene from data/cutscenes/<cutscene_id>.json"""
	var data = _load_cutscene_data(cutscene_id)
	if data.is_empty():
		push_error("CutsceneDirector: Failed to load cutscene '%s'" % cutscene_id)
		return

	_cutscene_id = cutscene_id
	_active = true
	_skipping = false
	_fast_forward = false
	_skip_hold_time = 0.0
	_current_world = data.get("world", 0)
	visible = true

	# Capture current viewport as backdrop behind dialogue
	await _capture_background()

	cutscene_started.emit(cutscene_id)

	# Block player input
	_freeze_player()

	# Execute steps
	var steps = data.get("steps", [])
	for step in steps:
		if _skipping:
			break
		await _execute_step(step)

	# Cleanup
	await _end_cutscene()


func play_cutscene_from_data(cutscene_id: String, data: Dictionary) -> void:
	"""Play a cutscene from an in-memory dictionary (no file load)."""
	_cutscene_id = cutscene_id
	_active = true
	_skipping = false
	_fast_forward = false
	_skip_hold_time = 0.0
	_current_world = data.get("world", 0)
	visible = true

	await _capture_background()
	cutscene_started.emit(cutscene_id)
	_freeze_player()

	var steps = data.get("steps", [])
	for step in steps:
		if _skipping:
			break
		await _execute_step(step)

	await _end_cutscene()


## =====================
## STEP EXECUTION
## =====================

func _execute_step(step: Dictionary) -> void:
	var step_type = step.get("type", "")
	match step_type:
		"dialogue":
			await _step_dialogue(step)
		"narration":
			await _step_narration(step)
		"fade_to_black":
			await _step_fade_to_black(step)
		"fade_from_black":
			await _step_fade_from_black(step)
		"wait":
			await _step_wait(step)
		"letterbox_in":
			await _step_letterbox_in(step)
		"letterbox_out":
			await _step_letterbox_out(step)
		"screen_shake":
			await _step_screen_shake(step)
		"screen_flash":
			await _step_screen_flash(step)
		"play_music":
			_step_play_music(step)
		"stop_music":
			_step_stop_music(step)
		"play_sfx":
			_step_play_sfx(step)
		"set_flag":
			_step_set_flag(step)
		"set_background":
			_step_set_background(step)
		"branch":
			await _step_branch(step)
		_:
			push_warning("CutsceneDirector: Unknown step type '%s'" % step_type)


## =====================
## STEP IMPLEMENTATIONS
## =====================

func _step_dialogue(step: Dictionary) -> void:
	"""Show dialogue lines with speakers and themes."""
	var lines = step.get("lines", [])
	if lines.is_empty():
		return

	var dialogue = _get_or_create_dialogue()
	dialogue.show_dialogue(lines)
	await dialogue.dialogue_finished


func _step_narration(step: Dictionary) -> void:
	"""Show narration text (no portrait, narrator theme)."""
	var text = step.get("text", "")
	var lines_array: Array = []

	if step.has("lines"):
		# Multiple narration lines
		for line_text in step.get("lines", []):
			lines_array.append({
				"speaker": "",
				"text": line_text,
				"theme": "narrator",
				"portrait": "narrator"
			})
	else:
		# Single narration
		lines_array.append({
			"speaker": "",
			"text": text,
			"theme": "narrator",
			"portrait": "narrator"
		})

	var dialogue = _get_or_create_dialogue()
	dialogue.show_dialogue(lines_array)
	await dialogue.dialogue_finished


func _step_fade_to_black(step: Dictionary) -> void:
	var duration = step.get("duration", 0.5)
	if _skipping:
		_effects_rect.visible = true
		_effects_rect.color = Color(0, 0, 0, 1)
		return

	_effects_rect.visible = true
	_effects_rect.color = Color(0, 0, 0, 0)
	var tween = create_tween()
	tween.tween_property(_effects_rect, "color", Color(0, 0, 0, 1), duration)
	await tween.finished


func _step_fade_from_black(step: Dictionary) -> void:
	var duration = step.get("duration", 0.5)
	if _skipping:
		_effects_rect.color = Color(0, 0, 0, 0)
		_effects_rect.visible = false
		return

	_effects_rect.visible = true
	_effects_rect.color = Color(0, 0, 0, 1)
	var tween = create_tween()
	tween.tween_property(_effects_rect, "color", Color(0, 0, 0, 0), duration)
	await tween.finished
	_effects_rect.visible = false


func _step_wait(step: Dictionary) -> void:
	var duration = step.get("duration", 1.0)
	if _skipping:
		return
	await get_tree().create_timer(duration).timeout


func _step_letterbox_in(step: Dictionary) -> void:
	var duration = step.get("duration", LETTERBOX_ANIM_DURATION)
	if _skipping:
		_apply_letterbox(true)
		return

	var screen_size = get_viewport().get_visible_rect().size
	var tween = create_tween().set_parallel(true)
	tween.tween_property(_letterbox_top, "position:y", 0.0, duration)
	tween.tween_property(_letterbox_bottom, "position:y", screen_size.y - LETTERBOX_HEIGHT, duration)
	await tween.finished
	_letterbox_visible = true


func _step_letterbox_out(step: Dictionary) -> void:
	var duration = step.get("duration", LETTERBOX_ANIM_DURATION)
	if _skipping:
		_apply_letterbox(false)
		return

	var screen_size = get_viewport().get_visible_rect().size
	var tween = create_tween().set_parallel(true)
	tween.tween_property(_letterbox_top, "position:y", float(-LETTERBOX_HEIGHT), duration)
	tween.tween_property(_letterbox_bottom, "position:y", screen_size.y, duration)
	await tween.finished
	_letterbox_visible = false


func _step_screen_shake(step: Dictionary) -> void:
	var duration = step.get("duration", 0.3)
	var intensity = step.get("intensity", 4.0)
	if _skipping:
		return

	var camera = get_viewport().get_camera_2d()
	if not camera:
		return

	var original_offset = camera.offset
	var shake_tween = create_tween()
	var steps_count = int(duration / 0.05)
	for i in range(steps_count):
		var offset = Vector2(
			randf_range(-intensity, intensity),
			randf_range(-intensity, intensity)
		)
		shake_tween.tween_property(camera, "offset", original_offset + offset, 0.05)
	shake_tween.tween_property(camera, "offset", original_offset, 0.05)
	await shake_tween.finished


func _step_screen_flash(step: Dictionary) -> void:
	var duration = step.get("duration", 0.15)
	var color = Color.WHITE
	if step.has("color"):
		color = Color(step["color"])
	if _skipping:
		return

	_effects_rect.visible = true
	_effects_rect.color = color
	var tween = create_tween()
	tween.tween_property(_effects_rect, "color:a", 0.0, duration)
	await tween.finished
	_effects_rect.visible = false


func _step_play_music(step: Dictionary) -> void:
	var track = step.get("track", "")
	if track != "" and SoundManager:
		SoundManager.play_music(track)


func _step_stop_music(_step: Dictionary) -> void:
	if SoundManager:
		SoundManager.stop_music()


func _step_play_sfx(step: Dictionary) -> void:
	var sfx = step.get("sfx", "")
	if sfx != "" and SoundManager:
		SoundManager.play_ui(sfx)


func _step_set_flag(step: Dictionary) -> void:
	var flag = step.get("flag", "")
	var value = step.get("value", true)
	if flag != "":
		# Store cutscene flags in game_constants for now
		if GameState:
			GameState.game_constants["cutscene_flag_" + flag] = value


func _step_branch(step: Dictionary) -> void:
	"""Execute different sub-steps based on a condition.
	Usage: {"type": "branch", "condition": "playstyle", "cases": {
	  "automator": [steps...], "grinder": [steps...], "default": [steps...]
	}}
	Or flag-based: {"type": "branch", "flag": "some_flag", "if_true": [steps...], "if_false": [steps...]}"""
	if step.has("flag"):
		# Flag-based branching
		var flag = step.get("flag", "")
		var flag_value = false
		if GameState and GameState.game_constants.has("cutscene_flag_" + flag):
			flag_value = GameState.game_constants["cutscene_flag_" + flag]
		var branch_steps = step.get("if_true", []) if flag_value else step.get("if_false", [])
		for sub_step in branch_steps:
			if _skipping:
				break
			await _execute_step(sub_step)
	elif step.get("condition", "") == "playstyle":
		# Playstyle-based branching
		var playstyle = _detect_playstyle()
		var cases = step.get("cases", {})
		var branch_steps = cases.get(playstyle, cases.get("default", []))
		for sub_step in branch_steps:
			if _skipping:
				break
			await _execute_step(sub_step)


func _detect_playstyle() -> String:
	"""Detect the dominant playstyle based on game stats.
	Returns: 'automator', 'manual', 'grinder', 'exploiter', or 'balanced'."""
	var autobattle_ratio: float = 0.0
	var total_battles: int = 0

	if SaveSystem and SaveSystem.autobattle_records:
		var auto_count: int = 0
		for key in SaveSystem.autobattle_records:
			auto_count += SaveSystem.autobattle_records[key].get("count", 0)
		if BattleManager and "total_battles_won" in BattleManager:
			total_battles = BattleManager.total_battles_won
		if total_battles > 0:
			autobattle_ratio = float(auto_count) / float(total_battles)

	# High automation rate → automator
	if autobattle_ratio > 0.7 and total_battles >= 20:
		return "automator"

	# High total battles → grinder
	if total_battles > 100:
		return "grinder"

	# Check for exploit-style play (low battles, high level — efficient)
	if total_battles > 0 and total_battles < 40:
		return "exploiter"

	# Mostly manual play
	if autobattle_ratio < 0.3 and total_battles >= 20:
		return "manual"

	return "balanced"


## =====================
## BACKGROUND MANAGEMENT
## =====================

func _capture_background() -> void:
	"""Capture current viewport as a dimmed backdrop behind cutscene dialogue.
	Falls back to a world-themed gradient if viewport is blank (e.g., prologue before overworld)."""
	var viewport = get_viewport()
	if not viewport:
		_apply_world_gradient()
		return

	# Wait one frame for the viewport to be fully rendered
	await get_tree().process_frame

	var img = viewport.get_texture().get_image()
	if img:
		# Check if the captured image is mostly black/blank (pre-overworld)
		var sample_colors: Array[Color] = []
		var w = img.get_width()
		var h = img.get_height()
		if w > 0 and h > 0:
			# Sample 9 points across the image
			for sx in [w / 4, w / 2, w * 3 / 4]:
				for sy in [h / 4, h / 2, h * 3 / 4]:
					sample_colors.append(img.get_pixel(sx, sy))

		var total_brightness: float = 0.0
		for c in sample_colors:
			total_brightness += c.r + c.g + c.b
		var avg_brightness = total_brightness / max(sample_colors.size() * 3.0, 1.0)

		if avg_brightness < 0.05:
			# Image is effectively black — use world gradient instead
			_apply_world_gradient()
		else:
			var tex = ImageTexture.create_from_image(img)
			_background_texture.texture = tex
			_background_texture.visible = true
			_background_dim.visible = true
	else:
		_apply_world_gradient()


func _apply_world_gradient() -> void:
	"""Apply a procedural gradient backdrop based on the current cutscene's world."""
	var colors = WORLD_BACKDROP_COLORS.get(_current_world, [Color(0.08, 0.08, 0.12), Color(0.12, 0.12, 0.15)])
	var top_color: Color = colors[0]
	var bottom_color: Color = colors[1]

	# Create a small gradient image and scale it up
	var gradient_height: int = 256
	var gradient_width: int = 2
	var img = Image.create(gradient_width, gradient_height, false, Image.FORMAT_RGBA8)
	for y in range(gradient_height):
		var t = float(y) / float(gradient_height - 1)
		var c = top_color.lerp(bottom_color, t)
		for x in range(gradient_width):
			img.set_pixel(x, y, c)

	var tex = ImageTexture.create_from_image(img)
	_background_texture.texture = tex
	_background_texture.visible = true
	# Don't show dim overlay on procedural gradients — they're already dark
	_background_dim.visible = false


func _step_set_background(step: Dictionary) -> void:
	"""Set a custom backdrop color/gradient mid-cutscene.
	Usage: {"type": "set_background", "color": "#1a2030"}
	   or: {"type": "set_background", "top": "#1a2030", "bottom": "#2a3040"}"""
	if step.has("color"):
		var c = Color(step["color"])
		var img = Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(c)
		_background_texture.texture = ImageTexture.create_from_image(img)
		_background_texture.visible = true
		_background_dim.visible = false
	elif step.has("top") and step.has("bottom"):
		var top_c = Color(step["top"])
		var bottom_c = Color(step["bottom"])
		var img = Image.create(2, 256, false, Image.FORMAT_RGBA8)
		for y in range(256):
			var t = float(y) / 255.0
			var c = top_c.lerp(bottom_c, t)
			img.set_pixel(0, y, c)
			img.set_pixel(1, y, c)
		_background_texture.texture = ImageTexture.create_from_image(img)
		_background_texture.visible = true
		_background_dim.visible = false


func _clear_background() -> void:
	"""Hide the background capture."""
	_background_texture.visible = false
	_background_dim.visible = false
	_background_texture.texture = null


## =====================
## DIALOGUE MANAGEMENT
## =====================

func _get_or_create_dialogue() -> Node:
	if _dialogue and is_instance_valid(_dialogue):
		return _dialogue

	var CutsceneDialogueClass = load("res://src/cutscene/CutsceneDialogue.gd")
	_dialogue = CutsceneDialogueClass.new()
	add_child(_dialogue)
	return _dialogue


## =====================
## SKIP SYSTEM
## =====================

func _trigger_skip() -> void:
	_skipping = true
	_skip_indicator.visible = false

	# Dismiss any active dialogue
	if _dialogue and is_instance_valid(_dialogue) and _dialogue.visible:
		_dialogue.skip_all()

	cutscene_skipped.emit(_cutscene_id)


## =====================
## PLAYER INPUT BLOCKING
## =====================

func _freeze_player() -> void:
	var player = MapSystem.get_player() if MapSystem else null
	if player and player.has_method("set_can_move"):
		player.set_can_move(false)


func _unfreeze_player() -> void:
	var player = MapSystem.get_player() if MapSystem else null
	if player and player.has_method("set_can_move"):
		player.set_can_move(true)


## =====================
## LETTERBOX HELPERS
## =====================

func _apply_letterbox(show: bool) -> void:
	var screen_size = get_viewport().get_visible_rect().size
	if show:
		_letterbox_top.position.y = 0
		_letterbox_bottom.position.y = screen_size.y - LETTERBOX_HEIGHT
	else:
		_letterbox_top.position.y = -LETTERBOX_HEIGHT
		_letterbox_bottom.position.y = screen_size.y
	_letterbox_visible = show


## =====================
## CUTSCENE LIFECYCLE
## =====================

func _end_cutscene() -> void:
	# Hide letterbox if still showing
	if _letterbox_visible:
		await _step_letterbox_out({"duration": 0.3 if not _skipping else 0.0})

	# Clear effects and background
	_effects_rect.visible = false
	_effects_rect.color = Color(0, 0, 0, 0)
	_clear_background()

	# Destroy dialogue
	if _dialogue and is_instance_valid(_dialogue):
		_dialogue.queue_free()
		_dialogue = null

	# Restore player control
	_unfreeze_player()

	_active = false
	visible = false
	cutscene_finished.emit(_cutscene_id)
	_cutscene_id = ""
	_skipping = false


## =====================
## DATA LOADING
## =====================

func _load_cutscene_data(cutscene_id: String) -> Dictionary:
	var path = "res://data/cutscenes/%s.json" % cutscene_id
	if not FileAccess.file_exists(path):
		push_error("CutsceneDirector: Cutscene file not found: %s" % path)
		return {}

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("CutsceneDirector: Failed to open: %s" % path)
		return {}

	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	file.close()

	if error != OK:
		push_error("CutsceneDirector: JSON parse error in %s: %s" % [path, json.get_error_message()])
		return {}

	return json.data if json.data is Dictionary else {}
