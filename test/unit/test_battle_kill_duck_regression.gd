extends GutTest

## Kill duck (cowir-main slate item 1, struktured-approved 2026-08-14).
##
## The dangerous part is not the envelope, it is WHICH bus effect it writes.
## duck_music_for_dialogue() hardcodes slot 0 and kills any running tween, so a kill duck
## sharing that property would silently release an active dialogue duck mid-conversation —
## the "two writers, one silently wins" class. The kill duck owns slot 1; serial Amplifies
## sum in dB, so the two sources compose instead of racing.
##
## msg-2700 ruling: ducking on QUIPS was rejected as exhausting. A kill is punctuation.
## The last test derives that the only caller is the death path, so the ruling cannot be
## violated by someone adding a bubble-side call later.

const SM_SRC: String = "res://src/audio/SoundManager.gd"
const SCENE_SRC: String = "res://src/battle/BattleScene.gd"


func _bus() -> int:
	return AudioServer.get_bus_index(SoundManager.MUSIC_DUCK_BUS)


func after_each() -> void:
	SoundManager.duck_music_for_dialogue(false)
	var idx: int = _bus()
	if idx != -1:
		for slot in range(AudioServer.get_bus_effect_count(idx)):
			var e = AudioServer.get_bus_effect(idx, slot)
			if e:
				e.volume_db = 0.0


func test_premise_the_duck_bus_and_both_slots_exist() -> void:
	SoundManager.duck_music_for_kill()
	var idx: int = _bus()
	assert_ne(idx, -1, "PREMISE: the MusicDuck bus must exist — every assert below reads it")
	assert_gt(AudioServer.get_bus_effect_count(idx), SoundManager.KILL_DUCK_EFFECT_SLOT,
		"PREMISE: slot %d must exist after a kill duck; _ensure_kill_duck_effect did not create it" % SoundManager.KILL_DUCK_EFFECT_SLOT)
	assert_eq(SoundManager.KILL_DUCK_EFFECT_SLOT, 1,
		"slot 0 belongs to dialogue (msg 2700). If this moved to 0 the two ducks share a property again.")


func test_the_configured_envelope_is_a_beat_not_a_dropout() -> void:
	## The DEPTH is a constant, so pin it deterministically here rather than by sampling the
	## bus — the peak is a transient the release starts erasing immediately, and a wall-clock
	## sample of it is a race (first cut of this test asserted -4.0 and measured -3.0).
	assert_eq(SoundManager.KILL_DUCK_TARGET_DB, -4.0, "cowir-main's envelope: -4dB")
	assert_lt(SoundManager.KILL_DUCK_ATTACK_TIME, SoundManager.KILL_DUCK_RELEASE_TIME,
		"attack must be shorter than release or it reads as a dropout rather than a beat")
	assert_lt(SoundManager.KILL_DUCK_TARGET_DB, 0.0, "a duck must attenuate")
	assert_gt(SoundManager.KILL_DUCK_TARGET_DB, SoundManager.DUCK_TARGET_DB,
		"the kill duck must be SHALLOWER than the dialogue duck — punctuation, not a conversation")


func test_the_kill_duck_engages_then_returns_to_rest() -> void:
	## Asserts the RELATIONSHIP (engages, then releases), not a magnitude at a sampled instant.
	assert_almost_eq(SoundManager.get_kill_duck_db(), 0.0, 0.01, "PREMISE: must start at rest")
	SoundManager.duck_music_for_kill()
	await wait_seconds(SoundManager.KILL_DUCK_ATTACK_TIME + 0.02)
	var ducked: float = SoundManager.get_kill_duck_db()
	assert_lt(ducked, -1.0,
		"the bus never meaningfully attenuated (measured %0.2f dB) — the duck did not engage" % ducked)
	assert_gt(ducked, SoundManager.KILL_DUCK_TARGET_DB - 0.5,
		"the bus went BELOW the configured target (%0.2f dB) — the envelope overshot" % ducked)
	await wait_seconds(SoundManager.KILL_DUCK_RELEASE_TIME + 0.25)
	assert_almost_eq(SoundManager.get_kill_duck_db(), 0.0, 0.35,
		"the duck must RELEASE — a kill that never returns to 0 is a permanent volume cut, not a beat")


