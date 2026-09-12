extends GutTest

const TRIPLE := '"""'

## A map whose area id has no arm in `_get_current_world_suffix` keeps the PREVIOUS
## world's suffix, and every derived bed follows it.
##
## The `_:` arm returns `_current_world_suffix` — deliberately, so battle music stays
## world-aware while `_current_area` is cleared mid-fight. The cost is that the cache
## has exactly ONE writer (`play_area_music:4914`) and that writer calls this same
## function: entering an area with no arm does not update the suffix, it PRESERVES
## whatever the last arm-matching area left there.
##
## ⛔ Scriptura Plaza is that map. `ScripturaPlaza._get_music_area_id` returns
## `scriptura_village`, which has an arm in the AREA dispatch (`SoundManager:4948`
## hardcodes "medieval" there, so the village bed is right) and NO arm here. It reads
## as covered because one of the two maps names it.
##
## Reachable through a shipped menu, not a hypothetical: TeleportMenu lists Scriptura
## Plaza under "Scriptura (W1)" and warps there from anywhere, and neither it nor
## FastTravelMenu touches the suffix. Arrive from World 4 and the plaza plays its own
## authored bed while a battle there resolves `battle_industrial`.
##
## 🔑 THE CORPUS IS DERIVED, which is the point of this file. The pre-existing guard
## (test_sound_world_suffix_canonical_map_ids_regression) checks a HAND-LIST of ids
## against the arms — so it agrees with itself and cannot see a map that was added
## without an arm, which is the only way this defect arrives. This one quantifies over
## every `_get_music_area_id()` in src/, so the next Scriptura reds on the commit that
## adds it.
##
## Interiors and `danger` are absent from that corpus by construction and want no arm:
## an interior inherits its village's bed, and a danger sting happens in the world you
## are already standing in. Both correctly keep the cached suffix.

const SM_PATH := "res://src/audio/SoundManager.gd"
const MAP_DIRS: Array[String] = ["res://src/maps", "res://src/exploration"]


func _sm_suffix_fn() -> String:
	var s: String = FileAccess.get_file_as_string(SM_PATH)
	assert_gt(s.length(), 10000, "SCOPE control: SoundManager.gd read back %d chars" % s.length())
	var start: int = s.find("func _get_current_world_suffix")
	assert_gt(start, 0, "CONTROL FAILED: _get_current_world_suffix is gone — this guard measures nothing")
	var end: int = s.find("\nfunc ", start + 10)
	assert_gt(end, start, "CONTROL FAILED: could not bound the function body")
	return _code_only(s.substr(start, end - start))


func _area_ids() -> Dictionary:
	## id -> the script that returns it.
	var out: Dictionary = {}
	for root in MAP_DIRS:
		for path in _gd_files(root):
			var txt: String = FileAccess.get_file_as_string(path)
			var at: int = txt.find("func _get_music_area_id")
			if at < 0:
				continue
			var ret: int = txt.find("return \"", at)
			if ret < 0 or ret - at > 400:
				continue
			var q: int = ret + 8
			var close: int = txt.find("\"", q)
			if close > q:
				out[txt.substr(q, close - q)] = path.get_file()
	return out


func _gd_files(root: String) -> Array[String]:
	var found: Array[String] = []
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var full: String = root + "/" + name
		if dir.current_is_dir():
			found.append_array(_gd_files(full))
		elif name.ends_with(".gd"):
			found.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return found


func test_control_the_derived_corpus_is_populated() -> void:
	## A zero-size corpus passes the arm below having read nothing — the failure mode
	## of every derived guard, and the one a hand-list cannot have.
	var ids: Dictionary = _area_ids()
	assert_gt(ids.size(), 10,
		"CONTROL FAILED: derived only %d area ids from %s — the scan is broken, not the code" % [ids.size(), MAP_DIRS])
	assert_true(ids.has("village"),
		"CONTROL FAILED: BaseVillage's own 'village' id is missing, so the scan is not reaching the base classes")


func test_every_map_area_id_has_an_arm() -> void:
	var fn: String = _sm_suffix_fn()
	var ids: Dictionary = _area_ids()
	var orphans: Array[String] = []
	for id in ids.keys():
		if not fn.contains("\"%s\"" % str(id)):
			orphans.append("%s (returned by %s)" % [str(id), str(ids[id])])
	assert_eq(orphans.size(), 0,
		"%d map area id(s) reach no arm in _get_current_world_suffix, so entering them keeps the PREVIOUS world's suffix and every derived bed — battle, boss, danger, victory — follows it: %s" % [orphans.size(), orphans])


func test_entering_a_world_one_village_does_not_keep_world_four_music() -> void:
	## The defect as a player meets it: fast-travel from W4 into Scriptura.
	SoundManager.play_area_music("industrial_dungeon")
	assert_eq(SoundManager._current_world_suffix, "industrial",
		"PREMISE FAILED: the W4 leg did not set the suffix, so the arm below cannot show it going stale")

	SoundManager.play_area_music("scriptura_village")
	assert_eq(SoundManager._current_world_suffix, "medieval",
		"Scriptura is a World 1 village but the suffix is still '%s', so a battle there plays World 4's bed" % SoundManager._current_world_suffix)


func test_control_an_arm_bearing_area_does_update_the_suffix() -> void:
	## Without this, the arm above could pass on a build where the suffix never changes
	## at all — which would look like the fix and be a different bug.
	SoundManager.play_area_music("industrial_dungeon")
	assert_eq(SoundManager._current_world_suffix, "industrial", "the W4 leg itself is broken")
	SoundManager.play_area_music("steampunk_dungeon")
	assert_eq(SoundManager._current_world_suffix, "steampunk",
		"an area WITH an arm did not update the suffix — the cache has stopped being written at all")


## Comment-strip that also drops """ blocks. GDScript docstrings are string
## LITERALS, so a #-only strip leaves them and prose quoting an arm reads AS the
## arm. Measured 2026-09-12: planting "scriptura_village" in the resolver's own
## docstring hid a DELETED arm from the scans here — the source assert fired 0
## times with it and 2 times without, and only a behavioural arm caught it.
##
## Drops the WHOLE line on a triple quote, which can also drop code sharing that
## line. That errs toward reporting an arm MISSING (a loud red) rather than
## present (a silent green), which is the direction a guard should fail in.
static func _code_only(body: String) -> String:
	var out: PackedStringArray = []
	var in_doc: bool = false
	for raw in body.split("\n"):
		if in_doc:
			if raw.contains(TRIPLE):
				in_doc = false
			continue
		var q: int = raw.find(TRIPLE)
		if q >= 0:
			if raw.find(TRIPLE, q + 3) < 0:
				in_doc = true
			continue
		out.append(raw.split("#")[0])
	return "\n".join(out)
