extends GutTest

## His .808 log printed "[MUSIC] Playing from manifest: village_harmonia ... resume=" five times around
## a pause menu, and the line had no position: `resume=` is the STINGER's resume target, empty for every
## bed. So a log reader could not tell a bed resumed by restore_music_state from one restarted at 0
## (cowir-music read it as a restart; the restore carries the position). The line now prints at=<s>,
## taken from _last_start_position, which _play_parked_position writes from the seek it really made.
## The arms judge that value against the player's own position, not against what was requested.

const GdSourceHelper = preload("res://test/unit/helpers/gd_source.gd")
const SM_PATH := "res://src/audio/SoundManager.gd"


func before_each() -> void:
	SoundManager.stop_music()
	SoundManager._pending_resume_position = 0.0
	SoundManager._pending_music_area = ""
	SoundManager._pending_home_area = ""


func after_each() -> void:
	SoundManager.stop_music()
	SoundManager._pending_resume_position = 0.0
	SoundManager._pending_music_area = ""
	SoundManager._pending_home_area = ""


func _position() -> float:
	var player: AudioStreamPlayer = SoundManager._music_player
	return player.get_playback_position() if player and player.playing else -1.0


func test_a_resumed_bed_logs_where_it_resumed() -> void:
	SoundManager.play_area_music("overworld", 9.0)
	SoundManager._start_area_music_deferred("overworld")
	assert_almost_eq(_position(), 9.0, 0.6, "CONTROL: the resume at 9.0 s took, so the logged value below has a real seek to report")
	assert_almost_eq(SoundManager._last_start_position, _position(), 0.6,
		"a resumed bed must log where it really started; logged %.2f, the player is at %.2f" % [SoundManager._last_start_position, _position()])


func test_a_fresh_bed_logs_its_own_start() -> void:
	SoundManager.play_music("battle_medieval")
	assert_gt(_position(), -1.0, "CONTROL: the battle bed is playing")
	assert_almost_eq(SoundManager._last_start_position, _position(), 0.6,
		"a fresh bed must log the position it opened at (0, or its loop blend); logged %.2f, the player is at %.2f" % [SoundManager._last_start_position, _position()])


func test_a_refused_seek_logs_the_restart_not_the_request() -> void:
	## A resume at or past the last second is refused and the bed plays from its head. The log must say
	## what PLAYED; a value copied from the request would claim a resume that never happened.
	SoundManager.play_area_music("overworld", 99999.0)
	SoundManager._start_area_music_deferred("overworld")
	assert_lt(_position(), 5.0, "CONTROL: the out-of-range resume was refused and the bed opened near its head")
	assert_almost_eq(SoundManager._last_start_position, _position(), 0.6,
		"a refused seek must log the restart; logged %.2f, the player is at %.2f" % [SoundManager._last_start_position, _position()])


func test_the_manifest_line_prints_the_start() -> void:
	var code: String = GdSourceHelper.code_of(SM_PATH)
	var at: int = code.find("[MUSIC] Playing from manifest:")
	assert_gt(at, -1, "CONTROL: the manifest log line survives comment stripping")
	var line: String = code.substr(at, code.find("\n", at) - at)
	assert_true(line.contains("at=%.2f"), "the manifest line must print the start position as at=<s>: %s" % line)
	assert_true(line.contains("_last_start_position"), "and take it from the recorded seek, not the request: %s" % line)
