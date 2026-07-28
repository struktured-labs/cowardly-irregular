extends GutTest

## Regression test for cowir-sfx's 2026-07-28 finding:
## the SFX volume slider did not control all SFX.
##
## set_sfx_volume wrote volume_db on exactly the three players SoundManager owns and made no
## AudioServer call at all. Two AudioStreamPlayers are constructed in OTHER files with hardcoded
## volumes:
##   BattleTransition.gd   the monster-transition sting, -15.0 dB, no bus (-> Master)
##   CutsceneDialogue.gd   the per-character voice blip, -6.0 dB
## Neither was reachable from any volume setting, and both are high-frequency — one per battle
## transition, one per dialogue CHARACTER. Set SFX to 0 and you still heard both.
##
## This is the partial-enumeration class: the volume system enumerated *SoundManager's* players,
## which was complete for its original direction and blind to players any other file creates. The
## file that's wrong contains no volume code at all, which is why reading SoundManager forever
## would not have found it.
##
## Fixed with a BUS rather than a longer list. cowir-sfx explicitly rejected "have set_sfx_volume
## reach out to known external players" as the graveyard shape — it rots the moment someone adds a
## fourth. A bus makes the class structurally impossible: anything on it is attenuated forever.
##
## Telling detail: CutsceneDialogue already wrote `bus = "SFX" if get_bus_index("SFX") >= 0`.
## The author anticipated this bus. It had simply never been created, so that line always fell
## through to Master.

const SFX_BUS := "SFX"


func test_the_sfx_bus_exists() -> void:
	assert_ne(AudioServer.get_bus_index(SFX_BUS), -1,
		"SoundManager must create the SFX bus — CutsceneDialogue has been asking for it by name")


func test_the_sfx_bus_routes_to_master() -> void:
	var idx := AudioServer.get_bus_index(SFX_BUS)
	assert_ne(idx, -1)
	assert_eq(AudioServer.get_bus_send(idx), &"Master",
		"SFX must reach the output, not dead-end on a bus with no send")


func test_soundmanagers_own_players_are_on_the_bus() -> void:
	for player_name in ["UIPlayer", "BattlePlayer", "AbilityPlayer"]:
		var p := SoundManager.get_node_or_null(player_name) as AudioStreamPlayer
		assert_not_null(p, "%s must exist" % player_name)
		if p != null:
			assert_eq(str(p.bus), SFX_BUS,
				"%s must sit on the SFX bus so one control attenuates it" % player_name)


func test_the_slider_attenuates_the_BUS_not_just_the_players() -> void:
	# The actual fix. Writing volume_db on three players can never reach a fourth player in
	# another file; setting the bus reaches every one of them.
	var idx := AudioServer.get_bus_index(SFX_BUS)
	var restore := AudioServer.get_bus_volume_db(idx)
	var was_muted := AudioServer.is_bus_mute(idx)

	SoundManager.set_sfx_volume(1.0)
	var loud := AudioServer.get_bus_volume_db(idx)
	SoundManager.set_sfx_volume(0.25)
	var quiet := AudioServer.get_bus_volume_db(idx)

	assert_lt(quiet, loud, "lowering the slider must lower the SFX BUS, not only the three players")

	SoundManager.set_sfx_volume(0.0)
	assert_true(AudioServer.is_bus_mute(idx),
		"slider at zero must MUTE the bus — that is what makes 'set SFX to 0' actually silent")

	AudioServer.set_bus_volume_db(idx, restore)
	AudioServer.set_bus_mute(idx, was_muted)


func test_base_levels_are_not_double_attenuated() -> void:
	# Players hold their design-intent mix; the bus carries the slider. Folding the slider into
	# both would attenuate twice and quietly break the authored channel hierarchy.
	SoundManager.set_sfx_volume(0.5)
	var ui := SoundManager.get_node_or_null("UIPlayer") as AudioStreamPlayer
	var battle := SoundManager.get_node_or_null("BattlePlayer") as AudioStreamPlayer
	assert_eq(ui.volume_db, SoundManager.SFX_UI_BASE_DB,
		"players must stay at their base level — the slider lives on the bus now")
	assert_eq(battle.volume_db, SoundManager.SFX_BATTLE_BASE_DB)
	# And the authored hierarchy survives: battle louder than UI.
	assert_gt(battle.volume_db, ui.volume_db,
		"the per-channel mix (UI quietest, battle punchiest) must be preserved")
	SoundManager.set_sfx_volume(1.0)


func test_externally_constructed_players_join_the_bus() -> void:
	# The two that escaped. Source-pinned because both are constructed inside runtime paths
	# (a battle transition and a dialogue open) that a unit test cannot cheaply drive.
	var bt := FileAccess.get_file_as_string("res://src/transitions/BattleTransition.gd")
	assert_string_contains(bt, 'bus = "SFX"',
		"BattleTransition's monster sting must join the SFX bus — it played at a hardcoded "
		+ "level with the slider at zero")
	var cd := FileAccess.get_file_as_string("res://src/cutscene/CutsceneDialogue.gd")
	assert_string_contains(cd, 'bus = "SFX"',
		"CutsceneDialogue's voice blip must join the SFX bus")


func test_no_sfx_player_is_left_on_master() -> void:
	# The ratchet that keeps this closed. Any AudioStreamPlayer created for a SOUND EFFECT must
	# declare the SFX bus; music players are deliberately exempt (they route through the
	# MusicNight/MusicDuck chain). Scans for the defect's shape rather than a maintained list.
	var offenders: Array = []
	for path in ["res://src/transitions/BattleTransition.gd", "res://src/cutscene/CutsceneDialogue.gd"]:
		var src := FileAccess.get_file_as_string(path)
		var creates := src.count("AudioStreamPlayer.new()")
		var joins := src.count('bus = "SFX"')
		if creates > joins:
			offenders.append("%s creates %d player(s) but only %d join the SFX bus"
				% [path.get_file(), creates, joins])
	assert_eq(offenders, [],
		"an SFX player not on the SFX bus is unreachable from the volume slider:\n  %s"
			% "\n  ".join(offenders))
