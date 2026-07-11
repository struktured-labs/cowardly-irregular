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
# abort ≠ skip: finished still emits (awaiters unblock) but the completion flag is withheld so the cutscene replays
var _aborted: bool = false
var _last_finished_aborted: bool = false
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
var _skip_pill_bg: ColorRect

## Dialogue reference (created on demand)
var _dialogue: Node = null

## Background layer (captured screenshot or solid color behind dialogue)
var _background_texture: TextureRect
var _background_dim: ColorRect

## Video backdrop (animated background, takes priority over static image)
var _background_video: VideoStreamPlayer = null

## Screen effects overlay
var _effects_rect: ColorRect

## Camera state (for restoring after cutscene)
var _original_camera_zoom: Vector2 = Vector2.ONE
var _original_camera_position: Vector2 = Vector2.ZERO

## Configuration
const LETTERBOX_HEIGHT: int = 40
const LETTERBOX_ANIM_DURATION: float = 0.4
const SKIP_THRESHOLD: float = 1.5
const SKIP_BAR_WIDTH: float = 220.0
const SKIP_BAR_HEIGHT: float = 10.0
const SKIP_PILL_PAD: float = 12.0
const SKIP_PILL_HEIGHT: float = 48.0

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

## Pre-cutscene music track (restored after cutscene if no explicit music was played)
var _pre_cutscene_music: String = ""

## HUD countdown timer — driven by cutscene start_timer / stop_timer steps.
## Spec from cowir-story: atmospheric only, never a fail state. Small
## corner monospace label that ticks down in real time during cutscene
## dialogue. The actual underlying duration is intentionally longer than
## the dialogue's run-length so the countdown stays in the high numbers
## throughout (W4 orrery: 300s countdown, ~10 lines of dialogue between
## start_timer/stop_timer = ~30 seconds of player time).
var _timer_label: Label = null
var _timer_remaining: float = 0.0
var _timer_flag: String = ""

## Staged-mode state (presentation:"staged" — CT-style live-world scene direction).
var _staged: bool = false
var _actors: Dictionary = {}
var _stage_hidden: Array = []
var _stage_cam_base_offset: Vector2 = Vector2.INF


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

	# Skip indicator (bottom-center, pill-style)
	_skip_indicator = Control.new()
	_skip_indicator.visible = false
	add_child(_skip_indicator)

	_skip_pill_bg = ColorRect.new()
	_skip_pill_bg.color = Color(0.05, 0.05, 0.08, 0.82)
	_skip_pill_bg.size = Vector2(SKIP_BAR_WIDTH + SKIP_PILL_PAD * 2, SKIP_PILL_HEIGHT)
	_skip_indicator.add_child(_skip_pill_bg)

	_skip_label = Label.new()
	_skip_label.text = "Hold B / Esc to skip..."
	_skip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skip_label.add_theme_font_size_override("font_size", 14)
	_skip_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.75, 0.95))
	_skip_indicator.add_child(_skip_label)

	_skip_bar_bg = ColorRect.new()
	_skip_bar_bg.color = Color(0.15, 0.15, 0.20, 0.95)
	_skip_bar_bg.size = Vector2(SKIP_BAR_WIDTH, SKIP_BAR_HEIGHT)
	_skip_indicator.add_child(_skip_bar_bg)

	_skip_bar = ColorRect.new()
	_skip_bar.color = Color(1.0, 0.75, 0.25, 1.0)
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

	# Bottom-center pill
	var pill_w: float = SKIP_BAR_WIDTH + SKIP_PILL_PAD * 2.0
	_skip_indicator.position = Vector2((screen_size.x - pill_w) / 2.0, screen_size.y - SKIP_PILL_HEIGHT - 18)
	_skip_pill_bg.position = Vector2(0, 0)
	_skip_pill_bg.size = Vector2(pill_w, SKIP_PILL_HEIGHT)
	_skip_label.position = Vector2(0, 6)
	_skip_label.size = Vector2(pill_w, 18)
	_skip_bar_bg.position = Vector2(SKIP_PILL_PAD, 30)
	_skip_bar.position = Vector2(SKIP_PILL_PAD, 30)

	_effects_rect.position = Vector2.ZERO
	_effects_rect.size = screen_size


