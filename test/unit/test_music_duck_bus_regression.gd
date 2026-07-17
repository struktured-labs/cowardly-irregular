extends GutTest

## Music duck bus routing (2026-07-16, cowir-main directive msg 2699/2700).
##
## Pins Option B: dedicated MusicDuck bus downstream of MusicNight so modal
## dialogue can taper music -6dB without touching _music_player.volume_db
## (which the danger-intensity system also writes — bus route sidesteps
## the tween-race puzzle).
##
## Signal chain: player → MusicNight (LPF+Reverb) → MusicDuck (Amplify) → Master.
##
## Six guarantees:
##   1. MusicDuck bus exists after SoundManager autoload boot.
##   2. It carries exactly one AudioEffectAmplify at effect index 0.
##   3. Amp defaults to volume_db=0.0 (bus is transparent until first duck).
##   4. Amp is ENABLED (not the enable/disable toggle path — we taper instead,
##      so the effect must always be in the signal chain).
##   5. MusicNight sends to MusicDuck (composed with the day/night filter).
##   6. duck_music_for_dialogue(true/false) is idempotent and tweens the
##      Amplify's volume_db toward DUCK_TARGET_DB / 0.0.


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _bus_index(name: String) -> int:
	return AudioServer.get_bus_index(name)


func test_music_duck_bus_exists_after_boot() -> void:
	assert_not_null(_sm(), "SoundManager autoload must be present")
	var idx: int = _bus_index("MusicDuck")
	assert_ne(idx, -1, "MusicDuck bus must be created at SoundManager _ready — the duck API depends on it")


func test_duck_bus_carries_single_amplify_effect() -> void:
	var idx: int = _bus_index("MusicDuck")
	if idx == -1:
		pass_test("Bus not present in this context")
		return
	assert_eq(AudioServer.get_bus_effect_count(idx), 1,
		"MusicDuck must carry exactly one Amplify — extras would compound the attenuation, missing would drop the duck")
	var e0 = AudioServer.get_bus_effect(idx, 0)
	assert_true(e0 is AudioEffectAmplify,
		"Effect 0 must be AudioEffectAmplify — it's what we taper for the duck")


func test_amp_defaults_to_transparent_and_enabled() -> void:
	var idx: int = _bus_index("MusicDuck")
	if idx == -1:
		pass_test("Bus not present in this context")
		return
	var amp = AudioServer.get_bus_effect(idx, 0)
	if amp == null:
		pass_test("Amp effect missing")
		return
	assert_almost_eq(amp.volume_db, 0.0, 0.01,
		"Amp default must be 0.0dB — bus must be transparent at rest so day-one shipping doesn't alter music mix")
	assert_true(AudioServer.is_bus_effect_enabled(idx, 0),
		"Amp must be ENABLED so the taper tween can move volume_db smoothly — the enable/disable toggle path was rejected because a hard step is audible (cowir-main msg 2700)")


func test_music_night_sends_to_music_duck() -> void:
	## Compose order: player → MusicNight → MusicDuck → Master. Verifies the
	## chain so the night filter can't accidentally bypass the duck.
	var night_idx: int = _bus_index("MusicNight")
	var duck_idx: int = _bus_index("MusicDuck")
	if night_idx == -1 or duck_idx == -1:
		pass_test("Both buses must exist for this assertion — see prior tests for cause")
		return
	assert_eq(AudioServer.get_bus_send(night_idx), "MusicDuck",
		"MusicNight must send to MusicDuck (not Master) so ducking applies AFTER the night filter")


func test_duck_music_for_dialogue_toggles_and_is_idempotent() -> void:
	var sm := _sm()
	if sm == null:
		pass_test("SoundManager not present in this context")
		return
	var was_active: bool = sm.is_music_ducked_for_dialogue()

	sm.duck_music_for_dialogue(true)
	assert_true(sm.is_music_ducked_for_dialogue(),
		"is_music_ducked_for_dialogue must report true after duck_music_for_dialogue(true)")
	sm.duck_music_for_dialogue(true)  # idempotent second call
	assert_true(sm.is_music_ducked_for_dialogue(),
		"Second duck_music_for_dialogue(true) must be a no-op (idempotent)")

	sm.duck_music_for_dialogue(false)
	assert_false(sm.is_music_ducked_for_dialogue(),
		"is_music_ducked_for_dialogue must report false after duck_music_for_dialogue(false)")
	sm.duck_music_for_dialogue(false)  # idempotent second call
	assert_false(sm.is_music_ducked_for_dialogue(),
		"Second duck_music_for_dialogue(false) must be a no-op (idempotent)")

	# Restore
	sm.duck_music_for_dialogue(was_active)


func test_duck_tween_moves_amp_volume_toward_target() -> void:
	## Verifies the amp actually moves — a tween created but never applied
	## would silently no-op. Allows for the 250ms taper to complete.
	var sm := _sm()
	if sm == null:
		pass_test("SoundManager not present in this context")
		return
	var idx: int = _bus_index("MusicDuck")
	if idx == -1:
		pass_test("Bus not present in this context")
		return
	var amp = AudioServer.get_bus_effect(idx, 0)
	if amp == null:
		pass_test("Amp effect missing")
		return
	var was_active: bool = sm.is_music_ducked_for_dialogue()

	sm.duck_music_for_dialogue(true)
	# Let the taper run past its 250ms window.
	await get_tree().create_timer(0.4).timeout
	assert_almost_eq(amp.volume_db, -6.0, 0.5,
		"Amp volume_db must taper toward DUCK_TARGET_DB (-6.0) after duck(true); got %.2f" % amp.volume_db)

	sm.duck_music_for_dialogue(false)
	await get_tree().create_timer(0.4).timeout
	assert_almost_eq(amp.volume_db, 0.0, 0.5,
		"Amp volume_db must taper back to 0.0 after duck(false); got %.2f" % amp.volume_db)

	# Restore
	sm.duck_music_for_dialogue(was_active)
