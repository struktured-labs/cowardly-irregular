extends CanvasLayer
class_name InnRestSequence

## A night at the inn as a BEAT, not a dialogue line (struktured 2026-11-01: "when u rest at the inn it should have a
## satisfying fade out/in sequence with accompanying ditty"): the music dips, the room dims to night, the rest ditty
## plays through the night, and the room comes back on morning. Since 2026-11-12 (the moon glyph and three Z's were
## "really lame") the night is a small scene: InnNightSky's pixel sky, the moon crossing it for as long as the ditty
## plays, dawn climbing, and the rest named in the damage numbers' pixel letters as morning arrives.
##
## THE HEAL IS THE CALLER'S, AND IT LANDS FIRST, in the same step as the payment: nothing on the field shows party HP, so
## healing before the fade looks identical to healing in the dark, and a scene change mid-fade can never leave a paid rest
## unhealed. A skip shortens only the night. Morning goes through GameState.set_day_phase, which fires
## time_of_day_changed, because the soundscape, the night music filter and VillageLighting all listen for the signal
## rather than reading the field.
## WALL CLOCK. The tweens ignore time_scale and the night is timed in real milliseconds, so a battle-speed setting or a
## hit-stop can neither stretch nor skip it. Input is held under one InputLockManager lock for the whole beat.

signal finished(skipped: bool)
## The scene's beats, for whoever scores them (cowir-sfx 24204): "night_falls" as the room dims, "night" as the sky
## opens, "dawn" as the light climbs, and "stopped" when a skip or an abort cuts the night short.
signal beat(name: String)

const FADE_OUT_SEC := 0.6
const FADE_IN_SEC := 0.8
const SKY_IN_SEC := 0.3
## The room under the night: dimmed to deep blue, not blacked out, so the fade reads as the lamps going down.
const NIGHT_TINT := Color(0.02, 0.03, 0.10)
const READOUT_TINT := Color(1.0, 0.95, 0.75)
## The night lasts the ditty, never less than this: a missing or very short cue must not make the beat a blink.
const MIN_NIGHT_SEC := 2.5
## How long the ditty may take to start sounding before the night stops waiting for it, and how far past its length the night may run.
const DITTY_GRACE_SEC := 0.5
const NIGHT_OVERRUN_SEC := 1.5
const DITTY_KEY := "inn_rest_ditty"
const FALLBACK_CUE := "inn_rest"
const LOCK_ID := "inn_rest"
## Early in "dawn" (GameState bands it 0.0-0.10), so a rest always wakes to first light.
const MORNING_PHASE := 0.02

var skipped := false
## True when the inn went away mid-night: the caller must not carry on as if the morning arrived.
var aborted := false
var night_sec := 0.0
## The night's clock is the ditty itself (cowir-music 24561): where it is HEARD is how far the night has come.
var _ditty_len := 0.0
var _ditty_heard := false
var _ditty_at := 0.0
var _on_frame_clock := false
## Seconds into the ditty as heard, or -1.0 when it is not the stream sounding. A test hands in its own.
var _ditty_position: Callable = func() -> float:
	return SoundManager.music_position_of(DITTY_KEY) if SoundManager and SoundManager.has_method("music_position_of") else -1.0

var _rect: ColorRect
var _sky: InnNightSky
var _readout: Node2D
## What the morning says, one line each; the caller may name who was restored (set it right after start()).
var restored_lines: PackedStringArray = ["HP + MP RESTORED"]
var _host: Node = null
var _dawn_sent := false
var _skippable := false
var _skip_requested := false
var _done := false
var _lock_held := false


## Plays the beat over everything and returns the node; `await seq.finished` for the end.
static func start(host: Node) -> InnRestSequence:
	var seq := InnRestSequence.new()
	seq._host = host
	host.get_tree().root.add_child(seq)
	## The inn going away mid-night (a scene change, a freed test room) ends the beat at once: the lock never outlives it.
	host.tree_exiting.connect(seq._abort, CONNECT_ONE_SHOT)
	seq._run()
	return seq


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = NIGHT_TINT
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.modulate.a = 0.0
	add_child(_rect)
	_sky = InnNightSky.new()
	_sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sky.modulate.a = 0.0
	add_child(_sky)
	_readout = Node2D.new()
	_readout.modulate = Color(READOUT_TINT.r, READOUT_TINT.g, READOUT_TINT.b, 0.0)
	add_child(_readout)


