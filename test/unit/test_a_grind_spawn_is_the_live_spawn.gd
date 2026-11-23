extends GutTest

## The grind builds a re-levelled spawn ("goblin@L15") in its own function, beside the live builder; this pins that the two agree.
## Two builders of one fight is how a grind starts paying or hitting differently from the field with no test noticing.

const ControllerScript := preload("res://src/autogrind/AutogrindController.gd")
const ES := preload("res://src/encounters/EncounterSystem.gd")

var _ctrl: Node
var _saved_flags: Dictionary


func before_each() -> void:
	_ctrl = ControllerScript.new()
	add_child_autofree(_ctrl)
	AutogrindSystem._test_disable_persistence = true
	_saved_flags = GameState.story_flags.duplicate(true)


func after_each() -> void:
	GameState.story_flags = _saved_flags
	AutogrindSystem._test_disable_persistence = false


## Every level-marked id the W1 story tiers hand out, at every gate: the marks a player's grind can really meet.
func _marks_in_play() -> Array:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ES.W1_TIERS_PATH))
	var marks: Array = []
	for dragons in 5:
		GameState.story_flags = _saved_flags.duplicate(true)
		GameState.story_flags[str(cfg["opens_with"])] = true
		for i in dragons:
			GameState.story_flags[str(cfg["dragon_flags"][i])] = true
		for pool_id in cfg["pools"]:
			for id in ES.tiered_pool(str(pool_id), EncounterSystem.enemy_pools.get(pool_id, []), GameState):
				if ES.spawn_level_of(str(id)) > 0 and not marks.has(str(id)):
					marks.append(str(id))
	GameState.story_flags = _saved_flags.duplicate(true)
	return marks


func test_a_marked_spawn_fights_and_pays_in_the_grind_as_it_does_live() -> void:
	var marks := _marks_in_play()
	assert_gt(marks.size(), 20, "CONTROL: the story tiers hand out marked spawns to judge (got %d)" % marks.size())
	var moved := 0
	for id in marks:
		var live: Dictionary = EncounterSystem._create_enemy_data(id)
		var grind: Dictionary = _ctrl._base_data_for_id(id)
		if grind.is_empty() or live.is_empty():
			fail_test("%s: one builder returned nothing (live %d keys, grind %d keys)" % [id, live.size(), grind.size()])
			continue
		var stats: Dictionary = grind.get("stats", {})
		for key in stats:
			if live.has(key) and int(live[key]) != int(stats[key]):
				fail_test("%s: the grind's %s is %d, live's is %d" % [id, key, int(stats[key]), int(live[key])])
		for pay in ES.PAY_KEYS:
			if int(live.get(pay, -1)) != int(grind.get(pay, -2)):
				fail_test("%s: the grind pays %s %d, live pays %d" % [id, pay, int(grind.get(pay, -2)), int(live.get(pay, -1))])
		assert_eq(int(grind.get("spawn_level", 0)), int(live.get("spawn_level", -1)), "%s: both builders carry the level it fights at" % id)
		var catalog: Dictionary = EncounterSystem._create_enemy_data(ES.spawn_base_id(id))
		if int(live.get("max_hp", 0)) != int(catalog.get("max_hp", 0)) and int(live.get("exp_reward", 0)) != int(catalog.get("exp_reward", 0)):
			moved += 1
	assert_eq(moved, marks.size(), "CONTROL: every mark really re-levels its species, so agreeing with live is not agreeing with the catalog")


func test_the_grind_carries_every_stat_the_live_spawn_re_levels() -> void:
	var marks := _marks_in_play()
	assert_gt(marks.size(), 0, "CONTROL: marks to judge")
	for id in marks:
		var stats: Dictionary = _ctrl._base_data_for_id(id).get("stats", {})
		for key in ES.BAND_STATS:
			assert_true(stats.has(key), "%s: the grind's spawn has no %s, so the fight would fall back to a default the live spawn does not use" % [id, key])
