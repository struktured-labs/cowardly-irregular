extends GutTest

## A boss defeat was logged as "Defeated " + its DUNGEON FLAG humanized, so an NPC heard "Defeated World1 Mordaine",
## "Defeated Fire Dragon" for Pyrroth, "Defeated Null Chamber Cleared", and "Defeated Unknown Boss" for a Masterite whose
## defeat flag is a cutscene constant. The event now names the boss the battle marked, by the name it fought under.

const GL := preload("res://src/GameLoop.gd")


func _enemy(shown: String, boss: bool) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = shown
	if boss:
		c.set_meta("is_miniboss", true)
	autofree(c)
	return c


func test_the_boss_is_named_as_the_battle_showed_it() -> void:
	var shown: String = str(EncounterSystem.monster_database.get("fire_dragon", {}).get("name", ""))
	assert_ne(shown, "", "CONTROL: a real boss row with a display name")
	var got: String = GL.defeated_boss_name([_enemy("Ember Imp", false), _enemy(shown, true)], "fire_dragon_defeated")
	assert_eq(got, shown, "THE DEFECT: the NPC heard the flag ('Fire Dragon'), not the boss it fought")


func test_a_flag_that_names_a_room_is_not_the_name() -> void:
	assert_eq(GL.defeated_boss_name([_enemy("The Null Process", true)], "null_chamber_cleared"), "The Null Process",
		"a dungeon whose flag names its room still names its boss")
	assert_eq(GL.defeated_boss_name([_enemy("Warden of the Assembly Line", true)], "unknown_boss"),
		"Warden of the Assembly Line", "a Masterite with no dungeon flag is not 'Unknown Boss'")


func test_with_no_marked_boss_the_flag_still_reads() -> void:
	assert_eq(GL.defeated_boss_name([_enemy("Slime", false)], "cave_rat_king_defeated"), "Cave Rat King",
		"CONTROL: the old humanized flag is the fallback when no enemy is marked")
	assert_eq(GL.defeated_boss_name([], "cave_rat_king_defeated"), "Cave Rat King", "and an empty party falls back the same way")
