extends GutTest

## The Enrichment Annex officer fight never started. AnnexLiberation sits under
## the room's npc holder and walks ancestors for _on_battle_triggered. Villages
## and caves have that relay. BaseInterior declared battle_triggered and never
## the method, so a party with no Bard and a non-Cleric lead got the fight
## toast and stayed in the room.


func test_the_annex_fight_reaches_the_interior_battle_signal() -> void:
	var interior := BaseInterior.new()
	autofree(interior)
	var holder := Node2D.new()
	interior.add_child(holder)
	var zone := AnnexLiberation.new()
	holder.add_child(zone)
	var heard: Array = []
	interior.battle_triggered.connect(func(enemies: Array) -> void:
		heard.append(enemies))
	zone._fire_battle()
	assert_eq(heard, [["cranky_lady"]],
		"confronting the officer from inside the annex must start the cranky_lady battle")
