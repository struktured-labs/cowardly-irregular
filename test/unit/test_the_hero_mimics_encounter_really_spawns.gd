extends GutTest

## Regression (struktured's play log, 2026-10-04: 4x "Unknown encounter enemy ID: hero_mimic — skipping" + "No valid encounter
## enemies found, falling back to defaults"). The rare Hero Mimics encounter (2%) builds its mimics INLINE with stats copied from the
## party; GameLoop reduced every encounter entry to an id and the spawner keeps only monsters.json ids, so the mimics were dropped and
## the rare fight silently became a default one. All-mimic parties now travel as data to BattleEnemySpawner.spawn_from_data.

const BattleStateHelper := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")

var _bm: RefCounted = null
var _scene: Node = null


func before_each() -> void:
	_bm = BattleStateHelper.new()
	_bm.snapshot()


func after_each() -> void:
	if _scene and is_instance_valid(_scene):
		_scene.queue_free()
	_scene = null
	if _bm != null:
		_bm.restore()


func after_all() -> void:
	SoundState.restore()


func test_the_mimics_are_inline_and_not_in_the_bestiary_data() -> void:
	var mimics: Array = EncounterSystem._generate_hero_mimics_party()
	assert_eq(mimics.size(), 4, "the rare encounter builds four mimics")
	for m in mimics:
		assert_true(bool(m.get("is_mimic", false)), "each mimic is flagged")
	var monsters: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	assert_false(monsters.has("hero_mimic"), "SCOPE: hero_mimic has no monsters.json entry, so an id-only route drops it")


func test_a_mimic_party_handed_over_as_data_spawns_four_mimics() -> void:
	var mimics: Array = EncounterSystem._generate_hero_mimics_party()
	_scene = load("res://src/battle/BattleScene.tscn").instantiate()
	_scene.autogrind_enemy_data = mimics.duplicate(true)
	for k in _scene.autogrind_enemy_data.size():
		_scene.autogrind_enemy_data[k]["id"] = "hero_mimic_%d" % k
	add_child(_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var names: Array = []
	for e in _scene.test_enemies:
		if is_instance_valid(e):
			names.append(str(e.combatant_name))
	var fit: int = mini(4, _scene.enemy_positions.size())
	assert_eq(names.size(), fit, "every mimic that fits the field spawns, not the default monsters (got %s)" % [names])
	for n in names:
		assert_string_contains(n, "Mimic", "every spawned enemy is a mimic: %s" % n)
		assert_false(n.ends_with(" A") or n.ends_with(" B") or n.ends_with(" C"), "each mimic is its own copy, not a lettered duplicate: %s" % n)


func test_gameloop_routes_an_all_mimic_party_as_data() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var i := src.find("func _start_battle_async")
	assert_gt(i, -1, "SCOPE: the battle starter exists")
	var body := src.substr(i, src.find("\nfunc ", i + 1) - i)
	var route := body.find("battle_scene.autogrind_enemy_data = specific_enemies.duplicate(true)")
	assert_gt(route, -1, "an all-mimic encounter must hand its data to the spawner, not reduce it to ids")
	assert_true(body.contains("e.get(\"is_mimic\", false)"), "the hand-over is keyed on the mimic flag")
	assert_true(body.contains("\"hero_mimic_%d\" % k"), "each mimic gets its own id")
