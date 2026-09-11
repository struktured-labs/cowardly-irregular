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
## ⛔ THIS WAS A CLASS-LEVEL LIST FOR ONE DAY AND THAT WAS THE HOLE. OverworldNPC was on it "for its
## quest marker only" — my own comment said so — while the code exempted EVERY label the class owns.
## The narrow rule was sitting right there as an unused const. A third label on that class, a real
## prompt, would have been waved through by a guard whose comment already said it should not be.
## Found 2026-09-11 from @cowir-sfx's framing: when an instrument treats two members of its own
## subject differently, that asymmetry is a finding about the INSTRUMENT until proven otherwise, and
## explaining the mechanism does not discharge it. I had explained it, in writing, and shipped it.
const CLASS_POSITIONAL := ["VillageMarker", "RoamingMonster"]
## OverworldNPC's exemption is per-LABEL: the marker glyph is positional, its name label is a prompt.
const NPC_PROMPT_TEXTS := ["!", "?"]
const NPC_SOURCE := "res://src/exploration/OverworldNPC.gd"


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


## Two kinds of OverworldNPC label survive in world space, and only one of them is a decision.
##   "!" / "?"  the quest marker — POSITIONAL, it tells you WHICH npc has the quest
##   ""         the label inside dialogue_box, which is NEVER SHOWN: `dialogue_box.visible = true`
##              appears nowhere in OverworldNPC.gd and :1235 says the production path is
##              NPCDialogue/CutsceneDialogue. Dead, not positional.
## ⚠️ THE SECOND EXEMPTION IS A DEBT AND IT EXPIRES BY ITSELF. It holds only while that box stays
## unshown; the assert below re-checks that every run, so wiring the box up reds this test and makes
## whoever did it lift the label rather than inherit a permission.
func _npc_label_is_exempt(lbl: Label) -> bool:
	if str(lbl.text) in NPC_PROMPT_TEXTS:
		return true
	var src := _read_source(NPC_SOURCE)
	var dead_box := not src.contains("dialogue_box.visible = true")
	assert_true(dead_box,
		"OverworldNPC's dialogue_box is shown now, so its label is a live prompt and must lift — the exemption below expired")
	return dead_box and str(lbl.text) == ""


func _read_source(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


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
			if owner_name in CLASS_POSITIONAL:
				continue
			if owner_name == "OverworldNPC" and _npc_label_is_exempt(lbl):
				continue
			offenders["%s:'%s'" % [owner_name, str(lbl.text).substr(0, 12)]] = \
				int(offenders.get("%s:'%s'" % [owner_name, str(lbl.text).substr(0, 12)], 0)) + 1

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
