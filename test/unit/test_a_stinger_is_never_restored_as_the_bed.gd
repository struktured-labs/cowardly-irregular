extends GutTest

## Open a chest, press Start, close the menu — and the 5 s stinger came back AS THE BED.
##
## `play_music` guards its OWN capture (`if not _is_stinger_track(_current_music)`) because two
## Limit Breaks in one fight made the second stinger resume to the first. But THREE other callers
## reach `capture_music_state()` directly and had no such guard:
##
##     JukeboxMenu:71          snapshot on open
##     GameLoop:1401           snapshot when the pause menu opens
##     CutsceneDirector:359    snapshot before a cutscene
##
## All three are reachable while an exploration stinger plays — `stinger_item_found`
## (TreasureChest), `stinger_save_point` (SavePoint), `stinger_quest_complete` (QuestSystem).
## Restoring one plays a one-shot as the bed; it ends, and nothing re-asserts until the player
## crosses an area boundary.
##
## The fix has ONE owner: capture_music_state() hands back what the stinger itself will resume to.

const STINGER := "stinger_item_found"
const BED := "overworld_medieval"


func before_each() -> void:
	SoundManager.stop_music()


func after_each() -> void:
	SoundManager.stop_music()


func test_control_the_stinger_is_declared_one() -> void:
	## Without this the arms below pass on an id the engine does not consider a stinger at all.
	assert_true(SoundManager._is_stinger_track(STINGER),
		"%s must be a declared stinger, or these arms test nothing" % STINGER)
	assert_false(SoundManager._is_stinger_track(BED),
		"CONTROL: the bed must NOT be a stinger, or the comparison below is vacuous")


func test_a_capture_taken_during_a_stinger_names_the_bed_not_the_stinger() -> void:
	SoundManager.play_music(BED, true)
	await get_tree().create_timer(0.2).timeout
	assert_eq(SoundManager._current_music, BED, "CONTROL: the bed is playing before the stinger")

	SoundManager.play_music(STINGER, true)
	assert_eq(SoundManager._current_music, STINGER, "CONTROL: the stinger took the player")

	var snap: Dictionary = SoundManager.capture_music_state()
	assert_ne(str(snap.get("track", "")), STINGER,
		"a menu opened over a stinger captured the ONE-SHOT as its resume target — closing it plays a 5s fragment as the bed and ends in silence")
	assert_eq(str(snap.get("track", "")), BED,
		"and the capture must name the bed the stinger will return to, got '%s'" % str(snap.get("track", "")))


func test_a_capture_with_no_bed_behind_the_stinger_restores_nothing() -> void:
	## The other direction: a stinger with nothing before it must not invent a bed.
	SoundManager.play_music(STINGER, true)
	var snap: Dictionary = SoundManager.capture_music_state()
	assert_eq(str(snap.get("track", "")), "",
		"with no bed behind the stinger the capture must be empty, not the stinger itself")


func test_an_ordinary_bed_still_captures_itself() -> void:
	## ⛔ THE DANGEROUS DIRECTION. A fix that blanked every capture would pass both arms above and
	## break the pause menu's restore for every normal track.
	SoundManager.play_music(BED, true)
	await get_tree().create_timer(0.2).timeout
	var snap: Dictionary = SoundManager.capture_music_state()
	assert_eq(str(snap.get("track", "")), BED,
		"a normal bed must still capture itself, or the pause menu restores nothing")
	assert_gt(float(snap.get("position", 0.0)), 0.0,
		"and it must carry its position, or the restore restarts the track")
