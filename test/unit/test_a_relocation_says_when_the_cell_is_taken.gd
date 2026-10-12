extends GutTest

## `BaseVillage._validate_placements` moves any NPC authored onto an impassable cell, and its
## warning said only that it had moved one. Three times it moved one ONTO ANOTHER NPC, and that is
## the case that costs something: interaction is nearest-wins, so the far one of two NPCs on a cell
## may never be selected. MapleHeights/Gerald landed on Neighborhood Dad's tile and Gerald is a
## quest giver (`gerald_w2`); Grimhollow/Creepy Child Wednesday and Sandrift/Sand Sage Mirage merely
## ended up a tile from where their author put them.
##
## 🔑 THE SWEEP DELIBERATELY DOES NOT AVOID THE OCCUPANT, and this guard exists to keep it that way.
## Reserving a free cell — which is what `InteriorPlacementSweep` does for interiors — was proposed
## and REJECTED for villages (cowir-main 2026-10-12), because all three incidents were fixed by
## moving the PROP: a planter is decoration, a quest giver's position is content. A sweep that
## quietly relocated the NPC to some other free cell would trade a loud authoring error for a silent
## content change. So the warning carries the diagnosis and the instruction, and the author fixes it.
##
## ⚠️ THE STACKED-NPC STATE ITSELF IS GUARDED ELSEWHERE and this file does not duplicate it:
## `test_a_village_npc_stands_where_it_was_authored_and_alone` asserts `shared == []` over 94
## talking NPCs in 13 villages, with a demonstrated red. Measured 2026-10-12: that guard and three
## neighbours pass, so no village has a live collision today. This file is about what the sweep SAYS
## when it happens, which nothing asserted.

const BaseVillageScript := preload("res://src/maps/villages/BaseVillage.gd")

const FROM := Vector2(320, 480)
const TO := Vector2(304, 464)


func test_an_unoccupied_relocation_reads_as_it_always_did() -> void:
	var msg: String = BaseVillageScript.relocation_warning("maple_heights", "Gerald", FROM, TO, "")
	assert_true(msg.contains("relocated 'Gerald'"), "the warning must still name who moved")
	assert_true(msg.contains("off impassable tile"), "and why it moved them")
	assert_false(msg.contains("ONTO"),
		"CONTROL: with nobody on the destination there is no occupant clause, or the arm below is free")
	assert_false(msg.contains("nearest-wins"),
		"CONTROL: the nearest-wins diagnosis belongs only to the collision case")


func test_a_relocation_onto_another_npc_names_them_and_says_what_to_do() -> void:
	var msg: String = BaseVillageScript.relocation_warning("maple_heights", "Gerald", FROM, TO, "Neighborhood Dad")
	assert_true(msg.contains("Gerald"), "the moved NPC is still named")
	assert_true(msg.contains("Neighborhood Dad"),
		"the OCCUPANT must be named — 'relocated Gerald' alone is what made this invisible three times")
	assert_true(msg.contains("nearest-wins"),
		"the warning must say WHY a shared cell matters, or a reader treats it as cosmetic")
	assert_true(msg.contains("may be unreachable"), "and what the player loses")
	assert_true(msg.contains("move the PROP, not the NPC"),
		"and the instruction, which is the recorded ruling rather than the reader's guess")


## The two cases must be distinguishable in a log, which is the whole point: a grep for the
## collision shape must not match an ordinary relocation.
func test_the_two_cases_are_distinguishable_in_a_log() -> void:
	var plain: String = BaseVillageScript.relocation_warning("sandrift", "Sand Sage Mirage", FROM, TO, "")
	var onto: String = BaseVillageScript.relocation_warning("sandrift", "Sand Sage Mirage", FROM, TO, "Caravan Master")
	assert_ne(plain, onto, "the collision case must not render identically to the ordinary one")
	assert_true(onto.begins_with(plain),
			"the collision message should EXTEND the plain one, so an existing log grep still matches")


## ---- the call-site halves, which the message arms above cannot reach ----

## A bare BaseVillage, never added to the tree, so `_ready` does not build a village.
func _bare_village() -> Node2D:
	var v = BaseVillageScript.new()
	autofree(v)
	return v


## An Area2D, because OverworldNPC extends Area2D — a Node2D silently fails to take the script and
## every label then reads "" from an aborted lookup rather than from a missing name.
func _stub_npc(label: String, at: Vector2) -> Node2D:
	var n = preload("res://src/exploration/OverworldNPC.gd").new()
	n.name = "GeneratedNodeName"
	n.npc_name = label
	n.position = at
	return n


func test_the_label_prefers_the_npc_name_over_the_generated_node_name() -> void:
	var v = _bare_village()
	var n := _stub_npc("Gerald", Vector2.ZERO)
	autofree(n)
	assert_eq(v._placement_label(n), "Gerald",
		"an OverworldNPC never sets its node name, so the warning printed '@Area2D@17548' and was unattributable")
	n.npc_name = ""
	assert_eq(v._placement_label(n), "GeneratedNodeName",
		"with no npc_name the node name is all there is — the fallback must still say something")


func test_the_occupant_lookup_finds_a_stacked_npc_and_ignores_the_mover() -> void:
	var v = _bare_village()
	v.npcs = Node2D.new()
	autofree(v.npcs)
	var dad := _stub_npc("Neighborhood Dad", Vector2(304, 464))
	var gerald := _stub_npc("Gerald", Vector2(304, 464))
	v.npcs.add_child(dad)
	v.npcs.add_child(gerald)

	var cell: Vector2i = v._cell_of(Vector2(304, 464))
	assert_eq(cell, Vector2i(9, 14), "CONTROL: 304/32 = 9.5 and 464/32 = 14.5, so the cell is (9,14)")
	assert_eq(v._occupant_of_cell(cell, gerald), "Neighborhood Dad",
		"the occupant of the destination must be found, and named")
	assert_eq(v._occupant_of_cell(cell, dad), "Gerald",
		"and the lookup must EXCLUDE the mover rather than reporting them as their own obstacle")
	assert_eq(v._occupant_of_cell(Vector2i(0, 0), gerald), "",
		"CONTROL: an empty cell has no occupant, or the arms above pass on everything")

