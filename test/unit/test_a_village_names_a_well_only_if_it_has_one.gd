extends GutTest

## Harmonia's text put a well in the square six times (Phil the Lost sits at it, the Elder says "Look east. Past the
## well.") while the village placed a fountain and no well. A village's authored text, its own script's and the
## scenes the story gate plays there, may name a well only if that village places one.

const VILLAGES := "res://src/maps/villages/"
const CUTSCENES := "res://data/cutscenes/"
const GAME_LOOP := "res://src/GameLoop.gd"
## A well as a THING: a determiner before it and no hyphen or letter after ("as well", "well-known" are not wells).
const WELL := "(?i)\\b(?:the|a|an|village|old|stone|dry|that|this|its|his|her|their|our) well\\b(?![-a-z])|\\bwell(?:'s| kerb| water| rope| bucket)\\b"


## A script's source without its full-line comments: a comment about a well is not text a player reads.
func _code(path: String) -> String:
	var kept := PackedStringArray()
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if not line.strip_edges().begins_with("#"):
			kept.append(line)
	return "\n".join(kept)


func _names_a_well(text: String) -> bool:
	return RegEx.create_from_string(WELL).search(text) != null


## cutscene id -> the map the story plays it on, read from the gate itself and the village-intro table.
func _scene_maps() -> Dictionary:
	var out := {}
	var src := FileAccess.get_file_as_string(GAME_LOOP)
	var at := src.find("func _get_pending_story_cutscene")
	var body := src.substr(at, src.find("\nfunc ", at + 10) - at)
	var gate := RegEx.create_from_string("_current_map_id == \"([a-z0-9_]+)\"[^\\n]*:\\n\\t+return \"([a-z0-9_]+)\"")
	for m in gate.search_all(body):
		out[m.get_string(2)] = m.get_string(1)
	var intros: Dictionary = load(GAME_LOOP).get_script_constant_map().get("_VILLAGE_INTROS", {})
	for map_id in intros:
		if not out.has(str(intros[map_id])):
			out[str(intros[map_id])] = str(map_id)
	return out


## map id -> {"file", "places", "names": [what names the well]} for every village script.
func _villages() -> Dictionary:
	var out := {}
	var snake := RegEx.create_from_string("(?<!^)(?=[A-Z])")
	for f in DirAccess.get_files_at(VILLAGES):
		if not f.ends_with("Village.gd") or f == "BaseVillage.gd":
			continue
		var map_id := snake.sub(f.trim_suffix("Village.gd"), "_", true).to_lower() + "_village"
		var code := _code(VILLAGES + f)
		var names := []
		if _names_a_well(code):
			names.append(f)
		out[map_id] = {"file": f, "places": code.contains("Kind.WELL"), "names": names}
	var maps := _scene_maps()
	for f in DirAccess.get_files_at(CUTSCENES):
		var cid := f.get_basename()
		if f.ends_with(".json") and out.has(maps.get(cid, "")) and _names_a_well(FileAccess.get_file_as_string(CUTSCENES + f)):
			out[maps[cid]]["names"].append(cid)
	return out


func test_the_scan_can_tell_a_well_from_an_adverb() -> void:
	assert_true(_names_a_well("Look east. Past the well."), "CONTROL: a well is a well")
	assert_true(_names_a_well("on the well kerb beside him"), "CONTROL: its kerb counts")
	assert_false(_names_a_well("You fought well, and the others as well."), "an adverb is not a well")
	assert_false(_names_a_well("the well-known cartographer"), "nor is a well-known anything")


func test_a_village_names_a_well_only_if_it_places_one() -> void:
	var villages := _villages()
	assert_gt(_scene_maps().size(), 30, "CONTROL: the story gate's scene-to-map pairs were read")
	var placing := 0
	var named_and_placed := 0
	var missing := []
	for map_id in villages:
		var v: Dictionary = villages[map_id]
		if v["places"]:
			placing += 1
			if not (v["names"] as Array).is_empty():
				named_and_placed += 1
		elif not (v["names"] as Array).is_empty():
			missing.append("%s names a well it does not place: %s" % [map_id, ", ".join(PackedStringArray(v["names"]))])
	assert_gt(placing, 3, "CONTROL: villages that place a well are found by their Kind.WELL prop")
	assert_gt(named_and_placed, 0, "CONTROL: some village both names and places one, so the two halves can meet")
	assert_eq(missing, [], "a village's text names a well the village does not place")
