extends GutTest

## Harmonia's text put a well in the square six times (Phil the Lost sits at it, the Elder says "Look east. Past the
## well.") while the village placed a fountain and no well. A village's authored text, its own script's and the
## scenes the story plays there, may name a well only if that village places one. A scene belongs to a village
## by either route: the story gate plays it on that map, or (quest-triggered scenes such as world1_orrery, which
## the gate never plays) one of its backgrounds is that village's, e.g. harmonia_square for harmonia_village.

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
	var background := RegEx.create_from_string("\"background\"\\s*:\\s*\"([a-z0-9_]+)\"")
	for f in DirAccess.get_files_at(CUTSCENES):
		if not f.ends_with(".json"):
			continue
		var cid := f.get_basename()
		var text := FileAccess.get_file_as_string(CUTSCENES + f)
		if not _names_a_well(text):
			continue
		var homes := {}
		if out.has(maps.get(cid, "")):
			homes[maps[cid]] = true
		for m in background.search_all(text):
			var home := _village_of_background(m.get_string(1), out)
			if home != "":
				homes[home] = true
		for home in homes:
			out[home]["names"].append(cid)
	return out


## The village a backdrop belongs to: the one whose stem ("harmonia" of harmonia_village) begins its id.
## A shared backdrop (prologue_village, cave_entrance) is nobody's.
func _village_of_background(bg: String, villages: Dictionary) -> String:
	for map_id in villages:
		var stem := str(map_id).trim_suffix("_village")
		if bg == stem or bg.begins_with(stem + "_"):
			return map_id
	return ""


func test_the_scan_can_tell_a_well_from_an_adverb() -> void:
	assert_true(_names_a_well("Look east. Past the well."), "CONTROL: a well is a well")
	assert_true(_names_a_well("on the well kerb beside him"), "CONTROL: its kerb counts")
	assert_false(_names_a_well("You fought well, and the others as well."), "an adverb is not a well")
	assert_false(_names_a_well("the well-known cartographer"), "nor is a well-known anything")


func test_a_quest_scene_is_read_through_its_backdrop() -> void:
	var villages := _villages()
	assert_eq(_village_of_background("harmonia_square", villages), "harmonia_village", "a village's square is that village")
	assert_eq(_village_of_background("node_prime", villages), "node_prime_village", "a bare stem is that village")
	assert_eq(_village_of_background("prologue_village", villages), "", "CONTROL: a shared backdrop is nobody's")
	assert_false(_scene_maps().has("world1_orrery"), "CONTROL: the gate never plays the orrery scene, so only the backdrop route can reach it")
	assert_has(villages["harmonia_village"]["names"], "world1_orrery", "Phil's well in the orrery scene is Harmonia's")


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
