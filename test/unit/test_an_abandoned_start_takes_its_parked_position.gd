extends GutTest

## `play_area_music` arms THREE pieces of state and defers the real start: the area, the resume
## position, and the home area. `_invalidate_pending_area_start` cleared only the area, so an
## abandoned start left the position parked — and `_play_parked_position` has 37 callers through
## `_try_play_from_manifest` of which exactly ONE parks a value first. The other 36 read a survivor
## as if it were theirs.
##
## Measured before the fix, driving the real functions: an overworld start armed at 12.0 s and then
## abandoned (stop_music disarms the area, the deferred start returns stale) left 12.0 parked, and the
## next battle bed opened at 12.00 s instead of its own entry point. A bed starting mid-phrase is the
## audible symptom.
##
## Sibling of @cowir-music's .658 fix: stop_music and fade_out_music learned to disarm the pending
## AREA, and the two values parked beside it were left behind. Found with their own pre-step — that
## file's comments index this class, and three of them say "THIRD SITE".
##
## ⚠️ A bed may legitimately open above zero: a manifest entry's `loop_blend_seconds` sets a minimum
## entry point so a crossfade-looped bed does not open on its own tail (battle_medieval: 4.0 s). So the
## assertion below is "not the stale offset", NOT "zero" — pinning zero would fail on a correct bed and
## would have to be relaxed by whoever added the next blend.

const STALE := 12.0


func before_each() -> void:
	SoundManager.stop_music()
	SoundManager._pending_resume_position = 0.0
	SoundManager._pending_music_area = ""
	SoundManager._pending_home_area = ""


func after_each() -> void:
	SoundManager.stop_music()
	SoundManager._pending_resume_position = 0.0
	SoundManager._pending_music_area = ""
	SoundManager._pending_home_area = ""


func _blend_of(track: String) -> float:
	var e: Dictionary = SoundManager._music_manifest.get(track, {})
	return float(e.get("loop_blend_seconds", 0.0))


func test_an_abandoned_area_start_leaves_nothing_parked() -> void:
	SoundManager.play_area_music("overworld", STALE)
	assert_eq(SoundManager._pending_music_area, "overworld",
		"CONTROL: the area start must actually arm, or nothing below is abandoning anything")
	SoundManager.stop_music()                      # the player stops the music, or any play_music runs
	assert_eq(SoundManager._pending_music_area, "",
		"CONTROL: stop_music must disarm the area (cowir-music's .658 fix), or this is not the abandoned case")
	SoundManager._start_area_music_deferred("overworld")   # fires, sees a stale area, returns
	assert_eq(SoundManager._pending_resume_position, 0.0,
		"an abandoned start left %.1f s parked — the next bed through _try_play_from_manifest will open there" % SoundManager._pending_resume_position)
	assert_eq(SoundManager._pending_home_area, "",
		"an abandoned start left a home area parked, which _start_interior_music's cold start reads as its own")


func test_an_unrelated_bed_does_not_open_at_the_stale_offset() -> void:
	## The audible half. Drives the real battle start, which is one of the 36 callers that park nothing.
	SoundManager.play_area_music("overworld", STALE)
	SoundManager.stop_music()
	SoundManager._start_area_music_deferred("overworld")
	SoundManager._start_battle_music()
	var player: AudioStreamPlayer = SoundManager._music_player
	assert_not_null(player, "VOID: no music player, so no position to read")
	if player == null:
		return
	var pos: float = player.get_playback_position()
	var track: String = str(player.stream.resource_path).get_file() if player.stream else ""
	assert_ne(pos, STALE, "the battle bed opened at the stale %.1f s left by an abandoned area start" % STALE)
	## Its own blend is legitimate; anything near the stale offset is not.
	var allowed: float = maxf(_blend_of("battle_medieval"), _blend_of("battle_" + str(SoundManager._current_world_suffix)))
	assert_lt(pos, maxf(allowed, 0.0) + 1.0,
		"the battle bed (%s) opened at %.2f s, above its own loop blend of %.2f s — something is still parked" % [track, pos, allowed])


func test_a_real_resume_still_resumes() -> void:
	## The feature the parked position exists for. If the fix had simply stopped arming it, this is the
	## arm that would fail, and the leak test above would pass for the wrong reason.
	SoundManager.play_area_music("overworld", 9.0)
	SoundManager._start_area_music_deferred("overworld")
	var player: AudioStreamPlayer = SoundManager._music_player
	assert_not_null(player, "VOID: no music player")
	if player == null:
		return
	assert_almost_eq(player.get_playback_position(), 9.0, 0.6,
		"an explicit resume at 9.0 s did not take — the disarm removed the feature, not just the leak")


func test_the_disarm_clears_every_value_the_arm_sets() -> void:
	## Derived rather than listed: every `_pending_*` that play_area_music assigns must be cleared by
	## _invalidate_pending_area_start. A fourth parked value added later is covered without editing this.
	var src := FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")
	assert_gt(src.length(), 0, "VOID: SoundManager.gd read empty")
	var armed: Array = []
	var at: int = src.find("func play_area_music(")
	var end: int = src.find("\nfunc ", at + 1)
	var body: String = src.substr(at, end - at)
	for raw in body.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("_pending_") and line.contains(" = "):
			var name: String = line.split(" = ")[0].strip_edges()
			if not armed.has(name):
				armed.append(name)
	assert_gt(armed.size(), 2, "VOID: only %s derived as armed by play_area_music" % [armed])
	var dis_at: int = src.find("func _invalidate_pending_area_start(")
	var dis_end: int = src.find("\nfunc ", dis_at + 1)
	var disarm: String = src.substr(dis_at, dis_end - dis_at)
	var missed: Array = []
	for name in armed:
		if not disarm.contains(str(name) + " ="):
			missed.append(name)
	assert_eq(missed, [],
		"play_area_music arms %s but the disarm clears only some: %s is left parked for the next bed" % [armed, missed])
