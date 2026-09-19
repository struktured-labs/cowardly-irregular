extends GutTest

## ⚠️ LATENT TODAY — 0 reachable. `night_crickets_wind` is in the sfx manifest with a file on disk,
## and `play_ambient` resolves music-first then sfx, so none of its four failure returns can fire for
## this key in the shipped data. This guard exists because the ambient layer has broken THIS EXACT
## WAY TWICE (village bed -> night -> dawn, and rain -> night -> day, both 2026-09-18) and the repair
## keyed the restore on night being the CURRENT bed.
##
## The hole that leaves: `play_ambient` calls `stop_ambient()` BEFORE any of its failure returns, so a
## night that cannot start has already stopped the old bed. `_current_ambient_key` is then "", the
## dawn branch tests `== NIGHT_AMBIENCE_KEY` and never fires, and `_pre_night_ambient_key` is
## discarded. The layer stays silent until a zone crossing, a weather change or a scene rebuild.

var _saved_file = null


func after_each() -> void:
	## ⛔ RESTORED HERE, NOT INLINE. The arm mutates the SHARED autoload's cached manifest; an abort
	## between the break and an inline restore strands night_crickets_wind as unplayable for every
	## later test in the process.
	if SoundManager != null and _saved_file != null:
		var e = SoundManager._sfx_manifest.get(SoundManager.NIGHT_AMBIENCE_KEY, null)
		if e is Dictionary:
			(e as Dictionary)["file"] = _saved_file
	_saved_file = null
	if SoundManager != null:
		SoundManager.stop_ambient()
		SoundManager._pre_night_ambient_key = ""


func test_a_night_that_cannot_start_does_not_keep_the_previous_bed() -> void:
	if SoundManager == null:
		assert_true(false, "SoundManager autoload unavailable — this arm would prove nothing")
		return
	SoundManager._load_sfx_manifest()
	SoundManager._load_music_manifest()
	var night = SoundManager._sfx_manifest.get(SoundManager.NIGHT_AMBIENCE_KEY, null)
	assert_true(night is Dictionary,
		"SCOPE control: %s is not in the sfx manifest, so this arm drives nothing" % SoundManager.NIGHT_AMBIENCE_KEY)
	if not (night is Dictionary):
		return

	## A village bed owns the layer first. Derived, not hardcoded: any ambient key that really plays.
	var bed: String = ""
	for k in ["ambient_village", "ambient_forest", "ambient_cave"]:
		SoundManager.play_ambient(k)
		if SoundManager._current_ambient_key == k:
			bed = k
			break
	assert_ne(bed, "",
		"SCOPE control: no ambient bed would play, so there is nothing for night to take and hand back")
	if bed == "":
		return

	## Break night the way a retired asset or a bad manifest edit would: an entry with no `file`.
	## That is play_ambient's SECOND failure return, reached after it has already stopped the bed.
	_saved_file = (night as Dictionary).get("file", "")
	(night as Dictionary)["file"] = ""

	SoundManager.set_night_ambience(true)
	assert_ne(SoundManager._current_ambient_key, SoundManager.NIGHT_AMBIENCE_KEY,
		"SCOPE control: night started anyway, so the failure path was never taken and the assert below is about nothing")
	assert_eq(SoundManager._current_ambient_key, bed,
		"night could not start, and it left the layer SILENT holding nothing — the old bed was stopped before the failure return, and the dawn branch keys on night being current so it never hands it back. The layer stays quiet until a zone crossing")
	assert_true(SoundManager._ambient_player.playing,
		"the ambient player is not playing: the key was restored without the stream, which is the same silence with a tidier field")


## The path that already worked must keep working — otherwise the fix above could 'pass' by never
## letting night take the layer at all.
func test_a_night_that_does_start_still_restores_at_dawn() -> void:
	if SoundManager == null:
		assert_true(false, "SoundManager autoload unavailable")
		return
	SoundManager._load_sfx_manifest()
	SoundManager.play_ambient("ambient_village")
	var bed: String = str(SoundManager._current_ambient_key)
	assert_eq(bed, "ambient_village", "SCOPE control: the village bed did not start")
	SoundManager.set_night_ambience(true)
	assert_eq(SoundManager._current_ambient_key, SoundManager.NIGHT_AMBIENCE_KEY,
		"SCOPE control: night did not take the layer, so the restore below is about nothing")
	SoundManager.set_night_ambience(false)
	assert_eq(SoundManager._current_ambient_key, bed,
		"dawn did not hand the layer back to the bed night interrupted — the 2026-09-18 defect verbatim")
