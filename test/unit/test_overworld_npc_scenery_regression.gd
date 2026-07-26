extends GutTest

## Scenery NPCs — present in the world, not talkable (Mordaine's ambient
## watch beats, cowir-story msg 3139 beats 1-2).
##
## THE TRAP THIS PINS: OverworldNPC has TWO independent interaction paths.
##   1. the "interactables" group, scanned by OverworldPlayer.gd:1978
##   2. its own _input(), gated on _player_nearby — NOT on group membership
## Suppressing only the group leaves the NPC fully talkable: walk up, face
## her, press accept, dialogue opens. I asserted the one-path version to the
## fleet before reading _input, so this file pins BOTH or it pins nothing.

const NPC := "res://src/exploration/OverworldNPC.gd"


func _read() -> String:
	return FileAccess.get_file_as_string(NPC)


func _npc(interactable: bool) -> Node:
	var n = load(NPC).new()
	n.npc_name = "Chancellor Mordaine"
	n.interactable = interactable
	add_child_autofree(n)
	return n


func test_scenery_npc_stays_out_of_the_interactables_group() -> void:
	var scenery := _npc(false)
	assert_false(scenery.is_in_group("interactables"),
		"scenery must not be in the group OverworldPlayer scans")
	var talkable := _npc(true)
	assert_true(talkable.is_in_group("interactables"),
		"ordinary NPCs are unaffected — the default must stay interactable")


## The second path. A group-only fix passes the test above and still lets
## the player talk to her.
func test_scenery_npc_input_handler_is_suppressed_too() -> void:
	var src := _read()
	var i := src.find("func _input")
	var next := src.find("\nfunc ", i + 1)
	var body: String = src.substr(i, next - i) if next > 0 else src.substr(i)
	assert_true(body.contains("if not interactable:"),
		"_input must bail for scenery — it gates on _player_nearby, not on the group, so the group flag alone does NOT stop dialogue")
	var bail := body.find("if not interactable:")
	var accept := body.find("is_action_pressed(\"ui_accept\")")
	assert_gt(accept, bail,
		"the bail must come BEFORE the ui_accept handling, or it does nothing")


## A floating name tag promises a conversation that can't happen.
func test_scenery_npc_shows_no_name_label_on_approach() -> void:
	var src := _read()
	var i := src.find("func _on_body_entered")
	var next := src.find("\nfunc ", i + 1)
	var body: String = src.substr(i, next - i) if next > 0 else src.substr(i)
	assert_true(body.contains("name_label.visible = interactable"),
		"name label tracks interactability — an unlabelled figure reads as scenery, a labelled one reads as a broken NPC")
	assert_false(body.contains("name_label.visible = true"),
		"the unconditional label must not return")


## "!" over something that can't be talked to would be a lie.
func test_scenery_npc_gets_no_quest_marker() -> void:
	var src := _read()
	var i := src.find("func _setup_quest_marker")
	var next := src.find("\nfunc ", i + 1)
	var body: String = src.substr(i, next - i) if next > 0 else src.substr(i)
	var bail := body.find("if not interactable:")
	assert_gt(bail, -1, "quest marker setup bails for scenery")
	var made := body.find("_quest_marker = Label.new()")
	assert_gt(made, bail, "and bails before building the marker")


## Persistence is the whole point — a CutsceneActor is freed by _end_staging,
## so "she doesn't leave when seen" needs a real NPC, not a staged puppet.
func test_scenery_npc_persists_and_defaults_to_interactable() -> void:
	var src := _read()
	assert_true(src.contains("@export var interactable: bool = true"),
		"defaults to true — every existing NPC keeps its behaviour unchanged")
	var scenery := _npc(false)
	assert_true(is_instance_valid(scenery),
		"an ordinary node with no staged lifetime — it stays until the scene does")
