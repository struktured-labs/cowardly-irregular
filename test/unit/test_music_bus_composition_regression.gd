extends GutTest

## Music bus composition regression (2026-07-16).
##
## Both night bus (LPF+Reverb, tick #7) and duck bus (Amplify taper,
## tick #9) shipped with individual coverage but no test proved they
## compose correctly. The signal-chain design is explicit:
##
##   MusicPlayer + MusicPlayerB → MusicNight (LPF, Reverb)
##                              → MusicDuck (Amplify)
##                              → Master
##
## A refactor that swaps init order, changes a send target, or routes
## players to the wrong bus would silently break the compound "night
## dialogue" case (should be both hushed AND ducked at once). Pins:
##   1. Init order guarantees the send chain resolves (duck before night).
##   2. Both effect states can coexist without one clobbering the other.
##   3. Player routing lands on the upstream (night) bus, not master
##      or duck directly — otherwise the night filter would be
##      bypassed.


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _bus_index(name: String) -> int:
	return AudioServer.get_bus_index(name)


func test_full_signal_chain_resolves() -> void:
	## Player → MusicNight → MusicDuck → Master. Each hop verified.
	var sm := _sm()
	if sm == null:
		pass_test("SoundManager not present")
		return
	var night_idx: int = _bus_index("MusicNight")
	var duck_idx: int = _bus_index("MusicDuck")
	assert_ne(night_idx, -1, "MusicNight must exist")
	assert_ne(duck_idx, -1, "MusicDuck must exist")

	# Hop 1: MusicPlayer + MusicPlayerB → MusicNight
	assert_eq(sm._music_player.bus, "MusicNight",
		"MusicPlayer must feed the night bus first — routing to duck directly would skip the night filter entirely")
	assert_eq(sm._music_player_b.bus, "MusicNight",
		"MusicPlayerB (crossfade) must also feed night — a mid-crossfade compound night+duck scene would sound wrong otherwise")

	# Hop 2: MusicNight → MusicDuck (proved in the night bus regression, re-asserted here so this test is self-contained)
	assert_eq(AudioServer.get_bus_send(night_idx), "MusicDuck",
		"MusicNight must send to MusicDuck — ducking must apply AFTER the night filter (or you can't duck night music)")

	# Hop 3: MusicDuck → Master (final stage)
	assert_eq(AudioServer.get_bus_send(duck_idx), "Master",
		"MusicDuck must send to Master — else the whole music path is orphaned and the game plays silent")

	## ⚠️ THE FOURTH PLAYER. This test is named "full signal chain" and pinned
	## three hops for two players; _ambient_player is the fourth and was absent,
	## so the ONE routing in the chain that diverges was the one nothing asserted.
	## Ambient goes straight to Master: it skips the night filter (it IS the
	## night) and it also skips the DIALOGUE DUCK, so while music steps back 6 dB
	## for a dialogue panel, rain and wind do not. That is a mix decision, it is
	## UNREVIEWED, and it is invisible from the assignment itself — which is why
	## the rule here (CLAUDE.md, divergent + invisible at authoring) is to demand
	## the ANNOTATION, not a particular bus. Change the routing freely; say why.
	assert_eq(sm._ambient_player.bus, "Master",
		"_ambient_player moved off Master to %s — that is allowed, but it now inherits the night filter and/or the dialogue duck, and the annotation beside the assignment must say so" % sm._ambient_player.bus)
	var src: String = FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")
	assert_gt(src.length(), 5000, "SCOPE control: SoundManager.gd read back %d chars" % src.length())
	var at: int = src.find("_ambient_player.bus =")
	assert_gt(at, 0, "SCOPE control: the ambient bus assignment is gone; this arm is anchored on nothing")
	var preceding: String = src.substr(max(0, at - 200), 200)
	assert_true(preceding.contains("MusicDuck") or preceding.contains("duck"),
		"the ambient bus assignment carries no annotation explaining what it diverges FROM — the next reader spends an hour deriving that it skips the duck, as I did. State it in one line.")


func test_compound_night_plus_duck_active_together() -> void:
	## Enable both, verify neither clobbers the other. Real gameplay case:
	## player pauses at night, dialogue triggers at night, LLM chat at night.
	var sm := _sm()
	if sm == null:
		pass_test("SoundManager not present")
		return
	var night_idx: int = _bus_index("MusicNight")
	var duck_idx: int = _bus_index("MusicDuck")
	if night_idx == -1 or duck_idx == -1:
		pass_test("Buses missing")
		return

	var was_night: bool = sm.are_night_music_effects_enabled()
	var was_duck: bool = sm.is_music_ducked_for_dialogue()

	sm.set_night_music_effects(true)
	sm.duck_music_for_dialogue(true)
	await get_tree().create_timer(0.4).timeout  # let duck taper settle

	# Night bus: LPF + Reverb both enabled
	assert_true(AudioServer.is_bus_effect_enabled(night_idx, 0),
		"Compound: night LPF must still be enabled with duck also active")
	assert_true(AudioServer.is_bus_effect_enabled(night_idx, 1),
		"Compound: night Reverb must still be enabled with duck also active")

	# Duck bus: Amplify volume tapered to target
	var amp = AudioServer.get_bus_effect(duck_idx, 0)
	assert_almost_eq(amp.volume_db, -6.0, 0.5,
		"Compound: duck amp volume_db must taper to DUCK_TARGET_DB even while night effects are on — signal chain must have both stages active; got %.2f" % amp.volume_db)

	# API state getters both agree
	assert_true(sm.are_night_music_effects_enabled(),
		"are_night_music_effects_enabled must report true under compound state")
	assert_true(sm.is_music_ducked_for_dialogue(),
		"is_music_ducked_for_dialogue must report true under compound state")

	# Restore (and await the duck taper so a following test sees settled amp)
	sm.set_night_music_effects(was_night)
	sm.duck_music_for_dialogue(was_duck)
	await get_tree().create_timer(0.4).timeout


func test_disabling_night_leaves_duck_intact() -> void:
	## Cross-toggle: turning off night must not affect duck (and vice versa).
	## A future refactor that shares state between the two would break this.
	var sm := _sm()
	if sm == null:
		pass_test("SoundManager not present")
		return
	var night_idx: int = _bus_index("MusicNight")
	if night_idx == -1:
		pass_test("Night bus missing")
		return

	var was_night: bool = sm.are_night_music_effects_enabled()
	var was_duck: bool = sm.is_music_ducked_for_dialogue()

	sm.set_night_music_effects(true)
	sm.duck_music_for_dialogue(true)
	await get_tree().create_timer(0.4).timeout

	sm.set_night_music_effects(false)  # kill night, leave duck alone
	assert_false(sm.are_night_music_effects_enabled(),
		"Night effects must disable cleanly")
	assert_true(sm.is_music_ducked_for_dialogue(),
		"Duck state must survive night toggle — two independent axes")

	sm.duck_music_for_dialogue(false)  # cleanup
	# Restore (and await the duck taper so a following test sees settled amp)
	sm.set_night_music_effects(was_night)
	sm.duck_music_for_dialogue(was_duck)
	await get_tree().create_timer(0.4).timeout