func _process(delta: float) -> void:
	if not _active:
		return

	# Heartbeat the input lock: cutscenes routinely run >10s, and the stale-lock expiry would otherwise re-open the mid-cutscene interact leak fixed at v3.33.108 (web-smoke budget find #2 class).
	var ilm_hb = get_tree().root.get_node_or_null("InputLockManager")
	if ilm_hb:
		ilm_hb.push_lock("cutscene")

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

	# Tick the cutscene HUD timer (atmospheric only — never a fail state).
	# Floor at 0 so the display freezes at 0:00 if the cutscene never hits
	# a stop_timer step (defensive). Real countdown is W4 orrery's 300→0
	# but the dialogue between start/stop is ~10 lines so the player should
	# see only the top few seconds of the countdown before stop_timer fires.
	if _timer_label and is_instance_valid(_timer_label):
		_timer_remaining = maxf(0.0, _timer_remaining - delta)
		_timer_label.text = _format_timer_text(_timer_remaining)


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

	# Staged mode: live world stays visible — no backdrop, no dim, puppets act in-scene.
	_staged = str(data.get("presentation", "")) == "staged"
	if _staged:
		_begin_staging()
	elif not _try_load_backdrop_image(data):
		await _capture_background()

	# Fade out current music before cutscene begins (smooth transition).
	# fade_out_music tweens volume_db → -40 over the supplied duration so the
	# cutscene's first dialogue / cue isn't preceded by a hard cut. The
	# matching await lets the fade complete before the cutscene starts
	# emitting its own audio.
	if SoundManager and SoundManager._music_playing:
		_pre_cutscene_music = SoundManager._current_music
		SoundManager.fade_out_music(0.3)
		await get_tree().create_timer(0.3).timeout

	cutscene_started.emit(cutscene_id)

	# Block player input
	_freeze_player()

	# Execute steps
	var steps = data.get("steps", [])
	var step_index := 0
	for step in steps:
		if _skipping or _aborted:
			break
		await _execute_step(step)
		step_index += 1

	# When skipped, still apply all set_flag steps so cutscenes never replay.
	if _skipping and not _aborted:
		_apply_remaining_set_flag_steps(steps, step_index)

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

	# Same staged-mode gate as play_cutscene — keep the two entry points in sync.
	_staged = str(data.get("presentation", "")) == "staged"
	if _staged:
		_begin_staging()
	elif not _try_load_backdrop_image(data):
		await _capture_background()
	cutscene_started.emit(cutscene_id)
	_freeze_player()

	var steps = data.get("steps", [])
	var step_index := 0
	for step in steps:
		if _skipping or _aborted:
			break
		await _execute_step(step)
		step_index += 1

	# When skipped, still apply all set_flag steps so cutscenes never replay.
	# Delegate to the shared helper so this path matches play_cutscene's
	# behaviour byte-for-byte (the inline loop drifted from the helper).
	if _skipping and not _aborted:
		_apply_remaining_set_flag_steps(steps, step_index)

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
		"grant_item":
			await _step_grant_item(step)
		"give_item":
			_step_give_item(step)
		"update_item":
			_step_update_item(step)
		"start_timer":
			_step_start_timer(step)
		"stop_timer":
			_step_stop_timer(step)
		"set_background":
			_step_set_background(step)
		"branch":
			await _step_branch(step)
		"chapter_title":
			await _step_chapter_title(step)
		"boss_intro":
			await _step_boss_intro(step)
		"roll_credits":
			await _step_roll_credits(step)
		"choice":
			await _step_choice(step)
		"battle":
			await _step_battle(step)
		"spawn_actor":
			_step_spawn_actor(step)
		"despawn_actor":
			_step_despawn_actor(step)
		"move_actor":
			await _step_move_actor(step)
		"face_actor":
			_step_face_actor(step)
		"emote":
			await _step_emote(step)
		"hop":
			await _step_hop(step)
		"camera_focus":
			await _step_camera_focus(step)
		"camera_restore":
			await _step_camera_restore(step)
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


## Tick 331: handle "choice" step type. Pre-fix the type was used by
## world6_orrery.json but had no handler — every play hit the unknown-
## step-type push_warning and silently skipped the prompt, never setting
## any response flag. Implementation:
##   1. Show the prompt as a single narration line so the player has
##      context (mirrors how dialogue → choice flows in classic JRPGs).
##   2. Hand the option strings to DialogueChoiceMenu and await.
##   3. Find the matched option by text and set its declared flag in
##      GameState.game_constants.
## When _skipping is true (player held the skip button) we still set
## the FIRST option's flag so the cutscene state machine doesn't get
## stuck waiting for a response that never arrives, matching the
## skip-resilient pattern used elsewhere in the director.
func _step_choice(step: Dictionary) -> void:
	var prompt: String = str(step.get("prompt", ""))
	var options: Array = step.get("options", [])
	if options.is_empty():
		push_warning("CutsceneDirector._step_choice: 'options' array empty — choice has nothing to present, skipping")
		return

	# Show the prompt as narration first (skipped if empty).
	if prompt != "":
		var narration_line: Dictionary = {
			"speaker": "",
			"text": prompt,
			"theme": "narrator",
			"portrait": "narrator",
		}
		var dialogue = _get_or_create_dialogue()
		dialogue.show_dialogue([narration_line])
		await dialogue.dialogue_finished

	# Build the choice text list. Drop options without text — they
	# can't be displayed.
	var choice_texts: Array[String] = []
	for opt in options:
		if not (opt is Dictionary):
			continue
		var t: String = str((opt as Dictionary).get("text", ""))
		if t.strip_edges() != "":
			choice_texts.append(t)
	if choice_texts.is_empty():
		push_warning("CutsceneDirector._step_choice: no valid option texts after filtering — skipping")
		return

	# Skip path: set the first option's flag deterministically. Avoids
	# leaving the cutscene state machine waiting on input that won't
	# come when the player hits skip.
	if _skipping:
		_set_choice_flag(options[0])
		return

	# Present the menu and await selection.
	var DialogueChoiceMenuScript = load("res://src/llm/DialogueChoiceMenu.gd")
	if DialogueChoiceMenuScript == null:
		push_warning("CutsceneDirector._step_choice: DialogueChoiceMenu script unloadable — setting first option's flag and continuing")
		_set_choice_flag(options[0])
		return
	var menu: Node = DialogueChoiceMenuScript.new()
	# Anchor to a CanvasLayer so it renders above the cutscene UI.
	var layer := CanvasLayer.new()
	layer.layer = 96  # Above CutsceneDirector layer (95).
	get_tree().root.add_child(layer)
	layer.add_child(menu)

	var result: String = await menu.present(choice_texts)
	layer.queue_free()

	# Find the matched option. Empty (cancel) falls back to first.
	var matched: Dictionary = options[0]
	if result != "":
		for opt in options:
			if opt is Dictionary and str((opt as Dictionary).get("text", "")) == result:
				matched = opt
				break
	_set_choice_flag(matched)


