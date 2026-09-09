extends GutTest
## Phil's Notebook (shipped .225) is a symptom list kept by a man who cannot hold his own memory.
## That premise lived ONLY in his NAME and in data/cutscenes/world1_harmonia_npcs.json -- a file no
## src/ path plays (audit 2026-09-09). His six shipped lines were the "are we NPCs?" gag and never
## mentioned losing, forgetting or the book, so a player met the prop with no reason for it to exist.
## Pins the COUPLING: while the notebook sits beside him, his dialogue must establish it.

##
## ⛔ WHAT THIS GUARD DOES NOT PROVE (stated 2026-09-09, from cowir-battle's retraction: "a test that
## calls the repaired function directly cannot tell either -- reachability is not a property you can
## observe from inside the thing you are reaching").
## It proves the NPC is IN THE TREE CARRYING THESE LINES. It does NOT prove a player can reach and
## talk to them. An NPC standing on a sealed one-tile ledge, behind a prop footprint, or with a
## missing interaction Area2D passes every assertion below -- and all three of those shipped in this
## repo this week. "reachable" in the filename means CONTENT-reachable, never INTERACTION-reachable.
## The instrument for the latter is a navigation/interaction probe and it does not live in this lane.

const VILLAGE := "res://src/maps/villages/HarmoniaVillage.tscn"


func _harmonia() -> Node:
	var packed: PackedScene = load(VILLAGE)
	assert_not_null(packed, "Harmonia scene must load")
	if packed == null:
		return null
	var scene: Node = packed.instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	return scene


func _find(root: Node, pred: Callable) -> Node:
	for child in root.get_children():
		if pred.call(child):
			return child
		var hit: Node = _find(child, pred)
		if hit != null:
			return hit
	return null


func test_the_scene_and_phil_actually_loaded() -> void:
	## Domain claim: without this, every assert below passes vacuously on a null scene.
	var scene: Node = await _harmonia()
	assert_not_null(scene, "Harmonia must instantiate")
	var phil: Node = _find(scene, func(n): return "npc_name" in n and str(n.npc_name) == "Phil the Lost")
	assert_not_null(phil, "Harmonia must contain 'Phil the Lost'")
	if phil != null:
		assert_gt((phil.dialogue_lines as Array).size(), 3,
			"Phil's dialogue looks empty/truncated: " + str(phil.dialogue_lines))


func test_notebook_prop_is_present_beside_him() -> void:
	var scene: Node = await _harmonia()
	var book: Node = _find(scene, func(n): return n.name == "PhilNotebook")
	assert_not_null(book, "Phil's Notebook prop must exist in Harmonia (shipped .225)")


func test_phil_establishes_the_notebooks_premise() -> void:
	var scene: Node = await _harmonia()
	var phil: Node = _find(scene, func(n): return "npc_name" in n and str(n.npc_name) == "Phil the Lost")
	assert_not_null(phil, "Phil must exist")
	if phil == null:
		return
	var joined := ""
	for l in (phil.dialogue_lines as Array):
		joined += str(l).to_lower() + " "

	## Two DISJOINT claims -- memory loss is why the book exists, the book is what he does about it.
	## Either alone leaves the prop unmotivated, so both are required.
	var says_he_loses := joined.find("lose") >= 0 or joined.find("forget") >= 0 \
		or joined.find("lose track") >= 0
	var says_he_writes := joined.find("write") >= 0 or joined.find("the book") >= 0

	assert_true(says_he_loses,
		"Phil never says he loses/forgets anything, so his notebook has no premise in game. " +
		"'Phil the Lost' is a NAME, not characterisation the player receives. Lines: " + joined)
	assert_true(says_he_writes,
		"Phil never mentions writing or the book, so nothing connects him to the prop beside him. " +
		"Lines: " + joined)
