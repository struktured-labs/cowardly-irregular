extends GutTest

## User complaint 2026-07-04: background agents running GUT suites
## emitted audible SFX/music through the user's speakers — one
## invocation per agent, all at once. Any headless invocation
## (--headless, GUT, CI) must be silent. SoundManager mutes the master
## bus at _ready when it detects headless mode; play_ui/play_battle/
## play_music remain callable but produce zero output.


func test_master_bus_muted_under_headless() -> void:
	# When this test is running, we ARE headless — the bus should already be muted.
	assert_true(AudioServer.is_bus_mute(0),
		"master bus must be muted in headless runs — otherwise background agents emit audio through the user's speakers")


func test_soundmanager_detects_headless_at_ready() -> void:
	# Source pin: the mute must run from _ready, not opt-in via a caller.
	# Otherwise a caller that predates the fix keeps making noise.
	var src: String = FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")
	var ready: int = src.find("func _ready()")
	assert_gt(ready, -1)
	var end_next: int = src.find("\nfunc ", ready + 1)
	var body: String = src.substr(ready, end_next - ready)
	assert_true(body.contains("AudioServer.set_bus_mute(0, true)"),
		"_ready must mute the master bus on headless — per-caller guards drift")
	assert_true(body.contains("OS.has_feature(\"headless\")") or body.contains("DisplayServer.get_name() == \"headless\""),
		"headless detection must be present")