## Apply a choice option's flag to GameState.game_constants. Safe-noop
## when the option has no flag (the player picks a "do nothing" option)
## or when GameState isn't reachable (test environments).
##
## Tick 332: prefix flag name with "cutscene_flag_" to match
## _step_set_flag's convention (line ~627). Pre-fix tick 331 wrote
## the bare name — so a branch step reading `cutscene_flag_<flag>`
## (the format _step_branch uses at line ~1004) never saw the choice
## response. The whole "choice → set flag → branch on flag" loop
## was broken by a one-prefix naming gap.
func _set_choice_flag(option: Variant) -> void:
	if not (option is Dictionary):
		return
	var flag_name: String = str((option as Dictionary).get("flag", ""))
	if flag_name == "":
		return
	var gs: Node = get_tree().root.get_node_or_null("GameState") if is_inside_tree() else null
	if gs == null or not ("game_constants" in gs):
		push_warning("CutsceneDirector._set_choice_flag: GameState unreachable — flag '%s' not persisted" % flag_name)
		return
	gs.game_constants["cutscene_flag_" + flag_name] = true
	# Tick 333: mirror to story_flags too (see _step_set_flag for
	# rationale — QuestLog and other bare-flag consumers don't fall
	# back to game_constants).
	if gs.has_method("set_story_flag"):
		gs.set_story_flag(flag_name, true)


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
	# Settings gate - skip entirely if user disabled screen shake
	if GameState and "screen_shake_enabled" in GameState and not GameState.screen_shake_enabled:
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
			# Tick 333: also mirror to story_flags so QuestLog (reads
			# get_story_flag, no game_constants fallback) and other
			# bare-flag consumers see the value. Pre-fix a cutscene
			# set_flag step that flipped a quest objective flag (e.g.
			# "talked_to_theron") never updated story_flags — QuestLog
			# kept showing the objective as incomplete even after the
			# Theron dialogue played. Mirrors the helper at GameLoop
			# ._set_cutscene_flag_and_mirror that's used for the
			# completion-flag write at cutscene_finished.
			if GameState.has_method("set_story_flag"):
				GameState.set_story_flag(flag, bool(value))
			# Party reacts when the card is more than half full (event chat)
			if flag == "fool_card_marks" and int(value) >= 3 and PartyChatSystem:
				PartyChatSystem.fire_event_flag("event_flag_fool_marks_three")
			# Orrery finale gate: marks are int-valued (story_flags mirror is bool-coerced) so the five-marks boolean must be emitted where the value lands
			if flag == "fool_card_marks" and int(value) >= 5:
				GameState.set_story_flag("quest_wiring_fool_card_five_marks")
				var qs = get_node_or_null("/root/QuestSystem")
				if qs and qs.has_method("notify_flag"):
					qs.notify_flag("quest_wiring_fool_card_five_marks")


func _step_grant_item(step: Dictionary) -> void:
	## Key/META item grant. Adds to inventory AND shows the gold-bordered
	## KeyItemPopup with name + description, then awaits dismiss so the
	## cutscene pauses on the reveal. Skipping the cutscene still adds
	## the item but skips the popup (player explicitly asked to skip).
	## Pre-fix this step was silently dropped — 9+ cutscene JSONs award
	## items via grant_item but the dispatch lacked the case, so the
	## player saw the "Take this fragment" dialogue and ended up with
	## nothing in their inventory.
	var item_id: String = str(step.get("item", ""))
	if item_id == "":
		push_warning("CutsceneDirector grant_item: missing 'item' field")
		return
	var quantity: int = int(step.get("quantity", 1))
	_add_item_to_party_leader(item_id, quantity)
	if _skipping:
		return
	var popup_data = {
		"name": str(step.get("name", item_id)),
		"description": str(step.get("description", "")),
		"sprite_path": str(step.get("sprite_path", "")),
	}
	var popup = KeyItemPopup.show_item(self, popup_data)
	if popup:
		await popup.dismissed


func _step_give_item(step: Dictionary) -> void:
	## Silent item grant — used for ordinary consumables/items within a
	## cutscene. The cutscene script provides surrounding narrative context
	## so we don't surface a popup or toast (would clutter the scene).
	## Pre-fix, like grant_item, this step was silently dropped — items
	## from cutscenes (e.g. world1_orrery's fool_card + luck_charm_minor)
	## never reached the player's inventory.
	var item_id: String = str(step.get("item", ""))
	if item_id == "":
		push_warning("CutsceneDirector give_item: missing 'item' field")
		return
	var quantity: int = int(step.get("quantity", 1))
	_add_item_to_party_leader(item_id, quantity)


func _step_start_timer(step: Dictionary) -> void:
	## Show a HUD countdown timer in the upper-right corner. cowir-story
	## spec: atmospheric only — never a fail state. Display ticks down in
	## real-time during the surrounding dialogue but the cutscene's
	## stop_timer step always lands well before the countdown reaches 0.
	## If somehow the timer DOES reach 0 (cutscene authoring error) the
	## display freezes at 0:00; no game-over fires.
	var duration: float = float(step.get("duration", 60))
	var flag: String = str(step.get("flag", ""))
	if duration <= 0:
		push_warning("CutsceneDirector start_timer: non-positive duration %s" % duration)
		return
	_timer_remaining = duration
	_timer_flag = flag
	_build_timer_hud()
	# Record `active` state in game_constants so other systems can probe
	# whether a cutscene timer is currently running. Only meaningful when
	# flag is non-empty (W4 orrery uses `world4_orrery_timer`).
	if flag != "" and GameState:
		GameState.game_constants["timer_active_" + flag] = true


