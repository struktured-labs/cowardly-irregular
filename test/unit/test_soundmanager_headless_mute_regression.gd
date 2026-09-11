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


func test_the_mute_is_CONDITIONAL_and_not_unconditional() -> void:
	## ⛔ THE DIRECTION THIS FILE WAS BLIND TO, and it is the worst one in the lane.
	##
	## Both assertions here are one-sided: the bus IS muted, and the source DOES contain the mute
	## call and the headless check. Make the mute UNCONDITIONAL — delete the `if`, leave both strings
	## in the file — and every one of them still passes, because this test runs headless so the bus
	## is muted either way. The shipped game would be COMPLETELY SILENT and nothing would fail.
	##
	## That is the zero-instance, maximum-consequence shape: audio failing silently is
	## indistinguishable from audio working, and no downstream gate disagrees — the render smoke
	## screenshots a picture, and a muted build exports, boots and plays.
	##
	## A GUT test cannot observe the non-headless branch (it IS the headless branch), so this asserts
	## the STRUCTURE instead: every master-bus mute must be nested under a line that tests for
	## headless. Structure is what a test running on one side of a branch can still see.
	var src := FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")
	assert_ne(src, "", "SoundManager.gd unreadable — this guard would pass vacuously")
	var lines := src.split("\n")

	var found := 0
	var unguarded: Array = []
	for i in range(lines.size()):
		var line: String = lines[i]
		if not line.contains("set_bus_mute(0, true)"):
			continue
		found += 1
		var indent: int = line.length() - line.strip_edges(true, false).length()
		## walk UP for a less-indented `if` that tests headless
		var guarded := false
		var j := i - 1
		while j >= 0 and j > i - 12:
			var prev: String = lines[j]
			var stripped: String = prev.strip_edges()
			if stripped == "" or stripped.begins_with("#"):
				j -= 1
				continue
			var prev_indent: int = prev.length() - prev.strip_edges(true, false).length()
			if prev_indent < indent and stripped.begins_with("if "):
				guarded = stripped.contains("headless")
				break
			if prev_indent < indent:
				break
			j -= 1
		if not guarded:
			unguarded.append("line %d: %s" % [i + 1, line.strip_edges()])

	assert_eq(found, 1,
		"expected exactly ONE master-bus mute in SoundManager (found %d) — more than one means a second path can silence the game" % found)
	assert_eq(unguarded.size(), 0,
		"a master-bus mute is NOT nested under a headless check — the shipped game would be silent and every other assertion in this file would still pass: %s" % [unguarded])
	## CONTROL: the walker must be able to SEE the guard it is looking for, or 0 unguarded is vacuous.
	assert_true(src.contains("if DisplayServer.get_name() == \"headless\" or OS.has_feature(\"headless\"):"),
		"control: the headless condition is not in the shape this walker recognises — it may be reporting 0 because it cannot parse the guard, not because the guard is there")


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
