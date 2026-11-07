extends GutTest

## Mordaine lv35 take (cowir-battle, v3.33.780, 2026-11-06): two KOs, two recoveries, and "A Sound Like a
## Verdict" restarted from its intro TWICE (music_id offsets 56.5 -> 1.0 and 33.8 -> 0.2). The danger swap
## took the channel and the recovery called play_music(base) with no position, so the bed began again.
## Same class as capture_music_state's "a restore without a position RESTARTS THE BED", in BattleScene.

const BattleSceneScript := preload("res://src/battle/BattleScene.gd")
const BED := "boss_mordaine"
const OTHER_BED := "battle_medieval"
const HELD_AT := 40.0

var _scene = null
var _member: Combatant = null


func before_each() -> void:
	SoundManager.stop_music()
	_scene = BattleSceneScript.new()
	_member = Combatant.new()
	_member.max_hp = 100
	_member.current_hp = 100
	_member.is_alive = true
	_scene.party_members = [_member] as Array[Combatant]
	_scene._base_music_track = BED


func after_each() -> void:
	SoundManager.stop_music()
	if is_instance_valid(_scene):
		_scene.free()
	if is_instance_valid(_member):
		_member.free()


func _settle() -> void:
	await get_tree().create_timer(0.3).timeout


func _position() -> float:
	return SoundManager._music_player.get_playback_position() if SoundManager._music_player.playing else -1.0


## Plays the bed at HELD_AT, then KOs the member: the danger bed takes over.
func _into_danger() -> void:
	SoundManager.play_music(BED, false, HELD_AT)
	await _settle()
	_scene._check_danger_music()  # full-HP baseline
	assert_false(_scene._is_danger_music, "CONTROL: a full-HP party must not start danger")
	_member.current_hp = 0
	_member.is_alive = false
	_scene._check_danger_music()
	await _settle()
	assert_true(_scene._is_danger_music, "CONTROL: a fresh KO must start the danger bed")
	assert_eq(SoundManager.playing_track_stem(), "danger_medieval", "CONTROL: the danger bed must be what is playing")


func _recover() -> void:
	_member.is_alive = true
	_member.current_hp = 100
	_scene._check_danger_music()
	await _settle()


func test_control_the_bed_is_held_mid_track_before_the_ko() -> void:
	SoundManager.play_music(BED, false, HELD_AT)
	await _settle()
	assert_eq(SoundManager.playing_track_stem(), BED)
	assert_gt(_position(), HELD_AT - 1.0, "CONTROL: the bed must really sit at %.0f s, or 'resumed' below is indistinguishable from 'restarted'" % HELD_AT)


func test_recovery_resumes_the_bed_where_danger_cut_it() -> void:
	await _into_danger()
	await _recover()
	assert_false(_scene._is_danger_music)
	assert_eq(SoundManager.playing_track_stem(), BED, "recovery must bring the base bed back")
	assert_gt(_position(), HELD_AT - 1.0,
		"recovery replayed %s from %.2f s: the theme restarts its intro after every KO instead of resuming at %.0f s" % [BED, _position(), HELD_AT])


func test_a_bed_changed_during_danger_starts_at_its_top() -> void:
	await _into_danger()
	_scene._base_music_track = OTHER_BED  # what a face swap does while danger owns the channel
	await _recover()
	assert_eq(SoundManager.playing_track_stem(), OTHER_BED)
	assert_lt(_position(), 5.0,
		"a NEW bed started at %.2f s: the old bed's position was carried onto a different track" % _position())