func _step_stop_timer(step: Dictionary) -> void:
	## Clear the HUD timer. Idempotent — safe to call when no timer is
	## active. Pairs with start_timer's flag bookkeeping if the step
	## supplies one (matches the flag from the matching start_timer).
	var flag: String = str(step.get("flag", ""))
	_clear_timer_hud()
	if flag != "" and GameState:
		GameState.game_constants["timer_active_" + flag] = false


func _build_timer_hud() -> void:
	## Renders the timer in the upper-right at large monospace font with
	## the same warm amber as the gold/EXP UI for visual consistency
	## (timer = "resource ticking down" feels in the same family).
	if _timer_label and is_instance_valid(_timer_label):
		_timer_label.queue_free()
	_timer_label = Label.new()
	_timer_label.name = "CutsceneTimerHUD"
	_timer_label.text = _format_timer_text(_timer_remaining)
	_timer_label.add_theme_font_size_override("font_size", 22)
	_timer_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var vp_size := Vector2(1280, 720)
	var vp := get_viewport()
	if vp:
		vp_size = vp.get_visible_rect().size
		if vp_size.x <= 0:
			vp_size = Vector2(1280, 720)
	_timer_label.position = Vector2(vp_size.x - 120, 20)
	_timer_label.size = Vector2(100, 28)
	add_child(_timer_label)


func _clear_timer_hud() -> void:
	if _timer_label and is_instance_valid(_timer_label):
		_timer_label.queue_free()
	_timer_label = null
	_timer_remaining = 0.0
	_timer_flag = ""


func _format_timer_text(secs: float) -> String:
	## "M:SS" — leading zero on the seconds, no leading zero on minutes.
	## Matches the corner-clock convention from classic JRPG timer
	## moments (FFVII's bomb timer in Mako Reactor, etc.).
	var s: int = int(maxf(0.0, secs))
	var minutes: int = s / 60
	var seconds: int = s % 60
	return "%d:%02d" % [minutes, seconds]


func _step_update_item(step: Dictionary) -> void:
	## Transforms an item ID in the player's inventory — used by world1_
	## orrery to convert "fool_card" → "wild_card" mid-cutscene as the
	## narrative reveals what the card was actually for. Walks all party
	## members so the swap finds the item even if it ended up on a non-
	## leader (TreasureChest puts items on leader, but ItemsMenu can move
	## them around). Removes old item, adds same quantity of new item.
	## Pre-fix, like grant_item/give_item, this step was silently dropped.
	var old_id: String = str(step.get("item", ""))
	var new_id: String = str(step.get("new_id", ""))
	if old_id == "" or new_id == "":
		push_warning("CutsceneDirector update_item: missing 'item' or 'new_id' field")
		return
	var game_loop = get_tree().root.get_node_or_null("GameLoop")
	if game_loop == null or not "party" in game_loop:
		return
	for member in game_loop.party:
		if member == null or not member.has_method("get_item_count"):
			continue
		var qty: int = member.get_item_count(old_id)
		if qty <= 0:
			continue
		# Tick 191: guard add_item on remove_item success — pre-fix a failed remove still ran add, producing duplication (player keeps old AND gets new).
		if not member.has_method("remove_item") or not member.has_method("add_item"):
			push_warning("CutsceneDirector update_item: party member '%s' missing remove_item/add_item — swap skipped" % member.combatant_name)
			return
		if not member.remove_item(old_id, qty):
			push_warning("CutsceneDirector update_item: remove_item('%s', %d) failed on %s — swap aborted, no duplication" % [old_id, qty, member.combatant_name])
			return
		member.add_item(new_id, qty)
		return  # First match wins — don't double-swap if item exists in multiple members
	# Not found anywhere — log so a malformed cutscene script doesn't
	# silently fail to transform.
	push_warning("CutsceneDirector update_item: no party member has item '%s' to swap" % old_id)


func _add_item_to_party_leader(item_id: String, quantity: int) -> void:
	## Mirrors TreasureChest's convention of routing item adds through the
	## party leader's inventory. ItemsMenu aggregates inventory across
	## all members for display, so leader-only storage is fine. Guards
	## absent GameLoop / empty party so test contexts that boot without
	## the full graph don't crash.
	##
	## Also surfaces a runtime push_warning when ItemSystem doesn't know
	## about the item ID — pre-fix the item ID would silently land in
	## inventory as a ghost entry (no name, no description, can't be
	## used), which is the same silent-failure class as the dispatch
	## drop the grant_item/give_item handlers were meant to fix. With
	## the warning, devs see the orphan loud at runtime; the regression
	## test (test_cutscene_grant_give_item_orphans) catches new orphans
	## at test time before they reach the player.
	if ItemSystem and ItemSystem.has_method("get_item"):
		var existing: Dictionary = ItemSystem.get_item(item_id)
		if existing.is_empty():
			push_warning("CutsceneDirector: item '%s' not defined in items.json — will be a ghost inventory entry" % item_id)
	var game_loop = get_tree().root.get_node_or_null("GameLoop")
	if game_loop and "party" in game_loop and game_loop.party.size() > 0:
		var leader = game_loop.party[0]
		if leader and leader.has_method("add_item"):
			leader.add_item(item_id, quantity)


## =====================
## STAGED SCENE DIRECTION (presentation:"staged")
## =====================

## The live Node2D the puppets act in. Null in headless/no-scene contexts —
## every staged step treats null as "resolve instantly" (spine-walker safety).
func _get_live_stage() -> Node2D:
	if MapSystem and MapSystem.current_map and is_instance_valid(MapSystem.current_map):
		return MapSystem.current_map
	var gl = get_tree().root.get_node_or_null("GameLoop")
	if gl and "current_scene" in gl and gl.current_scene is Node2D and is_instance_valid(gl.current_scene):
		return gl.current_scene
	var cs = get_tree().current_scene
	if cs is Node2D:
		return cs
	return null


