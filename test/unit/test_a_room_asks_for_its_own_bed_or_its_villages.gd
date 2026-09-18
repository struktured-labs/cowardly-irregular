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
	assert_gt(self_named, 5, "FLOOR: only %d self-named (interior_) requests — the convention this arm rests on has moved" % self_named)
	assert_gt(checked_against_a_door, 10, "FLOOR: only %d requests were judged against a real door" % checked_against_a_door)
