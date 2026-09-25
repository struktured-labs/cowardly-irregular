extends GutTest

## Test Voice must speak through the live path with the TYPED settings; the panel and its row never exist on web.

const Replay := preload("res://tools/replay_tts_backend.gd")
const MENU := "res://src/ui/SettingsMenu.gd"
const PANEL := "res://src/ui/LiveVoicePanel.gd"
const DIR := "user://test_live_voice_panel_cache"

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
	_replay.next_wav = WavFixture.tone(0.3, 20000)
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
	SoundManager.stop_voice()


## A line cached by one run is a hit in the next and never reaches the backend, so every run starts empty.
func _wipe() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(DIR + "/" + f)
	DirAccess.remove_absolute(DIR)


func test_test_voice_speaks_a_cast_line_through_play_voice_stream() -> void:
	GameState.tts_live_enabled = false
	var p := LiveVoicePanel.new()
	add_child_autofree(p)
	p._enabled_toggle.button_pressed = true
	await p._on_test_pressed()
	assert_eq(_replay.requests.size(), 1, "the TYPED enable is what the test uses: %s" % p._status_label.text)
	assert_eq(_replay.requests[0]["voice"], "bard.wav")
	assert_not_null(SoundManager._voice_player.stream, "the synthesized line reached the voice player")
	assert_string_contains(p._status_label.text, "ms")


func test_cancel_restores_the_settings_the_panel_opened_with() -> void:
	GameState.tts_live_enabled = false
	GameState.tts_server_url = "http://127.0.0.1:8004"
	var p := LiveVoicePanel.new()
	add_child(p)
	p._enabled_toggle.button_pressed = true
	p._url_field.text = "http://127.0.0.1:1"
	await p._on_test_pressed()
	p._on_cancel_pressed()
	assert_eq(GameState.tts_live_enabled, false, "Test applied the typed values; Cancel must put them back")
	assert_eq(GameState.tts_server_url, "http://127.0.0.1:8004")


func test_status_text_names_missing_voices_and_the_supported_server() -> void:
	var t := LiveVoicePanel.status_text({"enabled": true, "ready": true, "url": "http://127.0.0.1:8004",
		"last_latency_ms": 812, "last_error": "", "clipping_detected": true, "missing_voices": ["mage.wav"]})
	assert_string_contains(t, "mage.wav")
	assert_string_contains(t, "915ae28", "the clipping warning names the supported server")
	assert_string_contains(LiveVoicePanel.status_text({"enabled": false}), "off")


func test_the_row_and_the_open_helper_are_desktop_only() -> void:
	var src: String = FileAccess.get_file_as_string(MENU)
	var row: int = src.find("\"Configure Live Voice\"")
	assert_gt(row, -1, "the Settings row exists")
	var gate: int = src.rfind("if not OS.has_feature(\"web\"):", row)
	assert_gt(gate, -1)
	assert_eq(src.substr(gate, row - gate).count("\n"), 2, "the gate is the line immediately above the add_action call")
	var at: int = src.find("func _open_live_voice_config")
	assert_gt(at, -1)
	assert_true(src.substr(at, 120).contains("if OS.has_feature(\"web\"):"), "belt and braces, like _open_byok_config")
	assert_true(FileAccess.get_file_as_string(PANEL).contains("if OS.has_feature(\"web\"):"), "the panel refuses to build on web")


## A guard site enumerates several panel flags; _open_byok_config's own lines name only BYOK's and are not one.
const OTHER_FLAGS := ["_rebalance_review_open", "_jukebox_submenu_open", "_rebalance_history_open"]


func test_every_guard_that_knows_the_byok_panel_knows_this_one() -> void:
	var lines: PackedStringArray = FileAccess.get_file_as_string(MENU).split("\n")
	var sites := 0
	var missing: Array[String] = []
	for i in lines.size():
		if not lines[i].contains("_byok_config_open") or lines[i].strip_edges().begins_with("var "):
			continue
		var window: String = "\n".join(lines.slice(maxi(0, i - 2), i + 3))
		if not OTHER_FLAGS.any(func(f): return window.contains(f)):
			continue
		sites += 1
		if not window.contains("_live_voice_config_open"):
			missing.append("%d: %s" % [i + 1, lines[i].strip_edges()])
	assert_true(sites >= 3, "VOID: found only %d guard sites (expected _process, _input and the failsafe reset)" % sites)
	var src: String = FileAccess.get_file_as_string(MENU)
	assert_true(src.contains("path.ends_with(\"LiveVoicePanel.gd\")"), "the stuck-flag failsafe must recognise the panel")
	assert_eq(missing, [] as Array[String], "a guard that forgets this panel strands input: %s" % [missing])