func _get_live_player() -> Node2D:
	var p = get_tree().get_first_node_in_group("player")
	if p is Node2D and is_instance_valid(p):
		return p
	if MapSystem and MapSystem.has_method("get_player"):
		var mp = MapSystem.get_player()
		if mp is Node2D and is_instance_valid(mp):
			return mp
	return null


## Staged entry: hide the real player + best-effort HUD so puppets own the frame.
func _begin_staging() -> void:
	_actors.clear()
	_stage_hidden.clear()
	_stage_cam_base_offset = Vector2.INF
	var player := _get_live_player()
	if player and player.visible:
		player.visible = false
		_stage_hidden.append(player)
	var stage := _get_live_stage()
	if stage == null:
		return
	# Field-HUD widgets are Nodes wrapping a _canvas CanvasLayer (not CanvasItems) — resolve like GameLoop._set_field_hud_hidden or the hide silently no-ops.
	for prop in ["_minimap", "_threat_meter", "_quest_tracker", "_objective_arrow", "_border_indicator", "_danger_zone"]:
		if not (prop in stage):
			continue
		var w = stage.get(prop)
		if w == null or (w is Object and not is_instance_valid(w)):
			continue
		var target = null
		if w is CanvasItem or w is CanvasLayer:
			target = w
		elif w is Node and "_canvas" in w and w._canvas is CanvasLayer:
			target = w._canvas
		if target and is_instance_valid(target) and target.visible:
			target.visible = false
			_stage_hidden.append(target)
	# Live-playtest 2026-07-11 (msg 2388): ambient villagers/wanderers loitered inside the puppet blocking — puppets play EVERYONE, so hide live character NPCs (npc_name-bearing PROPS like BulletinBoard/TallyWall stay on stage).
	for n in stage.find_children("*", "Area2D", true, false):
		if (n is OverworldNPC or n is WanderingNPC) and n.visible:
			n.visible = false
			_stage_hidden.append(n)


## Staged teardown: despawn puppets, restore hidden nodes + camera. Idempotent —
## _end_cutscene calls it unconditionally so skip/abort paths clean up too.
func _end_staging() -> void:
	for id in _actors:
		var a = _actors[id]
		if a and is_instance_valid(a):
			a.queue_free()
	_actors.clear()
	for n in _stage_hidden:
		if n and is_instance_valid(n):
			n.visible = true
	_stage_hidden.clear()
	if _stage_cam_base_offset != Vector2.INF:
		var cam := get_viewport().get_camera_2d() if get_viewport() else null
		if cam:
			cam.offset = _stage_cam_base_offset
	_stage_cam_base_offset = Vector2.INF
	_staged = false


func _get_actor(id: String) -> CutsceneActor:
	var a = _actors.get(id)
	if a and is_instance_valid(a):
		return a
	return null


## {"type":"spawn_actor","id":"elder","kind":"npc","archetype":"old_man",
##  "at":[x,y],"facing":"down","replace_npc":"Elder Theron"}
## replace_npc hides the live OverworldNPC of that name and inherits its
## position (restored at teardown) so scenes don't show doubled NPCs.
func _step_spawn_actor(step: Dictionary) -> void:
	var id: String = str(step.get("id", ""))
	if id == "":
		push_warning("CutsceneDirector spawn_actor: missing 'id'")
		return
	var stage := _get_live_stage()
	if stage == null:
		return
	_step_despawn_actor({"id": id})
	var spawn_pos := Vector2.INF
	var replace_name: String = str(step.get("replace_npc", ""))
	if replace_name != "":
		var live_npc := _find_live_npc(stage, replace_name)
		if live_npc:
			spawn_pos = live_npc.global_position
			if live_npc.visible:
				live_npc.visible = false
				_stage_hidden.append(live_npc)
	var at = step.get("at", null)
	if at is Array and at.size() >= 2:
		spawn_pos = Vector2(float(at[0]), float(at[1]))
	if spawn_pos == Vector2.INF:
		var player := _get_live_player()
		spawn_pos = player.global_position if player else Vector2.ZERO
	var actor := CutsceneActor.build(id, step)
	stage.add_child(actor)
	actor.global_position = spawn_pos
	_actors[id] = actor


func _find_live_npc(stage: Node2D, npc_name: String) -> Node2D:
	for n in stage.find_children("*", "Area2D", true, false):
		if "npc_name" in n and str(n.npc_name) == npc_name:
			return n
	return null


func _step_despawn_actor(step: Dictionary) -> void:
	var id: String = str(step.get("id", ""))
	var a := _get_actor(id)
	if a:
		a.queue_free()
	_actors.erase(id)


## Awaited walk; skip/headless snaps to the target instantly (skip contract).
func _step_move_actor(step: Dictionary) -> void:
	var a := _get_actor(str(step.get("id", "")))
	if a == null:
		return
	var to = step.get("to", null)
	if not (to is Array and to.size() >= 2):
		push_warning("CutsceneDirector move_actor: missing 'to' [x,y]")
		return
	var target := Vector2(float(to[0]), float(to[1]))
	if _skipping:
		a.global_position = target
		a.stand()
		return
	var speed: float = float(step.get("speed", CutsceneActor.DEFAULT_WALK_SPEED))
	await a.walk_to(target, speed)


func _step_face_actor(step: Dictionary) -> void:
	var a := _get_actor(str(step.get("id", "")))
	if a == null:
		return
	var toward: String = str(step.get("toward", ""))
	if toward != "":
		var other := _get_actor(toward)
		if other:
			a.face_toward(other.position)
		return
	a.set_facing_name(str(step.get("dir", "down")))


