extends GutTest

## Every battle restarted the field music from 0:00.
##
## `capture_music_state()` recorded `{track, area, playing}` and no POSITION, so `restore_music_state`
## handed `play_area_music` an area and the bed began again at its head. Measured before the fix:
##
##     overworld bed at 1.21 s  ->  one battle  ->  back at 0.09 s
##
## 🔑 THE NUMBERS ARE WHY THIS MATTERS RATHER THAN THE MECHANISM. `overworld_medieval` is 198 s;
## a W1 encounter lands every ~30 s. So a player heard the first half-minute of a three-minute
## track, over and over, for the whole of World 1 — and the other two and a half minutes were
## authored, shipped, and unreachable in ordinary play. Same for every village and dungeon bed,
## and for every pause-menu open and cutscene that captures and restores.
##
## ⛔ AREA BEDS ONLY, AND THAT IS THE DESIGN RATHER THAN A LIMIT. A battle or victory track must
## start at its head — those are dramatic cues, not a place you were. The position is parked by
## `play_area_music` and consumed by the first manifest start after it, so `play_music` never sees
## one.

const AREA := "overworld"
const SELF_PATH := "res://test/unit/test_the_field_bed_picks_up_where_it_left_off.gd"


func before_each() -> void:
	SoundManager.stop_music()
	SoundManager.set_music_volume(1.0)


func after_each() -> void:
	SoundManager.stop_music()


func _frames(n: int = 6) -> void:
	for i in range(n):
		await get_tree().process_frame


## Let the bed actually advance. Frame-counting is not seconds, so this waits on the clock.
func _advance_ms(ms: int) -> void:
	var deadline: int = Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func test_the_state_carries_where_the_bed_had_reached() -> void:
	SoundManager.play_area_music(AREA)
	await _frames(10)
	await _advance_ms(900)
	var live: float = SoundManager._music_player.get_playback_position()
	assert_gt(live, 0.3, "CONTROL: the bed reached %.2f s — without real playback this file measures nothing" % live)

	var state: Dictionary = SoundManager.capture_music_state()
	assert_true(state.has("position"), "capture_music_state must record a position — without it a restore cannot do anything but restart")
	assert_almost_eq(float(state["position"]), live, 0.35,
		"the captured position (%.2f) must be where the bed actually was (%.2f)" % [float(state.get("position", -1.0)), live])


func test_a_battle_no_longer_restarts_the_field_music() -> void:
	SoundManager.play_area_music(AREA)
	await _frames(10)
	await _advance_ms(900)
	var before: float = SoundManager._music_player.get_playback_position()
	assert_gt(before, 0.3, "CONTROL: the bed was at %.2f s before the battle" % before)
	var state: Dictionary = SoundManager.capture_music_state()

	SoundManager.play_music("battle_medieval")
	await _frames(8)
	assert_true(SoundManager._current_area == "", "CONTROL: a battle clears the area, which is why the restore has to carry the position itself")

	SoundManager.restore_music_state(state)
	await _frames(14)
	var after: float = SoundManager._music_player.get_playback_position()
	assert_gt(after, before - 0.5,
		"the field bed restarted at %.2f s after a battle that began at %.2f — the other two and a half minutes of the track are unreachable in play" % [after, before])


func test_a_battle_bed_still_starts_at_its_head() -> void:
	## ⛔ THE DANGEROUS DIRECTION: a parked position outliving its own start would seek the NEXT
	## track, so a battle would open mid-phrase — worse than the defect being fixed.
	##
	## ⚠️ THE BATTLE IN THE MIDDLE IS LOAD-BEARING, and without it this arm tested nothing.
	## `play_area_music` early-outs when `_current_area` already equals the area, so a restore with
	## no battle before it never parks anything and the assert below passed on an empty mechanism.
	## Measured: parked 0.00 where the capture read 0.93. `play_music` is what clears `_current_area`.
	SoundManager.play_area_music(AREA)
	await _frames(10)
	await _advance_ms(900)
	var state: Dictionary = SoundManager.capture_music_state()
	assert_gt(float(state.get("position", 0.0)), 0.3, "CONTROL: there is a real position to leak")

	SoundManager.play_music("victory")
	await _frames(8)
	assert_eq(SoundManager._current_area, "", "CONTROL: the cue cleared the area, so the restore below really parks")
	SoundManager.restore_music_state(state)
	await _frames(14)
	assert_gt(SoundManager._music_player.get_playback_position(), 0.3,
		"CONTROL: the restore resumed, so a position was parked AND consumed")

	SoundManager.play_music("battle_medieval")
	await _frames(10)
	assert_lt(SoundManager._music_player.get_playback_position(), 0.5,
		"the battle bed opened at %.2f s — a parked area position leaked into a dramatic cue" % SoundManager._music_player.get_playback_position())


