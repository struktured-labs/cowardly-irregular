extends GutTest

## Press Test Voice twice and the second press must SPEAK, not report success silently.
##
## The defect (measured 2026-10-14, before the fix): `_on_test_pressed` cleared its own
## `_testing` latch the moment it handed the stream to SoundManager, while the sample kept
## playing for seconds — so a second press was accepted. `play_voice_stream` has refused
## while the one voice player is busy since `93b8e9b66` (it exists to stop two PCs talking
## over each other in battle), and the panel discarded that return value, so the second press
## synthesised a line, dropped the audio, and painted `status_text()` in OK_COLOR. The panel's
## only job is telling the player whether the voice server works, and it reported a line the
## player never heard. Pressing a test button again is the first thing anyone does.
##
## The fix is one call: a deliberate press stops the sample still speaking before starting its
## own, so the press does what it says. The colour now derives from whether audio actually
## started; that half has no reachable failure today — a wedged mixer refuses the WAV decode
## first, so `stream` is already null — and it is NOT claimed as covered here.
##
## Fixture shape and the replay TTS backend are taken from
## test_the_live_voice_panel_speaks_and_refuses_web, not invented.

const Replay := preload("res://tools/replay_tts_backend.gd")
const DIR := "user://test_second_test_voice_press_cache"
const CLIP_SEC := 3.0
const LET_IT_RUN_MSEC := 800

var _saved_gs: Dictionary = {}
var _saved_cast: Dictionary
var _saved_cache
var _replay


func before_each() -> void:
	for f in ["tts_live_enabled", "tts_server_url", "tts_model"]:
		_saved_gs[f] = GameState.get(f)
	_saved_cast = VoiceService._cast.duplicate(true)
	_saved_cache = VoiceService.cache
	_wipe()
	VoiceService.cache = VoiceCache.new(DIR, 10_000_000)
	VoiceService._cast = {"bard": {"voice": "bard.wav", "rev": 1}}
	_replay = Replay.new()
	_replay.next_wav = WavFixture.tone(CLIP_SEC, 20000)
	VoiceService.test_backend = _replay


func after_each() -> void:
	VoiceService.test_backend = null
	if is_instance_valid(_replay) and not _replay.is_inside_tree():
		_replay.free()
	for f in _saved_gs:
		GameState.set(f, _saved_gs[f])
	VoiceService._cast = _saved_cast
	VoiceService.apply_config()
	VoiceService.cache = _saved_cache
	_wipe()
	if SoundManager != null and not SoundManager.mixer_is_wedged():
		SoundManager.stop_voice()


## A line cached by one run is a hit in the next and never reaches the backend.
func _wipe() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(DIR + "/" + f)
	DirAccess.remove_absolute(DIR)


## True when this environment cannot host the measurement at all, rather than failing it.
func _mixer_unusable() -> bool:
	if SoundManager == null or not SoundManager.mixer_is_wedged():
		return false
	assert_false(SoundManager.mixer_is_wedged(),
		"headless mixer wedged before the press — the WAV decode is refused, so nothing here spoke (issue #224)")
	return true


func _panel() -> LiveVoicePanel:
	GameState.tts_live_enabled = false
	var p := LiveVoicePanel.new()
	add_child_autofree(p)
	p._enabled_toggle.button_pressed = true
	return p


func _let_it_run() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < LET_IT_RUN_MSEC:
		await get_tree().process_frame


func _pos() -> float:
	return SoundManager._voice_player.get_playback_position()


# ── the normal case, which the fix must not break ─────────────────────────────

func test_a_first_press_speaks_and_reports_its_latency() -> void:
	if _mixer_unusable():
		return
	var p := _panel()
	await p._on_test_pressed()
	assert_eq(_replay.requests.size(), 1, "the press synthesised once: %s" % p._status_label.text)
	assert_not_null(SoundManager._voice_player.stream, "the synthesised line reached the voice player")
	assert_true(SoundManager._voice_player.playing, "and it is speaking")
	assert_string_contains(p._status_label.text, "ms", "the status reports the latency it measured")
	assert_eq(p._status_label.get_theme_color("font_color"), LiveVoicePanel.OK_COLOR,
		"OVER-REACH: a press that did speak still reports success")


# ── the defect ────────────────────────────────────────────────────────────────

func test_a_second_press_speaks_instead_of_being_swallowed() -> void:
	if _mixer_unusable():
		return
	var p := _panel()
	await p._on_test_pressed()
	assert_true(SoundManager._voice_player.playing, "PREMISE: the first press is speaking")
	await _let_it_run()
	## PREMISE: without an advancing playhead the two outcomes are indistinguishable, so this
	## arm must fail loudly here rather than pass on a frozen clock.
	var ran: float = _pos()
	assert_gt(ran, 0.4,
		"PREMISE: the playhead must advance in this environment for the measurement below to mean anything (read %.3fs of a %.1fs clip after %dms)" % [ran, CLIP_SEC, LET_IT_RUN_MSEC])
	if ran <= 0.4:
		return
	await p._on_test_pressed()
	assert_true(SoundManager._voice_player.playing, "the second press left the player speaking")
	var after: float = _pos()
	assert_lt(after, 0.4,
		"the second press must speak its OWN line from the start; %.3fs in means the FIRST line was never interrupted and the press was swallowed while the status claimed success" % after)
	assert_eq(_replay.requests.size(), 1,
		"the second press is a cache hit on the same line, so the backend saw one request")
	assert_ne(p._status_label.get_theme_color("font_color"), LiveVoicePanel.FAIL_COLOR,
		"a press that spoke must not read as a failure")


# ── floor, and MEASURED rather than argued: it is not the sole detector here ───
#
# Renaming SoundManager.stop_voice reds ALL THREE arms (Failing 3, Passing none) — the abort
# lands inside the panel's own frame, so the arms above judge its aftermath and say so by
# symptom: the stream never reached the player, nothing is speaking, the status is stuck on
# "Speaking…". That is the absorbed-abort case, and it holds only because those defaults are
# distinguishable from success.
#
# What this arm is load-bearing for is the TEARDOWN pair: `mixer_is_wedged` and `test_backend`
# are reached in after_each, where an abort does not fail this file at all — it strands
# VoiceService.test_backend and poisons whatever runs next. Named here so a rename fails in the
# file that owns the fixture.

func test_the_autoload_surface_this_file_drives_still_exists() -> void:
	for m in ["play_voice_stream", "stop_voice", "mixer_is_wedged"]:
		assert_true(SoundManager.has_method(m),
			"SoundManager.%s is reached by the panel this file drives" % m)
	assert_true(VoiceService.has_method("synthesize"),
		"VoiceService.synthesize is the call the press awaits")
	assert_true("test_backend" in VoiceService,
		"VoiceService.test_backend is how this file replaces the server")
