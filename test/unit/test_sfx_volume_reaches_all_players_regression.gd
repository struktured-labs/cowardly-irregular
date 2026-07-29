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


func _gd_files_under(root: String, out: Array[String]) -> void:
	for d in DirAccess.get_directories_at(root):
		_gd_files_under(root.path_join(str(d)), out)
	for f in DirAccess.get_files_at(root):
		if str(f).ends_with(".gd"):
			out.append(root.path_join(str(f)))


func test_no_sfx_player_is_left_on_master() -> void:
	## DERIVED FROM src/ 2026-07-29. This used to iterate a two-entry list holding
	## exactly the files the 2026-07-28 incident was about, under a comment claiming
	## it "scans for the defect's shape rather than a maintained list". It was the
	## maintained list — and the header three paragraphs up records that cowir-sfx
	## REJECTED that shape when choosing the fix ("it rots the moment someone adds a
	## fourth"). Rejected in the fix, then written into the guard.
	##
	## SoundManager is excluded because it creates its players in loops (6 players,
	## 2 bus-assignment lines), so a line-count comparison cannot read it. That is a
	## named alternative, not a suppression: its players are checked at RUNTIME by
	## test_every_soundmanager_player_is_reachable_from_a_slider, which is stronger
	## than this scan because it enumerates live nodes rather than source text.
	var files: Array[String] = []
	_gd_files_under("res://src", files)
	var scanned: int = 0
	var offenders: Array = []
	for path in files:
		if path.ends_with("SoundManager.gd"):
			continue
		var src := FileAccess.get_file_as_string(path)
		var creates := src.count("AudioStreamPlayer.new()")
		if creates == 0:
			continue
		scanned += 1
		var joins := src.count('bus = "SFX"') + src.count('bus = &"SFX"')
		if creates > joins:
			offenders.append("%s creates %d player(s) but only %d join the SFX bus"
				% [path.get_file(), creates, joins])

	## Vacuity control: if the walk breaks, `files` is empty, nothing is scanned and
	## an empty offender list passes having proven nothing.
	assert_gt(scanned, 0,
		"control: found no file outside SoundManager constructing an AudioStreamPlayer — the src/ walk is broken, so the check below ran on nothing")
	assert_eq(offenders, [],
		"an SFX player not on the SFX bus is unreachable from the volume slider:\n  %s"
			% "\n  ".join(offenders))


func test_every_soundmanager_player_is_reachable_from_a_slider() -> void:
	## The property the 2026-07-28 finding was actually about: a player nobody can
	## turn down. Asserted BEHAVIOURALLY over SoundManager's live children rather
	## than against three hardcoded names — it owns six players, and the old test
	## named the three that were already known good.
	##
	## Deliberately does not assert WHICH bus: AmbientPlayer sits on Master by design
	## (it must miss the MusicNight filter chain) and is attenuated by set_music_volume
	## writing volume_db directly. Pinning bus names would have called that a defect
	## and forced an exemption; pinning reachability describes what must be true of
	## every player however it is wired.
	var sm := SoundManager
	var players: Array[AudioStreamPlayer] = []
	for c in sm.get_children():
		if c is AudioStreamPlayer:
			players.append(c)
	assert_gt(players.size(), 0, "control: SoundManager must own AudioStreamPlayers to check")

	## Reachability = EITHER the player's own volume_db drops OR its bus attenuates.
	## Measured separately rather than summed into an effective level, because the
	## sum is unreadable in this environment: the headless mute leaves Master muted,
	## so an effective-level probe reports AmbientPlayer at silence in BOTH states and
	## calls a correctly-wired player unreachable. Two mechanisms, two measurements.
	const SILENCE_FLOOR_DB := -80.0
	var bus_state := func(p: AudioStreamPlayer) -> float:
		var b := AudioServer.get_bus_index(str(p.bus))
		if b < 0:
			return 0.0
		return -1000.0 if AudioServer.is_bus_mute(b) else AudioServer.get_bus_volume_db(b)

	var sfx_idx := AudioServer.get_bus_index(SFX_BUS)
	var sfx_restore := AudioServer.get_bus_volume_db(sfx_idx)
	var sfx_mute_restore := AudioServer.is_bus_mute(sfx_idx)

	## MusicPlayerB is the crossfade's OUTGOING buffer, not an independently
	## controlled channel: SoundManager:246 constructs it silent and :1351 hands it
	## _music_player's already-slider-scaled level when a crossfade starts. Its
	## reachability is inherited, so asserting it responds to the slider directly
	## asserts something false about its design.
	##
	## Reset to that constructed baseline before measuring. Found by the FULL SUITE
	## (clean in isolation): an earlier test leaves it at -40 dB, which clears the
	## silence floor and flags it. Restoring the state the code itself establishes is
	## the same hygiene as clearing a persisted cooldown -- without it this guard is
	## flaky, and a flaky guard is worse than none.
	var mpb := SoundManager.get_node_or_null("MusicPlayerB") as AudioStreamPlayer
	var mpb_restore: float = mpb.volume_db if mpb != null else 0.0
	if mpb != null:
		mpb.volume_db = SILENCE_FLOOR_DB

	SoundManager.set_sfx_volume(1.0)
	SoundManager.set_music_volume(1.0)
	var loud_own: Dictionary = {}
	var loud_bus: Dictionary = {}
	for p in players:
		loud_own[p.name] = p.volume_db
		loud_bus[p.name] = bus_state.call(p)

	SoundManager.set_sfx_volume(0.0)
	SoundManager.set_music_volume(0.0)
	var unreachable: Array = []
	for p in players:
		## A player parked at the silence floor cannot be "still audible with the
		## sliders down" — MusicPlayerB sits at -80 ("Start silent", SoundManager:246)
		## until a crossfade hands it _music_player's already-slider-scaled level.
		## Skipping it is the property's scope, not an exemption: the assertion is
		## about players you can HEAR.
		if loud_own[p.name] <= SILENCE_FLOOR_DB:
			continue
		var own_dropped: bool = p.volume_db < loud_own[p.name]
		var bus_dropped: bool = bus_state.call(p) < loud_bus[p.name]
		if not (own_dropped or bus_dropped):
			unreachable.append("%s (bus=%s) held %.1f dB on a bus at %.1f dB with BOTH sliders at zero"
				% [p.name, str(p.bus), p.volume_db, bus_state.call(p)])

	SoundManager.set_sfx_volume(1.0)
	SoundManager.set_music_volume(1.0)
	AudioServer.set_bus_volume_db(sfx_idx, sfx_restore)
	AudioServer.set_bus_mute(sfx_idx, sfx_mute_restore)
	if mpb != null:
		mpb.volume_db = mpb_restore

	assert_eq(unreachable, [],
		"a player no slider can turn down is the 2026-07-28 defect exactly — set the sliders to zero and you still hear it:\n  %s"
			% "\n  ".join(unreachable))
