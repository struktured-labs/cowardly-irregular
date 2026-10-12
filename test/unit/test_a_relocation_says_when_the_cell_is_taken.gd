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
