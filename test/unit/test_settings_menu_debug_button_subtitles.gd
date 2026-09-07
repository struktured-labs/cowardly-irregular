extends GutTest

## tick 235: extends tick 234's live-subtitle pattern to two more
## SettingsMenu debug-only action buttons.
##
## Jukebox: subtitle was "[DEBUG] Play any music track". Now shows
##   the currently-playing track from SoundManager._current_music,
##   e.g. "[DEBUG] Now: Overworld medieval" or "[DEBUG] Now: (silence)".
##
## Debug Teleport: subtitle was "[DEBUG] Warp to any map". Now shows
##   the current map from GameLoop.get_current_map_id, e.g.
##   "[DEBUG] At: Harmonia village".
##
## Both helpers follow the tick 234 shape: scene-tree-root autoload
## lookup, graceful fallback to the static text when autoload isn't
## reachable, live read each menu rebuild.

const SETTINGS_MENU := "res://src/ui/SettingsMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Jukebox subtitle helper ─────────────────────────────────────────

func test_jukebox_helper_present() -> void:
	var src := _read(SETTINGS_MENU)
	assert_true(src.contains("func _get_jukebox_subtitle() -> String:"),
		"_get_jukebox_subtitle helper must exist")


func test_jukebox_helper_reads_soundmanager_via_root() -> void:
	var src := _read(SETTINGS_MENU)
	var fn_idx: int = src.find("func _get_jukebox_subtitle")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, src.length() - fn_idx) if next_fn < 0 else src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("get_node_or_null(\"/root/SoundManager\")"),
		"jukebox helper must use scene-tree-root autoload lookup")
	assert_true(body.contains("\"_current_music\" in sm"),
		"jukebox helper must check for _current_music property before reading")


func test_jukebox_helper_fallback_when_sm_missing() -> void:
	var src := _read(SETTINGS_MENU)
	var fn_idx: int = src.find("func _get_jukebox_subtitle")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, src.length() - fn_idx) if next_fn < 0 else src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("return \"[DEBUG] Play any music track\""),
		"jukebox helper must fall back to the original static subtitle")


func test_jukebox_silence_branch() -> void:
	# Pin: empty current track shows "(silence)" — clearer than
	# pretending nothing was set.
	var src := _read(SETTINGS_MENU)
	var fn_idx: int = src.find("func _get_jukebox_subtitle")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, src.length() - fn_idx) if next_fn < 0 else src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("return \"[DEBUG] Now: (silence)\""),
		"empty current track must show '(silence)' explicitly")


# ── Debug Teleport subtitle helper ──────────────────────────────────

func test_debug_teleport_helper_present() -> void:
	var src := _read(SETTINGS_MENU)
	assert_true(src.contains("func _get_debug_teleport_subtitle() -> String:"),
		"_get_debug_teleport_subtitle helper must exist")


func test_debug_teleport_helper_reads_gameloop_via_root() -> void:
	var src := _read(SETTINGS_MENU)
	var fn_idx: int = src.find("func _get_debug_teleport_subtitle")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, src.length() - fn_idx) if next_fn < 0 else src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("get_node_or_null(\"/root/GameLoop\")"),
		"teleport helper must use scene-tree-root autoload lookup")
	assert_true(body.contains("gl.has_method(\"get_current_map_id\")"),
		"teleport helper must check for get_current_map_id method")


func test_debug_teleport_helper_fallback_when_gl_missing() -> void:
	var src := _read(SETTINGS_MENU)
	var fn_idx: int = src.find("func _get_debug_teleport_subtitle")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, src.length() - fn_idx) if next_fn < 0 else src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("return \"[DEBUG] Warp to any map\""),
		"teleport helper must fall back to the original static subtitle")


# ── Wiring at the action-button add sites ───────────────────────────

func test_jukebox_button_uses_dynamic_subtitle() -> void:
	var src := _read(SETTINGS_MENU)
	assert_true(src.contains("add_action.call(\"Jukebox\", _get_jukebox_subtitle(), \"jukebox\")"),
		"Jukebox button must use _get_jukebox_subtitle()")


func test_debug_teleport_button_uses_dynamic_subtitle() -> void:
	var src := _read(SETTINGS_MENU)
	assert_true(src.contains("add_action.call(\"Debug Teleport\", _get_debug_teleport_subtitle(), \"debug_teleport\")"),
		"Debug Teleport button must use _get_debug_teleport_subtitle()")


# ── Negative pins: pre-fix static literals gone from the call sites ──

func test_jukebox_static_subtitle_gone_from_call_site() -> void:
	# The static "[DEBUG] Play any music track" literal still lives
	# inside the helper's fallback branch — that's fine. But the
	# add_action.call site itself must use the helper now.
	var src := _read(SETTINGS_MENU)
	assert_false(src.contains("add_action.call(\"Jukebox\", \"[DEBUG] Play any music track\""),
		"pre-fix static-subtitle Jukebox call must be gone")


func test_debug_teleport_static_subtitle_gone_from_call_site() -> void:
	var src := _read(SETTINGS_MENU)
	assert_false(src.contains("add_action.call(\"Debug Teleport\", \"[DEBUG] Warp to any map\""),
		"pre-fix static-subtitle Debug Teleport call must be gone")


# ── Live runtime checks ────────────────────────────────────────────

func test_jukebox_subtitle_at_runtime() -> void:
	var cls = load(SETTINGS_MENU)
	var menu = cls.new()
	add_child_autofree(menu)
	var subtitle: String = menu._get_jukebox_subtitle()
	# Either fallback OR live shape ("[DEBUG] Now: <something>").
	var is_fallback: bool = subtitle == "[DEBUG] Play any music track"
	var has_live_shape: bool = subtitle.begins_with("[DEBUG] Now: ")
	assert_true(is_fallback or has_live_shape,
		"jukebox subtitle must match fallback OR '[DEBUG] Now: ...' shape, got: '%s'" % subtitle)


func test_debug_teleport_subtitle_at_runtime() -> void:
	var cls = load(SETTINGS_MENU)
	var menu = cls.new()
	add_child_autofree(menu)
	var subtitle: String = menu._get_debug_teleport_subtitle()
	var is_fallback: bool = subtitle == "[DEBUG] Warp to any map"
	var has_live_shape: bool = subtitle.begins_with("[DEBUG] At: ")
	assert_true(is_fallback or has_live_shape,
		"teleport subtitle must match fallback OR '[DEBUG] At: ...' shape, got: '%s'" % subtitle)


# ── Cross-pin: tick 234 Controls subtitle preserved ─────────────────

func test_tick_234_controls_subtitle_preserved() -> void:
	var src := _read(SETTINGS_MENU)
	assert_true(src.contains("func _get_controls_subtitle() -> String:"),
		"tick 234 _get_controls_subtitle preserved")
	assert_true(src.contains("add_action.call(\"Controls\", _get_controls_subtitle(), \"controls\")"),
		"tick 234 Controls wiring preserved")
