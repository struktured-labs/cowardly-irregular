extends GutTest

## A village's first-entry intro must show each speaker the face that speaker wears in the village. The village draws a
## portrait through OverworldNPC._portrait_key() (the archetype, struktured 2026-07-31); an intro hand-types `portrait`,
## so Creepy Child Wednesday spoke her intro under an adult villager's face and Madame Hex under "elder", a key the
## village can never resolve to (cowir-cutscenes 2026-11-04, the Theron class: one character, two faces).
## Corpus is DERIVED: every village in GameLoop._VILLAGE_INTROS, every intro speaker who stands in that village.

const GAME_LOOP := "res://src/GameLoop.gd"


func _intros() -> Dictionary:
	var m: Dictionary = load(GAME_LOOP).get_script_constant_map().get("_VILLAGE_INTROS", {})
	return m


## harmonia_village -> res://src/maps/villages/HarmoniaVillage.gd
func _script_for(village_id: String) -> String:
	var pascal := ""
	for part in village_id.split("_"):
		pascal += str(part).capitalize().replace(" ", "")
	return "res://src/maps/villages/%s.gd" % pascal


func _intro_lines(cutscene_id: String) -> Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/cutscenes/%s.json" % cutscene_id))
	var out: Array = []
	if not (data is Dictionary):
		return out
	for step in data.get("steps", []):
		if step is Dictionary and str(step.get("type", "")) == "dialogue":
			for line in step.get("lines", []):
				if line is Dictionary and str(line.get("portrait", "")) != "":
					out.append(line)
	return out


## name -> the placed NPC's own portrait key, from a freshly built copy of the village.
func _village_faces(path: String) -> Dictionary:
	var faces := {}
	var vp := SubViewport.new()
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var made = load(path).new()
	vp.add_child(made)
	await get_tree().process_frame
	await get_tree().process_frame
	for n in (made as Node).find_children("*", "Area2D", true, false):
		if n.has_method("_portrait_key") and str(n.get("npc_name")) != "":
			faces[str(n.get("npc_name"))] = str(n.call("_portrait_key"))
	return faces


func test_every_intro_speaker_wears_their_village_face() -> void:
	var intros := _intros()
	assert_gt(intros.size(), 3, "floor: GameLoop._VILLAGE_INTROS was read")
	var judged := 0
	var mismatched: Array = []
	for vid in intros:
		var path := _script_for(str(vid))
		assert_true(ResourceLoader.exists(path), "CONTROL: %s resolves to a village script (%s)" % [vid, path])
		if not ResourceLoader.exists(path):
			continue
		var faces: Dictionary = await _village_faces(path)
		for line in _intro_lines(str(intros[vid])):
			var who := str(line.get("speaker", ""))
			if not faces.has(who):
				continue
			judged += 1
			if str(line["portrait"]) != str(faces[who]):
				mismatched.append("%s in %s: intro says %s, the village shows %s" % [who, intros[vid], line["portrait"], faces[who]])
	assert_gt(judged, 20, "floor: intro speakers who stand in their village were found and judged (%d)" % judged)
	assert_eq(mismatched, [], "an intro shows each speaker the face the village gives them")
