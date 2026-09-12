extends GutTest

## Every worldN fragment reveal must sound and look like world N. W5 and W6 named the PREVIOUS world's bed and backdrop.

const CUTSCENE_DIR := "res://data/cutscenes"
const MUSIC_MANIFEST := "res://data/music_manifest.json"

## One backdrop per world, derived from what each world's non-fragment scenes actually use.
const WORLD_BACKDROP := {
	1: "cave_entrance",
	2: "suburban_neighborhood",
	3: "steampunk_workshop",
	5: "node_prime",
	6: "vertex_village",
}


func _fragment_scenes() -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(CUTSCENE_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.ends_with(".json") or not f.contains("_fragment_"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [CUTSCENE_DIR, f]))
		if parsed is Dictionary:
			out[f.replace(".json", "")] = parsed
	return out


func _world_of(scene_id: String) -> int:
	return int(scene_id.substr(5, 1)) if scene_id.begins_with("world") else 0


func _bed(scene: Dictionary) -> String:
	for step in scene.get("steps", []):
		if step is Dictionary and (step as Dictionary).get("type") == "play_music":
			return str((step as Dictionary).get("track", ""))
	return ""


func test_the_fragment_scan_finds_the_whole_set() -> void:
	var s := _fragment_scenes()
	assert_eq(s.size(), 20, "CONTROL: the fragment set is 4 archetypes x 5 worlds; found %d" % s.size())
	assert_true(s.has("world1_fragment_warden"), "CONTROL: a known fragment scene must be found")
	assert_false(s.has("world4_fragment_warden"),
		"there is no world4 fragment set — if one was authored, add 4 to WORLD_BACKDROP and this count")


func test_every_fragment_bed_belongs_to_its_own_world() -> void:
	var offenders: Array = []
	for id in _fragment_scenes():
		var w := _world_of(id)
		var bed := _bed(_fragment_scenes()[id])
		assert_ne(bed, "", "%s must name a music bed" % id)
		if not bed.begins_with("cutscene_w%d_" % w):
			offenders.append("%s (world %d) plays %s, expected a cutscene_w%d_* bed" % [id, w, bed, w])
	offenders.sort()
	assert_eq(offenders, [],
		("a fragment reveal must play its OWN world's bed. W1-W3 each did; W5 played "
		+ "cutscene_w4_foreman_confession and W6 played cutscene_w5_cached_memory — the previous world's, "
		+ "on both counts, with no world4 fragment set existing at all. That is a slide, not a scheme: if "
		+ "recalling the previous world were the design, W2 would use W1's bed and it does not. Offenders: %s") % str(offenders))


func test_every_fragment_backdrop_belongs_to_its_own_world() -> void:
	var offenders: Array = []
	for id in _fragment_scenes():
		var w := _world_of(id)
		var bg := str(_fragment_scenes()[id].get("background", ""))
		if bg != str(WORLD_BACKDROP.get(w, "")):
			offenders.append("%s (world %d) shows %s, expected %s" % [id, w, bg, str(WORLD_BACKDROP.get(w, ""))])
	offenders.sort()
	assert_eq(offenders, [],
		("the backdrop slid with the bed and is the half that is actually visible: W5's digital-perimeter "
		+ "fragments rendered industrial_factory (W4) and W6's abstract-threshold fragments rendered "
		+ "node_prime (W5). Both resolve to real assets, so this was on screen, not inert. Offenders: %s") % str(offenders))


func test_every_fragment_bed_resolves_in_the_music_manifest() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(MUSIC_MANIFEST))
	var tracks: Dictionary = {}
	if raw is Dictionary:
		tracks = (raw as Dictionary).get("tracks", raw)
	assert_gt(tracks.size(), 50, "CONTROL: the music manifest should hold many tracks, got %d" % tracks.size())
	var missing: Array = []
	for id in _fragment_scenes():
		var bed := _bed(_fragment_scenes()[id])
		if bed != "" and not tracks.has(bed):
			missing.append("%s -> %s" % [id, bed])
	assert_eq(missing, [],
		("a fragment bed names a track absent from the manifest, which plays as silence — add the track to "
		+ "data/music_manifest.json or correct the spelling in the scene's play_music step: %s") % str(missing))
