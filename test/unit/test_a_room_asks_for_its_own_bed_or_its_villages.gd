extends GutTest

## ⛔ THE POPULATION BEHIND `test_the_forge_keeps_the_capitals_bed`, DERIVED RATHER THAN LISTED.
## That file names ONE room. The rule it found is general: an interior's music id may name ITSELF
## (`interior_*`, which takes play_area_music's inherit path when unauthored and leaves the bed
## alone) or the PLACE IT IS ENTERED FROM (which hits the already-playing return). A third place's
## AREA id restarts the music on every entry and exit — BlacksmithInterior asked for `"village"`
## inside Harmonia and played village_medieval.ogg over village_harmonia.ogg for as long as that
## door has existed.
##
## 🔑 WHY A POPULATION ARM AND NOT A LIST: the forge was invisible precisely because its siblings are
## right, so the next one will be invisible the same way. @cowir-sfx's shape — a claim about a
## population published over a predicate that names members.
##
## ⛔ AND THE CORPUS IS "FILES THAT REQUEST AN AREA BED", NOT "FILES IN THE INTERIORS DIRECTORY".
## My first version took the directory and red on four files: `InteriorPlacementSweep` is a utility
## that requests nothing, and Inn/Shop/Tavern are not BaseInterior subclasses at all — they own their
## `_ready` and call play_area_music("interior_inn"/"interior_shop"/"interior_tavern") directly. Three
## request shapes, one question. Deriving the REQUEST rather than the file type is what makes the
## floors below land on the cases that can actually be wrong.

const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const INTERIOR_DIR := "res://src/maps/interiors"
const OWNER_DIRS: Array = ["res://src/maps/villages", "res://src/exploration", "res://src/maps/dungeons"]
const BASE_VILLAGE := "res://src/maps/villages/BaseVillage.gd"
const BASE_INTERIOR := "res://src/maps/interiors/BaseInterior.gd"


func _code(path: String) -> String:
	return FileAccess.get_file_as_string(path)


## First string literal returned by `fname`, following a single const indirection.
func _first_return(code: String, fname: String) -> String:
	var i: int = code.find("func %s(" % fname)
	if i < 0:
		return ""
	var seg: String = code.substr(i, 700)
	var m := RegEx.create_from_string('return\\s+"([^"]+)"').search(seg)
	if m != null:
		return m.get_string(1)
	var ms := RegEx.create_from_string('return\\s+([A-Z_][A-Z0-9_]*)').search(seg)
	if ms == null:
		return ""
	var cm := RegEx.create_from_string('const\\s+%s[^=\\n]*=\\s*"([^"]+)"' % ms.get_string(1)).search(code)
	return cm.get_string(1) if cm != null else ""


