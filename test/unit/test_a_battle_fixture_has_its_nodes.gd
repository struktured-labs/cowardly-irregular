extends GutTest
## .849 gate: 4450 "Node not found" engine errors, every one from a BattleScene built as a bare script.
## battle_scene_fixture builds it from the .tscn, so its @onready paths resolve, with or without a probe subclass.

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
	for f in ["command_menu_shape_regression", "a_hit_knows_who_swung", "the_boss_last_words_are_a_moment",
			"a_cast_boss_speaks_its_last_words_live", "a_knock_back_leaves_from_the_sway", "an_unpayable_group_row_says_why_regression"]:
		var src := FileAccess.get_file_as_string("res://test/unit/test_%s.gd" % f)
		assert_gt(src.length(), 0, "CONTROL: read test_%s.gd" % f)
		assert_true(src.contains("battle_scene_fixture.gd"), "test_%s.gd must build its BattleScene through the fixture" % f)
