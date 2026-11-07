extends GutTest

## The SNES victory beat drops VICTORY! in one letter at a time (cowir-cutscenes 23487); letters 1-7 each land on a tick.
## Seven keys, never one replayed: SoundManager's per-key cooldown would swallow ticks 50 ms apart.

const MANIFEST := "res://data/sfx_manifest.json"
const LANDING_GAP_S := 0.05


func _sfx() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(parsed is Dictionary, "VOID: sfx_manifest.json did not parse")
	return (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}


func test_seven_ticks_exist_each_its_own_file() -> void:
	var sfx := _sfx()
	var files := {}
	for i in range(1, 8):
		var k := "victory_letter_%d" % i
		assert_true(sfx.has(k), "%s missing: that letter would land in silence" % k)
		var f := "res://" + str((sfx.get(k, {}) as Dictionary).get("file", ""))
		assert_true(ResourceLoader.exists(f), "%s -> %s does not load" % [k, f])
		files[FileAccess.get_sha256(f)] = k
	assert_eq(files.size(), 7, "two letter ticks are the same file, so the rise into the slam has a flat step")


func test_a_tick_ends_before_the_next_letter_lands() -> void:
	var sfx := _sfx()
	var long: Array[String] = []
	for i in range(1, 8):
		var d := float((sfx.get("victory_letter_%d" % i, {}) as Dictionary).get("duration_seconds", 1.0))
		if d >= LANDING_GAP_S:
			long.append("victory_letter_%d (%.3fs)" % [i, d])
	assert_eq(long, [], "a tick outlasts the %.2f s gap between landings, so consecutive letters smear: %s" % [LANDING_GAP_S, long])
