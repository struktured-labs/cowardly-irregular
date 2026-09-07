extends GutTest

## Scenery NPCs — present in the world, not talkable (Mordaine's ambient
## watch beats, cowir-story msg 3139 beats 1-2).
##
## THE TRAP THIS PINS: OverworldNPC has TWO independent interaction paths.
##   1. the "interactables" group, scanned by OverworldPlayer
##   2. its own _input(), gated on _player_nearby — NOT on group membership
## Suppressing only the group leaves the NPC fully talkable: walk up, face
## her, press accept, dialogue opens. I asserted the one-path version to the
## fleet before reading _input, so this file pins BOTH or it pins nothing.
##
## 2026-07-29: these were source-text pins (`body.contains("if not
## interactable:")`). A pin like that passes if the guard is present and
## wrong, and cannot see a guard that moves below the thing it guards. Every
## test here now drives the real node and reads a real observable.

const NPC := "res://src/exploration/OverworldNPC.gd"


## _on_body_entered only reacts to a body carrying set_can_move — that IS
## its player test, so the fake must carry it too.
class FakePlayer:
	extends Node2D
	func set_can_move(_v: bool) -> void:
		pass


func _npc(interactable: bool, parent: Node = null) -> Node:
	var n = load(NPC).new()
	n.npc_name = "Chancellor Mordaine"
	n.interactable = interactable
	# Empty lines make the deferred _start_dialogue a no-op, so the talkable
	# control can consume a press without opening real dialogue.
	n.dialogue_lines = []
	match parent == null:
		true: add_child_autofree(n)
		false: parent.add_child(n)
	return n


## The root viewport's handled flag is SHARED and arrives dirty — measured:
## in the full suite it is already true before this file runs, while a
## single-file run starts clean. Same class as the leaked-Input hazard in
## CLAUDE.md. A dedicated SubViewport makes _input's set_input_as_handled()
## land somewhere only this test can see.
func _isolated_viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	return vp


func _accept_event() -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	return ev


## The facing cone and the lock gate sit between the interactable gate and
## the press. If either is active the talkable control would "pass" for the
## wrong reason, so assert them rather than hope.
func _assert_input_path_is_clear() -> void:
	assert_null(get_tree().get_first_node_in_group("player"),
		"precondition: no leaked player node — one would engage the facing cone and make the talkable control pass vacuously")
	var ilm = get_tree().root.get_node_or_null("InputLockManager")
	if ilm != null:
		assert_false(ilm.is_locked(),
			"precondition: input must not be locked — a leaked lock suppresses BOTH npcs and hides the difference")
	assert_false(TutorialHint.is_any_active(),
		"precondition: no active tutorial hint — it gates this handler too")


func test_scenery_npc_stays_out_of_the_interactables_group() -> void:
	var scenery := _npc(false)
	assert_false(scenery.is_in_group("interactables"),
		"scenery must not be in the group OverworldPlayer scans")
	var talkable := _npc(true)
	assert_true(talkable.is_in_group("interactables"),
		"ordinary NPCs are unaffected — the default must stay interactable")


## THE SECOND PATH, driven rather than read. A group-only fix passes the test
## above and still lets the player talk to her. The observable is the
## viewport's handled flag, which _input sets only past every gate.
func test_scenery_npc_does_not_consume_the_interact_press() -> void:
	_assert_input_path_is_clear()
	var vp := _isolated_viewport()
	var scenery := _npc(false, vp)
	scenery._player_nearby = true

	assert_false(vp.is_input_handled(),
		"precondition: a fresh viewport starts clear, or this test cannot discriminate")

	scenery._input(_accept_event())
	assert_false(vp.is_input_handled(),
		"scenery must not consume ui_accept — _input gates on _player_nearby, not on the group, so the group flag alone does NOT stop dialogue")
	assert_false(scenery._is_talking, "and no dialogue may open")


## The control that makes the test above mean something: the SAME press, the
## same proximity, on an ordinary NPC, is consumed.
func test_an_ordinary_npc_does_consume_the_same_press() -> void:
	_assert_input_path_is_clear()
	var vp := _isolated_viewport()
	var talkable := _npc(true, vp)
	talkable._player_nearby = true

	assert_false(vp.is_input_handled(), "precondition: a fresh viewport starts clear")

	talkable._input(_accept_event())
	assert_true(vp.is_input_handled(),
		"an ordinary NPC still takes the press — if this fails the scenery result above proves nothing, because nothing was being suppressed")


## A floating name tag promises a conversation that can't happen.
func test_scenery_npc_shows_no_name_label_on_approach() -> void:
	var player := FakePlayer.new()
	add_child_autofree(player)

	var scenery := _npc(false)
	scenery._on_body_entered(player)
	assert_false(scenery.name_label.visible,
		"an unlabelled figure reads as scenery; a labelled one reads as a broken NPC")

	var talkable := _npc(true)
	talkable._on_body_entered(player)
	assert_true(talkable.name_label.visible,
		"ordinary NPCs still label on approach — otherwise this asserts nothing about interactable")


## "!" over something that can't be talked to would be a lie.
func test_scenery_npc_gets_no_quest_marker() -> void:
	var scenery := _npc(false)
	assert_null(scenery._quest_marker,
		"scenery builds no quest marker — it can never have quest business")
	var talkable := _npc(true)
	assert_not_null(talkable._quest_marker,
		"ordinary NPCs still build one — the bail must be conditional, not unconditional")


## Persistence is the whole point — a CutsceneActor is freed by _end_staging,
## so "she doesn't leave when seen" needs a real NPC, not a staged puppet.
func test_scenery_npc_persists_and_defaults_to_interactable() -> void:
	var default_npc = load(NPC).new()
	add_child_autofree(default_npc)
	assert_true(default_npc.interactable,
		"defaults to true — every existing NPC keeps its behaviour unchanged")

	var scenery := _npc(false)
	assert_true(is_instance_valid(scenery),
		"an ordinary node with no staged lifetime — it stays until the scene does")
