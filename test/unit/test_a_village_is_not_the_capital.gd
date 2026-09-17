extends GutTest

## Five World 1 villages played Castle Harmonia's signature bed.
##
## BaseVillage._get_music_area_id() returns "village" by default, and the dispatcher arm read
## `"village", "harmonia_village":` -- one arm for both -- routing the DEFAULT to
## _start_village_location_music("harmonia", "medieval"). Every village that never overrode the
## method therefore wore the capital's theme:
##
##     Eldertree · Frosthold · Grimhollow · Ironhaven · Sandrift  ->  village_harmonia.ogg
##
## 🔑 AND village_medieval.ogg IS AUTHORED -- 2.0 MB on disk, the per-world generic these villages
## exist for. It was unreachable from any village: the location lookup resolves village_harmonia
## first and only falls through to village_<world> when that file is MISSING.
##
## The dispatcher already carried a `"harmonia_village"` alias that nothing produced -- the split
## was anticipated and left unfinished. HarmoniaVillage now names its own bed (it already returned
## that id from _get_area_id), and the bare "village" default resolves to the world's generic.

const VILLAGE_DIR := "res://src/maps/villages/"


func before_each() -> void:
	SoundManager.stop_music()
	GameState.current_world = 1


func after_each() -> void:
	SoundManager.stop_music()
	GameState.current_world = 1


## The file the dispatcher actually loaded for an area key, or "" if it started nothing.
func _bed_for(area: String) -> String:
	SoundManager.stop_music()
	SoundManager._current_area = area
	SoundManager._pending_music_area = area
	SoundManager._start_area_music_deferred(area)
	var st = SoundManager._music_player.stream
	return st.resource_path if st else ""


func test_the_capital_keeps_its_signature_bed() -> void:
	## ⛔ THE DANGEROUS DIRECTION. The fix must not cost Harmonia the bed that is its own.
	var bed := _bed_for("harmonia_village")
	assert_true(bed.ends_with("village_harmonia.ogg"),
		"Castle Harmonia's town must still play its signature bed, got '%s'" % bed)


func test_a_generic_village_no_longer_wears_the_capitals_theme() -> void:
	var bed := _bed_for("village")
	assert_false(bed.ends_with("village_harmonia.ogg"),
		"the bare 'village' default still routes to the capital's signature bed")
	assert_true(bed.ends_with("village_medieval.ogg"),
		"a World 1 village must play the authored per-world bed, got '%s'" % bed)


func test_the_two_keys_no_longer_resolve_to_one_bed() -> void:
	## The bug was ONE arm serving both keys, so pin that they now differ.
	var generic := _bed_for("village")
	var capital := _bed_for("harmonia_village")
	assert_ne(generic, capital,
		"'village' and 'harmonia_village' resolve to the same file (%s) -- the shared arm is back" % generic)


func test_harmonia_asks_for_its_bed_by_name() -> void:
	## Without this override the capital falls to the generic default and loses its theme, so the
	## dispatcher fix alone is not enough -- the two changes only work as a pair.
	var src: String = FileAccess.get_file_as_string(VILLAGE_DIR + "HarmoniaVillage.gd")
	assert_true(src.contains("_get_music_area_id"),
		"HarmoniaVillage must name its own music area, or the capital gets the generic bed")


func test_every_village_without_an_override_reaches_a_real_bed() -> void:
	## DERIVED, not enumerated: whichever villages lack the override route through "village", and
	## that key must resolve to an authored file for the world they are in. A new village added
	## without an override is covered by construction rather than needing this list updated.
	var dir := DirAccess.open(VILLAGE_DIR)
	assert_not_null(dir, "CONTROL: the village directory must be readable")
	var defaulting: Array[String] = []
	for f in dir.get_files():
		if not f.ends_with(".gd") or f == "BaseVillage.gd":
			continue
		var src: String = FileAccess.get_file_as_string(VILLAGE_DIR + f)
		if not src.contains("_get_music_area_id"):
			defaulting.append(f)
	assert_gt(defaulting.size(), 0,
		"CONTROL: at least one village relies on the default, or this arm proves nothing")
	assert_false(defaulting.has("HarmoniaVillage.gd"),
		"HarmoniaVillage is back on the default and has lost its signature bed")
	var bed := _bed_for("village")
	assert_true(bed.ends_with(".ogg"),
		"the %d village(s) on the default (%s) reach '%s', which is not an authored file" % [defaulting.size(), ", ".join(defaulting), bed])
