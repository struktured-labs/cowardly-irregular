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


## Read the real constant — a hardcoded -6.0 here would still pass if the shipped duck changed.
func _duck_target() -> float:
	var sm := _sm()
	return float(sm.DUCK_TARGET_DB) if sm and "DUCK_TARGET_DB" in sm else -6.0


func _read_source(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "should be readable: %s" % path)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t


## Bounded to the NEXT top-level func so the ratchet can't drift into a neighbour's body.
func _func_body(src: String, fname: String) -> String:
	var start: int = src.find("func %s(" % fname)
	if start == -1:
		return ""
	var next: int = src.find("\nfunc ", start + 1)
	return src.substr(start, (next - start) if next != -1 else -1)


## Poll a WALL clock: the taper is a bare tween, so it runs on engine time and GUT's
## wait_seconds is itself time-scaled. Returns whether it settled before the deadline.
func _settle(amp, target_db: float, timeout_ms: int) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if abs(amp.volume_db - target_db) <= 0.05:
			return true
		await get_tree().process_frame
	return abs(amp.volume_db - target_db) <= 0.05


func test_music_duck_bus_exists_after_boot() -> void:
	assert_not_null(_sm(), "SoundManager autoload must be present")
	var idx: int = _bus_index("MusicDuck")
	assert_ne(idx, -1, "MusicDuck bus must be created at SoundManager _ready — the duck API depends on it")


func test_duck_bus_carries_one_amplify_PER_SOURCE() -> void:
	## Was "exactly one Amplify — extras would compound the attenuation". Compounding is now
	## the POINT: a kill landing mid-dialogue should duck further, not fight for one property.
	## The original invariant was right for one source and its rationale did not survive a
	## second. What must stay fixed is ONE SLOT PER SOURCE — a source sharing another's slot
	## would kill its tween and silently release it (the failure the split exists to prevent).
	var idx: int = _bus_index("MusicDuck")
	if idx == -1:
		pass_test("Bus not present in this context")
		return
	var sm = _sm()
	assert_eq(AudioServer.get_bus_effect_count(idx), 2,
		"MusicDuck must carry one Amplify per duck SOURCE: slot 0 dialogue (msg 2700), slot 1 kill. A third means a source was added without declaring itself here; one means a source is sharing a slot.")
	for slot in [0, sm.KILL_DUCK_EFFECT_SLOT]:
		assert_true(AudioServer.get_bus_effect(idx, slot) is AudioEffectAmplify,
			"Effect %d must be AudioEffectAmplify — it's what we taper for the duck" % slot)
	assert_eq(sm.KILL_DUCK_EFFECT_SLOT, 1,
		"the kill duck must not move onto dialogue's slot 0")


## Guarantee 3 is a CONSTRUCTION-time property, so pin it at the construction site.
## Reading the live bus instead made this intermittent: any earlier test that ducked
## left -6.0 on a GLOBAL, and resetting it in before_each would have been worse — the
## assert would check the value it just wrote and pass on a bus CREATED at -6.0.
func test_the_bus_is_CREATED_transparent() -> void:
	var src := _read_source("res://src/audio/SoundManager.gd")
	var body := _func_body(src, "_ensure_music_duck_bus")
	assert_false(body.is_empty(), "_ensure_music_duck_bus must exist — this ratchet is anchored to it")
	assert_true(body.contains("amp.volume_db = 0.0"),
		"the Amplify must be CREATED at 0.0dB inside _ensure_music_duck_bus — a bus born ducked alters the music mix on a fresh install, and no runtime read can distinguish that from a stale duck")
	var init_at: int = body.find("amp.volume_db = 0.0")
	var added_at: int = body.find("add_bus_effect")
	assert_true(added_at > init_at,
		"the 0.0 init must precede add_bus_effect — set after, and the bus is briefly live at whatever the default was")


## The REST state, measured on a real duck cycle rather than on whatever the global
## happened to hold. Bounded wall-clock poll: the taper is a bare tween (ENGINE time),
## so a frame count or GUT's time-scaled wait_seconds samples an arbitrary point.
func test_the_REST_state_is_transparent_after_a_full_duck_CYCLE() -> void:
	var idx: int = _bus_index("MusicDuck")
	var sm := _sm()
	if idx == -1 or sm == null:
		pass_test("Bus not present in this context")
		return
	var amp = AudioServer.get_bus_effect(idx, 0)
	if amp == null:
		pass_test("Amp effect missing")
		return

	sm.duck_music_for_dialogue(true)
	var engaged: bool = await _settle(amp, _duck_target(), 2000)
	assert_true(engaged,
		"the duck must actually ENGAGE — without this the rest-state assert below passes vacuously, because a duck that never ran is already at 0.0")

	sm.duck_music_for_dialogue(false)
	var released: bool = await _settle(amp, 0.0, 2000)
	assert_true(released,
		"music must return to 0.0dB after the dialogue closes — a rest state that isn't transparent leaves every later track quietly attenuated")


func test_amp_is_enabled() -> void:
	var idx: int = _bus_index("MusicDuck")
	if idx == -1:
		pass_test("Bus not present in this context")
		return
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