func _step_emote(step: Dictionary) -> void:
	var a := _get_actor(str(step.get("id", "")))
	if a == null or _skipping:
		return
	var duration: float = float(step.get("duration", 1.0))
	a.show_emote(str(step.get("emote", "exclaim")), duration)
	if duration > 0.0:
		await get_tree().create_timer(duration).timeout


func _step_hop(step: Dictionary) -> void:
	var a := _get_actor(str(step.get("id", "")))
	if a == null or _skipping:
		return
	await a.hop(int(step.get("times", 1)))


## Pan the live camera to frame an actor or point; offset-tween holds because
## nothing re-snaps camera position per frame (only rotation is forced).
func _step_camera_focus(step: Dictionary) -> void:
	if _skipping:
		return
	var vp := get_viewport()
	var cam := vp.get_camera_2d() if vp else null
	if cam == null:
		return
	var target := Vector2.INF
	var target_id: String = str(step.get("target", ""))
	var a := _get_actor(target_id)
	if a:
		target = a.global_position
	else:
		var at = step.get("target", null)
		if at is Array and at.size() >= 2:
			target = Vector2(float(at[0]), float(at[1]))
	if target == Vector2.INF:
		return
	if _stage_cam_base_offset == Vector2.INF:
		_stage_cam_base_offset = cam.offset
	var new_offset: Vector2 = cam.offset + (target - cam.get_screen_center_position())
	var tween := create_tween()
	tween.tween_property(cam, "offset", new_offset, float(step.get("duration", 0.8)))
	await tween.finished


func _step_camera_restore(step: Dictionary) -> void:
	var vp := get_viewport()
	var cam := vp.get_camera_2d() if vp else null
	if cam == null or _stage_cam_base_offset == Vector2.INF:
		return
	if _skipping:
		cam.offset = _stage_cam_base_offset
		return
	var tween := create_tween()
	tween.tween_property(cam, "offset", _stage_cam_base_offset, float(step.get("duration", 0.8)))
	await tween.finished


func _apply_remaining_set_flag_steps(steps: Array, from_index: int) -> void:
	## Walk the steps array starting at `from_index` and fire _step_set_flag
	## for every set_flag entry. Used when a cutscene is skipped — we still
	## need to set the completion flag so the cutscene doesn't replay on
	## the next visit / save load. Extracted from _start_cutscene to be
	## unit-testable without driving the full UI flow. CRITICAL — silent
	## failure here means skipped cutscenes replay forever.
	for i in range(from_index, steps.size()):
		if steps[i].get("type", "") == "set_flag":
			_step_set_flag(steps[i])


func _step_chapter_title(step: Dictionary) -> void:
	"""Show a cinematic chapter title card that fades in, holds, then fades out.
	Usage: {"type": "chapter_title", "title": "Chapter 3", "subtitle": "The Whispering Cave"}"""
	var title_text = step.get("title", "")
	var subtitle_text = step.get("subtitle", "")
	var hold_duration = step.get("duration", 2.5)

	if _skipping:
		return

	var screen_size = get_viewport().get_visible_rect().size

	# Container for the title card
	var container = Control.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.modulate.a = 0.0
	add_child(container)

	# Semi-transparent backdrop bar
	var bar = ColorRect.new()
	bar.color = Color(0, 0, 0, 0.6)
	bar.position = Vector2(0, screen_size.y * 0.35)
	bar.size = Vector2(screen_size.x, screen_size.y * 0.3)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(bar)

	# Chapter title label
	var title_label = Label.new()
	title_label.text = title_text
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.position = Vector2(0, screen_size.y * 0.36)
	title_label.size = Vector2(screen_size.x, 40)
	title_label.clip_text = false
	title_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.add_theme_color_override("font_color", Color(0.95, 0.90, 0.70))
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(title_label)

	# Subtitle label
	if subtitle_text != "":
		var sub_label = Label.new()
		sub_label.text = subtitle_text
		sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sub_label.position = Vector2(0, screen_size.y * 0.36 + 44)
		sub_label.size = Vector2(screen_size.x, 30)
		sub_label.clip_text = false
		sub_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		sub_label.add_theme_font_size_override("font_size", 18)
		sub_label.add_theme_color_override("font_color", Color(0.75, 0.72, 0.60))
		sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(sub_label)

	# Fade in
	var tween = create_tween()
	tween.tween_property(container, "modulate:a", 1.0, 0.6)
	await tween.finished

	# Hold
	await get_tree().create_timer(hold_duration).timeout

	# Fade out
	var fade_out = create_tween()
	fade_out.tween_property(container, "modulate:a", 0.0, 0.5)
	await fade_out.finished

	container.queue_free()


