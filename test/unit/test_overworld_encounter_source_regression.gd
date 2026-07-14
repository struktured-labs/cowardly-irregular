extends GutTest

## User report (2026-06-17): "cross paths with a monster, seconds pass, then battle triggers and you stop moving... could be Mode 7 alignment".
## Root cause: 5 W2-W6 overworlds had `controller.encounter_enabled = true` AND a MonsterSpawner running.
## Random step-based encounters were firing in addition to touch-based, so battles started with no nearby monster.

const OVERWORLD_FILES: Array[String] = [
	"res://src/exploration/OverworldScene.gd",         # W1 medieval
	"res://src/exploration/SuburbanOverworld.gd",      # W2
	"res://src/exploration/SteampunkOverworld.gd",     # W3
	"res://src/exploration/IndustrialOverworld.gd",    # W4
	"res://src/exploration/FuturisticOverworld.gd",    # W5
	"res://src/exploration/AbstractOverworld.gd",      # W6
]


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


## Pin: every overworld that uses MonsterSpawner MUST disable step-based random encounters.
func test_every_monster_spawner_overworld_disables_random_encounters() -> void:
	for path in OVERWORLD_FILES:
		var text := _read(path)
		var uses_spawner: bool = text.find("MonsterSpawner.new()") != -1 or text.find("MonsterSpawnerScript.new()") != -1
		if not uses_spawner:
			continue
		var disables: bool = text.find("controller.encounter_enabled = false") != -1
		assert_true(disables,
			"%s uses MonsterSpawner so controller.encounter_enabled must be set to false (visible monsters + step-based random encounters compete)" % path)
		var enables: bool = text.find("controller.encounter_enabled = true") != -1
		assert_false(enables,
			"%s must NOT set controller.encounter_enabled = true while MonsterSpawner is active (causes 'battles fire with no monster nearby' user report)" % path)
