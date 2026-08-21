extends GutTest

## struktured 2026-08-20, live: "I still cant hear the sfx when a monster dies its too low
## or subtle." Measured cause (ffmpeg volumedetect): the authored cue is a gentle scorch
## ("no bass no tones") at -22.8 dB mean — the same level as a plain attack_hit (-21.8).
## A death cue that is no louder than the hit that caused it cannot read as a climax.
## Second defect: SFX_MIN_INTERVAL_MS is per-key and its early-return suppresses the
## fallback, so a group kill played ONE death and swallowed the rest.

const SM := "res://src/audio/SoundManager.gd"


func _play_death_body() -> String:
	var src := FileAccess.get_file_as_string(SM)
	var i := src.find("func play_death")
	assert_gt(i, -1, "play_death must exist")
	var fn_end := src.find("\nfunc ", i + 1)
	return src.substr(i, (fn_end - i) if fn_end > -1 else 1500)


func test_death_cue_is_boosted_above_a_plain_hit() -> void:
	var src := FileAccess.get_file_as_string(SM)
	assert_true("const DEATH_CUE_BOOST_DB: float = 6.0" in src, "death cue boosted +6 dB over its channel base")
	assert_true("DEATH_PLAYER_BASE_DB + DEATH_CUE_BOOST_DB" in _play_death_body(), "boost applied on the manifest path")


func test_boost_is_absolute_not_a_ratchet() -> void:
	# The volume override PERSISTS on the player. Computing `volume_db + boost` from the live
	# player would climb +6 dB on every death — caught while writing this, pinned so it stays caught.
	var body := _play_death_body()
	assert_false("_death_player.volume_db + DEATH_CUE_BOOST_DB" in body, "must not derive the boost from the live player value")
	assert_true("DEATH_PLAYER_BASE_DB" in body, "derives from the shared base const instead")
	var src := FileAccess.get_file_as_string(SM)
	assert_true("_death_player.volume_db = DEATH_PLAYER_BASE_DB" in src, "player setup uses the SAME const, so setup and boost cannot drift apart")


func test_group_kills_bypass_the_per_key_cooldown() -> void:
	var body := _play_death_body()
	assert_true("_sfx_cooldowns.erase(world_key)" in body and "_sfx_cooldowns.erase(sound_key)" in body,
		"both the world-variant and base keys are un-cooled before play — 3 simultaneous deaths must all sound")


func test_thud_layers_on_the_sub_channel_not_the_battle_player() -> void:
	# The cry got its own voice because the shared battle player's hit tail stomped it
	# (see test_enemy_death_sound_timing_regression). A thud on _battle_player would
	# reintroduce that cut from the other direction.
	var body := _play_death_body()
	assert_true("_play_sound(_sub_player" in body, "low body goes on the dedicated sub channel")
	assert_false("_play_sound(_battle_player" in body, "never on the shared battle player")
	var src := FileAccess.get_file_as_string(SM)
	assert_true("const DEATH_THUD_FREQ: float = 48.0" in src, "lower than the 62 Hz crit thud — a body hitting the floor, not a punch")
