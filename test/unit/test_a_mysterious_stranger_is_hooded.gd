extends GutTest

## The tavern's "???" and Vertex's "The Shape" are npc_type "mysterious", and that type was mapped to the TRAVELER walk
## sheet: a cheerful figure in a brown hat with a staff, speaking with the traveler's face. A hooded "mysterious" sheet
## was generated for exactly this (2026-09-07) and nothing ever pointed at it. Madame Orrery, the travelling merchant
## who is also typed "mysterious", keeps the traveler look she has always had, by name.

const NpcScript := preload("res://src/exploration/OverworldNPC.gd")
const Dialogue := preload("res://src/cutscene/CutsceneDialogue.gd")


func _find(scene_path: String, npc_name: String) -> Node:
	var vp := SubViewport.new()
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var scene: Node = load(scene_path).new()
	vp.add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	for n in scene.find_children("*", "Area2D", true, false):
		if str(n.get("npc_name")) == npc_name:
			return n
	return null


func test_the_mysterious_sheet_is_on_disk_and_registered() -> void:
	var m = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	var e: Dictionary = (m.get("overworld_npc_sheets", {}) as Dictionary).get("mysterious", {})
	assert_true(FileAccess.file_exists(str(e.get("path", ""))), "CONTROL: the hooded sheet exists")
	assert_true(FileAccess.file_exists(str(Dialogue.PORTRAIT_SPRITES.get("mysterious", ""))), "CONTROL: the hooded portrait exists")


func test_the_shape_walks_and_speaks_hooded() -> void:
	var shape: Node = await _find("res://src/maps/villages/VertexVillage.gd", "The Shape")
	assert_not_null(shape, "CONTROL: The Shape stands in Vertex")
	if shape == null:
		return
	assert_eq(str(shape._resolve_archetype()), "mysterious", "The Shape is the hooded figure, not a traveler in a brown hat")
	assert_eq(str(shape._portrait_key()), "mysterious", "and speaks with the hooded face")


func test_the_tavern_stranger_walks_and_speaks_hooded() -> void:
	var n = NpcScript.new()
	n.npc_name = "???"
	n.npc_type = "mysterious"
	assert_eq(str(n._resolve_archetype()), "mysterious", "a plain mysterious NPC is hooded")
	assert_eq(str(n._portrait_key()), "mysterious")
	n.free()
	var src := FileAccess.get_file_as_string("res://src/maps/interiors/TavernInterior.gd")
	assert_true(src.contains('_create_npc("???", "mysterious"'), "CONTROL: the tavern's stranger is still typed mysterious")


func test_madame_orrery_keeps_her_travellers_look() -> void:
	for path in ["res://src/maps/villages/BrasstonVillage.gd", "res://src/maps/villages/RivetRowVillage.gd", "res://src/maps/villages/MapleStripMall.gd"]:
		var orrery: Node = await _find(path, "Madame Orrery")
		assert_not_null(orrery, "CONTROL: Madame Orrery stands in %s" % path.get_file())
		if orrery != null:
			assert_eq(str(orrery._resolve_archetype()), "traveler", "%s: the travelling merchant is unchanged" % path.get_file())
			assert_eq(str(orrery._portrait_key()), "traveler", "%s: and so is her face" % path.get_file())
