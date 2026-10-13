extends GutTest

## BLOWING A CRACKED WALL OPEN SOUNDED LIKE A WOODEN DOOR CREAKING.
##
## `DungeonMechanics.try_open` serves two lock kinds — `G`/key and `Z`/bomb (RESOURCE_FOR_LOCK) — and
## played `door_open` for both. The function already knows which: its FAILURE toast says "You need a
## key" or "Cracked, but solid. You need a blast charge", and its sprite picks `_door_texture()` or
## `_crack_texture()`. So the text and the art differentiated the two and the audio was the one
## surface that did not. @cowir-music found it and left the cue choice to this lane.
##
## ⛔ AND IT IS ONE OF FOUR. `door_open` is played at FOUR sites in that file, for four different
## physical events — this lock path, a TIMED PRESSURE PLATE (`_on_timed_plate_entered`), a MIRROR
## ROTATING (`toggle_mirror`) and a BLOCK PUSHED ONTO A TARGET (`mark_block_on_target`). Only the
## blast is fixed here, because it is the one with an authored cue; the other three are reported and
## need assets that do not exist yet. Nothing in the bank fits them — the nearest candidates are a
## save-crystal sting (which would make a puzzle sound like a save point) and footsteps.
## The arm below pins the COUNT so that fixing another one is a deliberate act, not a drift.

const SRC := "res://src/exploration/DungeonMechanics.gd"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")


func test_the_two_lock_kinds_do_not_share_a_cue() -> void:
	var code: String = GdSource.code_of(SRC)
	assert_ne(code, "", "CONTROL: DungeonMechanics code must survive the comment strip")
	var at: int = code.find("func try_open")
	assert_gt(at, -1, "CONTROL: try_open is gone — re-point this guard rather than deleting it")
	if at < 0:
		return
	var nxt: int = code.find("\nfunc ", at + 1)
	var body: String = code.substr(at, nxt - at) if nxt > at else code.substr(at)
	assert_true(body.contains("wall_blast"),
		"try_open no longer plays wall_blast, so a blast charge sounds like a wooden door again")
	assert_true(body.contains("resource == \"key\""),
		"try_open plays a cue without branching on the lock kind — the two kinds would share it")


func test_the_blast_cue_is_authored_and_plays() -> void:
	## Registration is not playback: a key whose file will not load falls through to the procedural
	## path while every manifest assertion stays green. The stream's LENGTH is the discriminator.
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))
	assert_true(parsed is Dictionary, "VOID: manifest did not parse")
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}
	assert_true(sfx.has("wall_blast"), "wall_blast is no longer authored")
	SoundManager._sfx_cooldowns.erase("wall_blast")
	SoundManager.play_ui("wall_blast")
	assert_true(SoundManager._sfx_cooldowns.has("wall_blast"),
		"play_ui(\"wall_blast\") did not reach the manifest entry, so it fell through to the procedural path")
	var p: AudioStreamPlayer = SoundManager._ui_player
	assert_not_null(p, "CONTROL: the UI player must exist")
	if p == null or p.stream == null:
		assert_not_null(p.stream if p else null, "wall_blast stamped its cooldown but left no stream")
		return
	assert_almost_eq(p.stream.get_length(), 0.95, 0.06,
		"the stream on the UI player is %.2fs, not the 0.95s blast cue — a different file answers to wall_blast" % p.stream.get_length())
	SoundManager._sfx_cooldowns.erase("wall_blast")


func test_the_other_three_door_open_sites_are_still_counted() -> void:
	## A LEDGER over the remaining three, pinned by COUNT so a fourth cue arriving is deliberate.
	## They are a timed plate, a mirror and a pushed block — none of them a door, none of them with a
	## cue that fits. If one gains its own cue this reds and the number must come down in the same
	## commit; if a NEW mechanic reaches for door_open it reds too, which is the point.
	var code: String = GdSource.code_of(SRC)
	var n: int = code.count("play_ui(\"door_open\")")
	assert_eq(n, 2,
		"DungeonMechanics plays door_open at %d sites, not the 2 declared. A heavy wooden door is the wrong sound for a rotating mirror or a pushed block; if you fixed one, bring this number down, and if you added one, it needs its own cue." % n)


## SECOND OF THE FOUR, authored on @cowir-main's "one per tick" instruction: a stone pressure plate
## underfoot played `door_open`, a heavy wooden door creaking. `_on_timed_plate_entered` fires every
## time a player steps on a timed plate, which makes it the most repeated of the four.
func test_the_timed_plate_has_its_own_voice() -> void:
	var code: String = GdSource.code_of(SRC)
	var at: int = code.find("func _on_timed_plate_entered")
	assert_gt(at, -1, "CONTROL: _on_timed_plate_entered is gone — re-point this arm")
	if at < 0:
		return
	var nxt: int = code.find("\nfunc ", at + 1)
	var body: String = code.substr(at, nxt - at) if nxt > at else code.substr(at)
	assert_true(body.contains("plate_engage"),
		"the timed plate no longer plays plate_engage, so stepping on stone sounds like a wooden door again")
	assert_false(body.contains("door_open"),
		"the timed plate plays door_open again")


func test_the_plate_cue_is_authored_and_plays() -> void:
	## Registration is not playback, and the stream LENGTH is what separates the authored file from
	## the procedural fallback — 0.55s here, where door_open is 1.00 and wall_blast 0.95.
	SoundManager._sfx_cooldowns.erase("plate_engage")
	SoundManager.play_ui("plate_engage")
	assert_true(SoundManager._sfx_cooldowns.has("plate_engage"),
		"play_ui(\"plate_engage\") did not reach the manifest entry, so it fell through to the procedural path")
	var p: AudioStreamPlayer = SoundManager._ui_player
	assert_not_null(p, "CONTROL: the UI player must exist")
	if p == null or p.stream == null:
		assert_true(false, "plate_engage stamped its cooldown but left no stream on the UI player")
		return
	assert_almost_eq(p.stream.get_length(), 0.55, 0.06,
		"the stream is %.2fs, not the 0.55s plate cue — at 1.00s it is door_open and at 0.95s it is wall_blast" % p.stream.get_length())
	SoundManager._sfx_cooldowns.erase("plate_engage")
