extends GutTest

const SfxState := preload("res://test/unit/helpers/sfx_state.gd")

## set_sfx_volume re-asserts three players' base levels "defensively in case a caller mutated them".
## The write lands on a LIVE stream, so moving the slider during a trimmed cue stepped it back to the
## bare channel base mid-playback. set_music_volume documents this exact hazard one function up and
## repairs it by putting the danger/corruption envelope back afterwards; the SFX side has no envelope
## to restore, so the repair is to decline to flatten while the player is sounding.
##
## Registered three times tonight as "a product call for struktured — is 3 of 13 players right?".
## It was not a threshold question: the sibling surface already had the fix.

const TRIMMED := "corruption_ap_flicker"   # -6.0 in _BATTLE_VOLUME_TRIM_DB, so a live trim to flatten


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _c(sm: Node, n: String) -> float:
	return float(sm.get_script().get_script_constant_map()[n])


func before_each() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	sm._sfx_cooldowns.clear()
	sm._battle_player.volume_db = _c(sm, "SFX_BATTLE_BASE_DB")


func after_each() -> void:
	SfxState.release_streams()
	var sm: Node = _sm()
	if sm == null:
		return
	sm._battle_player.volume_db = _c(sm, "SFX_BATTLE_BASE_DB")
	sm._sfx_cooldowns.clear()
	sm.set_sfx_volume(1.0)


func test_the_slider_leaves_a_sounding_cue_at_its_own_level() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	var base: float = _c(sm, "SFX_BATTLE_BASE_DB")
	sm.play_battle(TRIMMED)
	assert_true(sm._battle_player.playing,
		"CONTROL: %s must actually be sounding, or this arm measures a resting player" % TRIMMED)
	var during: float = sm._battle_player.volume_db
	assert_lt(during, base,
		"CONTROL: %s must be trimmed BELOW the base, or there is nothing for the slider to flatten" % TRIMMED)
	sm.set_sfx_volume(1.0)
	assert_eq(sm._battle_player.volume_db, during,
		"the SFX slider stepped a sounding cue from %.2f to %.2f — a %.2f dB jump on the sound the player is listening to" % [during, sm._battle_player.volume_db, sm._battle_player.volume_db - during])


func test_a_resting_player_still_gets_the_defensive_reassert() -> void:
	## Anti-overcorrection: the re-assert exists to undo a caller that left a level behind, and a
	## `playing` guard that skipped it always would trade one defect for the one it was written for.
	var sm: Node = _sm()
	if sm == null:
		return
	var base: float = _c(sm, "SFX_BATTLE_BASE_DB")
	sm._battle_player.stop()
	sm._battle_player.volume_db = base + 9.0
	assert_false(sm._battle_player.playing, "CONTROL: the player must be at rest for this arm")
	sm.set_sfx_volume(1.0)
	assert_eq(sm._battle_player.volume_db, base,
		"a RESTING player kept a stray %.2f dB — the defensive re-assert is gone, not just deferred" % sm._battle_player.volume_db)
