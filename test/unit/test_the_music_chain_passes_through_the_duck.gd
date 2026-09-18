extends GutTest

## The dialogue duck lives as an Amplify on the `MusicDuck` bus. It only attenuates anything if the
## music actually ROUTES through that bus — and whether it does is decided by BUS CREATION ORDER:
##
##     _ensure_music_night_bus() picks its send target AT CREATION:
##         MusicDuck if that bus exists, else "Master"
##     _ensure_music_duck_bus() is otherwise LAZY, called from duck_music_for_dialogue()
##
## ⛔ SO SWAPPING TWO LINES IN _setup_audio_players SILENTLY UNDUCKS THE MUSIC. The night bus would
## find no duck bus, fall back to Master, and every dialogue would dip a bus nothing sends to. It
## compiles, it passes every other arm in the suite, and the only symptom is that conversations stop
## being audible over the bed.
##
## 🔑 AND THE PARAMETER IS NOT THE ROUTING. My own duck probe measured the Amplify going
## 0.00 -> -6.00 dB and I used it to justify a fix and then a revert. An effect parameter on a bus
## nothing sends to reads exactly the same. This file measures the SIGNAL PATH instead.
##
## ⚠️ THE ARM ASSERTS MEMBERSHIP IN THE CHAIN, NOT THE NEXT HOP (@cowir-sfx's shape, and their
## mutation is why): re-parenting a bus is a legitimate mix change and must not red. What must red is
## the music no longer passing through the duck at all.

const MAX_HOPS := 8


## Every bus the player's signal traverses, ending at Master.
func _chain_from(bus_name: String) -> Array[String]:
	var out: Array[String] = [bus_name]
	var hop: String = bus_name
	for _i in MAX_HOPS:
		var idx: int = AudioServer.get_bus_index(hop)
		if idx <= 0:
			break
		hop = AudioServer.get_bus_send(idx)
		out.append(hop)
		if hop == "Master":
			break
	return out


func test_control_the_walk_terminates_at_master() -> void:
	## Without this every membership arm below could pass on a chain that never resolved — and
	## AudioServer.set_bus_send ACCEPTS A NAME THAT IS NOT A BUS and stores it silently, so a typo'd
	## send produces no error and no sound (@cowir-sfx, measured).
	assert_not_null(SoundManager._music_player, "CONTROL: the music player must exist")
	var chain := _chain_from(SoundManager._music_player.bus)
	assert_gt(chain.size(), 1, "CONTROL: the walk found only %s" % str(chain))
	assert_eq(chain[chain.size() - 1], "Master",
		"the music chain does not reach Master: %s — a send naming a bus that does not exist is stored silently and plays nothing" % " -> ".join(chain))


func test_the_music_passes_through_the_duck_bus() -> void:
	var chain := _chain_from(SoundManager._music_player.bus)
	assert_true(chain.has(SoundManager.MUSIC_DUCK_BUS),
		"the music chain is %s and does not include %s — the dialogue duck dips an Amplify the music never reaches, so conversations are inaudible over the bed while every duck arm still reports -6 dB" % [" -> ".join(chain), SoundManager.MUSIC_DUCK_BUS])


func test_the_crossfade_player_takes_the_same_path() -> void:
	## B carries the OUTGOING bed during a crossfade and through fade_out_music. A duck that catches
	## only one of the two players dips half the music.
	var a := _chain_from(SoundManager._music_player.bus)
	var b := _chain_from(SoundManager._music_player_b.bus)
	assert_eq(" -> ".join(b), " -> ".join(a),
		"the two music players take different paths: A %s vs B %s" % [" -> ".join(a), " -> ".join(b)])


func test_the_night_filter_is_on_the_music_path_too() -> void:
	## The other bus in the chain, so a repair cannot drop the night filter to satisfy the duck.
	var chain := _chain_from(SoundManager._music_player.bus)
	assert_true(chain.has(SoundManager.MUSIC_NIGHT_BUS),
		"the music chain is %s and does not include %s — set_night_music_effects would toggle a filter nothing passes through" % [" -> ".join(chain), SoundManager.MUSIC_NIGHT_BUS])


func test_the_creation_order_that_makes_this_true_is_pinned() -> void:
	## The runtime arms above are the claim; this names the two lines whose ORDER produces it, so a
	## reorder reds here with the reason rather than only showing up as a chain that lost a bus.
	var src: String = FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")
	var i: int = src.find("func _setup_audio_players")
	assert_gt(i, -1, "CONTROL: _setup_audio_players must exist")
	var body: String = src.substr(i, src.find("\nfunc ", i + 1) - i)
	var duck: int = body.find("_ensure_music_duck_bus()")
	var night: int = body.find("_ensure_music_night_bus()")
	assert_gt(duck, -1, "CONTROL: _setup_audio_players must build the duck bus")
	assert_gt(night, -1, "CONTROL: _setup_audio_players must build the night bus")
	assert_lt(duck, night,
		"the duck bus must be created BEFORE the night bus — the night bus picks its send target at creation and falls back to Master when no duck bus exists yet, which unducks the music silently")
