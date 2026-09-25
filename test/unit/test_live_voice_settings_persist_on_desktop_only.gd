extends GutTest

## Live voice settings round-trip through settings.json on desktop, and are skipped on web exactly like BYOK.

const SAVE_SYSTEM := "res://src/save/SaveSystem.gd"
const SETTINGS := "user://settings.json"
const FIELDS := ["tts_live_enabled", "tts_server_url", "tts_model"]

var _prior_existed: bool = false
var _prior_text: String = ""
var _saved: Dictionary = {}


func before_each() -> void:
	_prior_existed = FileAccess.file_exists(SETTINGS)
	_prior_text = FileAccess.get_file_as_string(SETTINGS) if _prior_existed else ""
	for f in FIELDS:
		_saved[f] = GameState.get(f)


func after_each() -> void:
	for f in FIELDS:
		GameState.set(f, _saved[f])
	if _prior_existed:
		var w := FileAccess.open(SETTINGS, FileAccess.WRITE)
		w.store_string(_prior_text)
		w.close()
	elif FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(SETTINGS)


func test_the_defaults_point_at_the_supported_local_server() -> void:
	var gs = load("res://src/meta/GameState.gd").new()
	assert_eq(gs.tts_live_enabled, false, "live voice is opt-in")
	assert_eq(gs.tts_server_url, "http://127.0.0.1:8004")
	assert_eq(gs.tts_model, "chatterbox", "chatterbox, not turbo: the engine struktured approved by ear")
	gs.free()


func test_the_settings_survive_a_save_and_load() -> void:
	GameState.tts_live_enabled = true
	GameState.tts_server_url = "http://127.0.0.1:9999"
	GameState.tts_model = "chatterbox-test"
	SaveSystem.save_settings()
	GameState.tts_live_enabled = false
	GameState.tts_server_url = "changed"
	GameState.tts_model = "changed"
	SaveSystem.load_settings()
	assert_eq(GameState.tts_live_enabled, true)
	assert_eq(GameState.tts_server_url, "http://127.0.0.1:9999")
	assert_eq(GameState.tts_model, "chatterbox-test")


func test_both_directions_sit_inside_the_web_gate() -> void:
	var src: String = FileAccess.get_file_as_string(SAVE_SYSTEM)
	for fn in ["func save_settings", "func load_settings"]:
		var at: int = src.find(fn)
		assert_gt(at, -1, "%s must exist" % fn)
		var end: int = src.find("\nfunc ", at + 1)
		var body: String = src.substr(at, (end if end != -1 else src.length()) - at)
		var gate: int = body.find("if not OS.has_feature(\"web\"):")
		assert_gt(gate, -1, "%s must gate on web" % fn)
		for f in FIELDS:
			var use: int = body.find(f)
			assert_gt(use, gate, "%s: %s must be written/read only after the web gate" % [fn, f])