func _step_boss_intro(step: Dictionary) -> void:
	"""Show a dramatic boss introduction card with name, title, and screen effects.
	Usage: {"type": "boss_intro", "name": "Warden of the Old Guard", "title": "Masterite — World 1"}"""
	var boss_name = step.get("name", "???")
	var boss_title = step.get("title", "")

	if _skipping:
		return

	var screen_size = get_viewport().get_visible_rect().size

	# Dark vignette overlay
	var vignette = ColorRect.new()
	vignette.color = Color(0, 0, 0, 0.0)
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	# Screen shake + flash
	if not _skipping:
		var shake_tween = create_tween()
		shake_tween.tween_property(vignette, "color:a", 0.7, 0.3)
	await get_tree().create_timer(0.3).timeout

	# Boss name label — large, dramatic
	var name_label = Label.new()
	name_label.text = boss_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(0, screen_size.y * 0.4)
	name_label.size = Vector2(screen_size.x, 50)
	name_label.clip_text = false
	name_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	name_label.add_theme_font_size_override("font_size", 36)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.3, 0.2))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.modulate.a = 0.0
	add_child(name_label)

	# Title subtitle
	var title_label: Label = null
	if boss_title != "":
		title_label = Label.new()
		title_label.text = boss_title
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_label.position = Vector2(0, screen_size.y * 0.4 + 48)
		title_label.size = Vector2(screen_size.x, 30)
		title_label.clip_text = false
		title_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		title_label.add_theme_font_size_override("font_size", 16)
		title_label.add_theme_color_override("font_color", Color(0.7, 0.6, 0.5))
		title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_label.modulate.a = 0.0
		add_child(title_label)

	# Slam in — name scales up with a punch
	var name_tween = create_tween()
	name_label.scale = Vector2(1.5, 1.5)
	name_label.pivot_offset = Vector2(screen_size.x / 2.0, 25)
	name_tween.set_parallel(true)
	name_tween.tween_property(name_label, "modulate:a", 1.0, 0.2)
	name_tween.tween_property(name_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)
	await name_tween.finished

	# Title fades in after name
	if title_label:
		var title_tween = create_tween()
		title_tween.tween_property(title_label, "modulate:a", 1.0, 0.4)
		await title_tween.finished

	# Hold
	await get_tree().create_timer(1.5).timeout

	# Fade everything out
	var fade = create_tween()
	fade.set_parallel(true)
	fade.tween_property(vignette, "color:a", 0.0, 0.4)
	fade.tween_property(name_label, "modulate:a", 0.0, 0.4)
	if title_label:
		fade.tween_property(title_label, "modulate:a", 0.0, 0.4)
	await fade.finished

	vignette.queue_free()
	name_label.queue_free()
	if title_label:
		title_label.queue_free()


func _step_roll_credits(step: Dictionary) -> void:
	"""Play the full scrolling credits sequence.
	Usage: {"type": "roll_credits", "world": 1, "music": "credits_medieval"}
	The caller is expected to fade out any existing music / letterbox state
	before issuing this step. Credits manage their own music if `music` is set."""
	if _skipping:
		return
	var world: int = step.get("world", 0)
	var music: String = step.get("music", "")
	var CreditsScript = load("res://src/ui/CreditsSequence.gd")
	var credits = CreditsScript.new()
	add_child(credits)
	await credits.play(world, music)
	credits.queue_free()


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
	elif step.get("condition", "") == "lead_job":
		# Lead-job branching: pick steps based on the party leader's job_id.
		# Used by W1 spotlight cutscenes to swap trope-demonstrating beats
		# based on who the player picked as lead. Falls back to "default"
		# case if leader's job has no explicit case or no leader is set.
		var lead_job = ""
		if GameState:
			var leader = GameState.get_party_leader()
			if leader is Dictionary:
				lead_job = leader.get("job_id", "")
		var cases = step.get("cases", {})
		var branch_steps = cases.get(lead_job, cases.get("default", []))
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
		## Tick 418: read GameState.battles_won (the canonical
		## persistent counter) instead of the dead BattleManager
		## reference that never existed — the old read always took
		## the false branch, leaving total_battles = 0 forever. The
		## autobattle-ratio playstyle gating below (>= 20 battles
		## for "automator", > 100 for veteran) silently never fired
		## pre-fix.
		if GameState and "battles_won" in GameState:
			total_battles = GameState.battles_won
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

func _try_load_backdrop_image(data: Dictionary) -> bool:
	"""Try to load a backdrop for the cutscene. Priority: video (OGV) > static image (PNG).
	Returns true if a backdrop was loaded, false to fall through to capture/gradient.
	Supports: {"background": "prologue_village"} → tries OGV first, then PNG."""
	var bg = data.get("background", "")
	if bg == "":
		return false

	# Try animated video backdrop first (OGV for Godot native playback)
	var video_path = "res://assets/cutscene_videos/%s.ogv" % bg
	if ResourceLoader.exists(video_path):
		var stream = load(video_path) as VideoStream
		if stream:
			_stop_backdrop_video()
			_background_video = VideoStreamPlayer.new()
			_background_video.stream = stream
			_background_video.set_anchors_preset(Control.PRESET_FULL_RECT)
			_background_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_background_video.expand = true
			_background_video.loop = true
			_background_video.volume_db = -80.0  # Mute — we have our own music
			add_child(_background_video)
			move_child(_background_video, 0)
			_background_video.play()
			_background_dim.visible = true
			_background_texture.visible = false
			return true

	# Fall back to static image
	var path = "res://assets/cutscene_backdrops/%s.png" % bg
	if not ResourceLoader.exists(path):
		push_warning("CutsceneDirector: Backdrop not found: %s (tried OGV and PNG)" % bg)
		return false

	var tex = load(path) as Texture2D
	if tex:
		_background_texture.texture = tex
		_background_texture.visible = true
		_background_dim.visible = true
		return true

	return false


func _stop_backdrop_video() -> void:
	"""Stop and remove any playing backdrop video."""
	if _background_video and is_instance_valid(_background_video):
		_background_video.stop()
		_background_video.queue_free()
		_background_video = null


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
	"""Hide the background capture and stop any video."""
	_stop_backdrop_video()
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
	# Canonical gate FIRST: set_can_move relies on MapSystem.get_player(), which is null on overworld scenes — A-presses leaked to save points + NPC dialogue mid-cutscene (struktured playtest 2026-07-11).
	var ilm = get_tree().root.get_node_or_null("InputLockManager")
	if ilm:
		ilm.push_lock("cutscene")
	var player = MapSystem.get_player() if MapSystem else null
	if player and player.has_method("set_can_move"):
		player.set_can_move(false)


