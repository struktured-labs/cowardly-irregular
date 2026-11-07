extends GutTest

## Forcing an MP-short ability (cowir-main 23445) needs two sounds of its own: the third press is ACCEPTED over an
## objection (menu_force_queue), and a cast still short at execution SPUTTERS (cast_fizzle), never the Corruption misfire.

const MANIFEST := "res://data/sfx_manifest.json"
const MUST_DIFFER := {"menu_force_queue": ["menu_select", "menu_error"], "cast_fizzle": ["corruption_misfire", "attack_miss"]}


func _sfx() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(parsed is Dictionary, "VOID: sfx_manifest.json did not parse")
	return (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}


func _file(sfx: Dictionary, key: String) -> String:
	return "res://" + str((sfx.get(key, {}) as Dictionary).get("file", ""))


func test_both_cues_exist_and_load() -> void:
	var sfx := _sfx()
	for k in MUST_DIFFER:
		assert_true(sfx.has(k), "%s missing: the force-queue path would play nothing or a stand-in" % k)
		assert_true(ResourceLoader.exists(_file(sfx, k)), "%s -> %s does not load" % [k, _file(sfx, k)])


func test_neither_cue_is_the_sound_it_must_not_be() -> void:
	var sfx := _sfx()
	var same: Array[String] = []
	for k in MUST_DIFFER:
		for other in MUST_DIFFER[k]:
			assert_true(FileAccess.file_exists(_file(sfx, str(other))), "CONTROL: %s must exist to compare against" % other)
			if FileAccess.get_sha256(_file(sfx, k)) == FileAccess.get_sha256(_file(sfx, str(other))):
				same.append("%s == %s" % [k, other])
	assert_eq(same, [], "a force-queue cue reuses the sound that means something else, so the player hears the wrong reason: %s" % [same])