func _gd_files(dir: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	return out


## Every area id this file asks play_area_music for on entry, by all three shapes.
func _requested_ids(code: String, base_interior_track: String) -> Array:
	var ids: Array = []
	for m in RegEx.create_from_string('play_area_music\\(\\s*"([^"]+)"').search_all(code):
		if not ids.has(m.get_string(1)):
			ids.append(m.get_string(1))
	if not ids.is_empty():
		return ids
	if code.find("func _get_music_track(") >= 0:
		return [_first_return(code, "_get_music_track")]
	if code.find("extends BaseInterior") >= 0:
		return [base_interior_track]
	return []


func test_a_room_asks_for_its_own_bed_or_its_villages() -> void:
	var base_village_area: String = _first_return(_code(BASE_VILLAGE), "_get_music_area_id")
	var base_interior_track: String = _first_return(_code(BASE_INTERIOR), "_get_music_track")
	assert_ne(base_village_area, "",
		"FLOOR: BaseVillage must still declare _get_music_area_id — every village that does not override it inherits this answer")
	assert_ne(base_interior_track, "",
		"FLOOR: BaseInterior must still declare _get_music_track — every room that does not override it inherits this answer")

	## map id -> [[owner file, owner's area id], ...]
	var doors: Dictionary = {}
	var target := RegEx.create_from_string('target_map\\s*=\\s*"([^"]+)"')
	var helper := RegEx.create_from_string('_add_interior_door\\(\\s*"[^"]*"\\s*,\\s*"([^"]+)"')
	for dir in OWNER_DIRS:
		for path in _gd_files(dir):
			var code: String = _code(path)
			var aid: String = _first_return(code, "_get_music_area_id")
			if aid == "" and dir.ends_with("villages"):
				aid = base_village_area
			for arr in [target.search_all(code), helper.search_all(code)]:
				for m in arr:
					var t: String = m.get_string(1)
					if not doors.has(t):
						doors[t] = []
					doors[t].append([path.get_file(), aid])

	var requesters: int = 0
	var self_named: int = 0
	var checked_against_a_door: int = 0
	for path in _gd_files(INTERIOR_DIR):
		## The abstract base is not a room: it declares the default the others inherit, has no door
		## because no player enters it, and its own literal is floored above. Named, not a blanket
		## "skip anything without a door" — that would silence exactly the case this arm is for.
		if path == BASE_INTERIOR:
			continue
		var code: String = _code(path)
		## ⛔ PER-FILE, INSIDE THE LOOP. A file that reads empty would otherwise contribute nothing and
		## read exactly like a room that was checked and passed — @cowir-ai's point that a floor's
		## indentation is the whole difference between per-source and aggregate.
		assert_gt(code.length(), 200, "FLOOR: %s must read as source, not an empty string" % path.get_file())
		var asks: Array = _requested_ids(code, base_interior_track)
		if asks.is_empty():
			continue
		requesters += 1
		for id in asks:
			assert_ne(str(id), "",
				"FLOOR: %s declares _get_music_track with no string literal — it would fall through to the base default and be judged on an id it never asks for" % path.get_file())
			if str(id).begins_with("interior_"):
				self_named += 1
				continue
			## Not self-named, so the claim needs the door — and a room in this branch with no
			## derivable door is the case that matters, not one to skip.
			var area_id: String = _first_return(code, "_get_area_id")
			assert_ne(area_id, "",
				"FLOOR: %s asks for the non-room id '%s' and declares no literal _get_area_id, so this census cannot tell which place it is entered from" % [path.get_file(), id])
			assert_true(doors.has(area_id),
				"FLOOR: %s asks for the non-room id '%s' and no door into '%s' was found — the door forms this census knows (target_map, _add_interior_door) have changed" % [path.get_file(), id, area_id])
			for d in doors[area_id]:
				checked_against_a_door += 1
				assert_true(str(id) == str(d[1]),
					"%s asks for '%s', which is neither an interior_ key nor %s's own '%s' — a third place's area id restarts the bed on every entry and exit" % [path.get_file(), id, str(d[0]), str(d[1])])

	## Aggregate anti-vacuity, ON TOP of the per-file floors rather than instead of them: these catch a
	## total corpus failure (a renamed accessor, an empty directory) and are structurally unable to see
	## one room go dark. Both are needed and they answer different questions.
	assert_gt(requesters, 20, "FLOOR: only %d rooms request an area bed at all" % requesters)
	## ⚠️ WAS `> 5`, AND IT FIRED ON A DELIBERATE CHANGE RATHER THAN ON DRIFT — which is the floor doing
	## its job. Ten single-village rooms moved from a room key to their village id on 2026-09-18,
	## because an unauthored room key is correct only when WALKED INTO (see the arrival-mode arm
	## below). The three that remain are Inn, Shop and the tavern. Inn and Shop are reused and have no
	## single owning village; the tavern is Harmonia-only but still asks for interior_tavern so a
	## walk-in inherits. A room key stays the right request, and the branch stays live.
	assert_gt(self_named, 2, "FLOOR: only %d self-named (interior_) requests — the interior_ branch this arm accepts is no longer exercised by anything" % self_named)
	assert_gt(checked_against_a_door, 10, "FLOOR: only %d requests were judged against a real door" % checked_against_a_door)


## ⛔ THE SAME ROOM MUST NOT HAVE TWO BEDS. Measured 2026-09-18 across the nine unauthored rooms:
##
##   walked in from the village   village_harmonia.ogg     (the interior_ key INHERITS)
##   loaded into from a save      village_medieval.ogg     (cold start has nothing to inherit, and
##                                                          _start_interior_music falls back BY WORLD)
##
## 🔑 REACHABLE WITH F2: quick-save works everywhere except the title and a cutscene, so a save taken
## inside a room and loaded back plays a different bed than walking through the door does.
##
## ⚠️ THIS ARM DELIBERATELY DOES NOT LEGISLATE THE CONVENTION. Naming the village fixes it because the
## village id is right in both modes; authoring the room's own bed fixes it too. The claim is the
## RELATIONSHIP — a coincidental pin on either spelling would red the other correct answer, which is
## exactly what the arm above already avoids.
##
## Inn and Shop are reused and have no single owning village, so the world-level fallback is the
## best answer available to them. The Dancing Tonberry is Harmonia-only; its door is an emit, so
## this derivation skips it too — the cold start is pinned in test_tavern_save_keeps_harmonia_theme.
func test_a_room_sounds_the_same_however_you_arrived() -> void:
	var base_village_area: String = _first_return(_code(BASE_VILLAGE), "_get_music_area_id")
	var base_interior_track: String = _first_return(_code(BASE_INTERIOR), "_get_music_track")
	var doors: Dictionary = {}
	var target := RegEx.create_from_string('target_map\\s*=\\s*"([^"]+)"')
	var helper := RegEx.create_from_string('_add_interior_door\\(\\s*"[^"]*"\\s*,\\s*"([^"]+)"')
	for dir in OWNER_DIRS:
		for path in _gd_files(dir):
			var code: String = _code(path)
			var aid: String = _first_return(code, "_get_music_area_id")
			if aid == "" and dir.ends_with("villages"):
				aid = base_village_area
			for arr in [target.search_all(code), helper.search_all(code)]:
				for m in arr:
					var t: String = m.get_string(1)
					if not doors.has(t):
						doors[t] = []
					doors[t].append(aid)

	var area_suffix: Dictionary = _area_world_suffix()
	assert_gt(area_suffix.size(), 20,
		"FLOOR: only %d area->suffix pairs read from the resolver — the arm cannot put GameState in the right world" % area_suffix.size())
	var world_for: Dictionary = {}
	for w in WeatherSystem.WORLD_IDS.keys():
		world_for[str(WeatherSystem.WORLD_IDS[w])] = int(w)
	var saved_world: int = int(GameState.current_world)

	var checked: int = 0
	for path in _gd_files(INTERIOR_DIR):
		if path == BASE_INTERIOR:
			continue
		var code: String = _code(path)
		var area_id: String = _first_return(code, "_get_area_id")
		var asks: Array = _requested_ids(code, base_interior_track)
		if area_id == "" or asks.size() != 1 or not doors.has(area_id) or doors[area_id].size() != 1:
			continue
		var village: String = str(doors[area_id][0])
		if village == "":
			continue

		SoundState.restore()
		GameState.current_world = world_for.get(str(area_suffix.get(village, "medieval")), 1)
		SoundManager.play_area_music(village)
		await get_tree().process_frame
		await get_tree().process_frame
		assert_not_null(SoundManager._music_player.stream,
			"FLOOR: %s's village '%s' loaded no bed, so both sides of this comparison are empty" % [path.get_file(), village])
		SoundManager.play_area_music(str(asks[0]))
		await get_tree().process_frame
		await get_tree().process_frame
		var walked: String = SoundManager._music_player.stream.resource_path.get_file() if SoundManager._music_player.stream else "<walked:none>"

		## ⛔ DRIVEN THE WAY BaseInterior._ready DRIVES IT, third argument included. An arm that calls
		## play_area_music with one argument is not simulating a cold start, it is simulating a caller
		## that does not exist. No floor on the home area: a room whose village answers to the generic
		## `village` id already agrees in both modes and needs none, so demanding one everywhere would
		## red nine correct rooms. The comparison is the claim.
		var home: String = _first_return(code, "_get_music_home_area")
		SoundState.restore()
		GameState.current_world = world_for.get(str(area_suffix.get(village, "medieval")), 1)
		SoundManager.play_area_music(str(asks[0]), 0.0, home)
		await get_tree().process_frame
		await get_tree().process_frame
		var cold: String = SoundManager._music_player.stream.resource_path.get_file() if SoundManager._music_player.stream else "<cold:none>"

		checked += 1
		assert_eq(cold, walked,
			"%s asks for '%s': walking in from %s gives %s, loading a save inside it gives %s — the same room with two beds, and which one you hear depends on how you got there" % [path.get_file(), str(asks[0]), village, walked, cold])

	GameState.current_world = saved_world
	assert_gt(checked, 8,
		"FLOOR: only %d single-village rooms were driven — the door derivation or the request derivation has narrowed" % checked)


## Village AREA id -> world suffix, read from _get_current_world_suffix's own `match _current_area:`.
## The arm below must put GameState in the world the village is in, the way walking there does —
## without it `_interior_world_suffix()` answers from a stale `current_world` and the two arrival
## modes are compared under different worlds. My first version of the arm did exactly that and
## reported a room as inconsistent when the fixture was.
func _area_world_suffix() -> Dictionary:
	var code: String = _code("res://src/audio/SoundManager.gd")
	var i: int = code.find("\tmatch _current_area:")
	var out: Dictionary = {}
	if i < 0:
		return out
	var pending: Array = []
	for line in code.substr(i, 1800).split("\n"):
		var t: String = line.strip_edges()
		if t.begins_with("\"") and t.ends_with(":"):
			pending = []
			for m in RegEx.create_from_string('"([^"]+)"').search_all(t):
				pending.append(m.get_string(1))
		elif t.begins_with("return \"") and not pending.is_empty():
			var suf: String = t.substr(8, t.length() - 9)
			for a in pending:
				out[a] = suf
			pending = []
		elif t.begins_with("_:"):
			break
	return out


## ⛔ THE WIRING, BECAUSE THE BEHAVIOURAL ARM ABOVE CANNOT SEE IT. That arm reproduces BaseInterior's
## call by hand — so deleting the third argument FROM BaseInterior leaves it green, measured. Driving
## the real `_ready` is not an option: it builds a tilemap, NPCs, transitions and a camera.
##
## A source pin, deliberately, and the same choice `test_interior_music_routing` already makes for the
## standalone rooms' direct calls. Anchored on the two SYMBOLS rather than on a rendering of the line,
## so reformatting cannot red it and a renamed accessor can.
func test_base_interior_hands_the_room_its_village() -> void:
	var code: String = _code(BASE_INTERIOR)
	assert_gt(code.length(), 200, "FLOOR: BaseInterior.gd must read as source")
	var i: int = code.find("play_area_music(")
	assert_gt(i, -1, "FLOOR: BaseInterior must still call play_area_music at all")
	var call: String = code.substr(i, 120)
	assert_true(call.contains("_get_music_home_area()"),
		"BaseInterior calls play_area_music without the room's village: %s — every unauthored room then cold-starts by WORLD again, and the behavioural arm above cannot see it because it passes the argument itself" % call.get_slice("\n", 0))
