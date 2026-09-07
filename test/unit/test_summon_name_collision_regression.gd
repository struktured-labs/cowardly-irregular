extends GutTest

## Smoke-log follow-up 2026-07-03: summon naming indexed by ALIVE
## same-type count, which (a) skipped "A" entirely (Imp, Imp B, Imp C)
## and (b) collided after deaths — "Goblin A" dies leaving "Goblin B",
## alive count 1 → suffix index 1 → a SECOND "Goblin B" on screen.
## pick_summon_name now assigns the first letter unused by any living
## same-type enemy.

const BattleSceneScript = preload("res://src/battle/BattleScene.gd")


func test_first_summon_of_a_type_is_unsuffixed() -> void:
	assert_eq(BattleSceneScript.pick_summon_name("Imp", []), "Imp")


func test_summon_next_to_unsuffixed_original_gets_a() -> void:
	assert_eq(BattleSceneScript.pick_summon_name("Imp", ["Imp"]), "Imp A",
		"the old alive-count index skipped straight to B")


func test_no_collision_with_surviving_letter() -> void:
	assert_eq(BattleSceneScript.pick_summon_name("Goblin", ["Goblin B"]), "Goblin A",
		"survivor keeps B; the old code minted a duplicate 'Goblin B'")


func test_recycles_dead_letters_before_extending() -> void:
	assert_eq(BattleSceneScript.pick_summon_name("Goblin", ["Goblin A", "Goblin C"]), "Goblin B")


func test_multiword_base_names_parse() -> void:
	assert_eq(BattleSceneScript.pick_summon_name("Skeleton Knight", ["Skeleton Knight", "Skeleton Knight A"]),
		"Skeleton Knight B")


func test_exhausted_letters_fall_through() -> void:
	var crowd := ["Imp", "Imp A", "Imp B", "Imp C", "Imp D", "Imp E"]
	assert_eq(BattleSceneScript.pick_summon_name("Imp", crowd), "Imp F")
