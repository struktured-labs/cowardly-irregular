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

	func is_music_ducked_for_dialogue() -> bool:
		return ducked

	func play_ambient(key: String) -> void:
		played_beds.append(key)
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


func test_a_band_change_leaves_weather_on_the_bed() -> void:
	_scape.seed_rng(5)
	_scape.start("harmonia_village", "day")
	_owner._current_ambient_key = "weather_rain"
	var n := _owner.played_beds.size()
	_scape.set_band("night")
	assert_eq(_owner.played_beds.size(), n, "nightfall replaced the rain with the village's night bed")
	assert_eq(_scape.bed_key(), "night_crickets_wind", "the layer still moved to night, ready for the rain to clear")


func test_a_late_exit_cannot_stop_the_next_place() -> void:
	assert_true(SoundManager.start_soundscape("harmonia_village"), "Harmonia starts through SoundManager")
	SoundManager._soundscape.audible = false
	SoundManager.stop_soundscape("eldertree_village")
	assert_eq(SoundManager.soundscape_place(), "harmonia_village", "another place's exit stopped Harmonia's soundscape")
	SoundManager.stop_soundscape("harmonia_village")
	assert_eq(SoundManager.soundscape_place(), "", "Harmonia's own exit stops it")


func test_a_place_without_a_recipe_keeps_the_old_loop() -> void:
	assert_false(SoundManager.start_soundscape("brasston_village"), "a place with no recipe must report false so BaseVillage falls back")
	assert_eq(SoundManager.soundscape_place(), "", "a refused start must not claim the place")