## The readout's glyph pixel: three screen pixels at 100%, stepping up in whole pixels with Text Size.
static func readout_px() -> int:
	return maxi(2, roundi(float(TextScale.scaled(30)) / 10.0))


## One line of pixel letters per restored line, centred low in the sky on whole pixels.
func _build_readout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_readout.position = Vector2(vp.x / 2.0, vp.y * 0.70).round()
	var px := readout_px()
	for i in restored_lines.size():
		var line := PixelText.new(str(restored_lines[i]).to_upper(), px)
		line.position = Vector2(0.0, float(i * (PixelText.ROWS + 4) * px))
		_readout.add_child(line)


## The room's own lighting, if it has a rig (cowir-overworld's InteriorLighting, main 24201): "night" and "dawn".
func _room_light(phase: String) -> void:
	if _host != null and is_instance_valid(_host) and _host.has_method("rest_light"):
		_host.rest_light(phase)


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
	beat.emit("night_falls")
	_room_light("night")
	await _fade(1.0, FADE_OUT_SEC)
	if _done:
		return

	if GameState and GameState.has_method("set_day_phase"):
		GameState.set_day_phase(MORNING_PHASE)

	_ditty_len = _play_ditty()
	night_sec = maxf(_ditty_len, MIN_NIGHT_SEC)
	_skippable = true
	_build_readout()
	_sky.set_night(0.0, 0.0)
	beat.emit("night")
	var sky_tw := create_tween().set_ignore_time_scale(true)
	sky_tw.tween_property(_sky, "modulate:a", 1.0, SKY_IN_SEC)
	## `elapsed` is frame time with the battle-speed scale divided out: the fallback clock, and the bound on the night.
	var elapsed := 0.0
	while not _skip_requested:
		var p: float = night_progress(elapsed)
		if p >= 1.0:
			break
		_show_night(p, p * night_sec)
		await get_tree().process_frame
		if _done:
			return
		elapsed += get_process_delta_time() / maxf(Engine.time_scale, 0.01)
	skipped = _skip_requested
	_skippable = false
	## A skip jumps to the morning it would have reached: the last frame of the night is dawn either way.
	if skipped:
		beat.emit("stopped")
	_show_night(1.0, night_sec)

	if SoundManager and SoundManager.has_method("restore_music_state"):
		SoundManager.restore_music_state(bed)
	var out_tw := create_tween().set_ignore_time_scale(true).set_parallel(true)
	out_tw.tween_property(_sky, "modulate:a", 0.0, FADE_IN_SEC)
	out_tw.tween_property(_readout, "modulate:a", 0.0, FADE_IN_SEC * 0.6)
	await _fade(0.0, FADE_IN_SEC)
	_finish(skipped)


## How far the night has come, 0..1. While the ditty sounds, its own position; once it has been heard and stops, the
## night is over; if it never starts (no file, muted, a browser that has not unlocked audio), the frame clock.
func night_progress(elapsed: float) -> float:
	if night_sec <= 0.0 or elapsed > night_sec + NIGHT_OVERRUN_SEC:
		return 1.0
	if _on_frame_clock or _ditty_len < MIN_NIGHT_SEC:
		return clampf(elapsed / night_sec, 0.0, 1.0)
	var at: float = float(_ditty_position.call())
	if at < 0.0:
		if _ditty_heard:
			return 1.0
		if elapsed > DITTY_GRACE_SEC:
			_on_frame_clock = true
			return clampf(elapsed / night_sec, 0.0, 1.0)
		return 0.0
	_ditty_heard = true
	## A position that goes backwards is the stream starting over: the night does not.
	if at + 0.25 < _ditty_at:
		return 1.0
	_ditty_at = maxf(_ditty_at, at)
	return clampf(_ditty_at / _ditty_len, 0.0, 1.0)


## One frame of the night: the sky at `p`, and the rest named once dawn starts to climb.
func _show_night(p: float, seconds: float) -> void:
	_sky.set_night(p, seconds)
	var d: float = _sky.dawn()
	if d > 0.0 and not _dawn_sent:
		_dawn_sent = true
		beat.emit("dawn")
		_room_light("dawn")
	_readout.modulate.a = clampf(d * 2.0, 0.0, 1.0)


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
	if not _done:
		beat.emit("stopped")
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
