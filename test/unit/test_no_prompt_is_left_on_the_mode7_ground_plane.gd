extends GutTest

## Text left in world space is not "a bit small" under Mode 7 — it is destroyed, twice over.
##
## The shader compresses it horizontally and stretches it vertically, AND a world-space upward
## offset is thrown toward the horizon by the perspective: the chest's loot panel is authored 110px
## above the chest, and rendered as an 8-pixel smear near the skyline, 180px left of the player who
## opened it. "Found Potion x3!" was, functionally, not displayed.
##
## Swept live 2026-09-10 across the five Mode 7 worlds: 243 world-space Labels in six classes —
## TreasureChest 104, OverworldNPC 93, RoamingMonster 21, WanderingNPC 11, VillageMarker 10,
## SavePoint 4. AreaTransition and Signpost were already absent, having been lifted earlier the
## same day, which is what suggested sweeping for the rest.
##
## THE SPLIT IS PROMPT vs POSITIONAL, and it is a per-class design call, not a per-instance excuse:
##   PROMPT — read while standing on the thing. Belongs on screen, over the player. All lifted.
##   POSITIONAL — its position IS its meaning. A village banner over its village, a "!" over the
##   NPC who has the quest, a mood tell over one monster among five. Anchoring those to the player
##   would delete what they say. They stay, and they are glyphs or short names rather than prose.
##
## This test is the sweep. It is a POSITIVE list: a class that appears here has been classified.
## A new class turns up as a failure that says "classify this", never as one that says "suppress it".

const WORLDS := {
	"medieval": "res://src/exploration/OverworldScene.gd",
	"suburban": "res://src/exploration/SuburbanOverworld.gd",
	"steampunk": "res://src/exploration/SteampunkOverworld.gd",
	"industrial": "res://src/exploration/IndustrialOverworld.gd",
	"futuristic": "res://src/exploration/FuturisticOverworld.gd",
}

## Classified as POSITIONAL — see the header. Every other class must lift its text.
const MAY_KEEP_WORLD_SPACE := ["VillageMarker", "RoamingMonster", "OverworldNPC"]
## OverworldNPC is on that list for its "!" quest marker only; its NAME label is a prompt and lifts.
const NPC_PROMPT_TEXTS := ["!", "?"]


func after_each() -> void:
	Mode7Overlay.is_active = false


func _under_canvas_layer(n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if p is CanvasLayer:
			return true
		p = p.get_parent()
	return false


func _owner_class(n: Node) -> String:
	var p := n.get_parent()
	while p != null:
		var s = p.get_script()
		if s != null:
			return str(s.resource_path).get_file().get_basename()
		p = p.get_parent()
	return "?"


func _collect(n: Node, found: Array) -> void:
	for c in n.get_children():
		if c is Label and not _under_canvas_layer(c):
			found.append(c)
		_collect(c, found)


func test_only_classified_positional_text_is_left_where_the_shader_can_reach_it() -> void:
	Mode7Overlay.is_active = true
	var offenders := {}
	var worlds_built := 0
	var labels_seen := 0

	for label in WORLDS:
		var vp := SubViewport.new()
		vp.size = Vector2i(64, 64)
		vp.world_2d = World2D.new()
		add_child_autofree(vp)
		var scene = load(WORLDS[label]).new()
		vp.add_child(scene)
		await get_tree().physics_frame
		await get_tree().process_frame
		await get_tree().process_frame
		worlds_built += 1

		var found: Array = []
		_collect(scene, found)
		for lbl in found:
			labels_seen += 1
			var owner_name := _owner_class(lbl)
			if not (owner_name in MAY_KEEP_WORLD_SPACE):
				offenders[owner_name] = int(offenders.get(owner_name, 0)) + 1

	assert_eq(worlds_built, WORLDS.size(), "CONTROL: every Mode 7 world must have been built")
	assert_gt(labels_seen, 40,
		"CONTROL: only %d world-space labels found across five worlds — the walk is broken and the zero below is free" % labels_seen)
	assert_eq(offenders, {},
		"prompt text left on the Mode 7 ground plane, where the shader destroys it: %s" % str(offenders))


func test_the_chest_puts_its_loot_where_the_player_who_opened_it_is_looking() -> void:
	Mode7Overlay.is_active = true
	var chest = load("res://src/exploration/TreasureChest.gd").new()
	add_child_autofree(chest)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(_under_canvas_layer(chest.name_label),
		"the chest's own prompt is still on the ground plane")
	assert_true(_under_canvas_layer(chest.dialogue_label),
		"the loot popup is still on the ground plane — this is the text naming what you just found")

	Mode7Overlay.is_active = false
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(chest.name_label.get_parent(), chest, "the chest prompt never came back for flat maps")
	assert_eq(chest.name_label.position, TreasureChest.FLAT_NAME_OFFSET, "it came back to the wrong offset")


func test_a_flat_map_leaves_every_prompt_in_the_world_where_it_was_authored() -> void:
	Mode7Overlay.is_active = false
	var chest = load("res://src/exploration/TreasureChest.gd").new()
	var post := Signpost.new()
	add_child_autofree(chest)
	add_child_autofree(post)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_false(_under_canvas_layer(chest.name_label), "a flat map moved the chest prompt to a layer")
	assert_false(_under_canvas_layer(post._label), "a flat map moved the sign text to a layer")
	assert_gt(chest.name_label.z_index, 0, "the chest prompt would draw under the player who opened it")
	assert_gt(post._label.z_index, 0, "the sign text would draw under the player who read it")
