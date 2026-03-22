extends GutTest

## Regression tests for overworld encounter system
## - Random encounters must be DISABLED when roaming monsters are active
## - Roaming monsters must be avoidable (player faster than chase speed)
## - Monsters must spawn far enough away to react

const MonsterSpawnerScript = preload("res://src/exploration/MonsterSpawner.gd")
const RoamingMonsterScript = preload("res://src/exploration/RoamingMonster.gd")
const OverworldSceneScript = preload("res://src/exploration/OverworldScene.gd")
const OverworldControllerScript = preload("res://src/exploration/OverworldController.gd")
const OverworldPlayerScript = preload("res://src/exploration/OverworldPlayer.gd")


func test_random_encounters_disabled_on_overworld():
	var scene = OverworldSceneScript.new()
	add_child_autofree(scene)
	await get_tree().process_frame
	assert_not_null(scene.controller, "Controller should exist")
	assert_false(scene.controller.encounter_enabled,
		"Random step encounters must be OFF when roaming monsters handle encounters")


func test_monster_spawner_active_on_overworld():
	var scene = OverworldSceneScript.new()
	add_child_autofree(scene)
	await get_tree().process_frame
	assert_not_null(scene.monster_spawner, "MonsterSpawner should exist on overworld")


func test_player_faster_than_chase():
	var player = OverworldPlayerScript.new()
	add_child_autofree(player)
	assert_gt(player.move_speed, RoamingMonsterScript.CHASE_SPEED,
		"Player (%.0f) must outrun monster chase (%.0f)" % [player.move_speed, RoamingMonsterScript.CHASE_SPEED])


func test_spawn_distance_gives_reaction_time():
	assert_gt(MonsterSpawnerScript.MIN_SPAWN_DIST_FROM_PLAYER,
		RoamingMonsterScript.CHASE_RADIUS * 2.0,
		"Spawn distance (%.0f) must be >2x chase radius (%.0f) so player can react" % [
			MonsterSpawnerScript.MIN_SPAWN_DIST_FROM_PLAYER,
			RoamingMonsterScript.CHASE_RADIUS])


func test_chase_radius_reasonable():
	assert_lt(RoamingMonsterScript.CHASE_RADIUS, 128.0,
		"Chase radius should be <128px so monsters don't aggro from too far")


func test_default_spawn_not_in_water():
	var scene = OverworldSceneScript.new()
	add_child_autofree(scene)
	await get_tree().process_frame
	var default_pos = scene.spawn_points.get("default", Vector2.ZERO)
	assert_ne(default_pos, Vector2.ZERO, "Default spawn point should be set")
	var tile_x = int(default_pos.x / 32)
	var tile_y = int(default_pos.y / 32)
	assert_gt(tile_x, 15, "Default spawn X (tile %d) should be away from western water" % tile_x)
	assert_lt(tile_x, 85, "Default spawn X (tile %d) should be away from eastern edge" % tile_x)
