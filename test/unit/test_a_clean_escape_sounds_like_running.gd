extends GutTest

## ability_flee plays at the ATTEMPT, so a failed flee sounded exactly like a clean getaway (cowir-sfx 23484).
## escape_run is the success beat alone, timed to cowir-adhoc's sprint: five members 0.12 s apart, the last gone by ~1.05 s.

const MANIFEST := "res://data/sfx_manifest.json"
const SPRINT_ENDS_S := 1.05


func _sfx() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(parsed is Dictionary, "VOID: sfx_manifest.json did not parse")
	return (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}


func test_the_escape_has_its_own_sound_apart_from_the_attempt() -> void:
	var sfx := _sfx()
	assert_true(sfx.has("escape_run"), "escape_run missing: a clean escape plays nothing of its own")
	assert_true(sfx.has("ability_flee"), "CONTROL: the attempt cue must exist to compare against")
	var run := "res://" + str((sfx.get("escape_run", {}) as Dictionary).get("file", ""))
	var tryit := "res://" + str((sfx.get("ability_flee", {}) as Dictionary).get("file", ""))
	assert_true(ResourceLoader.exists(run), "escape_run -> %s does not load" % run)
	assert_ne(FileAccess.get_sha256(run), FileAccess.get_sha256(tryit), "escape_run IS the attempt cue, so success and failure still sound the same")


func test_the_run_lasts_as_long_as_the_sprint() -> void:
	var d := float((_sfx().get("escape_run", {}) as Dictionary).get("duration_seconds", 0.0))
	assert_gte(d, SPRINT_ENDS_S, "escape_run (%.2fs) ends before the last member leaves the screen" % d)
	assert_lte(d, 1.5, "escape_run (%.2fs) outlasts the fade it plays under" % d)
