extends GutTest

## Regression test for the non-headless autogrind enemy-generation crash.
##
## Bug: AutogrindController._generate_scaled_enemies() read
## `BattleSceneScript.MONSTER_TYPES` off the loaded BattleScene.gd Resource.
## In commit cd01c07 BattleScene's `const MONSTER_TYPES` was converted to a
## NON-static instance property with a getter, so reading it off the GDScript
## Resource raised "Invalid access to property or key 'MONSTER_TYPES' on a base
## object of type 'GDScript'" and aborted enemy generation. Every NORMAL
## (non-headless, non-meta-boss) autogrind battle hit this on its first spawn.
## The existing autogrind tests only exercise the headless resolver, so this
## live path was uncaught.
##
## Fix: read the const where it actually lives — BattleEnemySpawner is a global
## class (`class_name BattleEnemySpawner`) with `const MONSTER_TYPES`, accessible
## directly off the class object without loading BattleScene.gd at all.

var _controller: Node = null


func before_each() -> void:
	_controller = preload("res://src/autogrind/AutogrindController.gd").new()
	add_child_autofree(_controller)


## Guards the const access pattern the fix relies on: MONSTER_TYPES must be
## readable directly off the BattleEnemySpawner global class.
func test_monster_types_const_accessible_on_spawner_class() -> void:
	var monster_types = BattleEnemySpawner.MONSTER_TYPES
	assert_true(monster_types is Array, "BattleEnemySpawner.MONSTER_TYPES should be an Array")
	assert_gt(monster_types.size(), 0, "BattleEnemySpawner.MONSTER_TYPES should not be empty")


## Guards against the regressed access path: BattleScene.MONSTER_TYPES is an
## instance property getter, NOT a const/static, so it must NOT be read off the
## loaded GDScript Resource (which is what raised the runtime SCRIPT ERROR).
func test_monster_types_not_readable_off_battlescene_resource() -> void:
	var BattleSceneScript = load("res://src/battle/BattleScene.gd")
	assert_false(
		"MONSTER_TYPES" in BattleSceneScript,
		"BattleScene.MONSTER_TYPES must remain an instance property, not a static/const on the script Resource"
	)


## End-to-end: _generate_scaled_enemies() must produce a non-empty list of
## scaled enemy dictionaries without raising the old MONSTER_TYPES SCRIPT ERROR.
func test_generate_scaled_enemies_returns_non_empty() -> void:
	var enemies = _controller._generate_scaled_enemies()
	assert_true(enemies is Array, "_generate_scaled_enemies should return an Array")
	assert_gt(enemies.size(), 0, "_generate_scaled_enemies should return at least one enemy")
	for enemy in enemies:
		assert_true(enemy is Dictionary, "Each generated enemy should be a Dictionary")
		assert_true(enemy.has("id"), "Each generated enemy should carry an id")
		assert_true(enemy.has("stats"), "Each generated enemy should carry stats")
