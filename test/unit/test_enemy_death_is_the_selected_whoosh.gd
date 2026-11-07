extends GutTest

## The normal monster-death cue is the selected audition file, on the cue that already
## plays it. Solo F_whoosh.ogg (airy burn), copied byte for byte over enemy_death.ogg.
## play_death("enemy_death") and the death tween are unchanged: a shorter file is not
## a new hold, and bosses stay on this cue because _on_enemy_died has one death cry.
## W4's industrial variant and the ally / injury cues are different files.

const ASSET := "res://assets/audio/sfx/enemy_death.ogg"
const W4_ASSET := "res://assets/audio/sfx/w4_enemy_death.ogg"
const MANIFEST := "res://data/sfx_manifest.json"
const AUDITION_SHA := "99346040269494fdbd937621dec8ba8b44798c34712c2ffc7f6861029c1a6db6"
const AUDITION_SECONDS := 0.84


func _entry() -> Dictionary:
	var raw := FileAccess.get_file_as_string(MANIFEST)
	assert_ne(raw, "", "sfx_manifest unreadable — the pins below would be vacuous")
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "sfx_manifest did not parse")
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {})
	assert_true(sfx.has("enemy_death"), "enemy_death cue missing — the death cry was renamed")
	return sfx["enemy_death"]


func test_the_shipped_file_is_the_audition_ogg() -> void:
	assert_true(FileAccess.file_exists(ASSET), "enemy_death.ogg missing")
	var bytes := FileAccess.get_file_as_bytes(ASSET)
	assert_gt(bytes.size(), 200, "enemy_death.ogg is too small to be the 13960-byte audition")
	assert_eq(bytes.slice(0, 4), "OggS".to_ascii_buffer(),
		"enemy_death.ogg is not Ogg Vorbis — an LFS pointer or a text stand-in shipped in its place")
	assert_false(bytes.slice(0, 12) == "version http".to_ascii_buffer(),
		"enemy_death.ogg is an LFS pointer, not the audio")
	assert_eq(FileAccess.get_sha256(ASSET), AUDITION_SHA,
		"enemy_death.ogg is not the selected F_whoosh audition (sha256 %s)" % AUDITION_SHA)
	var stream := load(ASSET) as AudioStream
	assert_not_null(stream, "enemy_death.ogg did not import as audio — reimport before trusting playback")
	assert_almost_eq(stream.get_length(), AUDITION_SECONDS, 0.05,
		"Godot's decoded length must stay the audition's 0.84s; a different length means the imported bytes are not this file")


func test_the_manifest_records_that_selection_on_the_same_cue() -> void:
	var entry := _entry()
	assert_eq(str(entry.get("file", "")), "assets/audio/sfx/enemy_death.ogg",
		"enemy_death must keep its file — a new path is a second cue")
	assert_eq(str(entry.get("source", "")), "supplied_audition",
		"the selected file needs a source the ElevenLabs generator refuses, or a --force run replaces it")
	assert_false(str(entry.get("source", "")).begins_with("elevenlabs"),
		"source elevenlabs* would let the generator overwrite the audition")
	assert_eq(float(entry.get("duration_seconds", -1.0)), AUDITION_SECONDS,
		"duration_seconds must describe the 0.84s audition, not the retired scorch")
	assert_true(AUDITION_SHA in str(entry.get("prompt", "")),
		"the selection note must name the audition sha, or the next regen has no record of which file shipped")
	var sfx_raw := FileAccess.get_file_as_string(MANIFEST)
	var parsed: Variant = JSON.parse_string(sfx_raw)
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {})
	var w4: Dictionary = sfx.get("w4_enemy_death", {})
	assert_eq(str(w4.get("file", "")), "assets/audio/sfx/w4_enemy_death.ogg",
		"the W4 industrial death variant must keep its own file")
	assert_ne(str(w4.get("file", "")), str(entry.get("file", "")),
		"w4_enemy_death must not be repointed at the base whoosh")


func test_the_world4_variant_was_not_replaced_with_the_whoosh() -> void:
	assert_true(FileAccess.file_exists(W4_ASSET), "w4_enemy_death.ogg missing")
	assert_ne(FileAccess.get_sha256(W4_ASSET), AUDITION_SHA,
		"w4_enemy_death.ogg was overwritten with the selected whoosh — that variant is a different death")


func test_the_death_tween_still_fires_the_same_cue_without_a_file_length_hold() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var fn := src.find("func _on_enemy_died")
	assert_gt(fn, -1, "_on_enemy_died missing")
	var next_fn := src.find("\nfunc ", fn + 1)
	var body := src.substr(fn, (next_fn - fn) if next_fn > -1 else -1)
	assert_eq(body.count('play_death("enemy_death")'), 2,
		"the spriteless fallback and the fade callback are the only enemy_death plays — a new cue name or a dropped call changes who hears the whoosh")
	assert_false("0.84" in body, "the audition length must not become a tween hold")
	assert_false("F_whoosh" in body, "battle code keeps the cue name; the file is what changed")
	var ally := src.find('play_death("party_ko")')
	assert_gt(ally, -1, "ally KO must stay on party_ko")
	assert_lt(ally, fn, "party_ko stays on the ally path, before _on_enemy_died")
