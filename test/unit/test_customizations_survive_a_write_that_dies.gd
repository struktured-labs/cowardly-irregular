extends GutTest

## GameLoop._save_customizations opened user://save_data.json with FileAccess.open(…, WRITE) —
## which TRUNCATES on open — and ran JSON.stringify inside that window. It is called at :2661,
## immediately after character creation.
##
## ⛔ THE ONLY MEMBER OF THIS FAMILY WHERE BOTH SIDES WERE SILENT. The writer had no `else`; the
## reader returned [] on all four failure paths without a word. Every other instance today —
## load_settings (tick 347), load_config (tick 167), ControllerMappings.register_user_mappings,
## and a TEST author documenting truncate-on-open — had a hardened READER beside a silent writer.
## That is not the pattern's general case: it is what a file looks like AFTER somebody was burned
## on the read side. Where nobody has been burned, both sides are silent, and that is the state
## the other four started from.
##
## The file has two jobs: the global customization store, and the legacy single-save whose
## EXISTENCE gates the title screen's Continue button (TitleScreen:446, pinned by
## test_title_screen_continue_slot_consistency). A truncated file still passes file_exists, so
## Continue appears for a file that parses to nothing and the characters come back as defaults.
##
## ⚠️ ATOMICITY IS NOT UNIT-OBSERVABLE — it only shows under a crash inside the window. The
## load-bearing arms are source-shape ratchets, the idiom cowir-music established on the
## SaveSystem twin. The autoload arm at the end is a control, not a detector.

const SRC := "res://src/GameLoop.gd"


func _body_of(fn: String) -> String:
	var code: String = load(SRC).source_code
	var start: int = code.find("func %s(" % fn)
	assert_true(start >= 0, "CONTROL: %s not found in GameLoop — this file measures nothing" % fn)
	if start < 0:
		return ""
	var end: int = code.find("\nfunc ", start + 8)
	return code.substr(start, (end - start) if end > start else -1)


func test_the_writer_does_not_open_its_destination() -> void:
	var body := _body_of("_save_customizations")
	assert_false(body.contains("FileAccess.open(CUSTOMIZATIONS_PATH, FileAccess.WRITE)"),
		"_save_customizations opens the DESTINATION with WRITE — that truncates the player's characters before a byte of the replacement is written")
	assert_false(body.contains('FileAccess.open("user://save_data.json", FileAccess.WRITE)'),
		"same defect via the raw literal — the path constant exists so writer and reader cannot drift, not to disguise the open")


func test_the_payload_is_serialized_before_any_file_is_opened() -> void:
	## The ORDER is the defect: a stringify below the open means the file is empty for the whole
	## serialization; above it, the open happens with the bytes already in hand.
	var body := _body_of("_save_customizations")
	var stringify_at: int = body.find("JSON.stringify(")
	var open_at: int = body.find("FileAccess.open(")
	assert_true(stringify_at >= 0, "CONTROL: _save_customizations no longer serializes anything")
	assert_true(open_at >= 0, "CONTROL: _save_customizations no longer opens a file")
	assert_lt(stringify_at, open_at,
		"JSON.stringify runs AFTER the open — save_data.json is 0 bytes on disk for the whole serialization")


func test_a_short_write_refuses_the_rename() -> void:
	## store_string returns NOTHING, so a full disk is invisible and a rename would carry the
	## partial file into place as happily as a whole one (cowir-controller, cowir-music).
	var body := _body_of("_save_customizations")
	assert_true(body.contains("get_error()"),
		"nothing checks whether the staged write succeeded — staging does not survive a short write, because the rename moves a partial file in just as willingly")
	assert_true(body.contains("rename_absolute"),
		"the staged file must be renamed into place — a rename is atomic, so the file on disk is only ever the old customizations or the new")


func test_the_writer_is_no_longer_silent() -> void:
	var body := _body_of("_save_customizations")
	assert_true(body.contains("could not open"),
		"a failed open must say so — this writer returns void, so silence is indistinguishable from a save that worked")


func test_the_reader_speaks_on_a_truncated_file_but_not_on_a_missing_one() -> void:
	## The parse failure IS the truncation symptom, and it was one of four silent returns.
	## File-missing stays silent BY DESIGN: a first-run player legitimately has no save_data.json,
	## the same call load_settings made at tick 347.
	var body := _body_of("_load_customizations")
	assert_true(body.contains("is not valid JSON"),
		"a file that fails to parse must say so — 'characters silently reverted to defaults' is indistinguishable from a game that never saved them")
	var missing_at: int = body.find("file_exists(CUSTOMIZATIONS_PATH)")
	var first_warn: int = body.find("push_warning")
	assert_true(missing_at >= 0, "CONTROL: the reader no longer checks for a missing file")
	assert_lt(missing_at, first_warn,
		"the missing-file return must come BEFORE any warning — a first-run player must not be warned about a file they were never going to have")


func test_the_path_has_one_source_in_this_file() -> void:
	## The writer stages `<path>.new` and the reader opens `<path>`; a literal in one and a const
	## in the other is how those drift apart.
	var code: String = load(SRC).source_code
	assert_eq(code.count('"user://save_data.json"'), 1,
		"the path appears as a raw literal more than once in GameLoop — it should be the const declaration only, so the staged write and the read cannot disagree")


func test_every_member_this_file_reaches_for_still_exists() -> void:
	var gl: Node = autofree(load(SRC).new())
	for m in ["_save_customizations", "_load_customizations", "_save_exists"]:
		assert_true(gl.has_method(m), "GameLoop has no method %s — this file drives or pins it" % m)
	assert_true("CUSTOMIZATIONS_PATH" in load(SRC).get_script_constant_map(),
		"CUSTOMIZATIONS_PATH is gone — the constant this file asserts is the single source of the path")