func test_a_resume_at_the_wrap_restarts_instead_of_stuttering() -> void:
	## ⛔ THIS IS THE CLAMP THAT IS MINE. Godot ALREADY restarts a seek past the end — measured:
	## play(212.4) on a 182.4 s stream reports position 0.00 and keeps playing. So an arm that
	## seeks past the end tests the ENGINE, not this file, and passed with the clamp deleted.
	## What the engine does NOT do is refuse a position just short of the end, and resuming with
	## 0.2 s left is a wrap the player hears as a stutter.
	SoundManager.play_area_music(AREA)
	await _frames(12)
	var length: float = SoundManager._music_player.stream.get_length()
	assert_gt(length, 10.0, "CONTROL: the bed is %.1f s long" % length)

	SoundManager.stop_music()
	SoundManager.play_area_music(AREA, length - 0.2)
	await _frames(14)
	assert_true(SoundManager._music_player.playing, "the bed must be playing")
	assert_lt(SoundManager._music_player.get_playback_position(), 2.0,
		"resumed at %.2f s on a %.1f s bed — within a second of the end is a wrap, not a resume" % [SoundManager._music_player.get_playback_position(), length])


func test_a_negative_position_never_reaches_the_player() -> void:
	## `play(-12)` does not clamp: measured, it reports a playback position of 89,466 s on a
	## 182 s stream. The `> 0.0` at the use site is the only thing between a bad capture and that.
	SoundManager.play_area_music(AREA, -12.0)
	await _frames(14)
	assert_true(SoundManager._music_player.playing, "a negative position must start the bed at its head, not refuse to play")
	assert_lt(SoundManager._music_player.get_playback_position(), 2.0,
		"the player reports %.2f s — a negative seek reached AudioStreamPlayer.play()" % SoundManager._music_player.get_playback_position())

func test_the_members_this_file_reaches_still_exist() -> void:
	## THE FILE IS LOUD ON A RENAME BY ARM ORDER, NOT BY CONSTRUCTION. Measured 2026-09-16,
	## renaming across src/ with this arm absent:
	##
	##     capture_music_state   EC=4 · Passing 4 · Risky 1 · Asserts 15 -> 7
	##     play_area_music       EC=4 · Passing 0 · Risky 5 · Asserts 15 -> 0
	##
	## Passing 4 is the number to read. Two of those four arms assert their CONTROL, then call
	## the missing method, abort, and score PASSING on the half of their asserts that ran. Only
	## `a_battle_bed_still_starts_at_its_head` reaches the subject BEFORE its first assert, and
	## that one arm is the whole reason the wrapper exits 4. Reorder it and this file goes green
	## with its subject deleted.
	##
	## The member list is DERIVED from this file's own text on every run, so a reach added later
	## is covered without anyone remembering to add it here.
	##
	## `has_method` for methods, `in` for properties: both ANSWER rather than raise, which is why
	## they fail here by name instead of aborting alongside the arms they protect. `get() != null`
	## cannot do the property half — a null-valued property is indistinguishable from an absent
	## one, which is why the fade guard's floor needed a hardcoded exemption.
	var src: String = FileAccess.get_file_as_string(SELF_PATH)
	assert_gt(src.length(), 1000, "CONTROL: this arm read its own source back — %d chars" % src.length())
	var methods := {}
	var props := {}
	## ⛔ THE STRIP IS NOT COSMETIC. These floors exist to catch RENAMES, and the commit that
	## renames a member is the commit whose comment explains the rename BY NAME — so prose naming
	## `SoundManager.<old>` is the MODAL case here, not a corner one (@cowir-sprites, 2026-09-16).
	## The shipped version skipped lines BEGINNING with `#`, which leaves a trailing comment on a
	## code line inside the corpus. Measured before switching: identical sets either way today, so
	## this is latent-not-live — and the shared helper is quote- and escape-aware where a `#` scan
	## is not.
	const GdSource := preload("res://test/unit/helpers/gd_source.gd")
	var re := RegEx.create_from_string("SoundManager\\.([A-Za-z_][A-Za-z0-9_]*)(\\()?")
	for line in GdSource.strip_comments(src).split("\n"):
		for m in re.search_all(str(line)):
			if m.get_string(2) == "(":
				methods[m.get_string(1)] = true
			else:
				props[m.get_string(1)] = true
	assert_gt(methods.size(), 3, "CONTROL: derived %d method reaches from this file's own source" % methods.size())
	assert_gt(props.size(), 0, "CONTROL: derived %d property reaches from this file's own source" % props.size())
	for name in methods:
		assert_true(SoundManager.has_method(name),
			"SoundManager has no method %s() — arms in this file call it and would abort mid-way, scoring PASSING on the asserts that already ran" % name)
	for name in props:
		assert_true(name in SoundManager,
			"SoundManager has no property %s — arms in this file read it directly and would go quiet rather than red" % name)
