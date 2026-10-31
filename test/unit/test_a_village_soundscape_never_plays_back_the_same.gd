extends GutTest

## The living village soundscape (struktured via cowir-main 20083): a bed plus one-shots rolled from
## data/ambient_recipes.json, swapping at night, holding while dialogue speaks, and never sounding like
## a loop. These arms drive AmbientSoundscape under a stub owner, so no real audio or bus is touched;
## the last two go through the real SoundManager for the place-keyed stop.

const RECIPES := "res://data/ambient_recipes.json"
const VILLAGES_DIR := "res://src/maps/villages/"
const STEP := 0.1


class StubOwner extends Node:
	var _sfx_manifest: Dictionary = {}
	var _music_base_db: float = -12.0
	const AMBIENT_OFFSET_DB := -16.0
	var _current_ambient_key: String = ""
	var ducked: bool = false
	var played_beds: Array = []
	var trims: Array = []

	func is_music_ducked_for_dialogue() -> bool:
		return ducked

	func play_ambient(key: String, trim_db: float = 0.0) -> void:
		played_beds.append(key)
		trims.append(trim_db)
		_current_ambient_key = key

	func stop_ambient() -> void:
		_current_ambient_key = ""


var _owner: StubOwner
var _scape: AmbientSoundscape


func before_each() -> void:
	_owner = StubOwner.new()
	add_child_autofree(_owner)
	_scape = AmbientSoundscape.new()
	_scape.audible = false
	_owner.add_child(_scape)


func after_each() -> void:
	SoundManager.stop_soundscape("harmonia_village")