func test_a_kill_does_NOT_release_an_active_dialogue_duck() -> void:
	## THE LOAD-BEARING GUARD. This is the whole reason for a separate slot: with one shared
	## Amplify, the kill's release tween would drive the dialogue duck back to 0 while the
	## dialogue box is still open, and nothing would report it.
	SoundManager.duck_music_for_dialogue(true)
	await wait_seconds(SoundManager.DUCK_TAPER_TIME + 0.05)
	var idx: int = _bus()
	var dialogue_amp = AudioServer.get_bus_effect(idx, 0)
	assert_not_null(dialogue_amp, "control: dialogue slot 0 must exist")
	assert_almost_eq(dialogue_amp.volume_db, SoundManager.DUCK_TARGET_DB, 0.6,
		"control: the dialogue duck must actually be engaged, else this test proves nothing")

	SoundManager.duck_music_for_kill()
	await wait_seconds(SoundManager.KILL_DUCK_ATTACK_TIME + SoundManager.KILL_DUCK_RELEASE_TIME + 0.2)

	assert_true(SoundManager.is_music_ducked_for_dialogue(),
		"the dialogue duck's own flag was cleared by a kill")
	assert_almost_eq(dialogue_amp.volume_db, SoundManager.DUCK_TARGET_DB, 0.6,
		"a kill duck released the DIALOGUE duck (slot 0 now %0.2f dB, expected %0.1f). The two ducks are sharing a property again." % [dialogue_amp.volume_db, SoundManager.DUCK_TARGET_DB])


func test_retrigger_does_not_stack_below_the_target() -> void:
	SoundManager.duck_music_for_kill()
	await wait_seconds(SoundManager.KILL_DUCK_ATTACK_TIME + 0.02)
	SoundManager.duck_music_for_kill()
	await wait_seconds(SoundManager.KILL_DUCK_ATTACK_TIME + 0.02)
	assert_gt(SoundManager.get_kill_duck_db(), SoundManager.KILL_DUCK_TARGET_DB - 1.0,
		"a second kill during the envelope drove the bus below the target — two live tweens on one property")


func test_the_flag_defaults_TRUE_and_can_be_turned_off() -> void:
	## Unknown ids default true so a typo cannot silently disable a shipped effect —
	## the failure direction matters: opt-OUT, never opt-in-by-spelling.
	assert_true(BattleJuice.flag("audio_kill_duck"), "a declared flag must default enabled")
	assert_true(BattleJuice.flag("nonexistent_flag_xyz"), "an UNKNOWN flag must default enabled, not disabled")
	BattleJuice.set_flag("audio_kill_duck", false)
	assert_false(BattleJuice.flag("audio_kill_duck"), "set_flag(false) must disable")
	BattleJuice.set_flag("audio_kill_duck", true)


func test_the_call_site_is_gated_on_FULL_and_on_the_flag() -> void:
	var src: String = FileAccess.get_file_as_string(SCENE_SRC)
	assert_gt(src.length(), 1000, "SCOPE control: BattleScene.gd read back empty")
	var at: int = src.find("duck_music_for_kill")
	assert_gt(at, 0, "the kill duck is not called from BattleScene at all")
	var window: String = src.substr(maxi(0, at - 400), 400)
	assert_true(window.contains("Tier.FULL"),
		"the kill duck call is not gated on Tier.FULL — it would fire at REDUCED/MINIMAL/OFF, breaking 'OFF reproduces current behavior'")
	assert_true(window.contains("audio_kill_duck"),
		"the kill duck call is not behind its feature flag")


func test_ONLY_the_death_path_ducks_which_is_what_protects_the_quip_ruling() -> void:
	## msg-2700: ducking on quips was rejected. Rather than asserting "bubbles don't duck"
	## (which passes trivially today and says nothing about tomorrow), this derives the
	## caller set: any NEW caller fails until someone states why it is punctuation.
	var scene: String = FileAccess.get_file_as_string(SCENE_SRC)
	var callers: Array[String] = []
	for line in scene.split("\n"):
		if line.contains("duck_music_for_kill") and not line.strip_edges().begins_with("#"):
			callers.append(line.strip_edges())
	assert_eq(callers.size(), 1,
		"expected exactly ONE kill-duck call site in BattleScene; found %d: %s. Every added caller must be punctuation, not chatter (msg 2700 rejected ducking on quips)." % [callers.size(), callers])

	var sm: String = FileAccess.get_file_as_string(SM_SRC)
	assert_false(sm.contains("func play_battle_bubble"),
		"control assumption changed: a bubble-specific play path now exists and this guard should cover it too")
