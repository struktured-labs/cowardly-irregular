extends CanvasLayer
class_name InnRestSequence

## A night at the inn as a BEAT, not a dialogue line (struktured 2026-11-01: "when u rest at the inn it should have a
## satisfying fade out/in sequence with accompanying ditty"): the music dips, the screen fades to black, the rest ditty
## plays through the night, and the screen fades back in on morning.
##
## THE HEAL IS THE CALLER'S, AND IT LANDS FIRST, in the same step as the payment: nothing on the field shows party HP, so
## healing before the fade looks identical to healing in the dark, and a scene change mid-fade can never leave a paid rest
## unhealed. A skip shortens only the night. Morning goes through GameState.set_day_phase, which fires
## time_of_day_changed, because the soundscape, the night music filter and VillageLighting all listen for the signal
## rather than reading the field.
## WALL CLOCK. The tweens ignore time_scale and the night is timed in real milliseconds, so a battle-speed setting or a
## hit-stop can neither stretch nor skip it. Input is held under one InputLockManager lock for the whole beat.

signal finished(skipped: bool)

const FADE_OUT_SEC := 0.6
const FADE_IN_SEC := 0.8
## The night lasts the ditty, never less than this: a missing or very short cue must not make the beat a blink.
const MIN_NIGHT_SEC := 2.5
const DITTY_KEY := "inn_rest_ditty"
const FALLBACK_CUE := "inn_rest"
const LOCK_ID := "inn_rest"
## Early in "dawn" (GameState bands it 0.0-0.10), so a rest always wakes to first light.
const MORNING_PHASE := 0.02

var skipped := false
## True when the inn went away mid-night: the caller must not carry on as if the morning arrived.
var aborted := false
var night_sec := 0.0

var _rect: ColorRect
var _moon: Label
var _skippable := false
var _skip_requested := false
var _done := false
var _lock_held := false


## Plays the beat over everything and returns the node; `await seq.finished` for the end.
static func start(host: Node) -> InnRestSequence:
	var seq := InnRestSequence.new()
	host.get_tree().root.add_child(seq)
	## The inn going away mid-night (a scene change, a freed test room) ends the beat at once: the lock never outlives it.
	host.tree_exiting.connect(seq._abort, CONNECT_ONE_SHOT)
	seq._run()
	return seq


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color.BLACK
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.modulate.a = 0.0
	add_child(_rect)
	_moon = Label.new()
	_moon.text = "☾  z z z"
	_moon.set_anchors_preset(Control.PRESET_CENTER)
	# A zero-size label anchored at the centre grows right by default, so its left edge sat on the middle of the screen.
	_moon.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_moon.grow_vertical = Control.GROW_DIRECTION_BOTH
	_moon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_moon.add_theme_color_override("font_color", Color(0.85, 0.85, 1.0))
	_moon.add_theme_font_size_override("font_size", TextScale.scaled(28))
	_moon.modulate.a = 0.0
	_rect.add_child(_moon)


func _run() -> void:
	if not is_inside_tree():
		await ready
	var ilm := get_tree().root.get_node_or_null("InputLockManager")
	if ilm:
		ilm.push_lock(LOCK_ID)
		_lock_held = true
	var bed: Dictionary = SoundManager.capture_music_state() if SoundManager and SoundManager.has_method("capture_music_state") else {}
	if SoundManager and SoundManager.has_method("fade_out_music"):
		SoundManager.fade_out_music(FADE_OUT_SEC)
	await _fade(1.0, FADE_OUT_SEC)
	if _done:
		return

	if GameState and GameState.has_method("set_day_phase"):
		GameState.set_day_phase(MORNING_PHASE)

	night_sec = maxf(_play_ditty(), MIN_NIGHT_SEC)
	_skippable = true
	var moon_tw := create_tween().set_ignore_time_scale(true)
	moon_tw.tween_property(_moon, "modulate:a", 1.0, 0.4)
	var started := Time.get_ticks_msec()
	while not _skip_requested and float(Time.get_ticks_msec() - started) / 1000.0 < night_sec:
		await get_tree().process_frame
		if _done:
			return
	skipped = _skip_requested
	_skippable = false
	_moon.modulate.a = 0.0

	if SoundManager and SoundManager.has_method("restore_music_state"):
		SoundManager.restore_music_state(bed)
	await _fade(0.0, FADE_IN_SEC)
	_finish(skipped)


func _finish(was_skipped: bool) -> void:
	if _done:
		return
	_done = true
	var ilm := get_tree().root.get_node_or_null("InputLockManager") if is_inside_tree() else null
	if ilm and _lock_held:
		ilm.pop_lock(LOCK_ID)
	_lock_held = false
	finished.emit(was_skipped)
	queue_free()


func _abort() -> void:
	aborted = true
	skipped = true
	_finish(true)


## Freed without the beat ending (the root torn down, a caller freeing it): the lock must not outlive the node.
func _exit_tree() -> void:
	if not _done:
		_abort()


## The ditty's length in seconds, 0.0 if nothing with a length played. A missing cue falls back to the old rest chime.
func _play_ditty() -> float:
	if SoundManager == null:
		return 0.0
	if SoundManager.has_method("has_music_track") and SoundManager.has_music_track(DITTY_KEY):
		SoundManager.play_music(DITTY_KEY, true)
		var player: AudioStreamPlayer = SoundManager.get("_music_player")
		if player and player.stream:
			return player.stream.get_length()
		return 0.0
	SoundManager.play_ui(FALLBACK_CUE)
	return 0.0


func _fade(to_alpha: float, sec: float) -> void:
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_property(_rect, "modulate:a", to_alpha, sec)
	await tw.finished


## Skippable only once the night has begun: never mid-fade, and the heal has always run by then.
func _input(event: InputEvent) -> void:
	if not _skippable or event.is_echo():
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		_skip_requested = true
		get_viewport().set_input_as_handled()


## Test seam: the same skip a button press makes.
func request_skip() -> void:
	if _skippable:
		_skip_requested = true