func _run(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		_scape.advance(STEP)
		t += STEP


func _recipe_places() -> Dictionary:
	return AmbientSoundscape.load_recipes()


func test_the_recipe_loads_and_names_places() -> void:
	var places := _recipe_places()
	assert_gt(places.size(), 0, "VOID: %s yielded no places, so every arm below judges nothing" % RECIPES)
	assert_true(places.has("harmonia_village"), "the pilot names Harmonia")
	assert_true(places.has("eldertree_village"), "the pilot names Eldertree")


func test_every_recipe_key_resolves_to_a_shipped_file() -> void:
	SoundManager._load_sfx_manifest()
	var checked := 0
	var broken: Array[String] = []
	for place in _recipe_places():
		var phases: Dictionary = _recipe_places()[place].get("phases", {})
		for phase in phases:
			var layer: Dictionary = phases[phase]
			var keys: Array = [layer.get("bed", "")]
			for ev in layer.get("events", []):
				keys.append_array(ev.get("keys", []))
			for k in keys:
				checked += 1
				var path: String = str(SoundManager._sfx_manifest.get(k, {}).get("file", ""))
				if path == "" or not ResourceLoader.exists("res://" + path):
					broken.append("%s/%s: '%s'" % [place, phase, k])
	assert_gt(checked, 5, "VOID: walked %d keys" % checked)
	assert_eq(broken, [], "these recipe keys name no shipped sfx file, so the place plays silence there: %s" % [broken])


## The src-scanning ambient guards collect literal play_ambient args, so a bed named only in this data is invisible to them.
func _import_loop(key: String) -> String:
	var path: String = str(SoundManager._sfx_manifest.get(key, {}).get("file", ""))
	for line in FileAccess.get_file_as_string("res://" + path + ".import").split("\n"):
		if line.strip_edges().begins_with("loop="):
			return line.strip_edges().substr(5).to_lower()
	return "absent"


func test_a_bed_loops_and_an_event_does_not() -> void:
	SoundManager._load_sfx_manifest()
	var beds := 0
	var shots := 0
	var bad: Array[String] = []
	for place in _recipe_places():
		var phases: Dictionary = _recipe_places()[place].get("phases", {})
		for phase in phases:
			var bed: String = phases[phase].get("bed", "")
			if bed != "":
				beds += 1
				if not bool(SoundManager._sfx_manifest.get(bed, {}).get("loop", false)) or _import_loop(bed) != "true":
					bad.append("bed %s (%s/%s) does not loop: manifest loop=%s, .import loop=%s" % [bed, place, phase, SoundManager._sfx_manifest.get(bed, {}).get("loop"), _import_loop(bed)])
			for ev in phases[phase].get("events", []):
				for k in ev.get("keys", []):
					shots += 1
					if _import_loop(k) == "true":
						bad.append("event %s (%s/%s) LOOPS, so one roll would play it forever" % [k, place, phase])
	assert_gt(beds, 0, "VOID: no bed in any recipe")
	assert_gt(shots, 0, "VOID: no event in any recipe")
	assert_eq(bad, [], "%s" % [bad])


func test_every_range_is_playable() -> void:
	var bad: Array[String] = []
	for place in _recipe_places():
		var phases: Dictionary = _recipe_places()[place].get("phases", {})
		for phase in phases:
			for ev in phases[phase].get("events", []):
				var tag := "%s/%s %s" % [place, phase, ev.get("keys", [])]
				for field in ["every", "vol_db", "pan", "pitch"]:
					var r: Array = ev.get(field, [])
					if r.size() != 2 or float(r[0]) > float(r[1]):
						bad.append("%s %s=%s" % [tag, field, r])
				if float(ev.get("every", [0, 0])[0]) <= 0.0:
					bad.append("%s fires with no gap" % tag)
				var pan: Array = ev.get("pan", [0, 0])
				if float(pan[0]) < -1.0 or float(pan[1]) > 1.0:
					bad.append("%s pans outside [-1, 1]" % tag)
				if float(ev.get("pitch", [1, 1])[0]) <= 0.0:
					bad.append("%s has a non-positive pitch" % tag)
	assert_eq(bad, [], "unplayable recipe ranges: %s" % [bad])


func test_every_place_is_a_real_village_area() -> void:
	## A typo'd place id never plays and never errors, so derive the real ids from the villages' own source.
	var real := {}
	var re := RegEx.new()
	re.compile("func _get_area_id\\(\\)[^\\n]*\\n\\s*return \"([a-z0-9_]+)\"")
	for f in DirAccess.get_files_at(VILLAGES_DIR):
		if not f.ends_with(".gd"):
			continue
		var m := re.search(FileAccess.get_file_as_string(VILLAGES_DIR + f))
		if m != null:
			real[m.get_string(1)] = true
	assert_true(real.has("harmonia_village"), "VOID: the area-id derivation found no Harmonia, so it measures nothing (%s)" % [real.keys()])
	var orphans: Array[String] = []
	for place in _recipe_places():
		if not real.has(place):
			orphans.append(place)
	assert_eq(orphans, [], "these recipe places are no village's _get_area_id, so they can never play: %s" % [orphans])


func test_every_event_fires_inside_its_own_interval() -> void:
	_scape.seed_rng(1)
	assert_true(_scape.start("harmonia_village", "day"), "Harmonia has a recipe")
	var events: Array = AmbientSoundscape.layer_for(_recipe_places()["harmonia_village"], "day")["events"]
	var times := {}
	var t := 0.0
	while t < 900.0:
		var before := _scape.fired.size()
		_scape.advance(STEP)
		t += STEP
		for i in range(before, _scape.fired.size()):
			var k: String = _scape.fired[i]["key"]
			if not times.has(k):
				times[k] = []
			times[k].append(t)
	for ev in events:
		var k: String = ev["keys"][0]
		assert_true(times.has(k), "'%s' never fired in 900s" % k)
		if not times.has(k):
			continue
		var lo: float = ev["every"][0]
		var hi: float = ev["every"][1]
		assert_lte(times[k][0], hi + STEP, "'%s' first fired at %.1fs, after its longest interval %.1fs" % [k, times[k][0], hi])
		for j in range(1, times[k].size()):
			var gap: float = times[k][j] - times[k][j - 1]
			assert_between(gap, lo - STEP, hi + STEP, "'%s' fired %.1fs after itself, outside [%s, %s]" % [k, gap, lo, hi])


func test_it_never_plays_back_the_same() -> void:
	_scape.seed_rng(1)
	_scape.start("harmonia_village", "day")
	_run(300.0)
	var a: Array = _scape.fired.duplicate()
	_scape.stop()
	_scape.fired.clear()
	_scape.seed_rng(2)
	_scape.start("harmonia_village", "day")
	_run(300.0)
	var b: Array = _scape.fired
	assert_gt(a.size(), 20, "VOID: only %d events in 300s" % a.size())
	assert_ne(a, b, "two visits played the identical sequence, so the soundscape is a loop by another name")
	## Inside ONE visit: the anvil's level must vary, or a repeated sample reads as a loop anyway.
	var levels := {}
	for s in a:
		if s["key"] == "anvil_strike":
			levels[snappedf(s["volume_db"], 0.1)] = true
	assert_gt(levels.size(), 3, "anvil_strike played at only %d distinct levels" % levels.size())


func test_night_swaps_the_bed_and_the_events() -> void:
	_scape.seed_rng(3)
	_scape.start("harmonia_village", "day")
	assert_eq(_owner.played_beds.back(), "ambient_plains", "day starts the day bed")
	_scape.set_band("night")
	assert_eq(_owner.played_beds.back(), "night_crickets_wind", "night swaps in the night bed")
	_scape.fired.clear()
	_run(600.0)
	var night_keys := {}
	for ev in AmbientSoundscape.layer_for(_recipe_places()["harmonia_village"], "night")["events"]:
		for k in ev["keys"]:
			night_keys[k] = true
	var stray: Array[String] = []
	for s in _scape.fired:
		if not night_keys.has(s["key"]):
			stray.append(s["key"])
	assert_gt(_scape.fired.size(), 0, "VOID: nothing fired in 600s of night")
	assert_eq(stray, [], "day events kept playing after nightfall: %s" % [stray])


func test_dawn_reads_day_and_dusk_reads_night_unless_named() -> void:
	assert_eq(AmbientSoundscape.phase_for_band("dawn"), "day")
	assert_eq(AmbientSoundscape.phase_for_band("day"), "day")
	assert_eq(AmbientSoundscape.phase_for_band("dusk"), "night")
	assert_eq(AmbientSoundscape.phase_for_band("night"), "night")
	var named := {"phases": {"day": {"bed": "d"}, "night": {"bed": "n"}, "dusk": {"bed": "k"}}}
	assert_eq(AmbientSoundscape.layer_for(named, "dusk")["bed"], "k", "a recipe that names dusk gets its own layer")
	assert_eq(AmbientSoundscape.layer_for(named, "dawn")["bed"], "d", "dawn falls back to day")


func test_dialogue_holds_the_one_shots() -> void:
	_scape.seed_rng(4)
	_scape.start("harmonia_village", "day")
	_owner.ducked = true
	_run(120.0)
	assert_eq(_scape.fired.size(), 0, "events played over %d seconds of held dialogue" % 120)
	_owner.ducked = false
	_run(60.0)
	assert_gt(_scape.fired.size(), 0, "CONTROL: the soundscape never resumed once dialogue let go")


## Same precedence SoundManager.set_night_ambience had before the soundscape (night outranks rain); whether it should is his open call.
func test_night_takes_the_bed_from_weather_and_dawn_gives_it_back() -> void:
	_scape.seed_rng(5)
	_scape.start("harmonia_village", "day")
	_owner._current_ambient_key = "weather_rain"
	_scape.set_band("night")
	assert_eq(_owner._current_ambient_key, "night_crickets_wind", "nightfall must take the layer from the rain")
	_scape.set_band("dawn")
	assert_eq(_owner._current_ambient_key, "weather_rain", "dawn must hand back the rain that night displaced, not the day bed")


func test_weather_that_starts_at_night_survives_dawn() -> void:
	_scape.seed_rng(6)
	_scape.start("harmonia_village", "night")
	_owner._current_ambient_key = "weather_storm_bed"
	_scape.set_band("dawn")
	assert_eq(_owner._current_ambient_key, "weather_storm_bed", "dawn overwrote a storm that started after nightfall")


func test_a_clean_night_hands_back_the_day_bed() -> void:
	_scape.seed_rng(7)
	_scape.start("harmonia_village", "day")
	_scape.set_band("night")
	_scape.set_band("dawn")
	assert_eq(_owner._current_ambient_key, "ambient_plains", "dawn left the layer on the night bed, or silent")


func test_the_old_night_system_stands_aside_for_a_soundscape() -> void:
	## Two owners of one player raced at dawn: if the old system ran first it stopped the crickets and the soundscape saw silence.
	assert_true(SoundManager.start_soundscape("harmonia_village"), "Harmonia starts through SoundManager")
	SoundManager._soundscape.audible = false
	var bed: String = SoundManager._current_ambient_key
	SoundManager.set_night_ambience(true)
	assert_eq(SoundManager._current_ambient_key, bed, "the old night system took the layer from a place whose soundscape owns it")
	SoundManager.set_night_ambience(false)
	assert_eq(SoundManager._current_ambient_key, bed, "the old night system's dawn branch touched a soundscape's layer")


func test_a_late_exit_cannot_stop_the_next_place() -> void:
	assert_true(SoundManager.start_soundscape("harmonia_village"), "Harmonia starts through SoundManager")
	SoundManager._soundscape.audible = false
	SoundManager.stop_soundscape("eldertree_village")
	assert_eq(SoundManager.soundscape_place(), "harmonia_village", "another place's exit stopped Harmonia's soundscape")
	SoundManager.stop_soundscape("harmonia_village")
	assert_eq(SoundManager.soundscape_place(), "", "Harmonia's own exit stops it")


## test_sfx_volume_reaches_all_players' source scan skips this file the way it skips SoundManager.gd; THIS arm is that check, at runtime.
func test_the_music_slider_reaches_every_voice() -> void:
	var scape: AmbientSoundscape = SoundManager._soundscape
	scape.ensure_voices()
	var voices: Array = scape.voices()
	assert_eq(voices.size(), AmbientSoundscape.VOICE_COUNT, "VOID: the soundscape built %d voices" % voices.size())
	for v in voices:
		(v as AudioStreamPlayer).set_meta("offset_db", -6.0)
	SoundManager.set_music_volume(1.0)
	var loud := {}
	for v in voices:
		loud[v.name] = (v as AudioStreamPlayer).volume_db
	SoundManager.set_music_volume(0.0)
	var stuck: Array[String] = []
	for v in voices:
		var p: AudioStreamPlayer = v
		if p.volume_db >= loud[p.name]:
			stuck.append("%s held %.1f dB with the music slider at zero" % [p.name, p.volume_db])
	SoundManager.set_music_volume(1.0)
	assert_eq(stuck, [], "a soundscape voice no slider can turn down: %s" % [stuck])


## The level is derived, not stored: (music_lufs - target) - (bed_lufs + AMBIENT_OFFSET_DB), from the recipe's own measurements.
func _expected_trim(place: String, band: String) -> float:
	var rec: Dictionary = _recipe_places()[place]
	var layer: Dictionary = AmbientSoundscape.layer_for(rec, band)
	return (float(rec["music_lufs"]) - AmbientSoundscape.target_lu()) - (float(layer["bed_lufs"]) + StubOwner.AMBIENT_OFFSET_DB)


func test_every_place_carries_the_loudness_its_level_is_derived_from() -> void:
	var t := AmbientSoundscape.target_lu()
	assert_between(t, 12.0, 30.0, "target_lu_under_music %.1f is outside anything calibrated (rain accepted at 23.8 LU under, too loud at 15.8)" % t)
	var bad: Array[String] = []
	for place in _recipe_places():
		var rec: Dictionary = _recipe_places()[place]
		if not rec.has("music_lufs") or float(rec["music_lufs"]) > -5.0 or float(rec["music_lufs"]) < -40.0:
			bad.append("%s music_lufs=%s" % [place, rec.get("music_lufs")])
		## music_key names the track music_lufs was measured on, so the pre-gate can re-measure it (cowir-music's check).
		if not SoundManager.has_music_track(str(rec.get("music_key", ""))):
			bad.append("%s music_key='%s' is no track in music_manifest" % [place, rec.get("music_key", "")])
		for phase in rec.get("phases", {}):
			var layer: Dictionary = rec["phases"][phase]
			if str(layer.get("bed", "")) != "" and (not layer.has("bed_lufs") or float(layer["bed_lufs"]) > -5.0 or float(layer["bed_lufs"]) < -50.0):
				bad.append("%s/%s bed_lufs=%s" % [place, phase, layer.get("bed_lufs")])
	assert_eq(bad, [], "a bed's level is derived from these measurements, so a missing or implausible one sets it wrong: %s" % [bad])


## The engine can see the place -> track link; a Python pre-gate could only re-implement it (cowir-music 2026-10-31).
func test_each_place_names_the_track_it_really_plays() -> void:
	var world_restore: int = GameState.current_world
	GameState.current_world = 1
	var checked := 0
	var wrong: Array[String] = []
	for place in _recipe_places():
		var script_path := ""
		for f in DirAccess.get_files_at(VILLAGES_DIR):
			if f.ends_with(".gd") and FileAccess.get_file_as_string(VILLAGES_DIR + f).contains("return \"%s\"" % place):
				script_path = VILLAGES_DIR + f
		if script_path == "":
			wrong.append("%s: no village script returns this area id" % place)
			continue
		var village: Node = load(script_path).new()
		var area: String = village.call("_get_music_area_id")
		village.free()
		SoundManager.play_area_music(area)
		await get_tree().process_frame
		await get_tree().process_frame
		var want: String = str(SoundManager._music_manifest.get(str(_recipe_places()[place].get("music_key", "")), {}).get("file", "")).get_file().get_basename()
		var got: String = SoundManager.playing_track_stem()
		checked += 1
		if got != want:
			wrong.append("%s (music area '%s') plays '%s', but the recipe's music_key resolves to '%s'" % [place, area, got, want])
	SoundManager.stop_music()
	GameState.current_world = world_restore
	assert_gt(checked, 1, "VOID: checked %d places" % checked)
	assert_eq(wrong, [], "music_lufs was measured on the wrong track, so the bed's level is derived from the wrong number: %s" % [wrong])


func test_a_bed_sits_its_target_under_the_music() -> void:
	_scape.seed_rng(8)
	_scape.start("harmonia_village", "day")
	assert_almost_eq(float(_owner.trims.back()), _expected_trim("harmonia_village", "day"), 0.01, "the day bed was not trimmed to sit target_lu() under the music")
	assert_gt(float(_owner.trims.back()), 0.0, "CONTROL: ambient_plains is a quiet file, so reaching the target must RAISE it")
	_scape.set_band("night")
	assert_almost_eq(float(_owner.trims.back()), _expected_trim("harmonia_village", "night"), 0.01, "the night bed kept the day bed's trim instead of its own")


func test_weather_handed_back_gets_no_trim() -> void:
	_scape.seed_rng(9)
	_scape.start("harmonia_village", "day")
	_owner._current_ambient_key = "weather_rain"
	_scape.set_band("night")
	_scape.set_band("dawn")
	assert_eq(_owner._current_ambient_key, "weather_rain", "precondition: dawn handed the rain back")
	assert_eq(float(_owner.trims.back()), 0.0, "the rain came back carrying a soundscape bed's trim, louder than his 09-07 ruling allows")


func test_events_ride_the_bed_trim() -> void:
	_scape.start("harmonia_village", "day")
	assert_almost_eq(_scape.base_db(), _owner._music_base_db + StubOwner.AMBIENT_OFFSET_DB + _expected_trim("harmonia_village", "day"), 0.01,
		"events are authored relative to the bed, so a bed raised by its trim without them leaves them that much quieter")


func test_todays_take_is_untrimmed() -> void:
	_scape.trim_enabled = false
	_scape.start("harmonia_village", "day")
	assert_eq(float(_owner.trims.back()), 0.0, "the 'today' A/B take must be the old untrimmed level, or the comparison is not with today")


func test_a_soundscape_bed_ducks_for_dialogue_and_hands_the_bus_back() -> void:
	assert_eq(SoundManager._ambient_player.bus, &"Master", "precondition: the ambient player boots on Master")
	assert_true(SoundManager.start_soundscape("harmonia_village"), "Harmonia starts through SoundManager")
	SoundManager._soundscape.audible = false
	assert_eq(str(SoundManager._ambient_player.bus), SoundManager.MUSIC_DUCK_BUS, "a soundscape bed must sit under the dialogue duck (cowir-music 2026-10-31)")
	SoundManager.stop_soundscape("harmonia_village")
	assert_eq(SoundManager._ambient_player.bus, &"Master", "leaving the place must hand the bus back, or rain in the next zone ducks too")


func test_a_place_without_a_recipe_keeps_the_old_loop() -> void:
	assert_false(SoundManager.start_soundscape("brasston_village"), "a place with no recipe must report false so BaseVillage falls back")
	assert_eq(SoundManager.soundscape_place(), "", "a refused start must not claim the place")