func _unfreeze_player() -> void:
	var ilm = get_tree().root.get_node_or_null("InputLockManager")
	if ilm:
		ilm.pop_lock("cutscene")
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

## For unrunnable states (missing duel PC), not player skips — see _aborted var note
func abort_current(reason: String) -> void:
	if not _active:
		return
	_aborted = true
	push_error("CutsceneDirector: '%s' aborted — %s (completion flag NOT set; will replay when runnable)" % [_cutscene_id, reason])


func last_finished_was_aborted() -> bool:
	return _last_finished_aborted


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

	# Restore pre-cutscene music if it was playing and cutscene stopped it
	if _pre_cutscene_music != "" and SoundManager:
		SoundManager.play_music(_pre_cutscene_music)
	_pre_cutscene_music = ""

	# Defensive: tear down the HUD timer if a cutscene ended without firing
	# a matching stop_timer (skip path or malformed cutscene script). Without
	# this, a lingering _timer_label would float over post-cutscene gameplay.
	_clear_timer_hud()

	# Staged-mode teardown: puppets, hidden nodes, camera. Idempotent no-op for overlay scenes.
	_end_staging()

	# Snapshot then clear BEFORE the emit. Otherwise: a listener that
	# synchronously chains into the next cutscene (e.g. prologue → chapter1
	# via GameLoop._on_prologue_finished) sets _cutscene_id to the new id
	# inside the emit's stack, but as soon as the listener yields on an
	# await, control returns here and `_cutscene_id = ""` below would
	# clobber the chained id. Snapshot + clear-first fixes that — when the
	# listener runs, our member vars are already in the "between
	# cutscenes" state and any new play_cutscene gets to fully own them.
	var finished_id: String = _cutscene_id
	_last_finished_aborted = _aborted
	_active = false
	visible = false
	_cutscene_id = ""
	_skipping = false
	_aborted = false
	cutscene_finished.emit(finished_id)


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

	# Out-of-family loud-fail gap: pre-fix this silently swallowed a
	# non-Dict root (e.g. someone wraps the cutscene in an Array by
	# mistake, or a corrupted file parses as a string). play_cutscene
	# would then receive {} and silently no-op the whole cutscene,
	# leaving the story flag uncompleted forever — the same loop class
	# tick 12 had to back-fill for the rat king flag.
	if not (json.data is Dictionary):
		push_error("CutsceneDirector: %s parsed but root is not a Dictionary (type=%s) — cutscene will not play" % [path, typeof(json.data)])
		return {}

	return json.data


## Tick 471: cutscene→battle→resume step type for the Spotlight Duels
## directive. Runs a solo-duel battle inline in the cutscene, retrying
## on defeat by default. Step schema:
##   {"type":"battle","combatants":["<pc_job_id>"],"enemies":["<mob_id>"],
##    "on_defeat":"retry"|"fail_forward"|"skip",
##    "music":"<track>", "background":"<terrain>"}
## Delegates to GameLoop.start_solo_battle which benches all but the
## spotlight PC, awaits BattleManager.battle_ended, and returns
## "victory" | "defeat". The retry loop lives HERE (not in GameLoop) so
## the cutscene stays paused across attempts and the intro cutscene
## never replays (matches cowir-story's UX requirement, msg 1931 #4).
func _step_battle(step: Dictionary) -> void:
	var combatants: Array = step.get("combatants", [])
	var enemies: Array = step.get("enemies", [])
	var on_defeat: String = str(step.get("on_defeat", "retry"))
	var opts: Dictionary = {
		"music": str(step.get("music", "")),
		"background": str(step.get("background", "")),
	}
	## Tick 472: thread the step's custom win_condition (if any)
	## through GameLoop.start_solo_battle → BattleManager. Shape:
	## {"type": "survive_turns"|"status_threshold", "value": int,
	## "status": String}. Cutscene author drops it inline on the
	## battle step; empty {} = default HP-zero (backwards compat).
	if step.has("win_condition") and step["win_condition"] is Dictionary:
		opts["win_condition"] = (step["win_condition"] as Dictionary).duplicate()
	if combatants.is_empty() or enemies.is_empty():
		push_warning("CutsceneDirector: battle step missing combatants or enemies — skipping")
		return
	var game_loop: Node = get_node_or_null("/root/GameLoop")
	if game_loop == null or not game_loop.has_method("start_solo_battle"):
		push_warning("CutsceneDirector: GameLoop.start_solo_battle unavailable — cutscene battle step skipped")
		return
	while true:
		# CutsceneDirector (layer 95) + CutsceneDialogue (96) render OVER the BattleScene (layer 0) —
		# without hiding, the spotlight battle plays under the cutscene UI and the player can't see it.
		visible = false
		if _dialogue != null and is_instance_valid(_dialogue):
			_dialogue.visible = false
		var result: String = await game_loop.start_solo_battle(str(combatants[0]), str(enemies[0]), opts)
		visible = true
		if _dialogue != null and is_instance_valid(_dialogue):
			_dialogue.visible = true
		if result == "victory":
			return
		if result != "defeat":
			# not retryable and must not complete-flag, or the duel gate never re-fires
			abort_current("battle step cannot run (result '%s')" % result)
			return
		match on_defeat:
			"retry":
				# instant restart reads as a glitch, not a retry
				await get_tree().create_timer(0.9).timeout
				continue
			"fail_forward", "skip":
				return
			_:
				push_warning("CutsceneDirector: unknown on_defeat '%s' — defaulting to retry" % on_defeat)
				continue
