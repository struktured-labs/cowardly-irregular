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


## The ticks are G pentatonic; on a boss win they land over stinger_boss_defeated (A-flat), a semitone rub (cowir-music 23498).
## So they play pitched to the music under them, from data/victory_letter_transpose.json (cowir-main 23499).
const SfxState := preload("res://test/unit/helpers/sfx_state.gd")


func after_each() -> void:
	for i in range(1, 8):
		SoundManager._sfx_cooldowns.erase("victory_letter_%d" % i)
	SfxState.release_streams()


func _under_keys() -> Array[String]:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/music_manifest.json"))
	var tracks: Dictionary = {}
	if parsed is Dictionary:
		tracks = (parsed as Dictionary).get("tracks", parsed)
	var out: Array[String] = []
	for k in tracks:
		if str(k).begins_with("victory") or str(k) == "stinger_boss_defeated":
			out.append(str(k))
	return out


func test_every_scene_under_the_letters_has_a_transpose() -> void:
	var keys := _under_keys()
	assert_gt(keys.size(), 6, "CONTROL: derived only %d victory beds + the boss stinger from the music manifest" % keys.size())
	var table: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/victory_letter_transpose.json")) as Dictionary).get("transpose", {})
	var missing: Array[String] = []
	for k in keys:
		if not table.has(k):
			missing.append(k)
	assert_eq(missing, [], "these can sound under the letters and have no transpose, so the ticks may clash with them: %s" % [missing])
	assert_eq(SoundManager.victory_letter_semitones("victory_medieval"), 0.0, "CONTROL: W1 is the key the ticks are written in")


func test_a_boss_win_plays_the_ticks_in_the_stingers_key() -> void:
	SoundManager.play_victory_letter(3, "stinger_boss_defeated")
	var p: AudioStreamPlayer = SoundManager._ui_player
	assert_not_null(p.stream, "the tick left no stream on the UI player")
	assert_almost_eq(p.pitch_scale, pow(2.0, -4.0 / 12.0), 0.001, "a boss win must pitch the ticks to the stinger, not jitter or leave them in G")
	SoundManager.play_victory_letter(3, "victory_medieval")
	assert_almost_eq(p.pitch_scale, 1.0, 0.001, "CONTROL: under the W1 bed the ticks play exactly as written")
	SoundManager.play_victory_letter(3, "no_such_bed")
	assert_almost_eq(p.pitch_scale, 1.0, 0.001, "an unlisted scene plays at 0, never silent")
