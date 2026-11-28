extends GutTest
## .849 gate: 4450 "Node not found" errors from bare-script BattleScenes; the fixture builds the .tscn instead.

const Fixture := preload("res://test/unit/helpers/battle_scene_fixture.gd")
const SceneScript := preload("res://src/battle/BattleScene.gd")
const PATHS := ["BattleField/PartyArea/Player1Pos", "BattleField/EnemyArea/Enemy1Pos", "UI/PartyStatusPanel", "UI/TurnInfoPanel/TurnInfo"]


class Probe extends "res://src/battle/BattleScene.gd":
	var probed := true


func test_a_bare_script_has_none_of_the_nodes() -> void:
	var bare: Node = autofree(SceneScript.new())
	for p in PATHS:
		assert_false(bare.has_node(p), "CONTROL: a bare BattleScene.gd has no %s, which is what the engine errors were" % p)


func test_the_fixture_has_every_node() -> void:
	var scene: Node = autofree(Fixture.build())
	assert_eq(scene.get_script(), SceneScript, "the fixture runs the real BattleScene script")
	for p in PATHS:
		assert_true(scene.has_node(p), "the fixture's scene must carry %s" % p)


func test_a_probe_subclass_keeps_its_script_and_the_nodes() -> void:
	var scene: Node = autofree(Fixture.build(Probe))
	assert_eq(scene.get_script(), Probe, "the probe subclass must be the scene's script")
	assert_true(bool(scene.get("probed")), "the probe's own members must be live")
	for p in PATHS:
		assert_true(scene.has_node(p), "a probe-scripted fixture must still carry %s" % p)


func test_the_top_offenders_build_through_the_fixture() -> void:
	for f in ["command_menu_shape_regression", "the_boss_last_words_are_a_moment"]:
		var src := FileAccess.get_file_as_string("res://test/unit/test_%s.gd" % f)
		assert_gt(src.length(), 0, "CONTROL: read test_%s.gd" % f)
		assert_true(src.contains("battle_scene_fixture.gd"), "test_%s.gd must build its BattleScene through the fixture" % f)


func test_the_root_sets_nothing_a_probe_swap_would_drop() -> void:
	## set_script resets script-owned vars, so the probe path is only faithful while the .tscn root sets none.
	var allowed := ["layout_mode", "anchors_preset", "anchor_left", "anchor_top", "anchor_right", "anchor_bottom",
		"offset_left", "offset_top", "offset_right", "offset_bottom", "grow_horizontal", "grow_vertical", "script"]
	var keys: Array = []
	var on := false
	for line in FileAccess.get_file_as_string(Fixture.SCENE_PATH).split("\n"):
		if line.begins_with("[node name=\"BattleScene\""):
			on = true
		elif on and line.begins_with("["):
			break
		elif on and " = " in line:
			keys.append(line.get_slice(" = ", 0))
	assert_true(keys.has("script"), "CONTROL: the root block was found and read")
	for k in keys:
		assert_true(allowed.has(k), "BattleScene.tscn's root sets '%s'; battle_scene_fixture's probe set_script would silently drop a script var" % k)
