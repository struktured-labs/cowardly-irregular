extends GutTest

## Day/night music bus routing (2026-07-16, cowir-main directive msg 2643/2659).
##
## Pins Option A: music players route through a dedicated "MusicNight" bus
## carrying a low-pass filter + reverb that a GameState is_night listener
## can toggle without touching individual tracks or crossfade logic.
##
## Guarantees:
##   1. The bus exists after SoundManager autoload boot.
##   2. Both music players are routed to it (else the toggle is a no-op).
##   3. Effects are the expected pair (LPF + Reverb) in the expected order.
##   4. Effects default DISABLED (bus is transparent until nightfall).
##   5. set_night_music_effects(true/false) toggles both effects together;
##      are_night_music_effects_enabled() reports state honestly.


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _bus_index(name: String) -> int:
	return AudioServer.get_bus_index(name)


func test_music_night_bus_exists_after_boot() -> void:
	assert_not_null(_sm(), "SoundManager autoload must be present")
	var idx: int = _bus_index("MusicNight")
	assert_ne(idx, -1, "MusicNight bus must be created at SoundManager _ready — the toggle API depends on it")


func test_both_music_players_route_to_night_bus() -> void:
	var sm := _sm()
	if sm == null:
		pass_test("SoundManager not present in this context")
		return
	assert_eq(sm._music_player.bus, "MusicNight",
		"_music_player must route to MusicNight — otherwise set_night_music_effects has no effect on the primary player")
	assert_eq(sm._music_player_b.bus, "MusicNight",
		"_music_player_b (crossfade B-side) must route to MusicNight — a mid-crossfade night flip would only affect A otherwise, causing an audible seam")


func test_bus_carries_lpf_plus_reverb_in_order() -> void:
	var idx: int = _bus_index("MusicNight")
	if idx == -1:
		pass_test("Bus not present in this context")
		return
	assert_eq(AudioServer.get_bus_effect_count(idx), 2,
		"MusicNight bus must carry exactly the 2 effects (LPF + Reverb) — extras would compound the filter, missing would drop the night flavor")
	var e0 = AudioServer.get_bus_effect(idx, 0)
	var e1 = AudioServer.get_bus_effect(idx, 1)
	assert_true(e0 is AudioEffectLowPassFilter,
		"Effect 0 must be AudioEffectLowPassFilter — carries the 'distant/muffled' night character")
	assert_true(e1 is AudioEffectReverb,
		"Effect 1 must be AudioEffectReverb — adds the ambient tail for a hushed nocturnal feel")


func test_effects_default_disabled_at_boot() -> void:
	var idx: int = _bus_index("MusicNight")
	if idx == -1:
		pass_test("Bus not present in this context")
		return
	assert_false(AudioServer.is_bus_effect_enabled(idx, 0),
		"Night LPF must default DISABLED — bus must be transparent until set_night_music_effects(true) flips it, or gameplay would ship altered on day one")
	assert_false(AudioServer.is_bus_effect_enabled(idx, 1),
		"Night reverb must default DISABLED — same reason")


func test_set_night_music_effects_toggles_both() -> void:
	var sm := _sm()
	if sm == null:
		pass_test("SoundManager not present in this context")
		return
	var idx: int = _bus_index("MusicNight")
	var was_enabled: bool = AudioServer.is_bus_effect_enabled(idx, 0)
	# Snapshot + restore, so this test can run in either order relative to
	# a caller that flipped state.
	sm.set_night_music_effects(true)
	assert_true(AudioServer.is_bus_effect_enabled(idx, 0), "LPF must enable on true")
	assert_true(AudioServer.is_bus_effect_enabled(idx, 1), "Reverb must enable on true")
	assert_true(sm.are_night_music_effects_enabled(),
		"are_night_music_effects_enabled must report true when both effects are enabled")

	sm.set_night_music_effects(false)
	assert_false(AudioServer.is_bus_effect_enabled(idx, 0), "LPF must disable on false")
	assert_false(AudioServer.is_bus_effect_enabled(idx, 1), "Reverb must disable on false")
	assert_false(sm.are_night_music_effects_enabled(),
		"are_night_music_effects_enabled must report false when both are disabled")

	# Restore
	sm.set_night_music_effects(was_enabled)


func test_set_night_music_effects_is_idempotent() -> void:
	var sm := _sm()
	if sm == null:
		pass_test("SoundManager not present in this context")
		return
	var was_enabled: bool = sm.are_night_music_effects_enabled()
	sm.set_night_music_effects(true)
	sm.set_night_music_effects(true)  # no-op second call must not throw
	sm.set_night_music_effects(false)
	sm.set_night_music_effects(false)  # no-op second call must not throw
	assert_false(sm.are_night_music_effects_enabled(),
		"After two consecutive false calls, state must be off — helper must be idempotent")
	sm.set_night_music_effects(was_enabled)
