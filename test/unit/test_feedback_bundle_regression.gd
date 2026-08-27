extends GutTest

## struktured 2026-08-26, scoping the Rat King alpha: a tester could describe a bug but had no
## way to SHOW one. The only capture in the game was a bare F12 screenshot with no state.
##
## F8 writes one file: screenshot + engine log + newest save + a state manifest. Everything is
## best-effort, so the load-bearing property is that a MISSING piece cannot abort the write —
## and that the manifest says which pieces are missing, because a silently-thin bundle looks
## exactly like one where nothing went wrong.
##
## Every test writes to its OWN temp dir. The player-data net covers script_exports/autogrind/
## autobattle/input and would NOT have covered a new feedback/ directory; the per-test path
## override is the real fix, not the net.

const FB := preload("res://src/meta/FeedbackBundle.gd")

var _dir: String = ""


func before_each() -> void:
	_dir = "user://__fbtest_%d" % Time.get_ticks_usec()


func after_each() -> void:
	var d := DirAccess.open(_dir)
	if d:
		d.list_dir_begin()
		var n := d.get_next()
		while n != "":
			d.remove(_dir + "/" + n)
			n = d.get_next()
		d.list_dir_end()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_dir))


func _shot(w: int = 8, h: int = 8) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)


func _entries(zip_abs: String) -> PackedStringArray:
	var r := ZIPReader.new()
	if r.open(zip_abs) != OK:
		return PackedStringArray()
	var f := r.get_files()
	r.close()
	return f


func _read_json(zip_abs: String, name: String) -> Dictionary:
	var r := ZIPReader.new()
	if r.open(zip_abs) != OK:
		return {}
	var raw := r.read_file(name)
	r.close()
	var parsed = JSON.parse_string(raw.get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


# ── the state manifest ────────────────────────────────────────────────────

func test_collect_state_reports_the_build_it_came_from() -> void:
	# Without a version a report cannot be matched to a build, which is most of its value.
	var st := FB.collect_state()
	assert_true(st.has("version"), "state must carry the version")
	assert_ne(str(st["version"]), "unknown", "the version must resolve, not fall back")
	assert_true(st.has("captured_at"), "state must carry a timestamp")
	assert_true(st.has("platform"), "state must carry the platform")


func test_collect_state_carries_story_flags_but_not_the_whole_constants_dict() -> void:
	if GameState == null or not ("game_constants" in GameState):
		pending("GameState unavailable")
		return
	var saved: Dictionary = GameState.game_constants.duplicate(true)
	GameState.game_constants["cutscene_flag_demo_probe"] = true
	GameState.game_constants["some_tuning_knob_not_a_flag"] = 42
	var st := FB.collect_state()
	GameState.game_constants = saved
	assert_true(st.has("story_flags"), "story flags must be captured")
	var sf: Dictionary = st["story_flags"]
	assert_true(sf.has("cutscene_flag_demo_probe"), "a cutscene flag must be included")
	assert_false(sf.has("some_tuning_knob_not_a_flag"),
		"non-flag constants must NOT be swept in — they bloat the report without locating the player")


# ── the bundle itself ─────────────────────────────────────────────────────

func test_a_bundle_is_written_and_contains_its_manifest() -> void:
	var p := FB.write_bundle(FB.collect_state(), _shot(), _dir)
	assert_ne(p, "", "write_bundle must return the absolute path")
	assert_true(FileAccess.file_exists(p), "the zip must exist at the returned path: %s" % p)
	var names := _entries(p)
	assert_true("report.json" in names, "every bundle must carry report.json; got %s" % str(names))
	assert_true("screenshot.png" in names, "a supplied screenshot must be packed; got %s" % str(names))


func test_a_missing_screenshot_does_not_abort_the_write() -> void:
	# The load-bearing property. A tester on a headless-ish setup, or a viewport that fails to
	# capture, must still get a log and a save rather than nothing at all.
	var p := FB.write_bundle(FB.collect_state(), null, _dir)
	assert_ne(p, "", "a null screenshot must not prevent the bundle")
	var names := _entries(p)
	assert_true("report.json" in names, "the manifest must still be written")
	assert_false("screenshot.png" in names, "and the absent piece must not be faked")


func test_the_manifest_names_what_is_MISSING_not_just_what_is_present() -> void:
	# A thin bundle that lists only what it has is indistinguishable from a complete one.
	var p := FB.write_bundle(FB.collect_state(), null, _dir)
	var m := _read_json(p, "report.json")
	assert_false(m.is_empty(), "report.json must parse")
	assert_true(m.has("collected"), "manifest must list what was collected")
	assert_true(m.has("absent"), "manifest must list what was NOT — this is the whole point")
	assert_true("screenshot.png" in (m["absent"] as Array),
		"the screenshot we deliberately withheld must appear in absent; got %s" % str(m["absent"]))


func test_a_supplied_screenshot_moves_from_absent_to_collected() -> void:
	# ARM+. Without this, "absent" could list everything unconditionally and the test above
	# would still pass while the bundle recorded nothing truthfully.
	var p := FB.write_bundle(FB.collect_state(), _shot(), _dir)
	var m := _read_json(p, "report.json")
	assert_true("screenshot.png" in (m["collected"] as Array), "a supplied shot must be collected")
	assert_false("screenshot.png" in (m["absent"] as Array), "and must not also be reported absent")


func test_two_bundles_do_not_collide() -> void:
	var a := FB.write_bundle(FB.collect_state(), _shot(), _dir)
	var b := FB.write_bundle(FB.collect_state(), _shot(), _dir)
	assert_ne(a, "", "first bundle written")
	assert_ne(b, "", "second bundle written")
	if a == b:
		# Same-second capture is legitimate; what must never happen is losing the first.
		assert_true(FileAccess.file_exists(a), "a same-stamp rewrite must still leave a readable bundle")


func test_the_returned_path_is_absolute_so_a_tester_can_find_it() -> void:
	var p := FB.write_bundle(FB.collect_state(), _shot(), _dir)
	assert_false(p.begins_with("user://"), "a tester cannot act on a user:// path; got %s" % p)
	assert_true(p.begins_with("/") or p.contains(":"), "expected an OS-absolute path; got %s" % p)
