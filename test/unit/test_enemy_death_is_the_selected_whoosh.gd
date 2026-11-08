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
	## 0.84 is the container length (ffprobe and get_length()). A raw s16 dump is 37952/44100 = 0.861s
	## because the decoder emits Vorbis padding the stream duration does not include. 0.86 is that dump.
	assert_almost_eq(stream.get_length(), AUDITION_SECONDS, 0.001,
		"Godot's length must be the 0.84s container duration, not the 0.86s padded PCM dump")


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


func test_only_enemy_death_gives_up_headroom() -> void:
	var sm := get_node_or_null("/root/SoundManager")
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	var table: Dictionary = sm.get_script().get_script_constant_map()["_DEATH_FILE_HEADROOM_DB"]
	assert_eq(table.keys(), ["enemy_death"],
		"headroom must name enemy_death and nothing else — party_ko and w4_enemy_death keep the shared boost")
	assert_almost_eq(float(table["enemy_death"]), -2.2, 0.001, "the measured trim is -2.2 dB")
	var base: float = float(sm.DEATH_PLAYER_BASE_DB)
	var boost: float = float(sm.DEATH_CUE_BOOST_DB)
	sm._sfx_cooldowns.clear()
	sm.play_death("enemy_death")
	assert_almost_eq(sm._death_player.volume_db, base + boost - 2.2, 0.001,
		"enemy_death plays at the shared +2 dB level minus its own headroom")
	sm._sfx_cooldowns.clear()
	sm.play_death("party_ko")
	assert_almost_eq(sm._death_player.volume_db, base + boost, 0.001,
		"party_ko must stay at the shared boost — the whoosh trim does not belong to it")


func test_the_mixed_whoosh_stays_under_full_scale_at_the_jitter_edge() -> void:
	## The +6 dB boost is real, and so is the +2 dB player level: -4 dB rest + 6 dB = +2 dB.
	## Master and the SFX bus are 0 dB and have no limiter, so a file peak of -0.9 dBFS at +2 dB
	## clips. This captures that mix at pitch 1.05, the top of SFX_PITCH_JITTER, with the thud
	## play_death layers under the cue.
	var sm := get_node_or_null("/root/SoundManager")
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	var master := AudioServer.get_bus_index("Master")
	var sfx := AudioServer.get_bus_index("SFX")
	assert_eq(AudioServer.get_bus_effect_count(master), 0, "CONTROL: Master already has an effect, so this capture is not the shipping mix")
	var cap := AudioEffectCapture.new()
	cap.buffer_length = 2.0
	AudioServer.add_bus_effect(master, cap)
	var level: float = float(sm.DEATH_PLAYER_BASE_DB) + float(sm.DEATH_CUE_BOOST_DB) - 2.2
	sm._sfx_cooldowns.clear()
	sm._play_sound(sm._sub_player, {"freq": sm.DEATH_THUD_FREQ, "duration": sm.DEATH_THUD_DURATION, "type": "thud"})
	var played: bool = sm._try_play_sfx_from_manifest(sm._death_player, "enemy_death", level, 1.05, false)
	if not played:
		AudioServer.remove_bus_effect(master, AudioServer.get_bus_effect_count(master) - 1)
	assert_true(played, "the whoosh did not play — the capture would measure silence")
	var peak := 0.0
	var frames := 0
	for _i in 90:
		await get_tree().process_frame
		var n: int = cap.get_frames_available()
		if n > 0:
			for s in cap.get_buffer(n):
				peak = maxf(peak, maxf(absf(s.x), absf(s.y)))
			frames += n
	AudioServer.remove_bus_effect(master, AudioServer.get_bus_effect_count(master) - 1)
	assert_gt(frames, 1000, "the mix produced %d frames — Dummy did not run, so a quiet peak would be a lie" % frames)
	assert_lt(peak, 1.0, "mixed whoosh peaked at %.3f (%.2f dBFS) — still clipping" % [peak, linear_to_db(peak)])
	assert_gt(peak, 0.5, "mixed whoosh peaked at %.3f — the headroom silenced it" % peak)
	if sfx >= 0:
		assert_eq(AudioServer.get_bus_effect_count(sfx), 0, "this test must not leave an effect on the SFX bus")
